---
layout: post
title: "Prefetch opam files for day10 --fork"
date: 2026-04-21 19:00:00 +0000
categories: ocaml,day10,opam
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
---

Last month, I [wrote](https://www.tunbury.org/2026/03/16/day10/) a walkthrough on using [mtelvers/day10](https://github.com/mtelvers/day10) and while stuck in traffic yesterday, I was thinking about all those individual opam files which are read for every solve.

`day10`'s solver is built around `Opam_0install.Solver.Make(Dir_context)`, and `Dir_context` reads opam files directly from an `opam-repository` working tree. For a typical package such as `0install.2.18`, I was seeing ~0.79s per solve, and on my machine , it showed 3m30s of user time for 200 packages at `--fork 10`. The wall time was 23.6s.

A quick check showed that [ocaml-opam/opam-0install-solver](https://github.com/ocaml-opam/opam-0install-solver) wasn't far off the installed upstream `Opam_0install.Dir_context` (same ~0.80s). The upstream `opam-0install` CLI reports 0.24s per solve, but that uses `Switch_context` over a pre-loaded opam switch state, so all the opam files are already parsed.

# Git object backends

My original thought was to use the git database directly, then multiple instances of `day10` could read different commits simultaneously without needing a working tree. Git's object database is content-addressed and fine with multiple concurrent readers, and Thomas uses the git store in the [ocurrent/solver-service](https://github.com/ocurrent/solver-service).

I tried four backends on the same solve (`0install.2.18` against my opam-repository HEAD, `caab044f22`).

| backend | solve time | notes |
|---|---|---|
| `Dir_context` (filesystem, baseline) | 0.79s | re-parses every opam file on every solve |
| subprocess `git cat-file --batch` (per-query) | 9.27s | one roundtrip per opam blob |
| subprocess + Hashtbl cache | 6.42s | dropped redundant probes too |
| **ocaml-git** (native OCaml, `git-unix` + packfile reader) | 42.57s | packfile inflate + delta resolution per object |
| `Sql_context` (SQLite ingestion) | 0.77s | 75 MB DB, 0.73s one-off ingest |

The `git cat-file --batch` subprocess version was OK-ish, but six seconds per solve wasn't going to win any awards. `ocaml-git` was by far the worst, as every `Search.find` walks from commit to tree to sub-tree to blob, and each hop hits a zlib inflate. Caching the results took it from unusably slow to only very slow. It also drags in lwt + mimic + carton + decompress + digestif + happy-eyeballs + tls.

SQLite was the surprise winner among the new backends. One sequential-scan prepared statement plus a blob lookup per `load` matched `Dir_context` almost exactly.

How did Thomas do it in [ocurrent/solver-service](https://github.com/ocurrent/solver-service)? It does use `ocaml-git`, but it defers almost all of the cost to an [`Eio.Lazy`](https://github.com/ocaml-multicore/eio) on a per package name basis:

```ocaml
type t = OpamFile.OPAM.t OpamPackage.Version.Map.t
         Eio.Lazy.t
         OpamPackage.Name.Map.t
```

`of_commit` reads exactly one tree object, the top-level `packages/` directory, and records each name's subtree SHA. No opam files are touched at startup. When the solver asks for candidates of `lwt`, the lazy for `lwt` is forced: it reads the `packages/lwt/` subtree and, in one batch, reads and parses every version's opam file. That result is then cached. Second and subsequent `candidates(lwt)` calls are map lookups.

The solver's access pattern is all versions of a single package name, so I ported this idea to the plain `cat-file --batch` subprocess, and it ran the first solve in 1.1s and subsequent solves in 0.25s. That's pretty close to the `Switch_context` on warm solves.

Full scoreboard after all this:

| approach | setup | solve | total |
|---|---|---|---|
| upstream CLI (`Switch_context`) | 0.37s | 0.24s | 0.61s |
| `Sql_context` | — | 0.77s | 0.77s |
| `Dir_context` | — | 0.79s | 0.79s |
| bulk `git archive` + tar, lazy parse | 0.59s | 0.73s | 1.33s |
| `git cat-file`, lazy per package name | 0.03s | 1.10s | 1.13s |
| `git cat-file`, per query | — | 6.42s | 6.42s |
| ocaml-git + caches | — | 42.57s | 42.57s |

# Actually addressing the problem

All of the above was interesting, but I concluded that it was largely irrelevant to `day10 --fork 256`. The real workload isn't one cold solve; it's [thousands of solves per invocation](/2026/03/16/day10/#step-2-solve-dry-run-pass), more like the solver service.

The `--fork` parameter in `day10` does `Os.fork ~np run_with_package packages`. Each of the 256 children starts with its own empty context, reads opam files off disk, parses them, caches nothing across solves. Each child does the same parsing work. Both the duplicated work and the fact that they are forks mean they can't efficiently share a cache.

However, Linux's `fork` is copy-on-write, so if the parent process parses all the opam files before the fork, every child inherits the parsed `OpamFile.OPAM.t` values for free via shared pages.

The smallest possible change: a process-wide `Hashtbl` in `Dir_context`, and a `prefetch` function that populates it:

```ocaml
let cache : (OpamPackage.t, OpamFile.OPAM.t) Hashtbl.t = Hashtbl.create 32768

let load t pkg =
  let { OpamPackage.name; _ } = pkg in
  match OpamPackage.Name.Map.find_opt name t.pins with
  | Some (_, opam) -> opam
  | None ->
      match Hashtbl.find_opt cache pkg with
      | Some v -> v
      | None ->
          let opam = ... read and parse from filesystem ... in
          Hashtbl.add cache pkg opam;
          opam

let prefetch ~packages_dirs () =
  ... walk every packages/<name>/<name.ver>/opam, parse, stash in the cache ...
```

And in `run_health_check_multi`'s fork branch:

```ocaml
| Some np ->
    let packages_dirs = List.map (fun r -> Path.(r / "packages")) config.opam_repositories in
    Dir_context.prefetch ~packages_dirs ();
    Os.fork ~np run_with_package packages
```

The non-fork paths (`Some 1 | None`) keep the existing behaviour.

# Results

Running on the same EPYC 9965 box as the [original post](/2026/03/16/day10/), with `--fork 256`, 4,325 packages at ocaml 5.4.1 / Debian 13 / `--dry-run`:

| run | wall | user CPU | sys |
|---|---|---|---|
| baseline | 36.0s | 25m 50s | 98m 19s |
| pre-parsed before fork | 10.0s | 7m 10s | 2m 26s |
| speedup | 3.6x | 3.6x | 40x |

The baseline figure matches the 36s I reported originally, which is reassuring!

Wall time drops from 36s to 10s, which I'm pretty happy with, particularly set against the reductions in CPU time. The prefetch step itself took 1.3s on this machine, which is a small price to offset the ~90 minutes of eliminated sys-time IO.
