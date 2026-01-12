---
layout: post
title: "Base Fibonacci"
date: 2026-01-11 21:00:00 +0000
categories: fibonacci
tags: tunbury.org
image:
  path: /images/base-fibonacci.jpg
  thumbnail: /images/thumbs/base-fibonacci.jpg
---

In Numberphile's latest [video](https://www.youtube.com/watch?v=S5FTe5KP2Cw), Tony Padilla does a 'magic trick' with Fibonacci numbers and talks about Zeckendorf decompositions, and I had my laptop out even before the video ended.

As a summary of the video, a player is asked to pick a number up to a maximum, and mark down which rows of a table their number appears in.

```
1,4,6,9,12
2,7,10
3,4,11,12
5,6,7
8,9,10,11,12
```

Let's say I picked seven as my number; it appears in row 2 and row 4. Then, I can _magically_ work out the original number by adding together the first two numbers in the row. 5 + 2 = 7. The first number in each row of the table is a Fibonacci number.

All numbers are the sum of one or more Fibonacci numbers, and there are typically multiple solutions. However, the Zeckendorf decomposition gives a unique solution by greedily subtracting the largest possible Fibonacci number. Let's see that in OCaml.

```ocaml
let to_zeckendorf n =
  let rec fibs a b acc =
    if a > n then acc else fibs b (a + b) (a :: acc)
  in
  let fib_list = fibs 1 2 [] in
  
  let rec convert remaining fibs acc =
    match fibs with
    | [] -> List.rev acc
    | f :: rest ->
        if f <= remaining then convert (remaining - f) rest (1 :: acc)
        else convert remaining rest (0 :: acc)
  in
  convert n fib_list []

let zeck_to_string bits =
  bits |> List.map string_of_int |> String.concat ""
```

Resulting in this binary-ish string representation:
```
# zeck_to_string (to_zeckendorf 7);;
- : string = "1010"
```

What we really want, though, is the original table so we can play the game with our friends with even larger numbers.

The simplest approach may be to count up while generating the Fibonacci sequence. This looks reasonably efficient. The `max_fibs` constant isn't a big constraint, as the 94th Fibonacci number is the largest which can be represented in an unsigned 64-bit integer, so we will run out of system resources long before that's an issue.

```ocaml
let fib_table hi =
  let max_fibs = 94 in
  let fibs = Array.make max_fibs 0 in
  let buckets = Array.make max_fibs [] in

  fibs.(0) <- 1;
  fibs.(1) <- 2;

  let rec decompose orig remaining i =
    if i < 0 then ()
    else if fibs.(i) <= remaining then (
      buckets.(i) <- orig :: buckets.(i);
      decompose orig (remaining - fibs.(i)) (i - 1)
    ) else
      decompose orig remaining (i - 1)
  in

  let rec go n num_fibs =
    if n > hi then num_fibs
    else
      let next = fibs.(num_fibs - 1) + fibs.(num_fibs - 2) in
      if n >= next then (
        fibs.(num_fibs) <- next;
        decompose n n num_fibs;
        go (n + 1) (num_fibs + 1)
      ) else (
        decompose n n (num_fibs - 1);
        go (n + 1) num_fibs
      )
  in

  let num_fibs = go 1 2 in
  Array.init num_fibs (fun i -> (fibs.(i), List.rev buckets.(i)))
  |> Array.to_list
```

Here is the resulting table.

