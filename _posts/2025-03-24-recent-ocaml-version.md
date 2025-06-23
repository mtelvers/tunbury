---
layout: post
title:  "Recent OCaml Versions"
date:   2025-03-24 00:00:00 +0000
categories: OCaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
permalink: /recent-ocaml-version/
---

Following my [post on discuss.ocaml.org](https://discuss.ocaml.org/t/docker-base-images-and-ocaml-ci-support-for-ocaml-4-08/16229), I have created a new release of [ocurrent/ocaml-version](https://github.com/ocurrent/ocaml-version) that moves the minimum version of OCaml, considered as _recent_, from 4.02 to 4.08.

```ocaml
let recent = [ v4_08; v4_09; v4_10; v4_11; v4_12; v4_13; v4_14; v5_0; v5_1; v5_2; v5_3 ]
```

This may feel like a mundane change, but [OCaml-CI](https://github.com/ocurrent/ocaml-ci), [opam-repo-ci](https://github.com/ocurrent/opam-repo-ci), [Docker base image builder](https://github.com/ocurrent/docker-base-images) among other things, use this to determine the set of versions of OCaml to test against. Therefore, as these services are updated, testing on the old releases will be removed.
