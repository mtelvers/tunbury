---
layout: post
title: "ZFS Send Streams"
date: 2025-05-02 20:00:00 +0000
categories: openzfs
tags: tunbury.org
image:
  path: /images/openzfs.png
  thumbnail: /images/openzfs.png
---

We often say that ZFS is an excellent replicated file system, but not the best _local_ filesystem. This led me to think that if we run `zfs send` on one machine, we might want to write that out as a different filesystem. Is that even possible?

What is in a ZFS stream?

```sh
fallocate -l 10G temp.zfs
zpool create tank `pwd`/temp.zfs 
zfs create tank/home
cp README.md /tank/home
zfs snapshot tank/home@send
zfs send tank/home@send | hexdump
```

I spent a little time writing an OCaml application to parse the record structure before realising that there already was a tool to do this: `zstreamdump`. Using the `-d` flag shows the contents; you can see your file in the dumped output.

```sh
zfs send tank/home@send | zstreamdump -d
```

However, this is _not_ like a `tar` file. It is not a list of file names and their content. It is a list of block changes. ZFS is a tree structure with a snapshot and a volume being tree roots. The leaves of the tree may be unchanged between two snapshots. `zfs send` operates at the block level below the file system layer.

To emphasise this point, consider a `ZVOL` formatted as XFS. The structure of the send stream is the same: a record of block changes.

```sh
zfs create -V 1G tank/vol
mkfs.xfs /dev/zvol/tank/vol
zfs snapshot tank/vol@send
zfs send tank/vol@send | zstreamdump -d
```

ZVOLs are interesting as they give you a snapshot capability on a file system that doesn’t have one. However, some performance metrics I saw posted online showed disappointing results compared with creating a file and using a loopback device. Furthermore, the snapshot would only be in a crash-consistent state as it would be unaware of the underlying snapshot. XFS does have `xfsdump` and `xfsrestore`, but they are pretty basic tools.

[1] See also [ZfsSend Documentation](https://openzfs.org/wiki/Documentation/ZfsSend)
