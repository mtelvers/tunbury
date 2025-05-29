---
layout: post
title: "Raptor Talos II - POWER9 unreliability"
date: 2025-04-29 12:00:00 +0000
categories: power9
tags: tunbury.org
image:
  path: /images/raptor-talos-ii.jpg
  thumbnail: /images/thumbs/raptor-talos-ii.jpg
---

We have two Raptor Computing Talos II POWER9 machines. One of these has had issues for some time and cannot run for more than 20 minutes before locking up completely. Over the last few days, our second machine has exhibited similar issues and needs to be power-cycled every ~24 hours. I spent some time today trying to diagnose the issue with the first machine, removing the motherboard as recommended by Raptor support, to see if the issue still exists with nothing else connected. Sadly, it does. I noted that a firmware update is available, which would move from v2.00 to v2.10.

![](/images/raptor-computing.jpeg)
