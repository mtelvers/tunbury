---
layout: post
title: "OCaml CI GitHub Rate Limit"
date: 2026-06-02 14:00:00 +0000
categories: [ocaml, ci]
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

While looking at OCaml CI for the FD leak, I noticed some odd pending events in the OCaml CI build graph.

I could see nodes which should be near-instantaneous stuck in the pending state. For example, `avsm/osrelease` had completed `head,` but `CI refs`, which would have started at the same time, was still pending.

![avsm/osrelease build graph](/images/avsm-osrelease.png)

I could see similar issues for `MisterDA`'s and `robur-coop`'s `list repos`. `talex5/cuekeeper` had one explicit `[INFO] Result: Error: GitHub query refs for talex5/cuekeeper failed: Cohttp_lwt__Connection.Retry` logged at startup.

I immediately blamed a GitHub rate limit, but where exactly?

The `current_github` Monitor structure is shared between `Refs` and `Head_ref`. Both go through the same code:

```ocaml
let read () =
  Lwt.catch
    (fun () -> exec t repo >|= fun c -> Ok c)
    (fun ex -> Lwt_result.fail @@ `Msg (Fmt.str "GitHub query %s for %a failed: %a"
                                          Query.name Repo_id.pp repo Fmt.exn ex))
in
```

and `exec` calls `exec_graphql`, which is:

```ocaml
let exec_graphql ?variables t query =
  ...
  get_token t >>= function
  | Error (`Msg m) -> failwith m
  | Ok token ->
    let headers = ... in
    Cohttp_lwt_unix.Client.post ~headers ~body graphql_endpoint >>=
    fun (resp, body) ->
    Cohttp_lwt.Body.to_string body >|= fun body ->
    ...
```

There is no timeout. We send these queries and assume that GitHub will always respond. `Cohttp_lwt_unix.Client.post` is the default cohttp client, and looking in `cohttp-lwt/client.ml`, it uses `Make_no_cache`, so each call opens a fresh TCP connection rather than using the pooling `Make`. Each `exec_graphql` is its own independent HTTPS connection.

The `Lwt.catch` above turns any exception into a permanent `Result.Error` and stores it in the Monitor's value. This explains why I see `Cohttp_lwt__Connection.Retry`, which is really just cohttp's way of saying that we should retry the request. The only way the read is ever retried is via `refresh`, and `refresh` only fires when a webhook arrives for the repo. For something like `avsm/osrelease` whose last commit is 3 years ago, that's unlikely to refresh soon.

At startup, the ocaml-ci-service activates a Monitor for every repo in every installation it sees. That's 660 repos each with 2 monitors, so 1320 concurrent `exec_graphql` calls. Since these all come from a single source IP, against api.github.com that is likely to cause throttling.

I added three logging events to `current_github`:

1. `get_token` entry/exit with the installation account and lock-hold duration.
2. `exec_graphql` POST start, response status received, body fully drained — each with elapsed-time.
3. Monitor `read()` START / OK / FAIL with the repo name and the query type (`refs` vs `head ref` vs others).

Checking the log upon restart:

```
13:38.35  Watch starting for owner/name: talex5/angstrom (head ref monitor)
13:38.35  Monitor read START: head ref for talex5/angstrom
13:38.35  Watch starting for owner/name: talex5/angstrom (refs monitor)
13:38.35  Monitor read START: refs for talex5/angstrom
13:38.56  Monitor read FAIL in 21.113s: refs for talex5/angstrom: Cohttp_lwt__Connection.Retry
```

`talex5/angstrom` failed visibly. But more interestingly, counting the number of START vs the number of OK + FAIL should give 1320:

```
1320 Monitor read START
1078 Monitor read OK
  12 Monitor read FAIL
```

However, I found 12 explicit `Connection.Retry` failures, all at 21 seconds and then nothing else. The other 230 reads are missing.

So rather than calling `exec` directly, I've inserted `exec_with_retry`. This adds a 30-second timeout to every read and allows `Connection.Retry` / `Lwt_unix.Timeout` to be explicitly retried up to three times with an exponential backoff.

```ocaml
let exec_with_retry t repo =
  let rec attempt n =
    Lwt.catch
      (fun () -> Lwt_unix.with_timeout 30.0 (fun () -> exec t repo))
      (function
        | (Lwt_unix.Timeout | Cohttp_lwt__Connection.Retry) as ex when n < 3 ->
            let delay = Float.pow 2.0 (float_of_int n) -. 1.0 in   (* 1s, then 3s *)
            Log.warn (fun f ->
              f "Retrying %s for %a in %.1fs (attempt %d/3) after %a"
                Query.name Repo_id.pp repo delay (n + 1) Fmt.exn ex);
            Lwt_unix.sleep delay >>= fun () ->
            attempt (n + 1)
        | e -> Lwt.reraise e)
  in
  attempt 1
```

Restarting the service and then grepping the log after a couple of minutes showed:

```
1314 Monitor read STARTed
1314 Monitor read OK
   0 Monitor read FAIL
```

The log shows 140 retries triggered: 32 `Connection.Retry` and 108 `Lwt_unix.Timeout`.

`avsm/osrelease` (head 6.6s, refs 6.6s, Ok), `talex5/cuekeeper` (head 13.4s; refs hit `Connection.Retry` once, retried 1s later, Ok in 32.9s total), `MisterDA/*` all of them resolved on the new run.

