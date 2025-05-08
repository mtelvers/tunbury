---
layout: post
title: "Debugging OBuilder on macOS"
date: 2025-05-08 12:00:00 +0000
categories: macOS,OBuilder
tags: tunbury.org
image:
  path: /images/obuilder.png
  thumbnail: /images/obuilder.png
---


The log from an OBuilder job starts with the steps needed to reproduce the job locally. This boilerplate output assumes that all OBuilder jobs start from a Docker base image, but on some operating systems, such as FreeBSD and macOS, OBuilder uses ZFS base images. On OpenBSD and Windows, it uses QEMU images. The situation is further complicated when the issue only affects a specific architecture that may be unavailable to the user.

```
2025-05-08 13:29.37: New job: build bitwuzla-cxx.0.7.0, using opam 2.3
                              from https://github.com/ocaml/opam-repository.git#refs/pull/27768/head (55a47416d532dc829d9111297970934a21a1b1c4)
                              on macos-homebrew-ocaml-4.14/amd64

To reproduce locally:

cd $(mktemp -d)
git clone --recursive "https://github.com/ocaml/opam-repository.git" && cd "opam-repository" && git fetch origin "refs/pull/27768/head" && git reset --hard 55a47416
git fetch origin master
git merge --no-edit b8a7f49af3f606bf8a22869a1b52b250dd90092e
cat > ../Dockerfile <<'END-OF-DOCKERFILE'

FROM macos-homebrew-ocaml-4.14
USER 1000:1000
RUN ln -f ~/local/bin/opam-2.3 ~/local/bin/opam
RUN opam init --reinit -ni
RUN opam option solver=builtin-0install && opam config report
ENV OPAMDOWNLOADJOBS="1"
ENV OPAMERRLOGLEN="0"
ENV OPAMPRECISETRACKING="1"
ENV CI="true"
ENV OPAM_REPO_CI="true"
RUN rm -rf opam-repository/
COPY --chown=1000:1000 . opam-repository/
RUN opam repository set-url -k local --strict default opam-repository/
RUN opam update --depexts || true
RUN opam pin add -k version -yn bitwuzla-cxx.0.7.0 0.7.0
RUN opam reinstall bitwuzla-cxx.0.7.0; \
    res=$?; \
    test "$res" != 31 && exit "$res"; \
    export OPAMCLI=2.0; \
    build_dir=$(opam var prefix)/.opam-switch/build; \
    failed=$(ls "$build_dir"); \
    partial_fails=""; \
    for pkg in $failed; do \
    if opam show -f x-ci-accept-failures: "$pkg" | grep -qF "\"macos-homebrew\""; then \
    echo "A package failed and has been disabled for CI using the 'x-ci-accept-failures' field."; \
    fi; \
    test "$pkg" != 'bitwuzla-cxx.0.7.0' && partial_fails="$partial_fails $pkg"; \
    done; \
    test "${partial_fails}" != "" && echo "opam-repo-ci detected dependencies failing: ${partial_fails}"; \
    exit 1


END-OF-DOCKERFILE
docker build -f ../Dockerfile .
```

It is, therefore, difficult to diagnose the issue on these operating systems and on esoteric architectures. Is it an issue with the CI system or the job itself?

My approach is to get myself into an interactive shell at the point in the build where the failure occurs. On Linux and FreeBSD, the log is available in `/var/log/syslog` or `/var/log/messages` respectively. On macOS, this log is written to `ocluster.log`. macOS workers are single-threaded, so the worker must be paused before progressing.

Each step in an OBuilder job consists of taking a snapshot of the previous layer, running a command in that layer, and keeping or discarding the layer depending on the command’s success or failure. On macOS, layers are ZFS snapshots mounted over the Homebrew directory and the CI users’ home directory. We can extract the appropriate command from the logs.

