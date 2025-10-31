---
layout: post
title:  "Scaleway Elastic Metal Reconfiguration"
date:   2025-10-31 12:00:00 +0000
categories: Scaleway
tags: tunbury.org
image:
  path: /images/scaleway-logo.png
  thumbnail: /images/thumbs/scaleway-logo.png
---

Scaleway offers the EM-L110X-SATA machine, which has 4 x 12TB disks. I've noted in a previous [post](https://www.tunbury.org/2025/05/01/removing-mdadm/) that the configuration isn't ideal for my purposes, and I outlined a way to reconfigure the machine. The premise of that post is that you can eject one of the disks from the RAID5 array to use as the new root filesystem. All well and good, but you must wait for the RAID5 array to finish building; otherwise, ejecting the disk immediately leads to an inaccessible file system.

Scaleway allows you to boot into a rescue console. This is a netboot environment which has SSH access using a randomly generated username and password.

Once booted, `lsblk` shows `md0` is now `md127` and `md1` is missing.

```
NAME          MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
loop0           7:0    0 826.6M  1 loop  /usr/lib/live/mount/rootfs/filesystem.squashfs
sda             8:0    0  10.9T  0 disk  
├─sda1          8:1    0     1M  0 part  
├─sda2          8:2    0   512M  0 part  
│ └─md127       9:127  0   511M  0 raid1 
│   └─md127p1 259:0    0   506M  0 part  
├─sda3          8:3    0  10.7T  0 part  
└─sda4          8:4    0   512M  0 part  
sdb             8:16   0  10.9T  0 disk  
├─sdb1          8:17   0     1M  0 part  
├─sdb2          8:18   0   512M  0 part  
│ └─md127       9:127  0   511M  0 raid1 
│   └─md127p1 259:0    0   506M  0 part  
├─sdb3          8:19   0  10.7T  0 part  
└─sdb4          8:20   0   512M  0 part  
sdc             8:32   0  10.9T  0 disk  
├─sdc1          8:33   0     1M  0 part  
├─sdc2          8:34   0   512M  0 part  
│ └─md127       9:127  0   511M  0 raid1 
│   └─md127p1 259:0    0   506M  0 part  
├─sdc3          8:35   0  10.7T  0 part  
└─sdc4          8:36   0   512M  0 part  
sdd             8:48   0  10.9T  0 disk  
├─sdd1          8:49   0     1M  0 part  
├─sdd2          8:50   0   512M  0 part  
│ └─md127       9:127  0   511M  0 raid1 
│   └─md127p1 259:0    0   506M  0 part  
├─sdd3          8:51   0  10.7T  0 part  
└─sdd4          8:52   0   512M  0 part  
```

`cat /proc/mdstat` shows that `md1` is now `md126` but is `inactive`:

```
Personalities : [raid1] [raid6] [raid5] [raid4] [linear] [multipath] [raid0] [raid10] 
md126 : inactive sdb3[4] sdc3[0] sda3[2] sdd3[1]
      45751787520 blocks super 1.2
       
md127 : active (auto-read-only) raid1 sdb2[3] sdc2[0] sda2[2] sdd2[1]
      523264 blocks super 1.2 [4/4] [UUUU]
      
unused devices: <none>
```


We can now use `mdadm --assemble --force --run /dev/md126 /dev/sda3 /dev/sdb3 /dev/sdc3 /dev/sdd3` bring the array back online

```
mdadm: Fail create md126 when using /sys/module/md_mod/parameters/new_array
mdadm: Marking array /dev/md126 as 'clean'
mdadm: /dev/md126 has been started with 3 drives (out of 4) and 1 rebuilding.
```

This is confirmed with `cat /proc/mdstat` which shows that the rebuild has automatically restarted and will finish in about a day.

```
root@51-159-101-156:~# cat /proc/mdstat
Personalities : [raid1] [raid6] [raid5] [raid4] [linear] [multipath] [raid0] [raid10] 
md126 : active raid5 sdc3[0] sdb3[4] sda3[2] sdd3[1]
      34313840640 blocks super 1.2 level 5, 512k chunk, algorithm 2 [4/3] [UUU_]
      [=>...................]  recovery =  8.8% (1014124636/11437946880) finish=1579.5min speed=109982K/sec
      bitmap: 10/86 pages [40KB], 65536KB chunk

md127 : active (auto-read-only) raid1 sdb2[3] sdc2[0] sda2[2] sdd2[1]
      523264 blocks super 1.2 [4/4] [UUUU]
      
unused devices: <none>
```

