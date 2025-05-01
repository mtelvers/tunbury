---
layout: post
title: "Reconfiguring a system with an mdadm RAID5 root"
date: 2025-05-01 12:00:00 +0000
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

# Addendum

I had tested this in QEMU with EFI under the assumption that a newly provisioned cloud machine would use EFI. However, when I ran the script against the machine, I found it used a legacy bootloader, and it was even more complicated than I had envisioned, as there were three separate MDADM arrays in place:

```
# cat /proc/mdstat 
Personalities : [raid1] [raid6] [raid5] [raid4] [raid0] [raid10] 
md2 : active raid5 sdb4[0] sdd4[2] sda4[4] sdc4[1]
      34252403712 blocks super 1.2 level 5, 512k chunk, algorithm 2 [4/4] [UUUU]
      bitmap: 2/86 pages [8KB], 65536KB chunk

md1 : active raid5 sdd3[1] sda3[2] sdc3[0] sdb3[4]
      61381632 blocks super 1.2 level 5, 512k chunk, algorithm 2 [4/4] [UUUU]
      
md0 : active raid1 sdd2[1] sda2[2] sdb2[3] sdc2[0]
      523264 blocks super 1.2 [4/4] [UUUU]
      
unused devices: <none>
```

With `lsblk` showing four disks each configured as below:

```
NAME        MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINTS
sda           8:0    0 10.9T  0 disk  
├─sda1        8:1    0    1M  0 part  
├─sda2        8:2    0  512M  0 part  
│ └─md0       9:0    0  511M  0 raid1 
│   └─md0p1 259:0    0  506M  0 part  /boot
├─sda3        8:3    0 19.5G  0 part  
│ └─md1       9:1    0 58.5G  0 raid5 
│   └─md1p1 259:1    0 58.5G  0 part  /
├─sda4        8:4    0 10.6T  0 part  
│ └─md2       9:2    0 31.9T  0 raid5 
│   └─md2p1 259:2    0 31.9T  0 part  /data
└─sda5        8:5    0  512M  0 part  [SWAP]
```

The boot device is a RAID1 mirror (four copies), so removing one of these copies is no issue. There is also a 1MB BIOS boot partition first to give some space for GRUB. The root device was RAID5 as I had anticipated.

The playbook could be adapted: double up on the `mdadm` commands to break two arrays, update two entries in `/etc/fstab` and use `grub-pc` rather than `grub-efi-amd64`. The updated playbook is [here](https://gist.github.com/mtelvers/ba3b7a5974b50422e2c2e594bed0bdb2).

For testing, I installed Ubuntu using this [script](https://gist.github.com/mtelvers/d2d333bf5c9bd94cb905488667f0cae1) to simulate the VM.

Improvements could be made, as `/boot` could be merged into `/` as there is no reason to separate them when not using EFI. There never _needed_ to be a `/boot` as GRUB2 will boot a RAID5 MDADM.

The system is a pretty minimal installation of Ubuntu, a more typical set of tools could be installed with:

```
apt install ubuntu-standard
```
