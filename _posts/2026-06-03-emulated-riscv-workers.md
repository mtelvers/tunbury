---
layout: post
title: "Emulating RISC-V workers when the hardware goes away"
date: 2026-06-03 18:00:00 +0000
categories: [ocaml, ci, riscv]
tags: tunbury.org
image:
  path: /images/riscv-logo.png
  thumbnail: /images/thumbs/riscv-logo.png
---

[Scaleway](https://www.scaleway.com/en/) provide the RISC-V workers for OCaml CI, and they have been down for about a [week](https://status.scaleway.com/incidents/knbkw67qr15j) with no real evidence that they'll be back anytime soon. I can't provision any new ones as they are "temporarily out of stock".

The `linux-riscv64` pool has dropped from 4 to 1 worker, and the queue is growing by the hour. We could drop testing on RISC-V, but that would be a little disappointing. We do have some capacity in our ARM64 pool, which could emulate RISC-V workers.

I had previously created a `Makefile` with cloud-init in [ocurrent/obuilder](https://github.com/ocurrent/obuilder/tree/master/qemu) which builds QEMU base images for the obuilder QEMU backend, so I had a good starting point. Furthermore, the current Windows workers are QEMU-based in [mtelvers/windows_worker](https://github.com/mtelvers/windows_worker).

The Linux-based workers are usually deployed using Ansible, but I could extend the cloud-init setup to complete the entire process: install Docker, pull `ocurrent/ocluster-worker:live` and extract the `ocluster-worker` binary, add the `linux-riscv64` pool capability, enable the service, and power off. The next boot is a live worker that registers and starts taking jobs.

My preferred worker layout is three disks, which is easy to emulate in QEMU. The Scaleway workers have a single disk with two loopback devices configured to create the illusion of three disks.

- root
- a disk formatted `ext4` for `/var/lib/docker`
- a disk formatted `btrfs` for `/var/cache/obuilder`

Since I'm doing this, I might as well create VMs which support the latest instruction set. The Scaleway ones are limited to older architecture, and annoyingly, Ubuntu 25.10 and 26.04 require the RVA23 profile. See [ocurrent/ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile/blob/c6fc165c232262fb7b75dc9ec7eff5ab5a0560cb/src-opam/distro.ml#L538). However, with QEMU, I can support any architecture I like. e.g. `-cpu rva23s64`. The only problem is that I need to build QEMU from source as the installed Ubuntu 24.04 only has apt packages for QEMU 8.2.

Building QEMU 11.0.1 from source with only the `riscv64-softmmu` target was very quick, and I installed it into `/usr/local`.

The only other problem I ran into was that without a `virtio-rng` device, the guest stalls during early boot waiting on the random pool. Adding `-device virtio-rng-pci` fixed it.

Since I have a generic build script, there's nothing stopping me from running this on any other free hardware. For example, I have some under-utilised POWER9 machines.

Performance is what you'd expect from emulated hardware, at least five times slower than the Scaleway VM.

I did try to rank the performance of ARM64 vs POWER9 vs AMD64, but the variability of obuilder jobs made the comparison difficult. In the noisy data, there was no machine/architecture that was obviously faster.

The `Makefile` is availble in [mtelvers/riscv_worker](https://github.com/mtelvers/riscv_worker)
