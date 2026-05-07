---
layout: post
title: "ocaml-ci moves to significant versions"
date: 2026-04-29 08:00:00 +0000
categories: [ocaml, ocaml-ci]
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

The same OCaml build matrix updates which where deployed in [opam-repo-ci]({% post_url 2026-04-27-opam-repo-ci-update %}) have now been applied to [ocaml-ci](https://github.com/ocurrent/ocaml-ci).

The changes add 5.5.0~beta1 testing, switch to the new `Ocaml_version.Releases.significant` list, and drop 32-bit architectures have now been applied to [ocaml-ci](https://github.com/ocurrent/ocaml-ci); this post covers the OCaml-CI specific changes.

# Switching to `Releases.significant`

OCaml-CI builds the test matrix in `service/conf.ml`. The two places which used `Releases.recent` now use `Releases.significant`:

```ocaml
let ovs = List.rev OV.Releases.significant @ OV.Releases.unreleased_betas in
```

and, for the `Minimal` profile used in local development:

```ocaml
let[@warning "-8"] (latest :: previous :: _) =
  List.rev OV.Releases.significant
in
```

Basically an identical change as in opam-repo-ci, dropping the OCaml version test matrix from eleven entries (every stable since 4.08) down to the curated `[4.08; 4.11; 4.14; 5.2; 5.3; 5.4]` set. This is covered in [PR#1050](https://github.com/ocurrent/ocaml-ci/pull/1050)

# Adding `5.5.0~beta1`

In the same release of ocaml-version, Kate's PR [ocurrent/ocaml-version#88](https://github.com/ocurrent/ocaml-version/pull/88) adds `5.5.0~beta1` to `OV.Releases.unreleased_betas`.

# Dropping i386 and Arm32

OCaml-CI's builds each compiler across `Dockerfile_opam.Distro.distro_arches`. That list is now filtered to skip 32-bit:

```ocaml
let arches =
  DD.distro_arches ov (distro :> DD.t)
  |> List.filter (function `I386 | `Aarch32 -> false | _ -> true)
in
```

This also makes the existing `excluded_selection` fudge in `lib/pipeline.ml` unused. This was a workaround for [issue #931](https://github.com/ocurrent/ocaml-ci/issues/931) that suppressed `conf-capnproto` selections on debian-12/i386. With i386 gone from the matrix, the filter has nothing left to filter, so it has been removed.

# Dropping the vendored submodules

In [PR #1049](https://github.com/ocurrent/ocaml-ci/pull/1049), I removed the vendored submodules: [ocurrent](https://github.com/ocurrent/ocurrent), [ocluster](https://github.com/ocurrent/ocluster), [ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile), [ocaml-version](https://github.com/ocurrent/ocaml-version) and [solver-service](https://github.com/ocurrent/solver-service). This mirrors [PR#349](https://github.com/ocurrent/opam-repo-ci/pull/349) from 2024, which did the same in opam-repo-ci.

As a result, the Dockerfile's are substantially shorter with only the solver-service pin remaining. `Dockerfile.gitlab` and `Dockerfile.web` were also updated at the same time: debian-13 / opam 2.5 / `docker-cli` (in place of the full `docker.io` engine package, which pulled in the daemon).
