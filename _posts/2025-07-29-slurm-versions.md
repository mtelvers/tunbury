---
layout: post
title:  "Slurm Versions"
date:   2025-07-29 00:00:00 +0000
categories: Slurm
tags: tunbury.org
image:
  path: /images/slurm.png
  thumbnail: /images/thumbs/slurm.png
---

Slurm requires both the client and server to be on the same version.

```
[2025-07-29T15:41:34.492] error: slurm_unpack_received_msg: [[foo.cl.cam.ac.uk]:34214] Invalid Protocol Version 10752 from uid=0: No error
[2025-07-29T15:41:34.492] error: slurm_unpack_received_msg: [[foo.cl.cam.ac.uk]:34214] Incompatible versions of client and server code
[2025-07-29T15:41:34.502] error: slurm_receive_msg [128.232.93.254:34214]: Incompatible versions of client and server code
```

Noble (24.04) has Slurm 23.11.4-1.2ubuntu5, whereas Plucky (25.04) has 24.11.3-2.

The latest version is 25.05.1. [https://www.schedmd.com/download-slurm](https://www.schedmd.com/download-slurm).

The recommended approach is to build the Debian `.deb` packages from source. First, install basic Debian package build requirements:

```sh
apt install build-essential fakeroot devscripts equivs
```

Unpack the distributed tarball:
```sh
curl -L https://download.schedmd.com/slurm/slurm-25.05.1.tar.bz2 | tar -xajf - && cd slurm-25.05.1
```

Install the Slurm package dependencies:
```sh
mk-build-deps -i debian/control
```

Build the Slurm packages:
```sh
debuild -b -uc -us
```

> Before installing, ensure any old installations have been removed with `apt remove slurm*` and `apt remove libslurm*`.

# Worker

```sh
dpkg -i slurm-smd-slurmd_25.05.1-1_amd64.deb slurm-smd-client_25.05.1-1_amd64.deb slurm-smd_25.05.1-1_amd64.deb slurm-smd_25.05.1-1_amd64.deb
```

# Head controller

```sh
dpkg -i slurm-smd-slurmctld_25.05.1-1_amd64.deb slurm-smd-client_25.05.1-1_amd64.deb slurm-smd_25.05.1-1_amd64.deb slurm-smd_25.05.1-1_amd64.deb
```

With the same version of Slurm on both machines, the instructions from my earlier [post](https://www.tunbury.org/2025/04/14/slurm-workload-manager/) are working again.

```sh
# sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
eeg*         up   infinite      1   idle foo

# srun -N1 -l /bin/hostname
0: foo.cl.cam.ac.uk
```

Slurm communicates directly over TCP connections using ports 6817/6818, so ensure that no firewalls are in the way!

