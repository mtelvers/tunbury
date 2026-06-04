---
layout: post
title: "OCaml-CI HTTP 502 errors"
date: 2026-05-28 14:00:00 +0000
categories: [ocaml, ci]
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Over the last few weeks, I have restarted the [OCaml-CI](https://ocaml.ci.dev) web container every 3 or 4 days because users are encountering HTTP 502 errors.

Restarting the container only requires `docker service update --force ocaml-ci_web`, but it's annoying, and it's time to investigate it properly.

The container memory and CPU usage were low:

```
$ docker stats --no-stream 4697d1fb629f
CPU %   MEM USAGE / LIMIT   PIDS
0.01%   70.43MiB / 251.8GiB  11
```

Checking on the threads:

```sh
for t in /proc/1642761/task/*; do
  echo "--- thread $t ---";
  cat $t/status | grep -E '^(Name|State|voluntary|nonvol)';
  cat $t/wchan;
  echo;
done
```

This showed that the main thread was waiting at `epoll_wait` and a handful of workers were waiting on a `futex_wait_queue`. That seems ok, it's just idle at the moment. However, `curl https://ocaml.ci.dev/` returned 502.

```
--- thread 1642761 ---
Name: ocaml-ci-web
State:        S (sleeping)
voluntary_ctxt_switches:      619162
nonvoluntary_ctxt_switches:   6215
ep_poll
--- thread 1642765 ---
Name: ocaml-ci-web
State:        S (sleeping)
voluntary_ctxt_switches:      2089
nonvoluntary_ctxt_switches:   11
futex_wait_queue
...
```

The most logical next check was file descriptors. `status` reports FDSize, which is the size of the kernel file descriptor table for this process. The actual limit is available in `limits`, and the currently in-use file descriptors are listed in `fd/*`:

```sh
$ cat /proc/1642761/status | grep -E 'FDSize|Threads|VmRSS'
FDSize:   1024
Threads:  10
VmRSS:    101192 kB

$ cat /proc/1642761/limits | grep 'Max open files'
Max open files            1024                 524288               files

$ ls /proc/1642761/fd | wc -l
1024
```

So all 1024 file descriptors are in use. That would explain the problem. A quick check on what they are:

```sh
$ readlink /proc/1642761/fd/* | awk -F: '{print $1}' | sort | uniq -c
   1019 socket
      2 pipe
      2 anon_inode
      1 /dev/null
```

1019 sockets. The container networking lives in its own network namespace, so running `ss` on the host doesn't show them, but running `ss` via `nsenter` shows them:

```
$ nsenter -t 1642761 -n ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c
    721 CLOSE-WAIT
      5 ESTAB
      3 LISTEN
```

721 sockets in the `CLOSE_WAIT` state are a problem. The `Recv-Q` is at 4097 of 4096, so the kernel will be dropping new SYN, which the reverse proxy will report as HTTP 502.

```sh
$ nsenter -t 1642761 -n ss -tanp 2>/dev/null
State      Recv-Q Send-Q   Local Address:Port    Peer Address:Port    Process
LISTEN     0      128            0.0.0.0:9090          0.0.0.0:*
users:(("ocaml-ci-web",pid=1642761,fd=7))
LISTEN     4097   4096           0.0.0.0:8090          0.0.0.0:*
users:(("ocaml-ci-web",pid=1642761,fd=8))
LISTEN     0      4096        127.0.0.11:41759         0.0.0.0:*
users:(("dockerd",pid=1543,fd=141))
ESTAB      0      0           172.18.0.9:39130  128.232.124.253:8202
users:(("ocaml-ci-web",pid=1642761,fd=6))
```

`CLOSE_WAIT` is the TCP state where the peer has sent its FIN, but our side hasn't called `close`. We can use `ss` to determine the peer IP address:

```
$ nsenter -t 1642761 -n ss -tan | awk '$1=="CLOSE-WAIT" {print $5}' | awk -F: '{print $1}' | sort -u
10.0.1.4
```

`10.0.1.4` is the Caddy container acting as the reverse proxy. Caddy makes a request, the OCaml-CI web service receives it, then Caddy closes its end, and the OCaml-CI web service never closes its.

Looking around the code for places without an obvious `close` call, found this block in `web-ui/view/step.ml`, which handles the streaming of the build log.

```ocaml
Dream.stream
  ~headers:[ ("Content-type", "text/html; charset=utf-8") ]
  (fun response_stream ->
    Dream.write response_stream header >>= fun () ->
    let rec loop next =
      Current_rpc.Job.log job ~start:next >>= function
      | Ok ("", _) ->
          Dream.write response_stream footer >>= fun () ->
          Dream.close response_stream
      | Ok (data, next) ->
          Dream.log "Fetching logs";
          Dream.write response_stream data >>= fun () ->
          Dream.flush response_stream >>= fun () -> loop next
      | Error (`Capnp ex) ->
          Dream.log "Error fetching logs: %a" Capnp_rpc.Error.pp ex;
          Dream.write response_stream
            (Fmt.str "ocaml-ci error: %a@." Capnp_rpc.Error.pp ex)
    in
    loop next)
