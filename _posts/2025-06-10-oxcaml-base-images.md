---
layout: post
title: "Base images for OxCaml"
date: 2025-06-10 00:00:00 +0000
categories: oxcaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
permalink: /oxcaml-base-images/
---

As @dra27 suggested, I first added support in [ocurrent/ocaml-version](https://github.com/ocurrent/ocaml-version.git). I went with the name `flambda2`, which matched the name in the `opam` package.

Wherever I found the type `Flambda`, I added `Flambda2`. I added a list of OxCaml versions in the style of the unreleased betas and a function `is_oxcaml` to test if the variant is of type `Flambda2`, closely following the `is_multicore` design! The final change was to `additional_packages` concatenated `ocaml-options-only-` to `flambda2` - again, this change was also needed for multicore.

It was a relatively minor change to the base-image-builder, adding `Ocaml_version.Releases.oxcaml` to the available switches on AMD64 and ARM64. Following the precedent set by `maybe_add_beta` and `maybe_add_multicore`, I added `maybe_add_jst`, which added the Jane Street opam repository for these builds.

The builds mostly failed because they depended on `autoconf,` which isn't included by default on most distributions. Looking in the `dockerfile`, there is a function called `ocaml_depexts`, which includes `zstd` for OCaml > 5.1.0. I extended this function to include `autoconf` when building OxCaml.

The Arch Linux builds failed due to missing `which`, so I added this as I did for `autoconf`

The following are working:

- Ubuntu 24.10, 24.04, 22.04
- OpenSUSE Tumbleweed
- Fedora 42, 41
- Debian Unstable, Testing, 12
- Arch

Failures

- Alpine 3.21
  - missing `linux/auxvec.h` header
- OpenSUSE 15.6
  - autoconf is too old in the distribution
- Debian 11
  - autoconf is too old in the distribution
- Oracle Linux 9, 8
  - autoconf is too old in the distribution

There is some discussion about whether building these with the [base image builder](https://images.ci.ocaml.org) is the best approach, so I won't create PRs at this time. My branches are:
- [https://github.com/mtelvers/ocaml-version.git](https://github.com/mtelvers/ocaml-version.git)
- [https://github.com/mtelvers/ocaml-dockerfile.git#oxcaml](https://github.com/mtelvers/ocaml-dockerfile.git#oxcaml)
- [https://github.com/mtelvers/docker-base-images#oxcaml](https://github.com/mtelvers/docker-base-images#oxcaml)
