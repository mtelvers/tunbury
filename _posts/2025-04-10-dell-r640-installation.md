---
layout: post
title:  "Dell R640 installation"
date:   2025-04-10 00:00:00 +0000
categories: Dell,R640
tags: tunbury.org
image:
  path: /images/dell-r640-final.jpg
  thumbnail: /images/thumbs/dell-r640-final.jpg
redirect_from:
  - /dell-r640-installation/
---

Today we have racked the five 14th generation Dell R640 servers and a Dell N4032 switch.

When inspecting the rack rails, I noticed that some of the left-hand rails had an extra tab on them while the others did not. For the first server, I used a rail with a tab only to discover that the tab prohibited the server from being pushed in all the way.  The tabs were easily removed but the server needed to be removed from the rack first.

![](/images/dell-r640-rail.jpg)

![](/images/dell-r640-rail-removal.jpg)

First server installed

![](/images/dell-r640-first-one.jpg)

The last server on the rails

![](/images/dell-r640-last-one.jpg)

Front view

![](/images/dell-r640-front-view.jpg)

Rear view

![](/images/dell-r640-rear-view.jpg)

Cabling

* Yellow CAT5 for iDRAC ports
* Red CAT6 for 10GBase-T

![](/images/dell-r640-cabled.jpg)

The initial iDRAC configuration was carried out using a crash cart.

![](/images/dell-r640-idrac-config.jpg)

The servers are called:

* myrina  
* thalestris  
* lampedo  
* otrera  
* antiope 

![](/images/dell-r640-final.jpg)

We had some difficulty with the 40G uplink from the switch and we could only get the link to come up by splitting it into 4 x 10G channels, as follows.

```
console>enable
console#configure
console(config)#interface Fo1/1/1
console(config-if-Fo1/1/1)#hardware profile portmode 4x10g
```

Then rebooting with `do reload`. The 4 x 10G uplinks has been configured as an LACP port channel (Po1).

# R640 Configuration

Each server has:

- 2 x Intel Xeon Gold 6244 3.6G 8C / 16T
- 8 x 16GB DIMM
- 10 x Kingston 7.68TB SSD

[Dell R640 has 24 DIMM slots](https://www.dell.com/support/manuals/en-uk/poweredge-r640/per640_ism_pub/general-memory-module-installation-guidelines?guid=guid-acbc0f13-dedb-492b-a0b0-18303ded565a&lang=en-us)