```
2025-05-08 14:31.17    application [INFO] Exec "zfs" "clone" "-o" "canmount=noauto" "--" "obuilder/result/a67e6d3b460fa52b5c57581e7c01fa74ddca0a0b5462fef34103a09e87f3feec@snap" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40"
2025-05-08 14:31.17    application [INFO] Exec "zfs" "mount" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40"
2025-05-08 14:31.17    application [INFO] Exec "zfs" "clone" "-o" "mountpoint=none" "--" "obuilder/result/a67e6d3b460fa52b5c57581e7c01fa74ddca0a0b5462fef34103a09e87f3feec/brew@snap" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40/brew"
2025-05-08 14:31.17    application [INFO] Exec "zfs" "clone" "-o" "mountpoint=none" "--" "obuilder/result/a67e6d3b460fa52b5c57581e7c01fa74ddca0a0b5462fef34103a09e87f3feec/home@snap" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40/home"
cannot open 'obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40@snap': dataset does not exist
2025-05-08 14:31.17    application [INFO] Exec "zfs" "clone" "--" "obuilder/cache/c-opam-archives@snap" "obuilder/cache-tmp/8608-c-opam-archives"
2025-05-08 14:31.17    application [INFO] Exec "zfs" "clone" "--" "obuilder/cache/c-homebrew@snap" "obuilder/cache-tmp/8609-c-homebrew"
2025-05-08 14:31.18       obuilder [INFO] result_tmp = /Volumes/obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40
2025-05-08 14:31.18    application [INFO] Exec "zfs" "set" "mountpoint=/Users/mac1000" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40/home"
2025-05-08 14:31.18    application [INFO] Exec "zfs" "set" "mountpoint=/usr/local" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40/brew"
2025-05-08 14:31.18       obuilder [INFO] src = /Volumes/obuilder/cache-tmp/8608-c-opam-archives, dst = /Users/mac1000/.opam/download-cache, type rw
2025-05-08 14:31.18    application [INFO] Exec "zfs" "set" "mountpoint=/Users/mac1000/.opam/download-cache" "obuilder/cache-tmp/8608-c-opam-archives"
Unmount successful for /Volumes/obuilder/cache-tmp/8608-c-opam-archives
2025-05-08 14:31.18       obuilder [INFO] src = /Volumes/obuilder/cache-tmp/8609-c-homebrew, dst = /Users/mac1000/Library/Caches/Homebrew, type rw
2025-05-08 14:31.18    application [INFO] Exec "zfs" "set" "mountpoint=/Users/mac1000/Library/Caches/Homebrew" "obuilder/cache-tmp/8609-c-homebrew"
Unmount successful for /Volumes/obuilder/cache-tmp/8609-c-homebrew
2025-05-08 14:31.19    application [INFO] Exec "sudo" "dscl" "." "list" "/Users"
2025-05-08 14:31.19    application [INFO] Exec "sudo" "-u" "mac1000" "-i" "getconf" "DARWIN_USER_TEMP_DIR"
2025-05-08 14:31.19    application [INFO] Fork exec "sudo" "su" "-l" "mac1000" "-c" "--" "source ~/.obuilder_profile.sh && env 'TMPDIR=/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/' 'OPAM_REPO_CI=true' 'CI=true' 'OPAMPRECISETRACKING=1' 'OPAMERRLOGLEN=0' 'OPAMDOWNLOADJOBS=1' "$0" "$@"" "/usr/bin/env" "bash" "-c" "opam reinstall bitwuzla-cxx.0.7.0;
        res=$?;
        test "$res" != 31 && exit "$res";
        export OPAMCLI=2.0;
        build_dir=$(opam var prefix)/.opam-switch/build;
        failed=$(ls "$build_dir");
        partial_fails="";
        for pkg in $failed; do
          if opam show -f x-ci-accept-failures: "$pkg" | grep -qF "\"macos-homebrew\""; then
            echo "A package failed and has been disabled for CI using the 'x-ci-accept-failures' field.";
          fi;
          test "$pkg" != 'bitwuzla-cxx.0.7.0' && partial_fails="$partial_fails $pkg";
        done;
        test "${partial_fails}" != "" && echo "opam-repo-ci detected dependencies failing: ${partial_fails}”;
        exit 1"
2025-05-08 14:31.28         worker [INFO] OBuilder partition: 27% free, 2081 items
2025-05-08 14:31.58         worker [INFO] OBuilder partition: 27% free, 2081 items
2025-05-08 14:32.28         worker [INFO] OBuilder partition: 27% free, 2081 items
2025-05-08 14:32.43    application [INFO] Exec "zfs" "inherit" "mountpoint" "obuilder/cache-tmp/8608-c-opam-archives"
Unmount successful for /Users/mac1000/.opam/download-cache
2025-05-08 14:32.44    application [INFO] Exec "zfs" "inherit" "mountpoint" "obuilder/cache-tmp/8609-c-homebrew"
Unmount successful for /Users/mac1000/Library/Caches/Homebrew
2025-05-08 14:32.45    application [INFO] Exec "zfs" "set" "mountpoint=none" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40/home"
Unmount successful for /Users/mac1000
2025-05-08 14:32.45    application [INFO] Exec "zfs" "set" "mountpoint=none" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40/brew"
Unmount successful for /usr/local
2025-05-08 14:32.46    application [INFO] Exec "zfs" "rename" "--" "obuilder/cache/c-homebrew" "obuilder/cache-tmp/8610-c-homebrew"
Unmount successful for /Volumes/obuilder/cache/c-homebrew
2025-05-08 14:32.46    application [INFO] Exec "zfs" "promote" "obuilder/cache-tmp/8609-c-homebrew"
2025-05-08 14:32.46    application [INFO] Exec "zfs" "destroy" "-f" "--" "obuilder/cache-tmp/8610-c-homebrew"
Unmount successful for /Volumes/obuilder/cache-tmp/8610-c-homebrew
2025-05-08 14:32.48    application [INFO] Exec "zfs" "rename" "--" "obuilder/cache-tmp/8609-c-homebrew@snap" "obuilder/cache-tmp/8609-c-homebrew@old-2152"
2025-05-08 14:32.48    application [INFO] Exec "zfs" "destroy" "-d" "--" "obuilder/cache-tmp/8609-c-homebrew@old-2152"
2025-05-08 14:32.48    application [INFO] Exec "zfs" "snapshot" "-r" "--" "obuilder/cache-tmp/8609-c-homebrew@snap"
2025-05-08 14:32.48    application [INFO] Exec "zfs" "rename" "--" "obuilder/cache-tmp/8609-c-homebrew" "obuilder/cache/c-homebrew"
Unmount successful for /Volumes/obuilder/cache-tmp/8609-c-homebrew
2025-05-08 14:32.49    application [INFO] Exec "zfs" "rename" "--" "obuilder/cache/c-opam-archives" "obuilder/cache-tmp/8611-c-opam-archives"
Unmount successful for /Volumes/obuilder/cache/c-opam-archives
2025-05-08 14:32.50    application [INFO] Exec "zfs" "promote" "obuilder/cache-tmp/8608-c-opam-archives"
2025-05-08 14:32.50    application [INFO] Exec "zfs" "destroy" "-f" "--" "obuilder/cache-tmp/8611-c-opam-archives"
Unmount successful for /Volumes/obuilder/cache-tmp/8611-c-opam-archives
2025-05-08 14:32.51    application [INFO] Exec "zfs" "rename" "--" "obuilder/cache-tmp/8608-c-opam-archives@snap" "obuilder/cache-tmp/8608-c-opam-archives@old-2152"
2025-05-08 14:32.51    application [INFO] Exec "zfs" "destroy" "-d" "--" "obuilder/cache-tmp/8608-c-opam-archives@old-2152"
2025-05-08 14:32.51    application [INFO] Exec "zfs" "snapshot" "-r" "--" "obuilder/cache-tmp/8608-c-opam-archives@snap"
2025-05-08 14:32.52    application [INFO] Exec "zfs" "rename" "--" "obuilder/cache-tmp/8608-c-opam-archives" "obuilder/cache/c-opam-archives"
Unmount successful for /Volumes/obuilder/cache-tmp/8608-c-opam-archives
2025-05-08 14:32.52    application [INFO] Exec "zfs" "destroy" "-r" "-f" "--" "obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40"
Unmount successful for /Volumes/obuilder/result/af09425cd7744c7b32ed000b11db90295142f3d3430fddb594932d5c02343b40
2025-05-08 14:32.58         worker [INFO] OBuilder partition: 27% free, 2081 items
2025-05-08 14:33.04         worker [INFO] Job failed: "/usr/bin/env" "bash" "-c" "opam reinstall bitwuzla-cxx.0.7.0;
        res=$?;
        test "$res" != 31 && exit "$res";
        export OPAMCLI=2.0;
        build_dir=$(opam var prefix)/.opam-switch/build;
        failed=$(ls "$build_dir");
        partial_fails="";
        for pkg in $failed; do
          if opam show -f x-ci-accept-failures: "$pkg" | grep -qF "\"macos-homebrew\""; then
            echo "A package failed and has been disabled for CI using the 'x-ci-accept-failures' field.";
          fi;
          test "$pkg" != 'bitwuzla-cxx.0.7.0' && partial_fails="$partial_fails $pkg";
        done;
        test "${partial_fails}" != "" && echo "opam-repo-ci detected dependencies failing: ${partial_fails}";
        exit 1" failed with exit status 1

```

