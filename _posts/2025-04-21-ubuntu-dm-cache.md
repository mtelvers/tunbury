---
layout: post
title:  "Ubuntu cloud-init with LVM and dm-cache"
date:   2025-04-21 00:00:00 +0000
categories: cloud-init, dm-cache, Ubuntu
tags: tunbury.org
image:
  path: /images/ubuntu.png
  thumbnail: /images/ubuntu.png
---

[dm-cache](https://en.wikipedia.org/wiki/Dm-cache) has been part of the mainline Linux kernel for over a decade, making it possible for faster SSD and NVMe drives to be used as a cache within a logical volume. [This technology brief from Dell](https://videos.cdn.redhat.com/summit2015/presentations/17856_getting-the-most-out-of-your-nvme-ssd.pdf) gives a good overview of `dm-cache` and the performance benefits. Skip to the graph on page 25, noting the logarithmic scale.

Given a system with a small SATADOM module, `/dev/sdd`, an SSD drive `/dev/sdc` and a couple of large-capacity spinning disks, `/dev/sd[ab]`, can we use cloud-init to configure RAID1 on the capacity disks with the SSD being used as a cache?

Unfortunately, the `storage:` / `config:` nodes are not very flexible when it comes to even modest complexity. For example, given an LVM volume group consisting of multiple disk types, it isn’t possible to create a logical volume on a specific disk as `devices:` is not a parameter to `lvm_partition`. It is also not possible to specify `raid: raid1`.

I have taken the approach of creating two volume groups, `vg_raid` and `vg_cache`, on disks `/dev/sd[ab]` and `/dev/sdc`, respectively, thereby forcing the use of the correct devices. On the `vg_raid` group, I have created a single logical volume without RAID. On `vg_cache`, I have created the two cache volumes, `lv-cache` and `lv-cache-meta`.

The `lv-cache` and `lv-cache-meta` should be sized in the ratio 1000:1.

As the final step of the installation, I used `late-commands` to configure the system as I want it. These implement RAID1 for the root logical volume, deactivate the two cache volumes as a necessary step before merging `vg_raid` and `vg_cache`, create the cache pool from the cache volumes, and finally enable the cache. The cache pool can be either _writethrough_ or _writeback_, with the default being _writethrough_. In this mode, data is written to both the cache and the original volume, so a failure in the cache device doesn’t result in any data loss. _Writeback_ has better performance as writes initially only go to the cache volume and are only written to the original volume later.

```
lvconvert -y --type raid1 -m 1 /dev/vg_raid/lv_data
lvchange -an vg_cache/lv_cache
lvchange -an vg_cache/lv_cache_meta
vgmerge vg_raid vg_cache
lvconvert -y --type cache-pool --poolmetadata vg_raid/lv_cache_meta vg_raid/lv_cache
lvconvert -y --type cache --cachemode writethrough --cachepool vg_raid/lv_cache vg_raid/lv_data
```

I have placed `/boot` and `/boot/EFI` on the SATADOM so that the system can be booted.

My full configuration given below.

```
#cloud-config
autoinstall:
  version: 1
  storage:
    config:
      # Define the physical disks
      - { id: disk-sda, type: disk, ptable: gpt, path: /dev/sda, preserve: false }
      - { id: disk-sdb, type: disk, ptable: gpt, path: /dev/sdb, preserve: false }
      - { id: disk-sdc, type: disk, ptable: gpt, path: /dev/sdc, preserve: false }
      - { id: disk-sdd, type: disk, ptable: gpt, path: /dev/sdd, preserve: false }

      # Define the partitions
      - { id: efi-part, type: partition, device: disk-sdd, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: true, offset: 1048576}
      - { id: boot-part, type: partition, device: disk-sdd, size: 1G, wipe: superblock, number: 2, preserve: false, grub_device: false }

      # Create volume groups
      - { id: vg-raid, type: lvm_volgroup, name: vg_raid, devices: [disk-sda, disk-sdb] }
      - { id: vg-cache, type: lvm_volgroup, name: vg_cache, devices: [disk-sdc] }

      # Create logical volume which will be for RAID
      - { id: lv-data, type: lvm_partition, volgroup: vg-raid, name: lv_data, size: 1000G, preserve: false}

      # Create cache metadata logical volume on SSD VG (ratio 1000:1 with cache data)
      - { id: lv-cache-meta, type: lvm_partition, volgroup: vg-cache, name: lv_cache_meta, size: 1G, preserve: false }

      # Create cache data logical volume on SSD VG
      - { id: lv-cache, type: lvm_partition, volgroup: vg-cache, name: lv_cache, size: 1000G, preserve: false }

      # Format the volumes
      - { id: root-fs, type: format, fstype: ext4, volume: lv-data, preserve: false }
      - { id: efi-fs, type: format, fstype: fat32, volume: efi-part, preserve: false }
      - { id: boot-fs, type: format, fstype: ext4, volume: boot-part, preserve: false }

      # Mount the volumes
      - { id: mount-1, type: mount, path: /, device: root-fs }
      - { id: mount-2, type: mount, path: /boot, device: boot-fs }
      - { id: mount-3, type: mount, path: /boot/efi, device: efi-fs }
  identity:
    hostname: unnamed-server
    password: "$6$exDY1mhS4KUYCE/2$zmn9ToZwTKLhCw.b4/b.ZRTIZM30JZ4QrOQ2aOXJ8yk96xpcCof0kxKwuX1kqLG/ygbJ1f8wxED22bTL4F46P0"
    username: mte24
  ssh:
    install-server: yes
    authorized-keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA7UrJmBFWR3c7jVzpoyg4dJjON9c7t9bT9acfrj6G7i mark.elvers@tunbury.org
    allow-pw: no
  packages:
    - lvm2
    - thin-provisioning-tools
  user-data:
    disable_root: false
  late-commands:
    - lvconvert -y --type raid1 -m 1 /dev/vg_raid/lv_data
    - lvchange -an vg_cache/lv_cache
    - lvchange -an vg_cache/lv_cache_meta
    - vgmerge vg_raid vg_cache
    - lvconvert -y --type cache-pool --poolmetadata vg_raid/lv_cache_meta vg_raid/lv_cache
    - lvconvert -y --type cache --cachemode writethrough --cachepool vg_raid/lv_cache vg_raid/lv_data
```
