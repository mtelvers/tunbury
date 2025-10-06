---
layout: post
title: "Attempting overlayfs with macFuse"
date: 2025-10-06 06:00:00 +0000
categories: macfuse
tags: tunbury.org
image:
  path: /images/macfuse-home.png
  thumbnail: /images/thumbs/macfuse-home.png
---

It would be great if overlayFS or unionFS worked on macOS! Initially, I attempted to use DYLD_INTERPOSE, but I wasn't able to intercept enough system calls to get it to work. However, macFuse provides a way to implement our own userspace file systems. Patrick previously wrote [obuilder-fs](https://github.com/ocurrent/obuilder-fs), which implemented a per-user filesystem redirection. It would be interesting to extend this concept to provide an overlayfs-style implementation.

My approach was to use an environment variable to flag which process should have the I/O redirected. When the user space layer of Fuse is called, the context includes the UID of the calling process. It is then possible to query the process's environment and check for the marker variables. If none are found, then we can check the parent process. This won't work for a double `fork()`, but it's good enough to traverse `sudo`. Processes without the environment marker will pass through to the existing path.

Passing through to the existing path is easier said than done. When the Fuse filesystem is mounted, the content of the underlying filesystem is completely hidden. The workaround was to move the existing files out of the way and redirect to requests to this temporary directory.

Initially, this showed promise as trivial commands like `stat` and `ls` worked. However, the excitement was short-lived as complex commands failed with "Device not configured".

For example, with Fuse mounted on `/usr/local`, some files and directories were created in `/tmp/a`, but very few.

```sh
% WRAPPER=/tmp/a git -C /usr/local clone https://github.com/ocaml/opam-repository
Cloning into 'opam-repository'...
/System/Volumes/Data/usr/local/opam-repository/.git/hooks/: Device not configured
```

The log showed that `fseventsd` tried to query all the directories which `git` created, but since it didn't have the environment variable set, it couldn't find the files. After a few failures, `fseventsd` seem to mark the filesystem as bad and block access. The log snippet below shows a a typically request from `fseventsd`

```
unique: 8, opcode: GETATTR (3), nodeid: 21, insize: 56, pid: 522
getattr /opam-repository/.git
Searching for WRAPPER in process tree starting from PID 522:
    PID 522 has 1 args, checking environment...
    arg[0]: /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/FSEvents.framework/Versions/A/Support/fseventsd
    Checked 4 environment variables, no WRAPPER found
  PID 522 (fseventsd): no wrapper
No WRAPPER found in process tree
*** GETATTR PASSTHROUGH: /opam-repository/.git -> /System/Volumes/Data/usr/local.fuse/opam-repository/.git ***
   unique: 8, error: -2 (No such file or directory), outsize: 16
unique: 6, opcode: LOOKUP (1), nodeid: 20, insize: 45, pid: 522
LOOKUP /opam-repository/.git
getattr /opam-repository/.git
Searching for WRAPPER in process tree starting from PID 522:
    PID 522 has 1 args, checking environment...
    arg[0]: /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/FSEvents.framework/Versions/A/Support/fseventsd
    Checked 4 environment variables, no WRAPPER found
  PID 522 (fseventsd): no wrapper
No WRAPPER found in process tree
*** GETATTR PASSTHROUGH: /opam-repository/.git -> /System/Volumes/Data/usr/local.fuse/opam-repository/.git ***
   unique: 6, error: -2 (No such file or directory), outsize: 16
```

Searching online suggested that `fseventsd` could be blocked by creating a file named `/.fseventsd/no_log` on the filesystem. This didn't work. Since the incoming request always came from `fseventsd` could it be blocked at the Fuse level?  As a quick test, I tried returning `ENOTSUP` based on the PID, and that worked! I replaced the static PID with a call to `proc_pidpath()` and matched the name against `fseventsd`.

```c
    if (context->pid == 522) {
        return -ENOTSUP;
    }
```

