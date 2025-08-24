---
layout: post
title: "Terminal GUI for ocluster monitoring"
date: 2025-08-24 00:00:00 +0000
categories: ocaml,notty
tags: tunbury.org
image:
  path: /images/ocluster-monitor.png
  thumbnail: /images/thumbs/ocluster-monitor.png
---

I've been thinking about terminal-based GUI applications recently and decided to give [notty](https://ocaml.org/p/notty/latest) a try.

I decided to write a tool to display the status of the [ocurrent/ocluster](https://github.com/ocurrent/ocsluter) in the terminal by gathering the statistics from `ocluster-admin`. I want to have histograms showing each pool's current utilisation and backlog. The histograms will resize vertically and horizontally as the terminal size changes. And yes, I do love `btop`.

It's functional, but still a work in progress. [mtelvers/ocluster-monitor](https://github.com/mtelvers/ocluster-monitor)
