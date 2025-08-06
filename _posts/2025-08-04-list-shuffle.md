---
layout: post
title: "Shuffling Lists"
date: 2025-08-04 00:00:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Shuffling a list into a random order is usually handled by the [Fisher-Yates Shuffle](https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle).

It could be efficiently written in OCaml using arrays:

```ocaml
Random.self_init ();

let fisher_yates_shuffle arr =
  let n = Array.length arr in
  for i = n - 1 downto 1 do
    let j = Random.int (i + 1) in
    let temp = arr.(i) in
    arr.(i) <- arr.(j);
    arr.(j) <- temp
  done
```

However, I had a one-off requirement to randomise a list, and this approach felt very _functional_.

```ocaml
Random.self_init ();

let shuffle lst =
  List.map (fun x -> (Random.bits (), x)) lst |> List.sort compare |> List.map snd
```

