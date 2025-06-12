---
layout: post
title: "opam-repository for OxCaml"
date: 2025-06-12 00:00:00 +0000
categories: oxcaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

This morning, Anil proposed that having an opam-repository that didn't have old versions of the packages that require patches to work with OxCaml would be good.

This is a fast-moving area, so this post is likely to be outdated very quickly, but at the time of writing, the development repository is [https://github.com/janestreet/opam-repository#with-extensions](https://github.com/janestreet/opam-repository/tree/with-extensions). This is a fork of [opam-repository](https://github.com/ocaml/opam-repository) but with some patched packages designated with `+jst`.

I have a short shell script which clones both [opam-repository](https://github.com/ocaml/opam-repository) and [https://github.com/janestreet/opam-repository#with-extensions](https://github.com/janestreet/opam-repository/tree/with-extensions) and searches for all packages with `+jst`. All versions of these packages are removed from opam-repository and replaced with the single `+jst` version. The resulting repository is pushed to [https://github.com/mtelvers/opam-repository-jst](https://github.com/mtelvers/opam-repository-jst).

To test the repository (and show that `eio` doesn't build), I have created a `Dockerfile` based largely on the base-image-builder format. This `Dockerfile` uses this modified opam-repository to build an OxCaml switch.

My build script and test Dockerfile are in [https://github.com/mtelvers/opam-repo-merge] (https://github.com/mtelvers/opam-repo-merge). Thanks to David for being the sounding board during the day!