With this working, I implemented an overlayfs-style semantics using environment variables `WRAPPER_UPPER` and `WRAPPER_LOWER`. Deletions are handled by creating a whiteout directory, `.deleted`, at the root, which is populated with empty files that reflect the files/directories which have been deleted. If a file `bar` is deleted from directory `foo`, then `/.delete/foo/bar` would be created. Later, if `foo` was removed, the directory `foo` would be removed from the whiteout directory and be replaced with a file instead. `/.deleted/foo`

opendir()/readdir() were the most complex functions to implement, as they needed to scan the upper directory and merge in the lower directory, taking account of any deleted files and hide the `/.deleted` directory.

The redirection worked. For example, given these steps, `/tmp/a` would be empty, `/tmp/b` contains the vanilla checkout of opam-repository, and `/tmp/c` contains the difference: `/tmp/c/.deleted` with the files removed, `/tmp/c/opam-repository/...` and `/tmp/c/opam-repository/.git` with just the files which contain differences.

```sh
% mkdir /tmp/a /tmp/b /tmp/c
% WRAPPER_LOWER=/tmp/a WRAPPER_UPPER=/tmp/b git -C /usr/local clone https://github.com/ocaml/opam-repository
% WRAPPER_LOWER=/tmp/b WRAPPER_UPPER=/tmp/c git -C /usr/local/opam-repository checkout c35a0314d6c7c7260c978f490fb8f7109f4e9766
```

Extending this further allows `/tmp/d` to be created with a different delta.

```sh
% mkdir /tmp/d
% WRAPPER_LOWER=/tmp/b WRAPPER_UPPER=/tmp/d git -C /usr/local/opam-repository checkout f33f62ebff75cd03620d09d46a4540340f5564a6
```

Annoyingly, this revealed a significant issue: running `git status` on `/tmp/c` showed that files had changed. I presumed there was a flaw in my code which was corrupting the files, but I couldn't find it. Examining the files on disk showed that they were correct, but when reading them through Fuse, gave different data:

```sh
% for x in c d ; do cat /tmp/$x/opam-repository/.git/HEAD ; WRAPPER_LOWER=/tmp/b WRAPPER_UPPER=/tmp/$x cat /usr/local/opam-repository/.git/HEAD ; done
c35a0314d6c7c7260c978f490fb8f7109f4e9766
c35a0314d6c7c7260c978f490fb8f7109f4e9766
f33f62ebff75cd03620d09d46a4540340f5564a6
c35a0314d6c7c7260c978f490fb8f7109f4e9766
```

The log showed the root cause - two OPEN calls, but only a single READ. The kernel is caching the reads.

```sh
% grep OPEN log5.txt
unique: 2, opcode: OPEN (14), nodeid: 4, insize: 48, pid: 52976
*** OPEN: /opam-repository/.git/HEAD from UPPER: /tmp/c/opam-repository/.git/HEAD ***
unique: 3, opcode: OPEN (14), nodeid: 4, insize: 48, pid: 52980
*** OPEN: /opam-repository/.git/HEAD from UPPER: /tmp/d/opam-repository/.git/HEAD ***

% grep READ log5.txt
unique: 3, opcode: READ (15), nodeid: 4, insize: 80, pid: 52976
```

You can disable attribute caching with `-o attr_timeout=0 -o entry_timeout=0`, and you can circumvent the cache by specifying `-o direct_io`. Setting `direct_io` is sufficient to resolve the issue in a simple `cat` test, but it has the side effect of disabling `mmap()`, which causes `git` to crash with a `bus error`. Setting `fi->keep_cache = 0` doesn't prevent the cache.

The kernel asks Fuse to allocate a node ID for a path. The node ID number is passed as a parameter to GETATTR, OPEN and READ. Even though GETATTR returns different mtime values at the second call, the kernel still sees a cache hit and returns the file content from the cache.

To control the node ID allocation process this needs to be rewritten using the Fuse low level API. This would allow full control over the allocation process and gives access to calls such as `fuse_lowlevel_notify_inval_inode()`.

My work-in-progress code is available on GitHub [mtelvers/macfuse](https://github.com/mtelvers/macfuse/blob/master/LoopbackFS-C/loopback/loopback.c).
