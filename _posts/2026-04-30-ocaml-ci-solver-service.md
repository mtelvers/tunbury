---
layout: post
title: "Update solver-service in OCaml-CI local mode"
date: 2026-04-30 21:00:00 +0000
categories: ocaml,ocaml-ci
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

When I (mostly) [unvendored ocaml-ci's submodules]({% post_url 2026-04-29-ocaml-ci-update %}) a few days ago. Four out of the five were published in the opam-repository, but `solver-service` was not, so it ended up as a `pin-depends` block in `ocaml-ci.opam.template` pinned at the same SHA the submodule had pointed at.

Patrick's [Issue #1044](https://github.com/ocurrent/ocaml-ci/issues/1044) caused me to revisit it. `ocaml-ci-local /path/to/repo` fails the analysis step with `Invalid_argument("filter_deps")`. The upstream fix is [`86d37c7`](https://github.com/ocurrent/solver-service/commit/86d37c716be36c0712dcc2be60b135497ead1132), a one line in `service/git_context.ml`:

```diff
-  |> OpamFilter.filter_deps ~build:true ~post:true ~test ~doc:false ~dev
+  |> OpamFilter.filter_deps ~build:true ~post:true ~test ~doc:false ~dev ~dev_setup:false
        ~default:false
```

Newer opam-format raises `Invalid_argument` from `OpamFilter.deps_var_env` if the filter formula references `with-dev-setup` and the caller hasn't passed `~dev_setup`. I had `opam-format.2.5.1` installed; the bug was easily reproduced.

The problem is that the pin can't be bumped as `f14bc6f` is the last commit before `12f49f6` "Initial OCaml 5 / Eio port" which changes everything:

* OCaml >= 5.1.0 (we still build OCaml-CI on 4.14 along with the rest of the stack is Lwt + OCurrent).
* Eio, `lwt_eio`, and an Eio_main-based `solver-service` binary.
* `opam-core`/`opam-state`/`opam-repository`/`opam-format` pinned to `2.3.0~alpha1` for performance fixes #6144/#6122 — none released to opam-repository.
* The deletion of the `solver-worker` opam package, whose functionality is now in `solver-service`.
* The deletion of `Solver_worker.Solver_request` Lwt library which `lib/backend_solver.ml` calls:

```ocaml
type t =
  | Remote of Current_ocluster.Connection.t
  | Local of Solver_worker.Solver_request.t Lwt.t
```

The thing is, though, the `Local` development mode doesn't run any solver code in the OCaml-CI process. It sets up a pool of child processes and sends solve requests to them through a pipe; the actual `OpamFilter.filter_deps` call is in an exec'd `solver-service` binary.

So there's no reason I can't have an Eio solver service binary exec'd by OCaml-CI using Lwt. This is just `Lwt_process.open_process`! The problem is that it's untidy to build it this way, since the two components need to be built with different compilers and different dependencies.

Even accepting that, the new `solver-service run-child` needs a socket pair where the older `solver-service --sockpath` used a socket file:

```ocaml
(* OLD: f14bc6f's --sockpath. Parent binds a UNIX socket file,
   exec's the child, child connects to the path, parent accepts. *)
let listener = Unix.socket ~cloexec:true PF_UNIX SOCK_STREAM 0 in
Unix.bind listener (ADDR_UNIX name);
Unix.listen listener 1;
let cmd = ("", [| "solver-service"; "--sockpath"; name |]) in
let _child = Lwt_process.open_process_none ~cwd:solver_dir ~stdin:`Close cmd in
let p, _ = Unix.accept ~cloexec:true listener in
Unix.close listener;
Unix.unlink name;

(* NEW: HEAD's run-child. Parent makes a socketpair, dups one half
   onto the child's stdin, exec's the child. *)
let parent_fd, child_fd = Unix.socketpair PF_UNIX SOCK_STREAM 0 in
Unix.set_close_on_exec parent_fd;
let _pid =
  Unix.create_process "solver-service"
    [| "solver-service"; "run-child"; "--cache-dir"; cache_dir |]
    child_fd Unix.stderr Unix.stderr
in
Unix.close child_fd;
let p = parent_fd in
...
```

There's a module called `lib/solver_pool.ml` which comes from 2020, prior to the move to the solver-service in 2023. [PR #634](https://github.com/ocurrent/ocaml-ci/pull/634). This was looking like a major tidy up operation.

Two options:

1. Drop the `solver-service`/`solver-worker` library deps from `lib/dune` and `dune-project`. For `Local` mode the `Backend_solver` could reuse the old `lib/solver_pool.ml`'s Cap'n Proto-over-pipe path, so OCaml-CI links only `solver-service-api` and exec's the `solver-service` binary as an opaque subprocess. Two switches at build time (OCaml-CI on 4.14/Lwt, solver-service on 5.x/Eio); one pipe at runtime.

2. Branch `solver-service` from `f14bc6f`, cherry-pick `86d37c7` onto it, repoint the three `pin-depends` lines at the new SHA.

I prototyped option 1, but it touched a lot of files, showed there's a bunch of tidy-up work to do, and wasn't easy to build for local development, so I went with the second option.

```
$ git checkout -b f14bc6f-dev-setup f14bc6f
$ git cherry-pick 86d37c7
```

`86d37c7` adds tests against a framework that doesn't exist at `f14bc6f` it postdates the Eio port, so the test files conflicted. I drop those, taking only the `service/git_context.ml` change. The result is a single commit `98c0470` on top of `f14bc6f` containing the one-line `~dev_setup:false` addition.

Pushed to `ocurrent/solver-service` as `f14bc6f-dev-setup`. The OCaml-CI diff is two files:

```diff
 pin-depends: [
-  ["solver-service.dev" "git+https://github.com/ocurrent/solver-service.git#f14bc6f…"]
-  ["solver-service-api.dev" "git+…f14bc6f…"]
-  ["solver-worker.dev" "git+…f14bc6f…"]
+  ["solver-service.dev" "git+https://github.com/ocurrent/solver-service.git#98c0470…"]
+  ["solver-service-api.dev" "git+…98c0470…"]
+  ["solver-worker.dev" "git+…98c0470…"]
 ]
```

`opam reinstall solver-service solver-service-api solver-worker` rebuilds the binary against the cherry-pick branch; `grep filter_deps` in the freshly built tree shows `~dev_setup:false` in place. OCaml-CI builds clean and tests pass. The PR is [ocurrent/ocaml-ci#1053](https://github.com/ocurrent/ocaml-ci/pull/1053).
