---
layout: post
title: "Expanding the Ceph Cluster to 600 TB"
date: 2026-03-27 14:00:00 +0000
categories: ceph
tags: tunbury.org
image:
  path: /images/dell-r640-angle.png
  thumbnail: /images/thumbs/dell-r640-angle.png
---

We purchased twenty of what felt like the last stock of 8 TB Kingston DC600M SSDs to the Cambridge cluster, bringing it from 66 to 86 OSDs across 20 Dell R640 hosts. The disks were distributed to balance the count per machine, with each host now running 4 or 5 disks.

# Pausing rebalance

Adding OSDs one at a time normally triggers a CRUSH recalculation and rebalance after each addition. To avoid 20 rounds of data movement, I paused recovery first to let CRUSH rebalance in a single pass at the end.

```
ceph osd set norebalance
ceph osd set nobackfill
```

# Adding the OSDs

Each disk was added individually with `ceph orch daemon add osd`. I left a short delay between each to avoid a race condition on OSD ID allocation that came up in an earlier batch.

```
ceph orch daemon add osd harmothoe:/dev/sdd
ceph orch daemon add osd kreousa:/dev/sdd
ceph orch daemon add osd lysippe:/dev/sdd
ceph orch daemon add osd melousa:/dev/sdd
ceph orch daemon add osd melousa:/dev/sde
ceph orch daemon add osd okyale:/dev/sdd
ceph orch daemon add osd okyale:/dev/sde
ceph orch daemon add osd philippis:/dev/sdd
ceph orch daemon add osd philippis:/dev/sde
ceph orch daemon add osd polemusa:/dev/sdd
ceph orch daemon add osd polemusa:/dev/sde
ceph orch daemon add osd tecmessa:/dev/sdd
ceph orch daemon add osd tecmessa:/dev/sde
ceph orch daemon add osd valasca:/dev/sdd
ceph orch daemon add osd valasca:/dev/sde
ceph orch daemon add osd xanthippe:/dev/sdd
ceph orch daemon add osd xanthippe:/dev/sde
ceph orch daemon add osd antiope:/dev/sdd
ceph orch daemon add osd myrina:/dev/sdd
ceph orch daemon add osd lampedo:/dev/sdd
```

# Unpausing

With all 20 OSDs registered and up, I unset the flags:

```
ceph osd unset norebalance
ceph osd unset nobackfill
```

CRUSH recalculated the PG mappings once, and the cluster began rebalancing data onto the new disks.

# Final state

The cluster now has 86 OSDs across 20 hosts. Raw capacity is 600 TB, yielding approximately 480 TB of usable capacity under the EC 8+2 erasure coding profile. Current data usage is around 160 TB.
