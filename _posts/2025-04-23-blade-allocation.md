---
layout: post
title:  "Blade Server Allocation"
date:   2025-04-23 00:00:00 +0000
categories: OCaml
tags: tunbury.org
image:
  path: /images/supermicro.png
  thumbnail: /images/thumbs/supermicro.png
---

Equinix has stopped commercial sales of Metal and will sunset the service at the end of June 2026. Equinix have long been a supporter of OCaml and has provided free credits to use on their Metal platform. These credits are coming to an end at the end of this month, meaning that we need to move some of our services away from Equinix. We have two new four-node blade servers, which will become the new home for these services. The blades have dual 10C/20T processors with either 192GB or 256GB of RAM and a combination of SSD and spinning disk.

192GB, 20C/40T with 1.1TB SSD, 2 x 6T disks
- rosemary: FreeBSD CI Worker (releasing spring & summer)
- oregano: OpenBSD CI Worker (releasing bremusa)
- basil: docs-ci (new implementation, eventually replacing eumache)
- mint: spare

256GB, 20C/40T with 1.5TB SSD, 2 x 8T disks
- thyme: Equinix c2-2 (registry.ci.dev)
- chives: Equinix c2-4 (opam-repo-ci) + Equinix c2-3 (OCaml-ci) + Equinix c2-1 (preview.dune.dev)

256GB, 20C/40T with 1.1TB SSD, 2 x 6T disks
- dill: spare
- sage: spare

VMs currently running on hopi can be redeployed to chives, allowing hopi to be redeployed.

Machines which can then be recycled are:
- sleepy (4C)
- grumpy (4C)
- doc (4C)
- spring (8T)
- tigger
- armyofdockerness