Stop the rebuild `echo frozen > /sys/block/md126/md/sync_action` and mount the drive as read-only.

```
mkdir -p /mnt/old
mount -o ro /dev/md126p1 /mnt/old
```

The Scaleway base installation is only ~2G, and `/tmp` is huge (as these systems have 96GB of RAM)

```
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            48G   28K   48G   1% /tmp
```

Create the backup

```
cd /mnt/old
tar czf /tmp/rootfs-backup.tar.gz \
  --exclude=./proc \
  --exclude=./sys \
  --exclude=./dev \
  --exclude=./tmp \
  --exclude=./run \
  --exclude=./mnt \
  .
```

Check if the backup was created successfully.

```
-rw-r--r-- 1 root root 1.2G Oct 31 14:50 /tmp/rootfs-backup.tar.gz
```

Unmount the drive, and stop the array.

```
cd /
umount /mnt/old
mdadm --stop /dev/md126
```

I found that the kernel was keen to remount the device, so I zeroed it out to prevent it.

```
mdadm --zero-superblock /dev/sda3 /dev/sdb3 /dev/sdc3 /dev/sdd3
```

Remove the partition from all the disks.

```
for disk in sda sdb sdc sdd; do
  parted /dev/$disk --script "rm 3 mkpart primary 1025MiB 34GiB set 3 raid on"
done
```

Create new 99GB RAID5 array (33GB × 3 usable with RAID5)

```
mdadm --create /dev/md126 --level=5 --raid-devices=4 \
  /dev/sda3 /dev/sdb3 /dev/sdc3 /dev/sdd3 \
  --chunk=512 --metadata=1.2
```

Check that it is building `cat /proc/mdstat`: 2 minutes to go!

```
Personalities : [raid1] [raid6] [raid5] [raid4] [linear] [multipath] [raid0] [raid10] 
md126 : active raid5 sdd3[4] sdc3[2] sdb3[1] sda3[0]
      103704576 blocks super 1.2 level 5, 512k chunk, algorithm 2 [4/3] [UUU_]
      [===>.................]  recovery = 19.1% (6606848/34568192) finish=2.2min speed=202080K/sec
      
md127 : active (auto-read-only) raid1 sdd2[1] sdc2[0] sdb2[3] sda2[2]
      523264 blocks super 1.2 [4/4] [UUUU]
      
unused devices: <none>
```

Create GPT partition table.

```
parted /dev/md126 mklabel gpt
parted /dev/md126 mkpart primary ext4 0% 100%
```

Format with ext4

```
mkfs.ext4 -L root /dev/md126p1
```

Verify

```
root@51-159-101-156:/# lsblk | grep md126
│ └─md126       9:126  0  98.9G  0 raid5 
│   └─md126p1 259:2    0  98.9G  0 part  
│ └─md126       9:126  0  98.9G  0 raid5 
│   └─md126p1 259:2    0  98.9G  0 part  
│ └─md126       9:126  0  98.9G  0 raid5 
│   └─md126p1 259:2    0  98.9G  0 part  
│ └─md126       9:126  0  98.9G  0 raid5 
│   └─md126p1 259:2    0  98.9G  0 part  
```

Mount the new filesystem

```
mkdir -p /mnt/new
mount /dev/md126p1 /mnt/new
```

Restore system

```
cd /mnt/new
tar xzf /tmp/rootfs-backup.tar.gz
```

Create system directories with correct permissions as these were excluded from the `tar` operation.

```
mkdir -p /mnt/new/proc
mkdir -p /mnt/new/sys
mkdir -p /mnt/new/dev
mkdir -p /mnt/new/run
mkdir -p /mnt/new/mnt
mkdir -p /mnt/new/tmp
```

Set correct permissions with the sticky bit for /tmp.

```
chmod 0555 /mnt/new/proc
chmod 0555 /mnt/new/sys
chmod 0755 /mnt/new/dev
chmod 0755 /mnt/new/run
chmod 0755 /mnt/new/mnt
chmod 1777 /mnt/new/tmp
```