```

The success branch closes the stream, but the error branch does not. It looked like a fairly obvious leak. I was sceptical, but it was easy to test. A curl loop attack like this should reproduce the problem:

```sh
$ for i in {1..100}; do
    curl -s --max-time 0.1 -o /dev/null \
      'https://ocaml.ci.dev/github/ocurrent/ocaml-ci/commit/.../variant/(analysis)' &
  done; wait
```

However, it did not. 100 concurrent client disconnects mid-stream. Zero leaked sockets.

```sh
sudo nsenter -t $WEB_PID -n ss -tan | grep -c CLOSE-WAIT
0
```

This streaming code has been there since Navin's rewrite in [ocurrent/ocaml-ci/pull/794](https://github.com/ocurrent/ocaml-ci/pull/794) in March 2023. Why would it only start being a problem now?

Checking the Dream source code in `dream-1.0.0~alpha6/server/helpers.ml` shows that the default behaviour of `Dream.stream` is to close the stream on both the success and failure paths. 

```ocaml
let stream ?status ?code ?headers ?(close = true) callback =
  let reader, writer = Stream.pipe () in
  let client_stream = Stream.stream reader Stream.no_writer
  and server_stream = Stream.stream Stream.no_reader writer in
  let response =
    Message.response ?status ?code ?headers client_stream server_stream in

  Lwt.async (fun () ->
    if close then
      match%lwt callback server_stream with
      | () -> Message.close server_stream                  (* closes on return *)
      | exception exn ->
        let%lwt () = Message.close server_stream in        (* closes on exn *)
        raise exn
    else callback server_stream);

  Lwt.return response
```

Looking back at the original snippet, a long compilation step that hasn't emitted output for a while will block on the `Current_rpc.Job.log job ~start:next` until more log data arrives. While it blocks, the fiber never gets to `Dream.write` or `Dream.close`. When/if `Current_rpc.Job.log` returns, `Dream.write` tries to send that data to the client, but an exception is raised as the client has gone away.

I can hack this by using `Lwt.choose` to race `Current_rpc.Job.log` against `Lwt_unix.sleep` and emit an HTML comment in the log to check the connection is still alive.

```ocaml
let rec loop next =
  let log_p = Current_rpc.Job.log job ~start:next in
  let rec wait () =
    Lwt.choose
      [ (log_p >|= fun r -> `Log r)
      ; (Lwt_unix.sleep 5.0 >|= fun () -> `Beat) ]
    >>= function
    | `Log (Ok ("", _)) -> Dream.write response_stream footer
    | `Log (Ok (data, next)) ->
        Dream.log "Fetching logs";
        Dream.write response_stream (Ansi.process ansi data) >>= fun () ->
        Dream.flush response_stream >>= fun () -> loop next
    | `Log (Error (`Capnp ex)) -> ...
    | `Beat ->
        Lwt.catch
          (fun () ->
            Dream.write response_stream "<!-- ping -->" >>= fun () ->
            Dream.flush response_stream >>= fun () -> wait ())
          (fun _exn -> Lwt.return ())   (* client gone *)
  in
  wait ()
```

This worked, but there is that nagging question about why this is suddenly a new problem. There are likely more web crawlers out there than in the past, following links to logs that are still building and then disconnecting rather than waiting, thereby causing the build-up of fds.

After 4 days, it's still ok, but I'm not going to call it fixed or open a PR as it doesn't make sense. There's something more to find.
