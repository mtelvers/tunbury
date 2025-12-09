---
layout: post
title: "Ceph Placemant Groups"
date: 2025-12-09 12:00:00 +0000
categories: ceph
tags: tunbury.org
image:
  path: /images/ceph-logo.png
  thumbnail: /images/thumbs/ceph-logo.png
---

Better planning leads to less data movement later!

Rather than tracking the placement of every individual object, Ceph hashes objects into placement groups, PGs, and then maps those PGs to Object Storage Daemons, OSDs. A PG is a logical collection of objects that are all stored on the same set of OSDs.

When a pool is created, it has few PGs. In my case, only 1 PG was allocated. As data is written, the autoscaler increases the target number of PGs. For my cluster, 1 became 32, then 128 and then 512. Each time this happens, a PG "splits", becoming 4, and then data is remapped to balance the placement across the OSDs. By default, only 5% of data can be misplaced, so the number of active placement groups increases slowly. Each time the amount of misplaced data is less than 5% more placement groups are created, resulting in more misplaced data, and the cycle continues.

As I am doing a bulk data copy, this behaviour is undesirable. Instead of creating the pool with:

```sh
ceph osd pool create mypool erasure <ec-profile>
```

I should have specified the number of PGs.

```sh
ceph osd pool create mypool 512 erasure <ec-profile>
```

You can calculate the number of PGs upfront. Firstly, work out your pool size factor:

- For a replicated pool, use the replication size
- For an EC pool, use k + m

> Target PGs = (Total OSDs * 100) / pool_size_factor

In my case, I have 24 OSDs with EC 3+1 (size factor = 4). `(24 * 100) / 4 = 600` then round to nearest power of 2 = 512.

The "100" appears to be a rule of thumb for target PGs per OSD. I have seen a range of recommended values between 100-200, depending on workload. The division by pool size accounts for the fact that each PG is stored on multiple OSDs.

You can set the number retrospectively, or let the autoscaler do it.

```sh
ceph osd pool set cephfs_data pg_num 512
ceph osd pool set cephfs_data pgp_num 512
```

Right now, I am waiting for 128 PGs to be autoscaled to 512. This could result in data being moved twice. For example, object X is in PG 5 on OSD 1. PG 5 splits, and object X hashes to new PG 133, which CRUSH puts on OSD 3. Subsequently, PG 133 splits, object X hashes to new PG 389, which CRUSH places on OSD 7.

I want to minimise the movement, so I have set the misplaced target ratio to 80% which will allow all the PG splits to occur.

```sh
ceph config set mgr target_max_misplaced_ratio 0.80
```

I would not recommend this for a cluster with active users, as the splitting causes a significant amount of I/O and performance degradation. However, all the splits occurred, and now the data is remapping. 52% of the data is misplaced. The recovery rate is ~300MB/s.