Set ownership (but should already be `root:root`)

```
chown root:root /mnt/new/{proc,sys,dev,run,mnt,tmp}
```

Mount boot partition.

```
mount /dev/md127p1 /mnt/new/boot
```

Bind mount system directories for chroot.

```
mount --bind /dev /mnt/new/dev
mount --bind /proc /mnt/new/proc
mount --bind /sys /mnt/new/sys
```

Chroot into the system.

```
chroot /mnt/new /bin/bash
```

Check the original `mdadm.conf` file in `/mnt/new/etc/mdadm/mdadm.conf`.

```
ARRAY /dev/md0 metadata=1.2 UUID=54d65d24:831a6594:d2c51416:5dd1692c
ARRAY /dev/md1 metadata=1.2 spares=1 UUID=dd7844ac:07f188e7:995ade90:71c23f7b
MAILADDR root
```

And compare that with the output from `mdadm --detail --scan`.

```
ARRAY /dev/md/ubuntu-server:0 metadata=1.2 name=ubuntu-server:0 UUID=54d65d24:831a6594:d2c51416:5dd1692c
ARRAY /dev/md126 metadata=1.2 name=52-158-100-155:126 UUID=6a249202:c916a184:76fd6446:839ad3a4
```

Fix the UUID `/dev/md1` in `mdadm.conf` using your favourite text editor:

```
sed -i "s/spares=1 UUID=.*/UUID=6a249202:c916a184:76fd6446:839ad3a4/g" /mnt/new/etc/mdadm/mdadm.conf 
```

Verify the changes to `/mnt/new/etc/mdadm/mdadm.conf`.

```
ARRAY /dev/md0 metadata=1.2 UUID=54d65d24:831a6594:d2c51416:5dd1692c
ARRAY /dev/md1 metadata=1.2 UUID=6a249202:c916a184:76fd6446:839ad3a4
MAILADDR root
```

Make the same edit to `/etc/fstab`.

```
sed -i 's/dd7844ac:07f188e7:995ade90:71c23f7b/6a249202:c916a184:76fd6446:839ad3a4/' /etc/fstab
```

Update initramfs with new array config.

```
update-initramfs -u -k all
```

Reinstall GRUB on all 4 disks (for redundancy).

```
for disk in sda sdb sdc sdd; do
  echo "Installing GRUB on /dev/$disk..."
  grub-install /dev/$disk
done
```

Update GRUB config.

```
update-grub
```

Exit the chroot environment.

```
exit
```

Many people would be happy here, but the free space is now in the middle of the disk with the swap space (nearly) at the end, and this means that my new partition, 5, would be out of order. `parted /dev/sda print free`

```
Model: ATA TOSHIBA MG07ACA1 (scsi)
Disk /dev/sda: 12.0TB
Sector size (logical/physical): 512B/4096B
Partition Table: gpt
Disk Flags: 
Number  Start   End     Size    File system     Name     Flags
        17.4kB  1049kB  1031kB  Free Space
 1      1049kB  2097kB  1049kB                           bios_grub
 2      2097kB  539MB   537MB
        539MB   1075MB  536MB   Free Space
 3      1075MB  36.5GB  35.4GB                  primary  raid
        36.5GB  11.7TB  11.7TB  Free Space
 4      11.7TB  11.7TB  537MB   linux-swap(v1)
        11.7TB  12.0TB  286GB   Free Space
```

I'm going to delete the swap partition, create the new data partition, and finally, create the swap partition at the very end.

```
for disk in sda sdb sdc sdd; do
  parted /dev/$disk --script "rm 4 mkpart primary ext4 36.5GB -1GB mkpart primary linux-swap -1GB 100%"
  mkswap /dev/${disk}5
done
```

Delete the old references to the swap space from `/etc/fstab`.

```
sed -i '/swap/d' /mnt/new/etc/fstab
```

Then add the new swap space to `/etc/fstab`.

```
blkid | awk -F'"' '/TYPE="swap"/ {print "/dev/disk/by-uuid/" $2 " none swap sw 0 0"}' >> /etc/fstab
```

Unmount everything.

```
umount /mnt/new/boot
umount /mnt/new/dev
umount /mnt/new/proc
umount /mnt/new/sys
umount /mnt/new
```

Final sync and reboot.

```
sync && reboot
```