Run each of the _Exec_ commands at the command prompt up to the _Fork exec_. We do need to run it, but we want an interactive shell, so let’s change the final part of the command to `bash`:

```
sudo su -l mac1000 -c -- "source ~/.obuilder_profile.sh && env 'TMPDIR=/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/' 'OPAM_REPO_CI=true' 'CI=true' 'OPAMPRECISETRACKING=1' 'OPAMERRLOGLEN=0' 'OPAMDOWNLOADJOBS=1' bash"
```

Now, at the shell prompt, we can try `opam reinstall bitwuzla-cxx.0.7.0`. Hopefully, this fails, which proves we have successfully recreated the environment!

```
$ opam source bitwuzla-cxx.0.7.0
$ cd bitwuzla-cxx.0.7.0
$ dune build
File "vendor/dune", lines 201-218, characters 0-436:
201 | (rule
202 |  (deps
203 |   (source_tree bitwuzla)
.....
216 |      %{p0002}
217 |      (run patch -p1 --directory bitwuzla))
218 |     (write-file %{target} "")))))
(cd _build/default/vendor && /usr/bin/patch -p1 --directory bitwuzla) < _build/default/vendor/patch/0001-api-Add-hook-for-ocaml-z-value.patch
patching file 'include/bitwuzla/cpp/bitwuzla.h'
Can't create '/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/build_9012b8_dune/patchoEyVbKAjSTw', output is in '/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/build_9012b8_dune/patchoEyVbKAjSTw': Permission denied
patch: **** can't create '/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/build_9012b8_dune/patchoEyVbKAjSTw': Permission denied
```

