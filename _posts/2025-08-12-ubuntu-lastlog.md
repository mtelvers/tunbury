---
layout: post
title:  "Lastlog in newer Ubuntu releases"
date:   2025-08-12 00:00:00 +0000
categories: ubuntu
tags: tunbury.org
image:
  path: /images/ubuntu.png
  thumbnail: /images/thumbs/ubuntu.png
---

With the release of Ubuntu 24.10 and subsequently Ubuntu 25.04, the `lastlog` command has been removed.

Running `lastlog` results in a straight `command not found` error from the shell. Checking on an older system, `dpkg -S /usr/bin/last` and `/usr/bin/lastlog` come from packages `util-linux` and `login` respectively.

We can view the change log with `apt-get changelog login` or `apt-get changelog util-linux`, which shows a deliberate move away from these commands.

See also [https://git.launchpad.net/ubuntu/+source/util-linux/commit/?id=e8866bb93ef4cdfa36a8ec94fc43fb66d33a67e4](https://git.launchpad.net/ubuntu/+source/util-linux/commit/?id=e8866bb93ef4cdfa36a8ec94fc43fb66d33a67e4)

The suggestion is to install `wtmpdb`, which restores `last`. It's a shame as it was helpful that `lastlog` was always available so you could see if a machine had been used recently without needing to install `wtmpdb`.
