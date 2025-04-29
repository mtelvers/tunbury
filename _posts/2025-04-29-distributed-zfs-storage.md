---
layout: post
title: "Distributed ZFS Storage"
date: 2025-04-29 20:00:00 +0000
categories: openzfs
tags: tunbury.org
image:
  path: /images/openzfs.png
  thumbnail: /images/openzfs.png
---

Following Anil’s [note](https://anil.recoil.org/notes/syncoid-sanoid-zfs), we will design and implement a distributed storage archive system for ZFS volumes and associated metadata. _Metadata_ here refers to key information about the dataset itself:

- A summary of what the dataset is
- Data retention requirement (both legal and desirable)
- Time/effort/cost required to reproduce the data
- Legal framework under which the data is available, restrictions on the distribution of the data, etc.

And also refers to the more _systems_ style meanings such as:

- Size of the dataset
- List of machines/ZFS pools where the data is stored
- Number and distribution of copies required
- Snapshot and replication frequency/policy

These data will be stored in a JSON/YAML or other structured file format.

The system would have a database of machines and their associated storage (disks/zpools/etc) and location. Each item of storage would have a 'failure domain' to logically group resources for redundancy. This would allow copies of a dataset to be placed in different domains to meet the redundancy requirements. For example, given that we are committed to holding two distinct copies of the data, would we use RAIDZ on the local disks or just a dynamic stripe, RAID0, to maximise capacity?

While under development, the system will output recommended actions - shell commands - to perform the snapshot and replication steps necessary to meet the replication and redundancy policies. Ultimately, these commands could be executed automatically.

Utilising ZFS encryption, the remote pools can be stored as an encrypted filesystem without the encryption keys.

When the data is being processed, it will be staged locally on the worker's NVMe drive for performance, and the resultant dataset _may_ be uploaded with a new dataset of metadata.