This matches the output we see on the CI logs. `/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T` is the `TMPDIR` value set in the environment. `Permission denied` looks like file system permissions. `ls -l` and `touch` show we can write to this directory.

As we are running on macOS, and the Dune is invoking `patch`, my thought goes to Apple's `patch` vs GNU's `patch`. Editing `vendor/dune` to use `gpatch` rather than `patch` allows the project to build.

```
$ dune build
(cd _build/default/vendor && /usr/local/bin/gpatch --directory bitwuzla -p1) < _build/default/vendor/patch/0001-api-Add-hook-for-ocaml-z-value.patch
File include/bitwuzla/cpp/bitwuzla.h is read-only; trying to patch anyway
patching file include/bitwuzla/cpp/bitwuzla.h
```

Running Apple's `patch` directly,

```
$ patch -p1 < ../../../../vendor/patch/0001-api-Add-hook-for-ocaml-z-value.patch
patching file 'include/bitwuzla/cpp/bitwuzla.h'
Can't create '/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/patchorVrfBtHVDI', output is in '/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/patchorVrfBtHVDI': Permission denied
patch: **** can't create '/var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/patchorVrfBtHVDI': Permission denied
```

However, `touch /var/folders/s_/z7_t3bvn5txfn81hk9p3ntfw0000z8/T/patchorVrfBtHVDI` succeeds.

Looking back at the output from GNU `patch`, it reports that the file itself is read-only.

```
$ ls -l include/bitwuzla/cpp/bitwuzla.h
-r--r--r--  1 mac1000  admin  52280 May  8 15:05 include/bitwuzla/cpp/bitwuzla.h
```

Let’s try to adjust the permissions:

```
$ chmod 644 include/bitwuzla/cpp/bitwuzla.h
$ patch -p1 < ../../../../vendor/patch/0001-api-Add-hook-for-ocaml-z-value.patch
patching file 'include/bitwuzla/cpp/bitwuzla.h’
```

And now, it succeeds. The issue is that the GNU patch and Apple patch act differently when the file being patched is read-only. Apple’s patch gives a spurious error, while the GNU patch emits a warning and makes the change anyway.

Updating the `dune` file to include `chmod` should both clear the warning and allow the use of the native patch.

```
(rule
 (deps
  (source_tree bitwuzla)
  (:p0001
   (file patch/0001-api-Add-hook-for-ocaml-z-value.patch))
  (:p0002
   (file patch/0002-binding-Fix-segfault-with-parallel-instances.patch)))
 (target .bitwuzla_tree)
 (action
  (no-infer
   (progn
    (run chmod -R u+w bitwuzla)
    (with-stdin-from
     %{p0001}
     (run patch -p1 --directory bitwuzla))
    (with-stdin-from
     %{p0002}
     (run patch -p1 --directory bitwuzla))
    (write-file %{target} "")))))
```

As an essential last step, we need to tidy up on this machine. Exit the shell. Refer back to the log file for the job and run all the remaining ZFS commands. This is incredibly important on macOS and essential to keep the jobs database in sync with the snapshots.

