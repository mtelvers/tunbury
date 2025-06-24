---
layout: post
title:  "GNU Parallel"
date:   2025-04-13 00:00:00 +0000
categories: GNU
tags: tunbury.org
image:
  path: /images/gnu.png
  thumbnail: /images/thumbs/gnu.png
redirect_from:
  - /gnu-parallel/
---

If you haven't used it before, or perhaps it has been so long that it has been swapped out to disk, let me commend GNU's [Parallel](https://www.gnu.org/software/parallel/parallel.html) to you.

Parallel executes shell commands in parallel! A trivial example would be `parallel echo ::: A B C`, which runs `echo A`, `echo B` and `echo C`.  `{}` can be used as a placeholder for the parameter in cases where it isn't simply appended to the command line.

Multiple parameters can be read from an input file using four colons, `parallel echo :::: params_file`. This is particularly useful as it correctly deals with parameters/file names with spaces. For example, create a tab-delimited list of source and destination paths in `paths.tsv` and then run:

```shell
parallel --jobs 8 --colsep '\t' --progress rsync -avh {1} {2} :::: paths.tsv
```