```
# fib_table 100;;
- : (int * int list) list =
[(1, [1; 4; 6; 9; 12; 14; 17; 19; 22; 25; 27; 30; 33; 35; 38; 40; 43; 46; 48; 51; 53; 56; 59; 61; 64; 67; 69; 72; 74; 77; 80; 82; 85; 88; 90; 93; 95; 98]);
 (2, [2; 7; 10; 15; 20; 23; 28; 31; 36; 41; 44; 49; 54; 57; 62; 65; 70; 75; 78; 83; 86; 91; 96; 99]);
 (3, [3; 4; 11; 12; 16; 17; 24; 25; 32; 33; 37; 38; 45; 46; 50; 51; 58; 59; 66; 67; 71; 72; 79; 80; 87; 88; 92; 93; 100]);
 (5, [5; 6; 7; 18; 19; 20; 26; 27; 28; 39; 40; 41; 52; 53; 54; 60; 61; 62; 73; 74; 75; 81; 82; 83; 94; 95; 96]);
 (8, [8; 9; 10; 11; 12; 29; 30; 31; 32; 33; 42; 43; 44; 45; 46; 63; 64; 65; 66; 67; 84; 85; 86; 87; 88; 97; 98; 99; 100]);
 (13, [13; 14; 15; 16; 17; 18; 19; 20; 47; 48; 49; 50; 51; 52; 53; 54; 68; 69; 70; 71; 72; 73; 74; 75]);
 (21, [21; 22; 23; 24; 25; 26; 27; 28; 29; 30; 31; 32; 33; 76; 77; 78; 79; 80; 81; 82; 83; 84; 85; 86; 87; 88]);
 (34, [34; 35; 36; 37; 38; 39; 40; 41; 42; 43; 44; 45; 46; 47; 48; 49; 50; 51; 52; 53; 54]);
 (55, [55; 56; 57; 58; 59; 60; 61; 62; 63; 64; 65; 66; 67; 68; 69; 70; 71; 72; 73; 74; 75; 76; 77; 78; 79; 80; 81; 82; 83; 84; 85; 86; 87; 88]);
 (89, [89; 90; 91; 92; 93; 94; 95; 96; 97; 98; 99; 100])]
```

The algorithm builds up an array of lists during execution and prints the results at the end. We can't print out row 1 in the table until the entire range has been evaluated. Upon closer examination of the table, a pattern of ranges emerges. For example, for 8, we have the ranges 8-12, 29-33, 42-46, 63-67, 84-88 and finally 97-100. There must be a pattern.

Here are the Fibonacci numbers less than 12.

| index | F(n) |
|-------+------|
| 0 | 1 |
| 1 | 2 |
| 2 | 3 |
| 3 | 5 |
| 4 | 8 |

We want all numbers containing `1`. These are `1` plus all of `Z + 1`, where `Z` is `{3, 5, 8}`, the subset of the Fibonacci sequence greater than `2`. We can't use `2` as a Zeckendorf decomposition cannot have consecutive Fibonacci numbers (by definition).

Starting with the highest Fibonacci number in our subset, `8`, we cannot use `5`, but can use `3`, resulting in `8 + 1`, `8 + 3 + 1`, aka `9` and `12`. Then, taking our next highest starting number of `5`, we have only `5 + 1`, aka `6` and finally `3 + 1` aka `4`. The result is `1, 4, 6, 9, 12`.

Continuing to the next row in the output, we now need to find all the numbers containing `2` which are `Z + 2` where Z is `{5, 8}`. This results in `8 + 2` and `5 + 2`, resulting in `2, 7, 10`.

This can be written as a recursive algorithm which requires no storage beyond the Fibonacci sequence itself. It prints the numbers as they are generated.

```ocaml
let fib_print hi =
  let rec build a b acc =
    if a > hi then Array.of_list (List.rev acc)
    else build b (a + b) (a :: acc)
  in
  let fibs = build 1 2 [] in
  let n = Array.length fibs in
  Array.iteri (fun k fk ->
    Printf.printf "%d:" fk;
    let rec go idx value prev_used =
      if fk + value > hi then ()
      else if idx < 0 then
        Printf.printf " %d" (fk + value)
      else if idx >= k - 1 && idx <= k + 1 then
        go (idx - 1) value false
      else (
        go (idx - 1) value false;
        if not prev_used then
          go (idx - 1) (value + fibs.(idx)) true
      )
    in
    go (n - 1) 0 false;
    print_newline ()
  ) fibs
```

