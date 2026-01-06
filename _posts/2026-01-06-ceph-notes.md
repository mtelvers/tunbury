---
layout: post
title: "Ceph Notes"
date: 2026-01-06 12:00:00 +0000
categories: ceph
tags: tunbury.org
image:
  path: /images/ceph-logo.png
  thumbnail: /images/thumbs/ceph-logo.png
---

We now have 209 TB of data on a seven-node Ceph cluster. Here are some further notes on using Ceph.

# Mounts

To mount a Ceph FS volume, obtain the base64-encoded secret using this command.

```sh
cephadm shell -- ceph auth get-key client.admin
```

Then pass that as an option to the `mount` command.

```sh
mount -o name=admin,secret=<base64-data> -t ceph <fqdn>:6789:/ /mnt/cephfs
```

You can create additional users using `ceph auth get-or-create client.foo ...` with different access permissions.

You can provide a comma-separated list of Ceph monitor machines. The client tries to connect to these in sequence to provide redundancy during the initial connection phase. This isn't for load balancing.

Once the mount has been set up, the client communicates directly with the metadata server and the individual OSD daemons, bypassing the monitor machine.

# Subvolumes

Our source data is on ZFS, which has a multitude of file system features. It's worth noting that Ceph FS has _subvolumes_ which provide snapshots, quotas, clone capabilities and namespaces. Like in ZFS, these need to be created in advance, which fortunately, I did! 

```sh
ceph fs subvolumegroup create cephfs tessera
ceph fs subvolume create cephfs v1 --group_name tessera
```

These structures do not support arbitrary depths like ZFS; you are limited to a two level hierarchy of subvolume groups and, within that, multiple subvolumes, like this:

```
Filesystem
├── Subvolume Group (e.g., "tessera")
│   ├── Subvolume (e.g., "v1")
│   ├── Subvolume (e.g., "v2")
│   └── Subvolume (e.g., "v3")
└── Subvolume Group (e.g., "other-project")
    └── Subvolume (e.g., "data")
```

The sub volumes appear as UUID values. e.g.

```sh
root@ceph-1:~# du /mnt/cephfs/
0    /mnt/cephfs/volumes/tessera/v1/dec6285d-84a2-4d34-9e8b-469d1c6180a8
1    /mnt/cephfs/volumes/tessera/v1
1    /mnt/cephfs/volumes/tessera
1    /mnt/cephfs/volumes
1    /mnt/cephfs/
```

The subvolume path structure is non-negotiable; therefore, I have used symlinks to match the original structure.

```sh
ln -s ../volumes/tessera/v1/dec6285d-84a2-4d34-9e8b-469d1c6180a8 /mnt/cephfs/tessera/v1
```

# Copying data

This Ceph cluster is composed of Scaleway machines, which are interconnected at 1 Gb/s. This is far from ideal, particularly as my source/client machine has 10 Gb/s networking.

The go-to tool for this is `rsync`, but the upfront file scan on large directories was extremely slow. `rclone` proved more effective in streaming files while scanning the tree simultaneously.

Initially, I mounted the Ceph file system on one of the Ceph machines and used `rclone` to copy from the client to that machine's local mount point. However, this created a bottleneck, as the incoming interface only operates at 1 Gb/s, resulting in a best-case transfer speed of ~100 MB/s. That machine received the data and then retransmitted it to the cluster machine holding the OSD, so the interface was maxed out in both directions. In practice, I saw a maximum write rate of ~70MBps.

However, mounting the Ceph cluster directly from the client machine means that the client, with 10 Gb/s networking, can communicate directly with multiple cluster machines.

On the client machine, first install `ceph-common` using your package manager. Then, copy `ceph.conf` and `ceph.client.admin.keyring` from the cluster to the local machine, and finally mount using the earlier commands.

```sh
scp root@ceph-1:/etc/ceph/ceph.conf /etc/ceph
scp root@ceph-1:/etc/ceph/ceph.client.admin.keyring /etc/ceph
```

The sync is now between two local mounts on the client machine. I used `rclone` again as it still outperformed `rsync`.

```sh
rclone sync /data/tessera/v1/ /mnt/cephfs/tessera/v1/ --transfers 16 --progress --stats 10s --checkers 1024 --max-backlog 10000000 --modify-window 1s
```

With this configuration, I saw write speeds of around 350 MB/s.

