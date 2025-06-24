---
layout: post
title: "ZFS Replication with Ansible"
date: 2025-05-16 00:00:00 +0000
categories: openzfs
tags: tunbury.org
image:
  path: /images/openzfs.png
  thumbnail: /images/thumbs/openzfs.png
redirect_from:
  - /zfs-replcation-ansible/
---

Rather than using the agent-based approach proposed yesterday, it’s worth considering an Ansible-based solution instead.

Given a set of YAML files on a one-per-dataset basis containing any metadata we would like for administrative purposes, and with required fields such as those below. We can also override any default snapshot and replication frequencies by adding those parameters to the file.

```yaml
dataset_path: "tank/dataset-02"
source_host: "x86-bm-c1.sw.ocaml.org"
target_host: "x86-bm-c3.sw.ocaml.org”
```

The YAML files would be aggregated to create an overall picture of which datasets must be replicated between hosts. Ansible templates would then generate the necessary configuration files for `synoid` and `sanoid`, and register the cron jobs on each machine.

Sanoid uses SSH authentication, so the keys must be generated on the source machines, and the public keys must be deployed on the replication targets. Ansible can be used to manage the configuration of the keys.

Given the overall picture, we can automatically generate a markdown document describing the current setup and use Mermaid to include a visual representation.

![](/images/zfs-replication-graphic.png)

I have published a working version of this concept on [GitHub](https://github.com/mtelvers/zfs-replication-ansible). The [README.md](https://github.com/mtelvers/zfs-replication-ansible/blob/master/README.md) contains additional information.

The replication set defined in the repository, [ZFS Replication Topology](https://github.com/mtelvers/zfs-replication-ansible/blob/master/docs/replication_topology.md), is currently running for testing.

