---
layout: post
title: "OCurrent on Eio"
date: 2026-04-28 21:00:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

[OCurrent](https://github.com/ocurrent/ocurrent) has always been Lwt-based but what would it take to migrate it to Eio? The pipeline DSL itself is incremental computation over `Current.t`, but the engine, the cache, every plugin's `BUILDER`/`PUBLISHER`, the web UI, and capnp-rpc were all built on `Lwt.t`.

With [capnp-rpc 2.x going Eio-only](https://github.com/mirage/capnp-rpc/releases/tag/v2.0.0) we have been running with `current_rpc` pinned to `capnp-rpc { < "2.0" }`. OCurrent 2.0 is a clean Eio break, no `ocurrent-lwt` transition shim. Users staying on Lwt pin `current { < "2.0" }`.

The `prometheus` and `prometheus-app` libraries use `register_lwt`, `Lwt_list`-based collectors, and a `cohttp-lwt-unix` HTTP server. The actual Lwt code is small, equating to ~50 lines in a project of ~700 lines. I forked it to Eio at [mtelvers/prometheus#eio](https://github.com/mtelvers/prometheus/tree/eio). The diff is 25 lines shorter, and Thomas's own `v1.2` CHANGES note already flagged the Lwt collector API as a stopgap.

Before any Eio work, I split `current.term` into its own opam package. `lib_term/` depends only on `bos`, `fmt`, and `current_incr`, without any Lwt. Splitting it out seemed like the logical direction, particularly as `current_incr` was already its own package. The migration was a one-line `(libraries ... current.term ...)` becomes `current_term` change.

The DSL functions are unchanged. `let>`, `and>`, `Current.list_iter`, `Current.gate`, and all the things plugins and pipelines use work as before. Including reading the same SQLite database and restoring the state from your last Lwt run.

Here's the `main` of `doc/examples/docker_build_local.ml` before and after.

Before:

```ocaml
let main config mode repo =
  let repo = Git.Local.v (Fpath.v repo) in
  let engine = Current.Engine.create ~config (pipeline ~repo) in
  let site = Current_web.Site.(v ~has_role:allow_all) ~name:program_name (Current_web.routes engine) in
  Lwt_main.run begin
    Lwt.choose [
      Current.Engine.thread engine;
      Current_web.run ~mode site;
    ]
  end
```

After:

```ocaml
let main config mode repo =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let process_mgr = Eio.Stdenv.process_mgr env in
  let repo = Git.Local.v ~sw ~process_mgr (Fpath.v repo) in
  let engine =
    Current.Engine.create ~sw ~env ~config (fun engine ->
      let caps = Current_cache.caps_of_engine engine in
      let git = Current_git.create ~caps in
      let module Docker = (val Current_docker.default ~caps ~git) in
      pipeline (module Docker) ~repo ())
  in
  let site = Current_web.Site.(v ~has_role:allow_all) ~name:program_name (Current_web.routes engine) in
  Current_web.run ~net ~mode site
```

There's no `Engine.thread` to compose with `Lwt.choose` any more. `Engine.create` forks itself as a daemon onto the ambient switch and returns. `Current_web.run` blocks; the switch's `Switch.run` block scopes the engine alongside it.

Following the Eio best practice [advice](https://github.com/ocaml-multicore/eio#best-practices), switches are generated at the fork-site rather than threaded.

Per-job work like the timeout fiber forks on `Job.switch job`; engine-wide watchers (GitHub install-monitor, GitLab webhook listeners, the cache's background fibers) fork on `Engine.switch engine`. The choice at each fork-site is "should this die with the job, or live until shutdown?", and Eio's structured cancellation does the rest.

`Job.t` carries the subset of capabilities a job actually needs. `Job.{switch, clock, fs, process_mgr}` accessors, populated by the engine when the job is created. `Current.Process.exec ~job cmd` reaches into the job for `process_mgr` and the switch internally, so plugin code doesn't have to.

The original codebase carried its own `Current.Switch` with `add_hook_or_fail` / `add_hook_or_exec` / `turn_off`. With `Eio.Switch`, the `Current.Switch` wrapper was just mirroring it, so I removed it. `Job.t` exposes `Job.switch : t -> Eio.Switch.t` directly; the per-job cleanup hooks fold into `Switch.on_release`; and `Eio.Process.spawn ~sw:(Job.switch job)` registers the SIGTERM-on-cancel hook automatically.

Plugins which conform to `BUILDER` or `PUBLISHER` lose the `Lwt.t`:

```ocaml
val build : t -> Current.Job.t -> Key.t -> Value.t Current.or_error
```

`Job.start` returns unit, `Process.exec` takes a `string list` and returns directly, `let* () =` from `Result.bind` replaces `>>!=`, and `Lwt.finalize` becomes `Fun.protect`. For example, `plugins/docker/build.ml` goes from this:

```ocaml
open Lwt.Infix
...
Current.Job.start ?timeout ?pool job ~level >>= fun () ->
with_context ~job commit @@ fun dir ->
...
Current.Process.exec ~cancellable:true ~pp_error_command ~job cmd
>|= (function
| Error _ as e -> e
| Ok () ->
  Bos.OS.File.read iidfile |> Stdlib.Result.map @@ fun hash ->
  Image.of_hash hash)
>|= (fun res -> Prometheus.Gauge.dec_one Metrics.docker_build_events; res)
```

to this:

```ocaml
open Current.Result.Syntax
...
Current.Job.start ?timeout ?pool job ~level;
with_context ~job commit @@ fun dir ->
...
Prometheus.Gauge.inc_one Metrics.docker_build_events;
Fun.protect
  ~finally:(fun () -> Prometheus.Gauge.dec_one Metrics.docker_build_events)
  (fun () ->
    match Current.Process.exec ~cancellable:true ~pp_error_command ~job cmd with
    | Error _ as e -> e
    | Ok () ->
      Bos.OS.File.read iidfile |> Stdlib.Result.map @@ fun hash ->
      Image.of_hash hash)
```

For OCurrent to be fully useful, it needs to dispatch jobs to OCluster. OCluster scheduler and OCluster worker with OBuilder are both complicated Lwt applications, but they are not OCurrent applications.

The capnp-rpc bindings are runtime-parameterised: `Schema.MakeRPC(Capnp_rpc_lwt)` produces Lwt-typed `Submission`/`Ticket`/`Job`; the same schema using `Capnp_rpc` (2.x) produces direct-style ones. So I added a parallel `cluster_api_eio/` directory next to the existing `cluster_api/`, which reruns the capnp compiler against the same `.capnp` source. Two opam packages now (`ocluster-api` and `ocluster-api-eio`), they install side-by-side, and the wire format is identical, so a Lwt server can talk to an eio client unchanged.

To test the port, I wanted to migrate a real application to see what impact it would have on the code. I picked [ocurrent-deployer](https://github.com/ocurrent/ocurrent-deployer) because it uses several plugins, including GitHub app authentication, the cluster plugin, the web UI, capnp-rpc, and the Slack plugin. There are also three versions of the deployer with varying degrees of visibility, so I picked the least used one. After seeing how it came out, there were a few iterations on OCurrent to get it the way I wanted!

The branch is at [mtelvers/ocurrent#eio](https://github.com/mtelvers/ocurrent/tree/eio); it's 33 commits, one per logical step. All 35 main tests + 40 lib_rpc tests + 1 mdx test pass, and the `current` opam package has zero Lwt runtime. The only Lwt-named package left is `lwt-dllist`, which isn't actually Lwt specific.
