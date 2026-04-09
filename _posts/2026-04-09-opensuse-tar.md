---
layout: post
title: "The CVE fix that broke CI"
date: 2026-04-09 14:30:00 +0000
categories: ocaml,ci
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Recently opam-repo-ci jobs started failing on openSUSE Leap 15.6. The error looked like a disk space problem with thousands of lines of `tar: Cannot mkdir: No such file or directory` during the `copy` step. However, the file system wasn't full.

This post walks through tracking this bug from the misleading error message to the satisfying discovery of the exact cause.

# Bug Report

[ocurrent/ocluster](https://github.com/ocurrent/ocluster) distributes build jobs to workers running [ocurrent/obuilder](https://github.com/ocurrent/obuilder). Each build step produces a filesystem layer, and [ocurrent/obuilder](https://github.com/ocurrent/obuilder) overlayfs store stacks them before running the next build step. The [ocurrent/obuilder](https://github.com/ocurrent/obuilder) spec closely matches a Dockerfile but written as s-expressions.

The bug was first reported by Jan and independently tracked as [issue #184](https://github.com/ocaml/infrastructure/issues/184).

The failing step was a `copy` operation that tars the opam-repository source tree into the build container:

```
(copy (src .) (dst opam-repository/))
```

The build log showed every single file failing:

```
tar: home/opam/opam-repository/./.gitattributes: Cannot open: No such file or directory
tar: home/opam/opam-repository/./.github: Cannot mkdir: No such file or directory
tar: home/opam/opam-repository/./.github/dependabot.yml: Cannot open: No such file or directory
```

All files failed, not just some.

# First hypotheses: space, inodes

The worker, `bremusa`, runs Ubuntu 24.04 with kernel 6.8 and an overlayfs store on a 400 GB tmpfs:

```
$ df /var/cache/obuilder/
Filesystem     1K-blocks    Used Available Use% Mounted on
tmpfs          419430400 9720028 409710372   3% /var/cache/obuilder

$ df -i /var/cache/obuilder/
Filesystem       Inodes   IUsed    IFree IUse% Mounted on
tmpfs          41258002 1097685 40160317    3% /var/cache/obuilder
```

We've previously seen [issue #121](https://github.com/ocaml/infrastructure/issues/121) where tar failed to extract due to Docker/libseccomp version issues.

# Into the Overlayfs Layers

Inspecting the actual overlayfs layers for this build on the worker, found the openSUSE 15.6 opam image base image (`e5f7bd54...`) already contained `/home/opam/opam-repository`. The build spec runs `rm -rf opam-repository/` in the step before the copy (`f4ff71...`), which correctly shows the overlayfs whiteout a character device `(0,0)`.

```
$ ls -la .../result/f4ff71.../rootfs/home/opam/
total 0
drwxr-xr-x 2 caelum caelum   60 Apr  9 07:48 .
drwxr-xr-x 3 root   root     60 Apr  4 08:18 ..
c--------- 1 root   root   0, 0 Apr  9 07:48 opam-repository
```

I manually recreated the overlayfs mount using the same layer chain and tested directory creation:

```
$ mount -t overlay overlay -olowerdir=... /tmp/test/merged
$ mkdir /tmp/test/merged/rootfs/home/opam/opam-repository
$ echo $?
0
```

This worked perfectly; the whiteout was respected, and the new directory was created. Overlayfs itself was operating as expected.

# Reproducing in runc

I often find that when debugging, I want to get to the exact state where the bug occurs, run that one line, and see the failure for myself. [ocurrent/obuilder](https://github.com/ocurrent/obuilder) runs tar inside an runc container, so I built a minimal OCI config pointing at the overlayfs merged rootfs and ran tar with the same paths that [ocurrent/obuilder](https://github.com/ocurrent/obuilder) generates:

```
$ runc run --bundle /tmp/test test-tar < test.tar
home/opam/opam-repository/./
home/opam/opam-repository/./.gitattributes
tar: home/opam/opam-repository/./.gitattributes: Cannot open: No such file or directory
```

Excellent, the bug can be reproduced manually. How about `mkdir` inside the container instead of tar:

```
$ runc run --bundle /tmp/test test-mkdir
mkdir /home/opam/opam-repository && echo OK
OK
```

That worked, so the filesystem, overlayfs, and runc were all fine. The issue was specific to how tar handled the extraction.

# The extra `./` in the path

We all saw that extra `./` in the paths in the tar archive: `home/opam/opam-repository/./`. That comes from [ocurrent/obuilder](https://github.com/ocurrent/obuilder)'s `tar_transfer.ml`:

```ocaml
and send_dir ~src_dir ~dst ~to_untar ~user items =
  items |> Lwt_list.iter_s (function
      | `Dir (src, items) ->
        let dst = dst / Filename.basename src in
        copy_dir ~src_dir ~src ~dst ~items ~to_untar ~user
    )
```

When the copy source is `.`, `Manifest.generate` produces `Dir("", items)` (empty string for the directory name). Then `Filename.basename ""` returns `"."` in OCaml, producing tar paths like `home/opam/opam-repository/./.gitattributes`.

This is semantically valid as `./` is just the current directory. But testing with and without it shows a clear difference:

| Tar path format | Result |
|---|---|
| `home/opam/opam-repository/./.gitattributes` | FAIL |
| `home/opam/opam-repository/.gitattributes` | PASS |

# Systematic elimination

It fails, with `runc`, but what about overlayfs with `chroot`, or just overlayfs, or just `chroot`?

| Test | Method | Result |
|---|---|---|
| overlayfs + chroot | `chroot /overlay/rootfs tar -xvf -` | FAIL |
| overlayfs + no chroot | `tar -C /overlay/rootfs -xvf test.tar` | PASS |
| plain tmpfs + chroot | `chroot /tmpfs/rootfs tar -xvf -` | FAIL |

`chroot` with `./` in the tar paths was enough to reproduce the problem. What about using the host's tar?

| Tar version | Inside chroot on overlayfs | Result |
|---|---|---|
| 1.34 (openSUSE container) | Yes | FAIL |
| 1.35 (Ubuntu host) | Yes | PASS |

# Too much detail: strace

I could have left it there; openSUSE's tar doesn't play well with `./` paths, but instead I straced both versions extracting the same archive inside a chroot.

tar 1.34 uses file-descriptor-based path walking for safe extraction. It opens each path component with `openat()` relative to the parent directory's fd:

```
openat(AT_FDCWD, "home", O_PATH|O_DIRECTORY) = 3
openat(3, "opam", O_PATH|O_DIRECTORY) = 4
openat(4, "brand-new-dir", O_PATH|O_DIRECTORY) = 3
openat(3, "", O_PATH|O_DIRECTORY) = -1 ENOENT   ← empty string!
```

The `./` in the path splits into directory components `"."` and `""` (the empty string after the trailing slash). `openat(fd, "")` always returns `ENOENT` as you cannot open an empty filename! The file creation fails, and tar's error recovery (`maybe_recoverable`) calls `make_directories`, which finds all directories already exist, sets `*interdir_made = false`, and the old recovery code gives up:

```c
// tar 1.34: recovery requires a directory to have been created
if (make_directories(file_name, interdir_made) == 0 && *interdir_made)
    return RECOVER_OK;
```

tar 1.35 uses `AT_FDCWD` for relative full paths instead of fd walking:

```
mkdirat(AT_FDCWD, "home/opam/brand-new-dir/.", 0700) = -1 EEXIST
openat(AT_FDCWD, "home/opam/brand-new-dir/./.gitattributes",
       O_WRONLY|O_CREAT|O_EXCL, 0600) = 3    <- works!
```

The kernel resolves `brand-new-dir/./.gitattributes` as a single path lookup, which handles the `./` correctly. tar 1.35 also removed the `*interdir_made` from the recovery path (commits [79a442d7](https://cgit.git.savannah.gnu.org/cgit/tar.git/commit/?id=79a442d7) and [79d1ac38](https://cgit.git.savannah.gnu.org/cgit/tar.git/commit/?id=79d1ac38)), so even if file creation fails transiently, the retry succeeds.

However, [ocurrent/obuilder](https://github.com/ocurrent/obuilder) has generated paths with `./` forever, so what changed? openSUSE Leap has always shipped tar 1.34 across the entire 15.x release. The race condition fixes were backported to openSUSE's tar in June 2022. So why did this just start breaking (in April 2026)?

The rpm changelog for tar on OpenSUSE shows a recent update:

```
* Mon Mar 23 2026 martin.schreiner@suse.com
- Fix bsc#1246399 / CVE-2025-45582.
- Add patch:
  * CVE-2025-45582.patch
```

[CVE-2025-45582](https://www.suse.com/security/cve/CVE-2025-45582.html) is a directory traversal vulnerability where an attacker can craft two tar archives to overwrite files outside the extraction directory. The first tar plants a symlink like `x -> ../../../.ssh`, the second contains `x/authorized_keys`. The fix is exactly the fd-based safe extraction we saw in the strace: walk each path component using `openat()` with directory file descriptors, verifying at each step that you haven't followed a symlink out of the target tree.

openSUSE applied this patch to their tar 1.34 on 23 March 2026 about three weeks before our builds started failing. The lag comes as we only build Docker base [images](https://images.ci.ocaml.org) once a week and [opam-repo-ci](https://opam.ci.ocaml.org) caches them for two weeks. The patch introduced the fd-based path walking code, but the openSUSE 1.34 package didn't have the complete fix for the empty-component edge case that upstream tar 1.35 handles via its `AT_FDCWD` relative approach and the `maybe_recoverable` improvements.

# Summary and fix

1. OBuilder's `Manifest.generate` returns `Dir("", items)` when the copy source is `.`
2. `Filename.basename ""` returns `"."` in OCaml
3. Tar paths become `home/opam/opam-repository/./.gitattributes`
4. The `./` is semantically valid and was always harmless
5. 23 March 2026 openSUSE patches tar 1.34 for CVE-2025-45582, adding fd-based safe extraction
6. The new code splits paths by `/`, producing an empty `""` component from the `./`
7. `openat(fd, "")` returns `ENOENT`
8. The recovery code finds all directories already exist but doesn't retry because its logic doesn't cover this edge case
9. Every file in the opam-repository fails to extract

The immediate fix is to eliminate the `./` from OBuilder's tar paths by handling the `Filename.basename ""` edge case in `tar_transfer.ml`. The `./` was never intentional; it is an artefact of OCaml's `Filename.basename` returning `"."` for the empty string.

[PR#205](https://github.com/ocurrent/obuilder/pull/205) will need to be deployed to all the workers that perform OpenSUSE builds.
