---
layout: post
title: "Reconfiguring a system with an mdadm RAID5 root"
date: 2025-04-30 12:00:00 +0000
categories: mdadm,ubuntu
tags: tunbury.org
image:
  path: /images/mdadm.jpg
  thumbnail: /images/mdadm.jpg
---

Cloud providers automatically configure their machines as they expect you to use them. For example, a machine with 4 x 8T disks might come configured with an mdadm RAID5 array spanning the disks. This may be what most people want, but we don’t want this configuration, as we want to see the bare disks. Given you have only a serial console (over SSH) and no access to the cloud-init environment, how do you boot the machine in a different configuration?

Example configuration:

```
$ lsblk
NAME    MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINTS
fd0       2:0    1    4K  0 disk
sda       8:0    0    4G  0 disk
├─sda1    8:1    0  512M  0 part  /boot/efi
└─sda2    8:2    0  3.5G  0 part
  └─md0   9:0    0 10.5G  0 raid5 /
sdb       8:16   0    4G  0 disk
└─sdb1    8:17   0    4G  0 part
  └─md0   9:0    0 10.5G  0 raid5 /
sdc       8:32   0    4G  0 disk
└─sdc1    8:33   0    4G  0 part
  └─md0   9:0    0 10.5G  0 raid5 /
sdd       8:48   0    4G  0 disk
└─sdd1    8:49   0    4G  0 part
  └─md0   9:0    0 10.5G  0 raid5 /
```

My initial approach was to create a tmpfs root filesystem and then use `pivot_root` to switch it. This worked except `/dev/md0` was still busy, so I could not unmount it.

It occurred to me that I could remove one of the partitions from the RAID5 set and use that as the new root disk. `mdadm --fail /dev/md0 /dev/sda2`, followed by `mdadm --remove /dev/md0 /dev/sda2` frees up a disk. `debootstrap` can then be used to install Ubuntu on the partition. As we have a working system, we can preserve the key configuration settings such as `/etc/hostname`, `/etc/netplan`, `/etc/fstab` etc by just copying them from `/etc` to `/mnt/etc`. Unfortunately, Ansible's copy module does not preserve ownership. Therefore, I used `rsync` instead. `/etc/fstab` must be edited to reflect the new root partition.

Lastly, run `grub-install` using `chroot` to the new environment and reboot.

```
# lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
fd0      2:0    1    4K  0 disk
sda      8:0    0    4G  0 disk
├─sda1   8:1    0  512M  0 part /boot/efi
└─sda2   8:2    0  3.5G  0 part /
sdb      8:16   0    4G  0 disk
└─sdb1   8:17   0    4G  0 part
sdc      8:32   0    4G  0 disk
└─sdc1   8:33   0    4G  0 part
sdd      8:48   0    4G  0 disk
└─sdd1   8:49   0    4G  0 part
```

The redundant RAID5 partitions can be removed with `wipefs -af /dev/sd[b-d]`

I have wrapped all the steps in an Ansible [playbook](https://gist.github.com/mtelvers/1fe3571830d982eb8adbcf5a513edb2c), which is available as a GitHub gist.
