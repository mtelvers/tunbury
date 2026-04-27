---
layout: post
title: "opam-repo-ci and OCaml significant versions"
date: 2026-04-27 07:30:00 +0000
categories: ocaml,opam-repo-ci
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Updates to [opam-repo-ci](https://github.com/ocurrent/opam-repo-ci) which pull in the latest [ocaml-version](https://github.com/ocurrent/ocaml-version) and [ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile) releases trim the build matrix and add in the latest releases of Alpine and Ubuntu.

# ocaml-version 4.1.0

[ocaml-version 4.1.0](https://github.com/ocurrent/ocaml-version/releases/tag/v4.1.0) adds OCaml 5.6 as a `dev` version and `5.5.0~beta1` to `unreleased_betas` [PR#88](https://github.com/ocurrent/ocaml-version/pull/88).

It also exposes a new `significant` list [PR#87](https://github.com/ocurrent/ocaml-version/pull/87):

```ocaml
let significant =
  let last_two = match List.rev all with
    | a :: b :: _ -> [b; a] | _ -> [] in
  List.sort_uniq compare ([ v4_08; v4_11; v4_14; v5_2 ] @ last_two)
```

Currently this resolves to `[4.08; 4.11; 4.14; 5.2; 5.3; 5.4]` which is a curated base from the 4.x series plus the last two releases as the list of OCaml versions against which opam packages should be regularly tested. For further detail, review the conversation on the thread of [PR#88](https://github.com/ocurrent/ocaml-version/pull/88). This is a deliberate thinning of `recent`, which had grown to all stable releases from 4.08 to 5.4 (eleven versions).

In `opam-ci-check`, the `all_supported` list used to drive the full build matrix is updated to use `significant`:

```ocaml
let all_supported = Ocaml_version.Releases.significant @ Ocaml_version.Releases.unreleased_betas
```

The betas are only built on the master distro on x86_64, so this does not multiply out across the matrix.

# Alpine 3.23 and Ubuntu 25.10 and 26.04

[ocaml-dockerfile 8.3.5](https://github.com/ocurrent/ocaml-dockerfile/releases/tag/8.3.5) adds Alpine 3.23, replacing Alpine 3.22 and add Ubuntu 25.10. Additionally, [ocaml-dockerfile 8.3.6](https://github.com/ocurrent/ocaml-dockerfile/releases/tag/8.3.6) adds Ubuntu 26.04. No code changes are required in opam-repo-ci; pulling in the updated dockerfile package and bumping the pinned opam-repository SHA in the `Dockerfile` and `Dockerfile.web` is sufficient.

# Dropping i386 and Arm32

The `extras` function in `lib/build.ml` builds each non-master architecture against the two default compilers. Previously, this covered every arch in `Ocaml_version.arches` other than `X86_64`. [PR#467](https://github.com/ocurrent/opam-repo-ci/pull/467) dropped `Aarch32`; this has been extended to also drop `I386`:

```ocaml
List.filter_map (function
  | `X86_64 | `Aarch32 | `I386 -> None
  | `Riscv64 -> ...
  | arch -> ...
) Ocaml_version.arches
```

Neither architecture reflects a realistic target for modern opam packages, and both were a steady source of flaky builds that rarely surfaced genuine portability issues. See [Issue#366](https://github.com/ocurrent/opam-repo-ci/issues/466) for more information. [PR#346](https://github.com/ocurrent/docker-base-images/pull/346) proposes to stop build the 32-bit base images as well.
