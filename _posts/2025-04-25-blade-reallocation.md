---
layout: post
title:  "Blade Server Reallocation"
date:   2025-04-25 10:15:00 +0000
categories: OCaml
tags: tunbury.org
image:
  path: /images/supermicro.png
  thumbnail: /images/thumbs/supermicro.png
---

We have changed our mind about using `dm-cache` in the SSD/RAID1 configuration. The current thinking is that the mechanical drives would be better served as extra capacity for our distributed ZFS infrastructure, where we intend to have two copies of all data, and these disks represent ~100TB of storage.

As mentioned previously, we have a deadline of Wednesday, 30th April, to move the workloads from the Equinix machines or incur hosting fees.

I also noted that the SSD capacity is 1.7TB in all cases. The new distribution is:

- rosemary: FreeBSD CI Worker (releasing spring & summer)
- oregano: OpenBSD CI Worker (releasing bremusa)
- basil: Equinix c2-2 (registry.ci.dev)
- mint: @mte24 workstation
- thyme: spare
- chives: Equinix c2-4 (opam-repo-ci) + Equinix c2-3 (OCaml-ci) + Equinix c2-1 (preview.dune.dev)
- dill: spare
- sage: docs-ci (new implementation, eventually replacing eumache)
