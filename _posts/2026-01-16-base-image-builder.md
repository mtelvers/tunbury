---
layout: post
title: "Base Image Builder"
date: 2026-01-16 17:20:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

The base image builder has a growing number of failed builds; it's time to address these.

# OCaml < 5.1 with GCC >= 15

Distributions that have moved to GCC 15 have had failing builds since last [April](https://github.com/ocurrent/docker-base-images/issues/320). This affects builds older than OCaml 5.1.1 but not OCaml 4.14.2.

```
# gcc -c -O2 -fno-strict-aliasing -fwrapv -pthread -g -Wall -fno-common -fexcess-precision=standard -ffunction-sections  -I./runtime  -D_FILE_OFFSET_BITS=64  -DCAMLDLLIMPORT= -DIN_CAML_RUNTIME -DDEBUG  -o runtime/main.bd.o runtime/main.c
In file included from runtime/interp.c:34:
runtime/interp.c: In function 'caml_interprete':
runtime/caml/prims.h:33:23: error: too many arguments to function '(value (*)(void))*(caml_prim_table.contents + (sizetype)((long unsigned int)*pc * 8))'; expected 0, have 1
33 | #define Primitive(n) ((c_primitive)(caml_prim_table.contents[n]))
   |                      ~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
runtime/interp.c:1037:14: note: in expansion of macro 'Primitive'
1037 |       accu = Primitive(*pc)(accu);
     |              ^~~~~~~~~
```

I was about to create the patches, but I noticed that @dra27 had already done so. [ocaml-opam/ocaml](https://github.com/ocaml-opam/ocaml/branches). The patches can be added as an overlay repository. I have done this before for GCC 14 when a similar issue occurred for OCaml < 4.08. [PR#298](https://github.com/ocurrent/docker-base-images/pull/298). The new PR is [PR#337](https://github.com/ocurrent/docker-base-images/pull/337)

# Ubuntu 25.10

The GCC 15 patch resolved most Ubuntu issues, but Ubuntu 25.10 persisted. Ubuntu 25.10 switched to the Rust-based Coreutils, which does not support commas in the install command until version 0.5.0. Ubuntu 25.10 ships with 0.2.2. 

```
#9 137.0 # /usr/bin/install -c -m u=rw,g=rw,o=r \
#9 137.0 #   VERSION \
#9 137.0 #   "/home/opam/.opam/4.09/lib/ocaml"
#9 137.0 # /usr/bin/install: Invalid mode string: invalid operator (expected +, -, or =, but found ,)
```

[PR#255](https://github.com/ocurrent/ocaml-dockerfile/pull/255) switches to GNU Coreutils. I expect this problem will be cleared in subsequent releases of Ubuntu.

# Windows

The Windows workers needed to be updated to Windows Server 2025, as older kernels cannot run newer containers. Furthermore, the OCluster code is not yet using native Windows opam.

The Windows Server virtual machines are created with Packer. I've pushed my scripts to [mtelvers/packer](https://github.com/mtelvers/packer).

OCluster worker is deployed using Ansible. My scripts are at [mtelvers/windows_worker](https://github.com/mtelvers/windows_worker).

