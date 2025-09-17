---
layout: post
title: "FreeBSD unionfs deadlock"
date: 2025-09-17 12:00:00 +0000
categories: FreeBSD,unionfs
tags: tunbury.org
image:
  path: /images/freebsd-logo.png
  thumbnail: /images/thumbs/freebsd-logo.png
---

FreeBSD Jails provide isolated system containers that are perfect for CI testing. Miod [ported OBuilder](https://tarides.com/blog/2023-10-04-porting-obuilder-to-freebsd/) to FreeBSD back in 2023. I have been looking at some different approaches using unionfs.

I'd like to have a read-only base layer with the OS, a middle layer containing source code and system libraries, and a top writable layer for the build results. This is easily constructed in an `fstab` for the `jail` like this.

```
/home/opam/bsd-1402000-x86_64/base/fs /home/opam/temp-2b9f69/work nullfs ro 0 0
/home/opam/temp-2b9f69/lower /home/opam/temp-2b9f69/work unionfs ro 0 0
/home/opam/temp-2b9f69/fs /home/opam/temp-2b9f69/work unionfs rw 0 0
/home/opam/opam-repository /home/opam/temp-2b9f69/work/home/opam/opam-repository nullfs ro 0 0
```

Running `jail -c name=temp-2b9f69 path=/home/opam/temp-2b9f69/work mount.devfs mount.fstab=/home/opam/temp-7323b6/fstab ...` works as expected; it's good enough to build OCaml, but it reliably deadlocks the entire machine when trying to build dune. This appears to be an old problem: [165087](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=165087), [201677](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=201677) and [unionfs](https://people.freebsd.org/~daichi/unionfs). There is a [project](https://freebsdfoundation.org/project/unionfs-stability-and-enhancement) aiming to improve unionfs for use in jails.

My workaround is to create a temporary layer that merges the base and lower layers together. Initially, I did this by mounting `tmpfs` to the lower mount point and using `cp` to copy the files. The performance was poor, so instead I created the layer on disk and used `cp -l` to hard link the files. The simplified `fstab` works successfully in my testing.

```
/home/opam/temp-2b9f69/lower /home/opam/temp-2b9f69/work nullfs ro 0 0
/home/opam/temp-2b9f69/fs /home/opam/temp-2b9f69/work unionfs rw 0 0
/home/opam/opam-repository /home/opam/temp-2b9f69/work/home/opam/opam-repository nullfs ro 0 0
```

FreeBSD protects key system files by marking them as immutable; this prevents hard links to the files. Therefore, I needed to remove these flags after the `bsdinstall` has completed. `chflags -R 0 basefs`

