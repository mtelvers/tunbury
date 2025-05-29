---
layout: post
title: "Worker moves"
date: 2025-05-09 12:00:00 +0000
categories: OBuilder,FreeBSD,OpenBSD
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Following the setup of _rosemary_ with [FreeBSD 14](https://www.tunbury.org/freebsd-uefi/) (with 20C/40T), I have paused _spring_ and _summer_ (which combined have 12C/24T) and _rosemary_ is now handling all of the [FreeBSD workload](https://github.com/ocurrent/freebsd-infra/pull/14).

_Oregano_ has now taken the OpenBSD workload from _bremusa_. _bremusa_ has been redeployed in the `linux-x86_64` pool. With the extra processing, I have paused the Scaleway workers _x86-bm-c1_ through _x86-bm-c9_.

These changes, plus the [removal of the Equnix machines](https://www.tunbury.org/equinix-moves/), are now reflected in [https://infra.ocaml.org](https://infra.ocaml.org).
