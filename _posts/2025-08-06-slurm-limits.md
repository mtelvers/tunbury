---
layout: post
title:  "Further investigations with Slurm"
date:   2025-08-06 00:00:00 +0000
categories: Slurm
tags: tunbury.org
image:
  path: /images/slurm.png
  thumbnail: /images/thumbs/slurm.png
---

Slurm uses cgroups to constrain jobs with the specified parameters and an accounting database to track job statistics.

After the initial [configuration](https://www.tunbury.org/2025/04/14/slurm-workload-manager/) and ensuring everything is at the same [version](https://www.tunbury.org/2025/07/29/slurm-versions/), what we really need is some shared storage between the head node and the cluster machine(s). I'm going to quickly share `/home` over NFS.

Install an NFS server on the head node with `apt install nfs-kernel-server` and set up `/etc/exports`:

```
/home    foo(rw,sync,no_subtree_check,no_root_squash)
```

On the cluster worker, install the NFS client, `apt install nfs-common` and mount the home directory:

```
mount -t nfs head:/home/mte24 /home/mte24
```

I have deleted my user account on the cluster worker and set my UID/GID on the head node to values that do not conflict with any of those on the worker.

With the directory shared, and signed into the head node as my users, I can run `sbatch ./myscript`

Configure Slurm to use cgroups, create `/etc/slurm/cgroups.conf` containing the following:

```
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
```

Set these values in `/etc/slurm/slurm.conf`:

```
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup,task/affinity
JobAcctGatherType=jobacct_gather/cgroup
DefMemPerNode=16384
```

For accounting, we need to install a database and another Slurm daemon.

```sh
apt install mariadb-server
```

And `slurmdbd` with:

```sh
dpkg -i slurm-smd-slurmdbd_25.05.1-1_amd64.deb
```

Set up a database in MariaDB:

```sql
mysql -e "CREATE DATABASE slurm_acct_db; CREATE USER 'slurm'@'localhost' IDENTIFIED BY 'password'; GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';"
```

Create `/etc/slurm/slurmdbd.conf`

```
DbdHost=localhost
SlurmUser=slurm
StorageType=accounting_storage/mysql
StorageHost=localhost
StorageUser=slurm
StoragePass=password
StorageLoc=slurm_acct_db
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/var/run/slurmdbd/slurmdbd.pid
```

Secure the file as the password is in plain text:

```sh
chown slurm:slurm /etc/slurm/slurmdbd.conf
chmod 600 /etc/slurm/slurmdbd.conf
```

Then add these lines to slurm.conf

```
AccountingStorageType=accounting_storage/slurmdbd
AccountingStoragePort=6819
AccountingStorageEnforce=limits,qos,safe
```

Finally, we need to configure a cluster with a name that matches the name in `slurm.conf`. An account is a logical grouping, such as a department name. It is not a user account. Actual user accounts are associated with a cluster and an account. Therefore, a minimum configuration might be:

```sh
sacctmgr add cluster cluster
sacctmgr add account name=eeg Organization=EEG
sacctmgr -i create user name=mte24 cluster=cluster account=eeg
```

To test this out, create `script1` as follows:

``` 
#!/bin/bash
# Test script
date
echo "I am now running on compute node:"
hostname
sleep 120
date
echo "Done..."
exit 0 
```

Then submit the job with a timeout of 30 seconds.

```sh
~$ sbatch -t 00:00:30 script1
Submitted batch job 10
```

The job output is in `slurm-10.out`, and we can see the completion state with `sacct`:

```sh
~$ sacct -j 10
JobID           JobName  Partition    Account  AllocCPUS      State ExitCode 
------------ ---------- ---------- ---------- ---------- ---------- -------- 
10              script1        eeg        eeg          2    TIMEOUT      0:0 
10.batch          batch                   eeg          2  COMPLETED      0:0 
```

Running a job with a specific memory and cpu limitation:

```
sbatch --mem=32768 --cpus-per-task=64 script1
```

To cancel a job, use `scancel`.

Slurm queues up jobs when the required resources can't be satisfied. What is unclear is why users won't request excessive RAM and CPU per job.
