---
layout: post
title: "Sys.readdir or Unix.readdir"
date: 2025-07-08 00:00:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/sys-or-unix.png
  thumbnail: /images/thumbs/sys-or-unix.png
---

When you recursively scan a massive directory tree, would you use `Sys.readdir` or `Unix.readdir`? My inclination is that `Sys.readdir` feels more convenient to use, and thus the lower-level `Unix.readdir` would have the performance edge. Is it significant enough to bother with?

Quickly coding up the two different options for comparison. Here's the `Unix.readdir` version, running `Unix.opendir` then recursively calling `Unix.readdir` until the `End_of_file` exception is raised.

```ocaml
let rec traverse_directory_unix path x =
  let stats = Unix.lstat path in
  match stats.st_kind with
  | Unix.S_REG -> x + 1
  | S_LNK | S_CHR | S_BLK | S_FIFO | S_SOCK -> x
  | S_DIR ->
      try
        let dir_handle = Unix.opendir path in
        let rec read_entries acc =
          try
            match Unix.readdir dir_handle with
            | "." | ".." -> read_entries acc
            | entry ->
                let full_path = Filename.concat path entry in
                read_entries (traverse_directory_unix full_path acc)
          with End_of_file ->
            Unix.closedir dir_handle;
            acc
        in
        read_entries x
      with _ -> x
```

The `Sys.readdir` version nicely gives us an array so we can idiomatically use `Array.fold_left`.

```ocaml
let traverse_directory_sys source =
  let rec process_directory s current_source =
    let entries = Sys.readdir current_source in
    Array.fold_left
      (fun acc entry ->
        let source = Filename.concat current_source entry in
        try
          let stat = Unix.lstat source in
          match stat.st_kind with
          | Unix.S_REG -> acc + 1
          | Unix.S_DIR -> process_directory acc source
          | S_LNK | S_CHR | S_BLK | S_FIFO | S_SOCK -> acc
        with Unix.Unix_error _ -> acc)
      s entries
  in
  process_directory 0 source
```

The file system may have a big impact, so I tested NTFS, ReFS, and ext4, running each a couple of times to ensure the cache was primed.

`Sys.readdir` was quicker in my test cases up to 500,000 files. Reaching 750,000 files, `Unix.readdir` edged ahead. I was surprised by the outcome and wondered whether it was my code rather than the module I used.

Pushing for the result I expected/wanted, I rewrote the function so it more closely mirrors the `Sys.readdir` version.

```ocaml
let traverse_directory_unix_2 path =
  let rec process_directory s path =
    try
      let dir_handle = Unix.opendir path in
      let rec read_entries acc =
        try
          let entry = Unix.readdir dir_handle in
          match entry with
          | "." | ".." -> read_entries acc
          | entry ->
              let full_path = Filename.concat path entry in
              let stats = Unix.lstat full_path in
              match stats.st_kind with
              | Unix.S_REG -> read_entries (acc + 1)
              | S_LNK | S_CHR | S_BLK | S_FIFO | S_SOCK -> read_entries acc
              | S_DIR -> read_entries (process_directory acc full_path)
        with End_of_file ->
          Unix.closedir dir_handle;
          acc
      in
      read_entries s
    with _ -> s
  in
  process_directory 0 path
```

This version is indeed faster than `Sys.readdir` in all cases. However, at 750,000 files the speed up was < 0.5%.

