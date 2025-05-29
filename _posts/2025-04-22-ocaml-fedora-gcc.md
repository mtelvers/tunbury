---
layout: post
title:  "OCaml < 4.14, Fedora 42 and GCC 15"
date:   2025-04-22 00:00:00 +0000
categories: OCaml,Fedora,GCC
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Late last week, @MisterDA added Fedora 42 support to the [Docker base image builder](https://images.ci.ocaml.org). The new base images attempted to build over the weekend, but there have been a few issues!

The code I had previously added to force Fedora 41 to use the DNF version 5 syntax was specifically for version 41. For reference, the old syntax was `yum groupinstall -y 'C Development Tools and Libraries’`, and the new syntax is `yum group install -y 'c-development'`. Note the extra space.

```ocaml
let c_devtools_libs : (t, unit, string, t) format4 =
  match d with
  | `Fedora `V41 -> {|"c-development"|}
  | `Fedora _ -> {|"C Development Tools and Libraries"|}
  | _ -> {|"Development Tools”|}
...
let dnf_version = match d with `Fedora `V41 -> 5 | _ -> 3
```

To unburden ourselves of this maintenance in future releases, I have inverted the logic so unmatched versions will use the new syntax.

```ocaml
let (dnf_version, c_devtools_libs) : int * (t, unit, string, t) format4 =
  match d with
  | `Fedora
    ( `V21 | `V22 | `V23 | `V24 | `V25 | `V26 | `V27 | `V28 | `V29
    | `V30 | `V31 | `V32 | `V33 | `V34 | `V35 | `V36 | `V37 | `V38
    | `V39 | `V40 ) ->
    (3, {|"C Development Tools and Libraries"|})
  | `Fedora _ -> (5, {|"c-development"|})
  | _ -> (3, {|"Development Tools"|})
```

Fedora 42 also removed `awk`, so it now needs to be specifically included as a dependency. However, this code is shared with Oracle Linux, which does not have a package called `awk`. Fortunately, both have a package called `gawk`!

The next issue is that Fedora 42 is the first of the distributions we build base images for that has moved to GCC 15, specifically GCC 15.0.1. This breaks all versions of OCaml < 4.14.

The change is that the code below, which previously gave no information about the number or type of parameters. (see `runtime/caml/prims.h`)

```c
typedef value (*c_primitive)();
```

Now means that there are no parameters, aka:

```c
typedef value (*c_primitive)(void);
```

This is caused by a change of the default compilter language version. See [GCC change log](https://gcc.gnu.org/gcc-15/changes.html)

> C23 by default: GCC 15 changes the default language version for C compilation from `-std=gnu17` to `-std=gnu23`. If your code relies on older versions of the C standard, you will need to either add `-std=` to your build flags, or port your code; see the porting notes.

Also see the [porting notes](https://gcc.gnu.org/gcc-15/porting_to.html#c23), and [this bug report](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=118112).

This is _not_ an immediate problem as OCaml-CI and opam-repo-ci only test against OCaml 4.14.2 and 5.3.0 on Fedora. I have opened [issue#320](https://github.com/ocurrent/docker-base-images/issues/320) to track this problem.

