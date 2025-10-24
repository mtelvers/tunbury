---
layout: post
title:  "Slurm with multiple architectures"
date:   2025-10-24 12:00:00 +0000
categories: Slurm
tags: tunbury.org
image:
  path: /images/slurm.png
  thumbnail: /images/thumbs/slurm.png
---

If we implement Slurm over a cluster of machines with different processor architectures, what would the job submission look like?

Slurm will happily have different processor architectures in the same cluster and even in the same partition. The processor cores and memory are aggregated as they would be for like architectures. It is the submitter's responsibility to ensure that their script runs on the available processors. Rather than leave it to chance, we could create multiple partitions within a cluster. For example, with these settings in `slurm.conf`:

```
# Define your node groups first
NodeName=node[01-10] CPUs=32 RealMemory=128000
NodeName=node[11-20] CPUs=64 RealMemory=256000

# Then define partitions
PartitionName=x86_64 Nodes=node[01-10] Default=YES MaxTime=INFINITE State=UP
PartitionName=arm64 Nodes=node[11-20] Default=NO MaxTime=INFINITE State=UP
```

However, it is probably better to use node "features" and keep all the machines in a single partition:

```
# Define your node groups first
NodeName=node[01-10] CPUs=32 Feature=x86_64
NodeName=node[11-20] CPUs=64 Feature=arm64

# Then define the partition
PartitionName=compute Nodes=node[01-20] Default=YES State=UP
```

Users can select the processor architecture using the `--constraint` option to `sbatch`.

```
sbatch --constraint=x86_64 job.sh
sbatch --constraint=arm64 job.sh
```

I have implemented this strategy in [mtelvers/slurm-ansible](https://github.com/mtelvers/slurm-ansible), which builds a Slurm cluster based upon my previous posts on [14/4](https://www.tunbury.org/2025/04/14/slurm-workload-manager/) and [6/8](https://www.tunbury.org/2025/08/06/slurm-limits/) to include accounting, cgroups and NFS sharing and additionally applies features based upon `uname -m`.
