---
layout: post
title: "OCaml CI lingering solves"
date: 2026-06-02 20:00:00 +0000
categories: [ocaml, ci]
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

By now, you'll know that I've been looking at OCaml CI more than I ever had before and was confused by the solver jobs, which seemed to hang around in the job queue.

At ocurrent's `/jobs` endpoint, there is a list of build jobs, mostly [RISCV]({% post_url 2026-06-03-emulated-riscv-workers %}) at this moment, but there is a build-up of several hundred `solver-job-XXXXXX` which have started but not finished. Perhaps these relate to those open FDs I've been chasing?

Each `solver-job-XXXXXX` job page showed only:

```
2026-06-02 15:02.13: Waiting for resource in pool OCluster
2026-06-02 15:02.13: Got resource from pool OCluster
```

When I manually triggered OCaml CI Analyse job on a repo, I could see the `ci-analyse-XXXXXX` job was created along with several `solver-job-XXXXXX` entries. The `ci-analyse` contained the [solve](https://ocaml.ci.dev:8100/job/2026-06-04/171355-ci-analyse-a71779) we're familiar with; while each `solver-job` contained just those [two lines](https://ocaml.ci.dev:8100/job/2026-06-04/171356-solver-job-426cf4).

These didn't seem to affect normal operation, but they did build up over time. When you clicked on them the log was still being streamed.

My initial guess here was totally wrong. Under the assumption that this was a new problem, I went through what had changed, and I was leaning heavily towards the [move of the scheduler]({% post_url 2026-04-01-from-scaleway-to-cambridge %}).

With this move, OCaml CI and the scheduler are running on the same machine, each in its own Docker container. While OCaml CI connects to `scheduler.ci.dev` using the public IP, it is actually being hairpinned back to a container on the same machine. After a lot of `tcpdump`, I concluded that Docker handles this beautifully.

I had a realisation that there were `ci-analyse` jobs and `ci-solve` jobs. I know I said that earlier, but why are there two kinds of jobs? The solver output is in `ci-analyse`, so what is `ci-solve`?

Looking at `backend_solver.ml`:

```ocaml
let switch = Current.Switch.create ~label:"solver-remote" ()
let config = Current.Config.v ()
...
let remote_solve con job request =
  ...
  let dummy_job = Current.Job.create ~label:"solver-job" ~switch ~config () in
  Current.Job.start_with ~pool:build_pool dummy_job ~level:Current.Level.Average
  >>= fun build_job ->
  Capnp_rpc_lwt.Capability.with_ref build_job
    (Current_ocluster.Connection.run_job ~job)
```

The `switch` is at the module-level, thus shared by every `remote_solve` call. The dummy_job's only purpose is to satisfy `Current.Job.start_with`, which needs a job to get a pool. Once `start_with` returns `build_job`, the `dummy_job`'s actual work is done. However, nothing marks it complete, and its log file stays open at "Got resource from pool OCluster", and Current keeps it in `Running` state.

I moved the switch into `remote_solve` and explicitly turned it off at the end.

```ocaml
let remote_solve con job request =
  ...
  let switch = Current.Switch.create ~label:"solver-remote" () in
  let dummy_job = Current.Job.create ~label:"solver-job" ~switch ~config () in
  Lwt.finalize
    (fun () ->
      Current.Job.start_with ~pool:build_pool dummy_job
        ~level:Current.Level.Average
      >>= fun build_job ->
      Capnp_rpc_lwt.Capability.with_ref build_job
        (Current_ocluster.Connection.run_job ~job))
    (fun () -> Current.Switch.turn_off switch)
```

Is this the source of the leaking file descriptors? I doubt it, as this was introduced in commit `2b8bc91` in January 2023.
