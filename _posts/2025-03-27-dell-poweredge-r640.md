---
layout: post
title:  "Dell PowerEdge R640 Storage Server"
date:   2025-03-27 00:00:00 +0000
categories: Dell
tags: tunbury.org
image:
  path: /images/kingston-768tb.png
  thumbnail: /images/thumbs/kingston-768tb.png
permalink: /dell-poweredge-r640/
---

We have received our first batch of 7.68TB Kingston SSD drives for deployment in some Dell PowerEdge R640 servers, which will be used to create a large storage pool.

The first job was to mount each of the drives in a caddy.

![](/images/kingston-with-caddy.png)

And then install them in the server.

![](/images/kingston-in-slot.png)

These R640 servers are equipped with the Dell PERC H740P RAID controller. They support either hardware RAID 0,1,5,10,50 etc or Enhanced HBA mode.

![](/images/r640-enhanced-hba.png)

In eHBA mode, the disks operate in a passthrough mode, presenting the raw disks to the OS, however each disk needs to be specifically selected in an additional step after enabling eHBA mode.

![](/images/r640-jbod.png)

In RAID mode, one or more virtual disks need to be created to present the disks to the OS. Preconfigured profiles are available to complete this step easily.

![](/images/r640-raid5.png)

We will run these with a ZFS file system, so need to decide on whether we want to use the hardware RAID features or follow the advice on Wikipedia on the [Avoidance of hardware RAID controllers](https://en.wikipedia.org/wiki/ZFS#Avoidance_of_hardware_RAID_controllers).  Online opinion is divided.  My summary is that hardware RAID will be easier to manage when a disk fails, but ZFS on the raw disks will have some integrity advantages.
