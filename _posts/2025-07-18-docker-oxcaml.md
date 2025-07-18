---
layout: post
title:  "Docker Container for OxCaml"
date:   2025-07-18 18:00:00 +0000
categories: oxcaml
image:
  path: /images/oxcaml.png
  thumbnail: /images/thumbs/oxcaml.png
---

Jon asked me to make a Docker image that contains [OxCaml](https://oxcaml.org) ready to run without the need to build it from scratch.

I have written a simple OCurrent pipeline to periodically poll [oxcaml/opam-repository](https://github.com/oxcaml/opam-repository). If the SHA has changed, it builds a Docker image and pushes it to current/opam-staging:oxcaml.

The resulting image can be run like this:

```sh
$ docker run --rm -it ocurrent/opam-staging:oxcaml
ubuntu@146eab4efc18:/$ ocaml
OCaml version 5.2.0+ox
Enter
#help;; for help.

#
```

The exact content of the image may change depending upon requirements, and we should also pick a better place to put it rather than ocurrent/opam-staging!

The pipeline code is available here [mtelvers/docker-oxcaml](https://github.com/mtelvers/docker-oxcaml) and the service is deployed at [oxcaml.image.ci.dev](https://oxcaml.image.ci.dev).
