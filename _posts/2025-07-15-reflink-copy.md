---
layout: post
title:  "Reflink Copy"
date:   2025-07-15 00:00:00 +0000
categories: ocaml
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

I hadn't intended to write another [post](https://www.tunbury.org/2025/07/08/unix-or-sys/) about traversing a directory structure or even thinking about it again, but weirdly, it just kept coming up again!

Firstly, Patrick mentioned `Eio.Path.read_dir` and Anil mentioned [bfs](https://tavianator.com/2023/bfs_3.0.html). Then Becky commented about XFS reflink performance, and I commented that the single-threaded nature of `cp -r --reflink=always` was probably hurting our [obuilder](https://github.com/ocurrent/obuilder) performance tests.

Obuilder is written in LWT, which has `Lwt_unix.readdir`. What if we had a pool of threads that would traverse the directory structure in parallel and create a reflinked copy?

Creating a reflink couldn't be easier. There's an `ioctl` call that _just_ does it. Such a contrast to the ReFS copy-on-write implementation on Windows!

```c
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/unixsupport.h>
#include <sys/ioctl.h>
#include <errno.h>

#ifndef FICLONE
#define FICLONE 0x40049409
#endif

value caml_ioctl_ficlone(value dst_fd, value src_fd) {
    CAMLparam2(dst_fd, src_fd);
    int result;

    result = ioctl(Int_val(dst_fd), FICLONE, Int_val(src_fd));

    if (result == -1) {
        uerror("ioctl_ficlone", Nothing);
    }

    CAMLreturn(Val_int(result));
}
```

We can write a reflink copy function as shown below. (Excuse my error handling.) Interestingly, points to note: the permissions set via `Unix.openfile` are filtered through umask, and you need to `Unix.fchown` before `Unix.fchmod` if you want to set the suid bit set.

```ocaml
external ioctl_ficlone : Unix.file_descr -> Unix.file_descr -> int = "caml_ioctl_ficlone"

let copy_file src dst stat =
  let src_fd = Unix.openfile src [O_RDONLY] 0 in
  let dst_fd = Unix.openfile dst [O_WRONLY; O_CREAT; O_TRUNC] 0o600 in
  let _ = ioctl_ficlone dst_fd src_fd in
  Unix.fchown dst_fd stat.st_uid stat.st_gid;
  Unix.fchmod dst_fd stat.st_perm;
  Unix.close src_fd;
  Unix.close dst_fd;
```

My LWT code created a list of all the files in a directory and then processed the list with `Lwt_list.map_s` (serially), returning promises for all the file operations and creating threads for new directory operations up to a defined maximum (8). If there was no thread capacity, it just recursed in the current thread. Copying a root filesystem, this gave me threads for `var`, `usr`, etc, just as we'd want. Wow! This was slow. Nearly 4 minutes to reflink 1.7GB!

What about using the threads library rather than LWT threads? This appears significantly better, bringing the execution time down to 40 seconds. However, I think a lot of that was down to my (bad) LWT implementation vs my somewhat better threads implementation.

At this point, I should probably note that `cp -r --reflink always` on 1.7GB, 116,000 files takes 8.5 seconds on my machine using a loopback XFS. A sequential OCaml version, without the overhead of threads or any need to maintain a list of work to do, takes 9.0 seconds.

Giving up and getting on with other things was very tempting, but there was that nagging feeling of not bottoming out the problem.

Using OCaml Multicore, we can write a true multi-threaded version. I took a slightly different approach, having a work queue of directories to process, and N worker threads taking work from the queue.

```
Main Process: Starts with root directory
     ↓
WorkQueue: [process_dir(/root)]
     ↓
Domain 1: Takes work → processes files → adds subdirs to queue
Domain 2: Takes work → processes files → adds subdirs to queue
Domain 3: Takes work → processes files → adds subdirs to queue
     ↓
WorkQueue: [process_dir(/root/usr), process_dir(/root/var), ...]
```

Below is a table showing the performance when using multiple threads compared to the baseline operation of `cp` and a sequential copy in OCaml.

| Copy command           | Duration (sec) |
| ---------------------- | -------------- |
| cp -r --reflink=always | 8.49           |
| Sequential             | 8.80           |
| 2 domains              | 5.45           |
| 4 domains              | 3.28           |
| 6 domains              | 3.43           |
| 8 domains              | 5.24           |
| 10 domains             | 9.07           |

The code is available on GitHub in [mtelvers/reflink](https://github.com/mtelvers/reflink).

