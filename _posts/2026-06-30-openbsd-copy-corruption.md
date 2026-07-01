---
layout: post
title: "Corrupt copies on the OpenBSD CI worker"
date: 2026-06-30 21:00:00 +0000
categories: [openbsd, obuilder]
tags: tunbury.org
image:
  path: /images/openbsd-logo.png
  thumbnail: /images/thumbs/openbsd-logo.png
---

[Last week]({% post_url 2026-06-26-week-26-2025 %}) I updated the OpenBSD workers to OCaml 5.5.0 and took that opportunity to deploy OpenBSD 7.8. Shortly after, [issue#1061](https://github.com/ocurrent/ocaml-ci/issues/1061) was opened as jobs randomly failed with an opam parse error.

The log reported:

```
[ERROR] At /home/opam/.opam/5.5.0/.opam-switch/sources/tls/tls.opam:1:0-1:1::
Parse error [skipped]
[ERROR] No valid package definition found for tls
```

As Hannes wrote, "It is very unclear why on OpenBSD an opam parse error exists."

`tls.opam` is a perfectly ordinary opam file `opam-version: "2.0"`. To rule out opam itself, I booted the base image and pinned a copy fetched inside the VM:

```
$ opam pin add -yn tls.dev ~/srctest/
tls is now pinned to file:///home/opam/srctest (version dev)
```

Perfect, so opam on OpenBSD 7.8 works as expected and `tls.opam` is fine.

[ocurrent/obuilder](https://github.com/ocurrent/obuilder) will have cached the failing step, so the exact file was sitting in a result layer cache on the worker. The QEMU store keeps each layer as a qcow2, so I made a read-only overlay of that exact layer, booted it, and pulled the files out. Every `.opam` file had the correct size but the wrong contents:

```
tls.opam            DIFFERS (data)        <- an FFS directory block
tls-async.opam      DIFFERS (ASCII text)  <- the ocaml-zxcvbn opam file
tls-lwt.opam        DIFFERS (ASCII text)  <- the opam-repository config
```

Right names, right lengths, but the data blocks held whatever was on disk before. other packages' opam files, repository metadata, and a raw directory block. This is the unmistakable signature of FFS soft-updates after an unclean shutdown: the metadata (inode, size, directory entry) is committed, but the file data never reached the disk.

```
(copy (src tls.opam) (dst /home/opam/src/./))
```

obuilder copies files into the sandbox by streaming `ocaml-tar` into the guests `tar`. This process is the same regardless of the backend: an OpenBSD QEMU machine, a FreeBSD jail, or a Linux or Windows container. After the copy, the container is stopped and the cache layer committed. In the QEMU case, obuilder sends an ACPI power-down event and, if the guest has not stopped within `--qemu-boot-time` (30 seconds), it issues a hard `quit`.

In isolation, the guest powers off in <15 s, and the data survives. Under the worker's concurrent load, a clean shutdown may overrun the 30s allocation, and `quit` is the instant stop, like pulling out the power cable. I reproduced it by interrupting the shutdown: 5 of 5 copies corrupted without a sync, 0 of 5 with one.

The fix is to run `sync` before powering off. This avoids the 30-second timer, as normal command blocks are not subject to time limits. Regardless of how long the sync takes, the builder will wait, and then the normal shutdown process applies. ACPI followed by a hard power off after 30 seconds. [ocurrent/obuilder#212](https://github.com/ocurrent/obuilder/pull/212).

I recompiled the worker code to test the fix, wiped all the cache layers, and restarted with `unpause && sleep 1 && pause`, effectively running only 10 jobs. The parse errors were gone, but now jobs were failing at the `copy` step with something new. [Issue#1064](https://github.com/ocurrent/ocaml-ci/issues/1064).

```
gtar: home: Cannot utime: Operation not permitted
gtar: Exiting with failure status due to previous errors
```

The copy tar carries a directory entry for every ancestor of the destination (`Tar_transfer` emits these for extractors that cannot auto-create parents, such as Windows bsdtar). On extraction, `gtar` dutifully restores each directory's mtime and mode. The QEMU backend connects as the unprivileged `opam` user, so when it reaches the pre-existing, root-owned `/home`, it cannot update it and fails.

The QEMU backend is a bit of an oddity as every other obuilder backend - runc, docker, hcs, jail - extracts the tar as `root`. Only QEMU does it as `opam`.

My first thought was that OpenBSD 7.8 had shipped a newer, stricter tar. However, 7.7 and 7.8 both ship GNU tar 1.35 and fail identically with the same archive. The trigger was the obuilder's ancestor directory entries, which were added for Windows HCS. `--no-overwrite-dir` was tempting, but only moves the failure from `utime` to `chmod`.

The fix is to extract under `doas`, so the copy runs as root like every other backend; the tar headers still carry the target uid/gid, so the files remain `opam` owned. [ocurrent/obuilder#213](https://github.com/ocurrent/obuilder/pull/213).
