---
layout: post
title: "Advent of Code 2025"
date: 2025-12-12 18:00:00 +0000
categories: aoc
tags: tunbury.org
image:
  path: /images/aoc2025.png
  thumbnail: /images/thumbs/aoc2025.png
---

With the start of Advent comes a new set of Advent of Code problems. My code is available at [mtelvers/aoc2025](https://github.com/mtelvers/aoc2025).

# Day 1 - Secret Entrance

A dial points to 50. Follow the sequence of turns to see how many times it lands on zero. The only gotcha here was that the real input had values > 100.

```
L68
L30
R48
L5
R60
L55
L1
L99
R14
L82
```

Part 2 was fiddly as the corner cases needed careful consideration. Landing on zero should be counted, so start with the answer from part 1. Add the number of clicks to turn through divided by 100 (the quotient) to count the number of full rotations. Then add the cases where the turning left by the number of clicks modulo 100 would be less than zero, and the same for turning right when it would be greater than 100.

Note that starting at 0 and turning left 5 does not count as passing zero. So if your zero passing test is `position < value`, then this is only true when `position > 0`.
# Day 2 - Gift Shop

Find repeating patterns in some number ranges.

```
11-22,95-115,998-1012,1188511880-1188511890,222220-222224,
1698522-1698528,446443-446449,38593856-38593862,565653-565659,
824824821-824824827,2121212118-2121212124
```

## Part 1

I decided right away to use integer comparison rather than converting numbers to strings and then comparing them. The number of digits in an integer when written in base 10 is the `1 + int(log10 x)`. For part 1, the challenge was to look for exact splits `11` or `123123`; therefore, the length must be even. We can use the divisor `10^(length/2)`, and test with `x / divisor = x mod divisor` and sum all the numbers where this is true.

## Part 2

The problem is extended to allow any equal chunking. Thus, `824824824` is now valid as it has three chunks of 3 digits. Given the maximum length of a 64-bit integer is 20 digits, we only need the factors of the numbers 1 to 20, which could be entered as a static list. I decided to calculate these in code using a simple division test up to the square root of the number. I should memoise these results to avoid repeated recalculation. Once I had a list of factors, I folded over the list, testing each with a recursive function to verify that each chunk was equal.

```ocaml
let base = pow 10 factor in
let modulo = x mod base in

let rec loop v =
  if v = 0 then true
  else if v mod base = modulo then loop (v / base)
  else false
in

loop (x / base)
```

The only gotcha I found was that numbers less than 10 came out as true, so I constrained the lower bound of the range to 10.
# Day 3 - Lobby

Sum the largest number you can make using N digits from the given sequences. The order of the digits cannot be changed.

```
987654321111111
811111111111119
234234234234278
818181911112111
```

## Part 1

As it was initially presented, you are only required to consider two digits. As `9_` will always be bigger than `8_`, this becomes a case of finding the largest digit available, which still leaves one digit. If there is more than one digit left, then pick the largest one. For example, given `818181911112111`, the largest first digit is `9`, followed by the largest digit in `11112111`, which is 2.

I pattern-matched the list of numbers to extract two digits in a recursive loop:

```ocaml
let rec loop max_left max_right = function
  | l :: r :: tl ->
    if l > max_left then loop l r (r :: tl)
    else if r > max_right then loop max_left r (r :: tl)
    else loop max_left max_right (r :: tl)
  | _ -> (max_left, max_right)
in
let l, r = loop 0 0 bank in
let num = l * 10 + r
```

## Part 2

Annoyingly, this changed the problem significantly, as it increased the number length from 2 to 12. My list approach now seemed unworkable, and I switched to using arrays.

Taking `818181911112111` as an example, I extracted `8181`, leaving 11 digits available and found the maximum value, which is the first `8`. Then I extracted a new subarray, `1818`, starting after the first digit matched and leaving 10 digits available. The maximum here is the `8` at index 1. Repeating this process, finding the maximum in `181`, then of `19`, and finally, all the remaining numbers must be taken to achieve the correct length.

```
818181911112111

8181 -> i=0 [i]=8
1818 -> i=1 [i]=8
181 -> i=1 [i]=8
19 -> i=1 [i]=9
1 -> i=0 [i]=1
1 -> i=0 [i]=1
1 -> i=0 [i]=1
1 -> i=0 [i]=1
2 -> i=0 [i]=2
1 -> i=0 [i]=1
1 -> i=0 [i]=1
1 -> i=0 [i]=1
```

This worked out nicely, and I parameterised the function to accept the length of the number required so that I could use this code for part 1 as well.

# Day 4 - Paper Bale Warehouse

Find the number of `@` which have fewer than four `@` as neighbours.

```
..@@.@@@@.
@@@.@.@.@@
@@@@@.@.@@
@.@@@@..@.
@@.@@@@.@@
.@@@@@@@.@
.@.@.@.@@@
@.@@@.@@@@
.@@@@@@@@.
@.@.@@@.@.
```

I chose	to read the input into a Map, which I have used several times before, so I copied my implementation from AoC 2024 Day 10.

```ocaml
type coord = { y : int; x : int }

module CoordMap = Map.Make (struct
  type t = coord

  let compare = compare
end)
```

I set up a list of directions around the centre point.

```ocaml
let neighbours =
  [
    { y = 1; x = -1 };
    { y = 1; x = 0 };
    { y = 1; x = 1 };
    { y = 0; x = -1 };
    { y = 0; x = 1 };
    { y = -1; x = -1 };
    { y = -1; x = 0 };
    { y = -1; x = 1 };
  ]
```

## Part 1

Fold over the map, and where there is an `@`, I folded over the list of neighbours, counting the number with bales, which could then be summed in the outer fold.

## Part 2

For the second part, the free bales needed to be removed, and then the calculation was repeated, trying again until no more bales could be removed.

At this point, I realised that the map could be simplified to a set, as there is no need to distinguish between the boundary and an empty square.

Therefore, rather than just counting the free bales, I added these to a set which could be subtracted from the original set and iterated.

```ocaml
let rec part2 w =
  CoordSet.fold
    (fun k acc -> if is_free_bales w k then CoordSet.add k acc else acc)
    w CoordSet.empty
  |> fun free_bales ->
  if CoordSet.is_empty free_bales then CoordSet.cardinal w
  else CoordSet.diff w free_bales |> part2

let () =
  Printf.printf "part 2: %i\n" (CoordSet.cardinal warehouse - part2 warehouse)
```
# Day 5 - Cafeteria

Count the number of elements from the second list which appear in the list of (inclusive) ranges.

```
3-5
10-14
16-20
12-18

1
5
8
11
17
32
```

## Part 1

I read the input data into two variables, `fresh` as a list of pairs for the ranges and `ingredients` as an int list. For part one, it's just a case of summing values where the ingredient falls within the range:

```ocaml
let part1 =
  List.fold_left
    (fun f i ->
      List.find_opt (fun (l, h) -> i >= l && i <= h) fresh |> function
      | Some _ -> f + 1
      | _ -> f)
    0 ingredients
```

## Part 2

Ignoring the second list, count the values represented by the list of ranges. `3-5,10-14` would be a `3 + 5 = 8`. I didn't verify this, but it is likely that the actual input ranges aren't as tidy as the example data. We are told that ranges overlap, but I expect there will be ranges that entirely encompass other ranges, as well as ranges that are immediately adjacent, and so on. I wrote an `add` function to add a range to a list of ranges. I think it would have looked better using `type range = { low: int; high: int }`, but I'd come this far using pairs.

```ocaml
let add (low, high) t =
  let rec loop acc (low, high) = function
    | [] -> List.rev ((low, high) :: acc)
    | (l, h) :: tl when h + 1 < low -> loop ((l, h) :: acc) (low, high) tl
    | (l, h) :: tl when high + 1 < l ->
        List.rev_append acc ((low, high) :: (l, h) :: tl)
    | (l, h) :: tl -> loop acc (min l low, max h high) tl
  in
  loop [] (low, high) t
```

I wrote some test cases to cover the weird cases not present in the example data.

```ocaml
[] |> add (2, 5) |> add (7, 9);;                 # simple [(2, 5); (7, 9)]
[] |> add (2, 5) |> add (7, 9) |> add (4, 8);;   # join [(2, 9)]
[] |> add (2, 5) |> add (7, 9) |> add (1, 10);;  # encompass [(1, 10)]
[] |> add (2, 5) |> add (6, 9);;                 # adjacent [(2, 9)]
```

With the code tested, part 2 used the `add` function to create a combined list, and then summed the difference between the high and low values + 1. 

```ocaml
let part2 =
  List.fold_left (fun acc (l, h) -> add (l, h) acc) [] fresh
  |> List.fold_left (fun acc (l, h) -> acc + (h - l + 1)) 0
```
# Day 6 - Trash Compactor

Sum the cryptically presented equations.

```
123 328  51 64 
 45 64  387 23 
  6 98  215 314
*   +   *   +  
```

# Part 1

Apply the operator at the bottom of the column to the numbers above it and sum the results.

This was a straightforward case of reading a list of lines, then splitting it up into a list of lists of numbers, resulting in a kind of matrix. Use a transpose function and then apply the operator on each list using a fold operation. Note that it's just addition and multiplication, both of which are commutative.

```ocaml
let rec transpose = function
  | [] | [] :: _ -> []
  | rows -> List.map List.hd rows :: transpose (List.map List.tl rows)
```

# Part 2

It was odd in the original input that sometimes there was one space between the numbers, while other times there were two. This all became clear in part 2, as the problem was reframed that the numbers themselves were also transposed. Thus, the far right column was actually `4 + 431 + 623`.

Reading the input as characters and transposing it resulted in, what is in effect, the part 1 problem, but the data structure isn't pretty.

```
1  *
24  
356 
    
369+
248 
8   
    
 32*
581 
175 
    
623+
431 
  4 
```

I can see that you could write a conversion function for both the part 1 and the transposed part 2 structure into a standard format and use the same processing function to sum both datasets, but I didn't!

I created a `split_last` function to from the last element from each row (list).

```ocaml
let rec split_last = function
  | [] -> assert false
  | [ x ] -> ([], x)
  | x :: xs ->
      let init, last = split_last xs in
      (x :: init, last)
```

This gives me the operator plus a list of characters. The list of characters can be concatenated, trimmed and converted into a number. Then, using an inelegant fold which threads the operator, the intermediate sum and the overall sum, you can calculate the answer.
# Day 7 - Laboratories

Starting from `S`, beam down through the map, splitting at each `^`.

```
.......S.......
...............
.......^.......
...............
......^.^......
...............
.....^.^.^.....
...............
....^.^...^....
...............
...^.^...^.^...
...............
..^...^.....^..
...............
.^.^.^.^.^...^.
...............
```

I read the diagram as a map of `(x,y)` coordinates, but in retrospect, a list of arrays may have been a more optimal choice.

## Part 1

In this part, calculate how many times we reach an `^`. This is a breadth-first search tracking the number of beams at each iteration. I used a coordinate map to track the beams at each level which helpfully automatically absorbs duplicate beams.

## Part 2

This time, follow each possible path and count how many ways there are to get to the end. This is a depth-first search where the trivial algorithm works on the test dataset, but with the actual input, the number of possibilities is too large. Therefore, I added a hashtbl to memoise the results at each level. With this, all 25 trillion ways are counted in a matter of a few milliseconds.
# Day 8 - Playground

Compute the distance between vectors in 3D space and build them into a graph by linking the closest pairs.

```
162,817,812
57,618,57
906,360,560
592,479,940
352,342,300
466,668,158
542,29,236
431,825,988
739,650,466
52,470,668
216,146,977
819,987,18
117,168,530
805,96,715
346,949,466
970,615,88
941,993,340
862,61,35
984,92,344
425,690,689
```

I read the input in as a list of vectors `type vector = { x : float; y : float; z : float }`. Next, I computed a list of distances between all the pairs, resulting in a `((vector * vector) * float) list`. A network is a set of vectors, and overall, there is a set of networks. I couldn't decide on the best way to store this, so for expediency, I went with sets.

```ocaml
module Network = Set.Make (struct
  type t = vector

  let compare = compare
end)

module NetworkSet = Set.Make (Network) 
```

With this, I wrote a function to join two nodes together. This first checks if either node already existed in any network. If neither node exists, create a new network with those two nodes. If one node exists in any network, then add the other node. If both nodes exist, then union the two networks together. As adding a value to a set is idempotent, it is not necessary to distinguish which value needs to be added: `|> Network.add v1 |> Network.add v2`

```ocaml
let join v1 v2 acc =
  let s1, s2 =
    NetworkSet.partition (fun vs -> Network.mem v1 vs || Network.mem v2 vs) acc
  in  
  NetworkSet.singleton
    (match NetworkSet.cardinal s1 with
    | 0 -> Network.(singleton v1 |> add v2)
    | 1 -> NetworkSet.choose s1 |> Network.add v1 |> Network.add v2
    | 2 -> NetworkSet.fold (fun vs acc -> Network.union acc vs) s1 Network.empty
    | _ -> assert false)
  |> NetworkSet.union s2

```

# Part 1

Take the first 1000 vector pairs and add them to the `NetworkSet`, then convert the `NetworkSet` into a list of the size of each network, sort the list, take the first three and fold over them to get the answer.

# Part 2

Continue adding vector pairs until all the vectors are connected then find the produce of the x coordinate of the final two vectors. I used a recursive function to repeatedly add pairs until the size of the network equalled the total number of vectors.
# Day 9 - Movie Theatre

The input is a set of vertices. Draw the largest rectangle between any pair.

The vertices were specified as a list.

```
7,1
11,1
11,7
9,7
9,5
2,5
2,3
7,3
```

Visually, this is:

```
..............
.......#...#..
..............
..#....#......
..............
..#......#....
..............
.........#.#..
..............
```

## Part 1

This couldn't have been easier, particularly following day 8, as the input parser and combination generator are the same. Calculate the area of all the rectangles, then sort the list to find the largest.

## Part 2

The extension was that the rectangle must be within the polygon defined by the input list of vertices. The input coordinates are in the range 0-100,000 on both x and y; therefore, we must do this mathematically, as the set will be too large.

To test if a polygon is contained within another polygon, then all vertices of A must be inside B, and none of the edges of A must cross the edges of B.

I used the ray casting algorithm to determine if a point was in a polygon. Due to the way the coordinate grid works, the code is somewhat messy, as all the boundaries are contained within the shape. Then test all pairs of edges to see if they crossed using the cross product to see if the endpoints lie on opposite sides of the infinite line defined by the other segment.

# Day 10 - Factory

The input is a pattern of lights, followed by a list of buttons and which lights they turn on and finally a list of counter values.

```
[.##.] (3) (1,3) (2) (2,3) (0,2) (0,1) {3,5,4,7}
[...#.] (0,2,3,4) (2,3) (0,4) (0,1,2) (1,2,3,4) {7,5,12,7,2}
[.###.#] (0,1,2,3,4) (0,3,4) (0,1,2,4,5) (1,2) {10,11,11,5,10,5}
```

# Part 1

Press the buttons to toggle the lights on/off until you achieve the target pattern. The lights are a target bit pattern (but in reverse order), and the button positions are bit positions. So, `(1,3)` means toggle bits 1 and 3. The problem then becomes a breadth-first search through all the possible options. Starting at 0, xor that once for each button, then xor each of those with all the buttons again. This width grows quickly, but there aren't many bit positions, so it only takes a few iterations to cover all the possible values. I used a set of integers to store the values at each iteration.

# Part 2

In part two, there are n counters set to zero; you need to increment the counters until you get to the values specified in the final field of the input data. Pressing button `(1,3)` increments counters 1 and 3 by one. You might view this as an extension of the first problem, but since the counter target values range from 1 to 300, the problem depth is too great to be solved naively using a BFS.

Looking at the first example in more detail, I rewrote it like this:

```
btn | 0 1 2 3 | index
----+---------+----
3   | 0 0 0 1 | 5
1,3 | 0 1 0 1 | 4
2   | 0 0 1 0 | 3
2,3 | 0 0 1 1 | 2
0,2 | 1 0 1 0 | 1
0,1 | 1 1 0 0 | 0
----+---------+----
    | 3 5 4 7
```

From that matrix, a set of equations can be written as

```
v0 + v1 = 3
v0 + v4 = 5
v1 + v2 + v3 = 4
v2 + v4 + v5 = 7
```

These linear equations need to be solved, and the minimum sum solution found. I used the package [lp](https://opam.ocaml.org/packages/lp/) to do this.

```ocaml
#require "lp";;
#require "lp-glpk";;
open Lp

let v = Array.init 6 (fun i -> var ~integer:true (Printf.sprintf "v%d" i))
  
let sum indices = 
  List.fold_left (fun acc i -> acc ++ v.(i)) (c 0.0) indices 
  
let obj = minimize (sum [0; 1; 2; 3; 4; 5])   (* sum of all variables *)

let constraints = [
  sum [0; 1] =~ c 3.0;       (* v0 + v1 = 3 *)
  sum [0; 4] =~ c 5.0;       (* v0 + v4 = 5 *)
  sum [1; 2; 3] =~ c 4.0;    (* v1 + v2 + v3 = 4 *)
  sum [2; 4; 5] =~ c 7.0;    (* v2 + v4 + v5 = 7 *)
]
  
let problem = make obj constraints

let () =
  match Lp_glpk.solve problem with
  | Ok (obj_val, xs) ->
      Printf.printf "Minimum: %.2f\n" obj_val;
      Array.iteri (fun i var ->
        Printf.printf "v%d = %.2f\n" i (PMap.find var xs)
      ) v
  | Error msg ->
      print_endline msg
```

This gives the solution as 10.

```
GLPK Simplex Optimizer 5.0
4 rows, 6 columns, 10 non-zeros
      0: obj =   0.000000000e+00 inf =   1.900e+01 (4)
      4: obj =   1.000000000e+01 inf =   0.000e+00 (0)
OPTIMAL LP SOLUTION FOUND
GLPK Integer Optimizer 5.0
4 rows, 6 columns, 10 non-zeros
6 integer variables, none of which are binary
Integer optimization begins...
Long-step dual simplex will be used
+     4: mip =     not found yet >=              -inf        (1; 0)
+     4: >>>>>   1.000000000e+01 >=   1.000000000e+01   0.0% (1; 0)
+     4: mip =   1.000000000e+01 >=     tree is empty   0.0% (0; 1)
INTEGER OPTIMAL SOLUTION FOUND
Minimum: 10.00
v0 = 3.00
v1 = 0.00
v2 = 4.00
v3 = 0.00
v4 = 2.00
v5 = 1.00
```

All that is left is to sum the answer for each line of input.
# Day 11 - Reactor

Count the number of paths to traverse a graph.

# Part 1

```
aaa: you hhh
you: bbb ccc
bbb: ddd eee
ccc: ddd eee fff
ddd: ggg
eee: out
fff: out
ggg: out
hhh: ccc fff iii
iii: out
```

In the first part, the task was to count the number of many ways to get from `you` to `out`. There aren't many, so a simple depth-first search worked out of the box.

```ocaml
module Outputs = Set.Make (String)
module Racks = Map.Make (String)

let rec dfs = function
  | "out" -> 1
  | r -> Outputs.fold (fun o acc -> acc + dfs o) (Racks.find r racks) 0

let () = dfs "you" |> Printf.printf "Part 1: %i\n"
```

# Part 2

The examples for the second part unusually gave new data. However, the puzzle input was the same. The new example data removed the `you` node and added an `svr` node. The question is now, how many ways from `svr` to `out`, but passing through `fft` and `dac`?

```
svr: aaa bbb
aaa: fft
fft: ccc
bbb: tty
tty: ccc
ccc: ddd eee
ddd: hub
hub: fff
eee: dac
dac: fff
fff: ggg hhh
ggg: out
hhh: out
```

On my actual dataset, the number of ways from `svr` to `out` was vast (45 quadrillion), so we definitely need memoisation. The key here was to realise that it was a DAG and so either `dac` to `fft` was possible or `fft` to `dac` was possible, but not both.

Using a DFS I calculated the number of paths between the key components and simplied the graph to four nodes. Since `dac` to `fft` has zero paths, the path must be `svr` to `fft` to `dac` to `out`. Thus the solution is `1 * 1 * 2 = 2`.

```
                   ┌─────┐
                   │ svr │
                   └──┬──┘
            ┌─────────┴─────────┐
            │                   │
          2 │                   │ 1
            │                   │
            ▼         0         ▼
         ┌─────┐ ──────────► ┌─────┐
         │ dac │      1      │ fft │
         └──┬──┘ ◄────────── └──┬──┘
            │                   │
          2 │                   │ 4
            │                   │
            │      ┌─────┐      │
            └────► │ out │ ◄────┘
                   └─────┘
```

# Day 12 - Christmas Tree Farm

```
0:
###
##.
##.

1:
###
##.
.##

2:
.##
###
##.

3:
##.
###
##.

4:
###
#..
###

5:
###
.#.
###

4x4: 0 0 0 0 2 0
12x5: 1 0 1 0 2 2
12x5: 1 0 1 0 3 2
```

This is a packing problem. Given this input, `12x5: 1 0 1 0 2 2`, take a 12x5 grid and try to place 1 copy of shape 0, 1 copy of shape 2, 2 copies each of shapes 4 and 5.

On face value, this is a variation on the pentominoes problem, and the packing does not need to be complete. Fortunately, I looked at the real dataset before coding up a depth-first search to place the objects.

My first line of actual input is `45x41: 52 43 45 41 47 59`, still with 3x3 shapes to be placed. This is a massive problem space. Google has shown that Knuth's Dancing Links is a common approach for this, and OCaml/opam has a [combine](https://opam.ocaml.org/packages/combine/) package that implements this. I read the input data and passed it to the library to solve. However, the problem was too large.

As there are so many ways to pack the shapes, may there always be a solution at this scale? I used a simplistic area calculation to try this. I calculated the area of each shape, multiplied it by the number of copies and compared it to the area of the grid. Rightly or wrongly, this gave the correct answer to the problem on the real dataset (but not on the test input)

