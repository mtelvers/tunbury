---
layout: post
title:  "Slurm Workload Manager"
date:   2025-04-14 00:00:00 +0000
categories: Slurm
tags: tunbury.org
image:
  path: /images/slurm.png
  thumbnail: /images/thumbs/slurm.png
redirect_from:
  - /slurm-workload-manager/
---

Sadiq mentioned `slurm` as a possible way to better schedule the group's compute resources. Many resources are available showing how to create batch jobs for Slurm clusters but far fewer on how to set up a cluster. This is a quick walkthrough of the basic steps to set up a two-node compute cluster on Ubuntu 24.04. Note that `slurmd` and `slurmctld` can run on the same machine.

Create three VMs: `node1`, `node2` and `head`.

On `head`, install these components.

```shell
apt install munge slurmd slurmctld
```

On `node1` and `node2` install.

```shell
apt install munge slurmd
```

Copy `/etc/munge/munge.key` from `head` to the same location on `node1` and `node2`. Then restart `munge` on the other nodes with `service munge restart`.

You should now be able to `munge -n | unmunge` without error. This should also work via SSH. i.e. `ssh head munge -n | ssh node1 unmunge`

If you don't have DNS, add `node1` and `node2` to the `/etc/hosts` file on `head` and add `head` to the `/etc/hosts` on `node1` and `node2`.

On `head`, create the daemon spool directory:

```shell
mkdir /var/spool/slurmctld
chown -R slurm:slurm /var/spool/slurmctld/
chmod 775 /var/spool/slurmctld/
```

Create `/etc/slurm/slurm.conf`, as below. Update the compute node section by running `slurmd -C` on each node to generate the configuration line. This file should be propagated to all the machines. The configuration file can be created using this [tool](https://slurm.schedmd.com/configurator.html).

```
ClusterName=cluster
SlurmctldHost=head
ProctrackType=proctrack/linuxproc
ReturnToService=1
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmctldPort=6817
SlurmdPidFile=/var/run/slurmd.pid
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurmd
SlurmUser=slurm
StateSaveLocation=/var/spool/slurmctld
TaskPlugin=task/affinity,task/cgroup

# TIMERS
InactiveLimit=0
KillWait=30
MinJobAge=300
SlurmctldTimeout=120
SlurmdTimeout=300
Waittime=0

# SCHEDULING
SchedulerType=sched/backfill
SelectType=select/cons_tres

# LOGGING AND ACCOUNTING
JobCompType=jobcomp/none
JobAcctGatherFrequency=30
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurmd.log

# COMPUTE NODES
NodeName=node1 CPUs=1 Boards=1 SocketsPerBoard=1 CoresPerSocket=1 ThreadsPerCore=1 RealMemory=1963
NodeName=node2 CPUs=1 Boards=1 SocketsPerBoard=1 CoresPerSocket=1 ThreadsPerCore=1 RealMemory=1963
PartitionName=debug Nodes=ALL Default=YES MaxTime=INFINITE State=UP
```

On `head`, start the control daemon.

```shell
service slurmctld start
```

And on the nodes, start the slurm daemon.

```shell
service slurmd start
```

From `head`, you can now run a command simultaneously on both nodes.

```shell
# srun -N2 -l /bin/hostname
0: node1
1: node2
```

The optional `Gres` parameter on `NodeName` allows nodes to be configured with extra resources such as GPUs.

Typical configurations use an NFS server to make /home available on all the nodes. Note that users only need to be created on the head node and don’t need SSH access to the compute nodes.
