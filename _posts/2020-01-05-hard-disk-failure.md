---
layout: post
title:  "Hard disk failure"
date:   2020-10-05 13:41:29 +0100
categories: ubuntu
image:
  path: /images/savvio-10k-sas-disks.jpg
  thumbnail: /images/thumbs/savvio-10k-sas-disks.jpg
permalink: /hard-disk-failure/
---
Check the status with `sudo mdadm --detail /dev/md0`

    /dev/md0:
               Version : 1.2
         Creation Time : Wed Sep  2 21:55:39 2015
            Raid Level : raid5
            Array Size : 878509056 (837.81 GiB 899.59 GB)
         Used Dev Size : 292836352 (279.27 GiB 299.86 GB)
          Raid Devices : 4
         Total Devices : 4
           Persistence : Superblock is persistent

           Update Time : Sun Oct  4 07:35:23 2020
                 State : clean, degraded 
        Active Devices : 3
       Working Devices : 3
        Failed Devices : 1
         Spare Devices : 0

                Layout : left-symmetric
            Chunk Size : 512K

    Consistency Policy : resync

                  Name : plum:0  (local to host plum)
                  UUID : 4a462153:dde89a43:0a4dd678:451bb2b4
                Events : 24024

        Number   Major   Minor   RaidDevice State
           0       8       17        0      active sync   /dev/sdb1
           1       8       33        1      active sync   /dev/sdc1
           5       8       49        2      active sync   /dev/sdd1
           -       0        0        3      removed

           4       8       65        -      faulty   /dev/sde1

Check which disks are which `sudo lshw -class disk`.

| Mount    | Model       | Description                                               |
| -------- | ----------- | --------------------------------------------------------- |
| /dev/sdb | ST9300603SS | Seagate Savvio 10 K.3 St9300603ss                         |
|          | MBE2073RC   | Fujitsu MBE2073RC 73.5GB SAS Hard Drive                   |
|          | MBE2073RC   | Fujitsu MBE2073RC 73.5GB SAS Hard Drive                   |
| /dev/sdc | ST9300603SS | Seagate Savvio 10 K.3 St9300603ss                         |
| /dev/sdd | ST300MM0006 | Seagate Enterprise Performance 10K HDD ST300MM0006 300 GB |
| /dev/sde | ST9300603SS | Seagate Savvio 10 K.3 St9300603ss                         |

The boot drive is a hardware RAID1 using the two 73GB disks. `/var` made up of the 300GB disks in a software RAID5 configuration.

The ST9300603SS is still available on Amazon but the newer 10k.5 generation equivalent the ST9300605SS is on a same day delivery and it’s cheaper as well!

Remove the disk

    mdadm -r /dev/md0 /dev/sde1

This server does support hot plug but there were some zombie processes which I wanted to clear out and operationally a five minute outage would be fine.

Shutdown the server and replace the disk.  New disk (slot 2) during boot:

![](/images/perc-bios.jpg)

After the reboot copy the partition table from one of the existing disks over to the new disk.

    sfdisk -d /dev/sdb | sfdisk /dev/sde

Add the new disk into the array

    mdadm /dev/md0 -a /dev/sde1

Monitor the rebuild process

    watch -n 60 cat /proc/mdstat
