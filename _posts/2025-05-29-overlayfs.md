---
layout: post
title: "OverlayFS on TMPFS vs BTRFS on NVMe in OBuilder on POWER9"
date: 2025-05-29 00:00:00 +0000
categories: opam
tags: tunbury.org
image:
  path: /images/orithia-nvme-write-rate.png
  thumbnail: /images/thumbs/orithia-nvme-write-rate.png
permalink: /overlayfs/
---

[OBuilder](https://github.com/ocurrent/obuilder) takes a build script (similar to a Dockerfile) and performs the steps in it in a sandboxed environment. After each step, OBuilder uses the snapshot feature to store the state of the build as a `layer`. Repeating a build will reuse the cached results where possible.

Depending upon the platform, different snapshot systems can be used along with different sandboxes. The tables below give a cross-section of the supported configurations.

# Sandboxes

|         | RUNC | QEMU | Jails | Docker | User Isolation |
| ------- | ---- | ---- | ----- | ------ | -------------- |
| Linux   | ✅   | ✅   | ❌    | ✅     | ❌             |
| FreeBSD | ❌   | ❌   | ✅    | ❌     | ❌             |
| Windows | ❌   | ❌   | ❌    | ✅     | ❌             |
| macOS   | ❌   | ❌   | ❌    | ❌     | ✅             |

* QEMU support could be extended to other platforms, however the real limitation is which operating systems can be run in a QEMU virtual machine.
* User isolation could be implemented on Windows.

# Snapshots

|           | Linux | FreeBSD | Windows | macOS |
| --------- | ----- | ------- | ------- | ----- |
| Docker    | ✅    | ❌      | ✅      | ❌    |
| ZFS       | ✅    | ✅      | ❌      | ✅    |
| BTRFS     | ✅    | ❌      | ❌      | ❌    |
| XFS       | ✅    | ❌      | ❌      | ❌    |
| OVERLAYFS | ✅    | ❌      | ❌      | ❌    |
| BTRFS     | ✅    | ❌      | ❌      | ❌    |
| RSYNC     | ✅    | ✅      | ❌      | ✅    |

* QEMU uses `qemu-img` to perform snapshots

Our default implementation is to use BTRFS, as this outperforms ZFS. ZFS snapshots and XFS reflinks perform similarly. `rsync` performs badly, but is a useful reference case as it runs on any native filesystem.

OverlayFS can be run on top of any filesystem, but the interesting case is running it on top of TMPFS. This is the fastest configuration for any system with enough RAM. Until this week, I had never tested this beyond AMD64; however, with the recent problems on the Talos II machines, I had the opportunity to experiment with different configurations on POWER9.

```
ocluster-worker -c pool.cap --name=scyleia --obuilder-store=overlayfs:/var/cache/obuilder --capacity=22 ...
ocluster-worker -c pool.cap --name=orithia --obuilder-store=btrfs:/var/cache/obuilder --capacity=22 ...
```

Comparing my favourite metric of the number of jobs accepted per hour shows that OverlayFS on TMPFS is twice as fast as BTRFS. Scyleia had TMPFS configured at 400GB. Orithia had BTRFS on a dedicated 1.8TB NVMe.

![](/images/jobs-accepted-per-hour-orithia-scyleia.png)

This side-by-side graphic showing `btop` running on both systems gives a good look at what is happening. I/O is saturated on the NVMe, preventing the CPUs from getting the needed data, while the RAM footprint is tiny. Conversely, TMPFS consumes 50% of the RAM, with most cores working flat out.

![](/images/btop-orithia-scyleia.png)

I found that TMPFS can run out of inodes just like a regular filesystem. You can specify the number of inodes in `/etc/fstab`.

```
tmpfs       /var/cache/obuilder     tmpfs noatime,size=400g,nr_inodes=10000000     0 1
```

