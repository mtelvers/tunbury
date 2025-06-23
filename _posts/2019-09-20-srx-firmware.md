---
layout: post
title:  "Juniper SRX100 Firmware Update"
date:   2019-09-20 13:41:29 +0100
categories: juniper
image:
  path: /images/SRX100H2.jpg
  thumbnail: /images/thumbs/SRX100H2.jpg
permalink: /srx-firmware/
---
Download the latest version of the software and copy it over to the SRX

    scp junos-srxsme-12.3X48-D65.1-domestic.tgz root@192.168.1.1:/var/tmp

On the SRX install the software into the alternative root partition

    request system software add /var/tmp/junos-srxsme-12.3X48-D65.1-domestic.tgz no-copy no-validate unlink

Reboot

    request system reboot

Once it has rebooted, update the alternate image to the new version.

    request system snapshot slice alternate
