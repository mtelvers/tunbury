---
layout: post
title: "Hardlinks and Reflinks on Windows"
date: 2025-06-18 00:00:00 +0000
categories: OCaml,Windows
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
permalink: /windows-reflinks/
---

Who knew there was a limit on creating hard links? I didn't even consider this until my hard links started to fail. On NTFS, the limit is 1024 links to any given file. Subsequent research shows that the limit varies between file systems, with NTFS at the lower end of the scale.

Here's an excerpt from [Wikipedia](https://en.wikipedia.org/wiki/Hard_link) on the subject.

> In AT&T Unix System 6, released in 1975, the number of hard links allowed was 127. On Unix-like systems, the in-memory counter is 4,294,967,295 (on 32-bit machines) or 18,446,744,073,709,551,615 (on 64-bit machines). In some file systems, the number of hard links is limited more strictly by their on-disk format. For example, as of Linux 3.11, the ext4 file system limits the number of hard links on a file to 65,000. Windows limits enforces a limit of 1024 hard links to a file on NTFS volumes.

This restriction probably doesn't even come close to being a practical limit for most normal use cases, but it's worth noting that `git.exe` has 142 hard links on a standard Cygwin installation.

```
fsutil hardlink list %LOCALAPPDATA%\opam\.cygwin\root\bin\git.exe
```

Back in 2012, Microsoft released ReFS as an alternative to NTFS. The feature gap has closed over the years, with hard links being introduced in the preview of Windows Server 2022. ReFS supports 1 million hard links per file, but even more interestingly, it supports [block cloning](https://learn.microsoft.com/en-us/windows/win32/fileio/block-cloning), aka [reflinks](https://blogs.oracle.com/linux/post/xfs-data-block-sharing-reflink), whereby files can share common data blocks. When changes are written to a block, it is copied, and its references are updated.

The implementation is interesting because it doesn't work in quite the way that one would think. It can only be used to clone complete clusters. Therefore, we must first call [FSCTL_GET_INTEGRITY_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/winioctl/ni-winioctl-fsctl_get_integrity_information), which returns [FSCTL_GET_INTEGRITY_INFORMATION_BUFFER](https://learn.microsoft.com/en-us/windows/win32/api/winioctl/ns-winioctl-fsctl_get_integrity_information_buffer) with the cluster size in bytes.

Despite [FSCTL_DUPLICATE_EXTENTS_TO_FILE](https://learn.microsoft.com/en-us/windows/win32/api/winioctl/ni-winioctl-fsctl_duplicate_extents_to_file) taking an exact number of bytes, we must round up the file size to the next cluster boundary.

Additionally, the target file needs to exist before the clone and be large enough to hold the cloned clusters. In practice, this means calling [CreateFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew) to create the file and then calling [SetFileInformationByHandle](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfileinformationbyhandle) to set the file size to match the source file (not the rounded cluster size).

Taking an example file of 23075 bytes, this would be rounded to 24576 bytes (6 clusters). We can use `fsutil file queryextents` to get detailed information about the clusters used in the source file:

```
D:\> fsutil file queryextents source.txt
VCN: 0x0        Clusters: 0x6        LCN: 0x2d3d801
```

Now we clone the file `ReFS-clone d:\source.txt d:\target.txt` and then query the extents which it uses.

```
D:\> fsutil file queryextents target.txt
VCN: 0x0        Clusters: 0x5        LCN: 0x2d3d801
VCN: 0x5        Clusters: 0x1        LCN: 0x2d3c801
```

The first five whole clusters are shared between the two files, while the final partial cluster has been copied. When trying to implement this, I initially used a text file of just a few bytes and couldn't get it clone. After I rounded up the size to 4096, the API returned successfully, but there are no shared clusters. It wasn't until I tried a larger file with the size rounded up that I started to see actual shared clusters.

```
D:\>echo hello > foo.txt

D:\>fsutil file queryextents foo.txt
VCN: 0x0        Clusters: 0x1        LCN: 0x2d3dc04

D:\>ReFS-clone.exe foo.txt bar.txt
ReFS File Clone Utility
ReFS Clone: foo.txt -> bar.txt
Cluster size: 4096 bytes
File size: 8 bytes -> 4096 bytes (1 clusters)
Cloning 4096 bytes...
Success!
ReFS cloning completed successfully.

D:\>fsutil file queryextents bar.txt
VCN: 0x0        Clusters: 0x1        LCN: 0x2d3d807
```

The code is on GitHub in [ReFS-Clone](https://github.com/mtelvers/ReFS-Clone).
