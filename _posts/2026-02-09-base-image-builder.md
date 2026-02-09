---
layout: post
title: "Windows Docker Images"
date: 2026-02-09 09:30:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/docker-base-images.png
  thumbnail: /images/thumbs/docker-base-images.png
---

In my previous post on the [base image builder](https://www.tunbury.org/2026/01/16/base-image-builder/), I included a footnote that we now had Windows 2025 workers, but I didn't mention that the base images weren't building.

Docker on Windows is very slow, so I have had a background task nudging these builds forward a little bit each day, and I'm pleased to now report that over the weekend, the images all built, and the entire dashboard is green!

The most significant change was moving away from fdopen's opam to native opam. This has unlocked OCaml 5 builds for the first time but has removed images for OCaml < 4.13. MSVC 5.0-5.2 are not available as the MSVC port was broken until OCaml 5.3 [ocaml/ocaml#12954](https://github.com/ocaml/ocaml/pull/12954). Each version is built on Windows Server LTSC 2019, LTSC 2022, and LTSC 2025.

| OCaml Version | MinGW | MSVC |
|---------------|:-----:|:----:|
| 4.13.1        | ✓     | ✓    |
| 4.14.2        | ✓     | ✓    |
| 5.0.0         | ✓     | ✗    |
| 5.1.1         | ✓     | ✗    |
| 5.2.1         | ✓     | ✗    |
| 5.3.0         | ✓     | ✓    |
| 5.4.0         | ✓     | ✓    |

Below are the detailed changes.

# [PR 257 ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile/pull/257)

`src-opam/distro.ml`:

- Changed `opam_repository` to use standard `ocaml/opam-repository.git` for Windows instead of `ocaml-opam/opam-repository-mingw.git#sunset`
- Added version filter: Windows builds now require OCaml >= 4.13 (native opam 2.2+ requires official packages)
- MSVC filter: OCaml 5.0-5.2 excluded (MSVC support restored in 5.3)

`src-opam/windows.ml`:

- `ocaml_for_windows_package_exn` now returns `Ocaml_version.Opam.V2.package` directly, using official package names (`ocaml-base-compiler/ocaml-variants+options`) instead of fdopen's `+mingw64`/`+msvc64` naming

`src-opam/opam.ml`:

- Reduce parallelism on Windows to avoid OOM on unbound `make -j`
- Update Visual Studio to Windows 11 SDK
- create_switch adds `system-mingw/system-msvc` for all Windows versions (not just 5.x)
- `setup_default_opam_windows_msvc` persists MSVC environment (`PATH`, `INCLUDE`, `LIB`, `LIBPATH`) with correct `PATH` ordering: MSVC → Cygwin → Windows

# [PR 339 docker-base-images](https://github.com/ocurrent/docker-base-images/pull/339)

`src/pipeline.ml`:

- Port package (`system-mingw`/`system-msvc`) added for all Windows versions
- Removed fdopen overlay addition (`maybe_add_overlay` no longer called for Windows)
- Removed `opam repo remove ocurrent-overlay` step
- Changed `depext` to `Option` type - returns `None` for Windows (opam 2.2+ has depext built-in)
- Uses `opam_repository_master` for Windows instead of `opam_repository_mingw_sunset`

`src/git_repositories.ml` (implied by pipeline changes):

- Removed references to `opam_repository_mingw_sunset` and `opam_overlays`.
