---
layout: post
title: "Upgrading to macOS Sequoia"
date: 2025-05-19 00:00:00 +0000
categories: openzfs
tags: tunbury.org
image:
  path: /images/sequoia.jpg
  thumbnail: /images/thumbs/sequoia.jpg
permalink: /macos-sequoia/
---

We have 8 Mac Minis running [OCluster](https://github.com/ocurrent/ocluster) that need to be updated to macOS Sequoia.

I'd been putting this off for some time, as the downloads are huge even in an ideal scenario. After the OS installation, there are usually updates to Xcode and OpenZFS. We have 4 x i7 units and 4 x M1 units.

Rather than using the software update button, I went to the AppStore and downloaded the [Sequoia installer](https://support.apple.com/en-gb/102662). This is approximately 15GB. I copied `/Applications/Install macOS Sequoia.app` to the other three systems of the same architecture using `rsync` to avoid downloading it on each machine. The OS updated from `Darwin 23.4.0` to `Darwin 24.5.0`.

After the OS update, I updated Xcode via Settings, Software Update. This was a 1.65GB download. This moved from `Command Line Tools for Xcode 15.3` to `Command Line Tools for Xcode 16.3`, upgrading `clang` from 25.0.0 to 27.0.0. Before moving to the remaining machines, tested [obuilder](https://github.com/ocurrent/obuilder), OpenZFS etc.

`softwareupdate --history` lists all the updates/os installations.

Wall clock time elapsed: ~3 days.
