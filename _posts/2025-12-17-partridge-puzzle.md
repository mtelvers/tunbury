---
layout: post
title: "Partridge Puzzle"
date: 2025-12-17 23:00:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/solution.png
  thumbnail: /images/thumbs/solution.png
---

Quite often, you install a new package from opam and are keen to jump right in and want a tailored example for your use case. This happened to me during [Day 12](https://www.tunbury.org/2025/12/12/advent-of-code/) of [Advent of Code](https://adventofcode.com).

I had identified the [combine](https://opam.ocaml.org/packages/combine/) package as potentially suitable to solve the day's problem of placing shapes in a grid. I cloned the git repository.

I prompted Claude Code with `Please can you read the combine directory`:

```
● Here's a summary of the combine directory:

  Overview

  Combine is an OCaml library for combinatorics problem solving, created by
  Remy El Sibaie and Jean-Christophe Filliâtre (2012-2014). Licensed under
  LGPL.

  Main Modules

  The library contains four main modules:
  - Dlx: Implements Knuth's dancing links algorithm
  - Zdd: Implements Zero-suppressed binary decision diagrams
  - Emc: Common interface to Dlx and Zdd to solve Exact Matrix Cover problems (+ SAT reduction)
  - Tiling: Converts 2D tiling problems into EMC problems

  Project Structure

  combine/
  ├── src/
  │   ├── main.ml           # CLI entry point
  │   └── lib/              # Core library
  │       ├── dlx.ml/mli    # Dancing links
  │       ├── zdd.ml/mli    # ZDD implementation
  │       ├── emc.ml/mli    # Exact Matrix Cover
  │       ├── tiling.ml/mli # 2D tiling
  │       ├── parser.mly    # Menhir parser
  │       ├── lexer.mll     # OCamllex lexer
  │       └── ...           # Other modules
  ├── tests/                # Test files
  ├── examples/
  │   ├── cmb/              # .cmb tiling problem files (pentominoes, dominos, etc.)
  │   └── lib/              # Example programs (queens, sudoku, color)
  ├── misc/                 # Statistics and test data
  ├── www/                  # Website files
  ├── dune-project          # Dune build (v2.4, uses menhir)
  └── combine.opam          # Package definition

  Dependencies

  - OCaml ≥ 4.07
  - Dune ≥ 2.4
  - Menhir ≥ 20200211
  - Zarith
  - Optional: graphics, ocamlgraph

  Tiling Language

  The project includes a DSL (.cmb files) for describing 2D tiling problems,
   with operations like union, intersection, shift, rotation, and various
  isometries.
```

This is perfect for knowing that you're on the right track. I continued with Claude and asked, "Please, can you show me an example of how to use the API to tile a 5x3 rectangle with 3 L pentoninos?"

```
● Here's how to use the Tiling API programmatically for your 3 L pentominoes
   example:

  open Combine

  (* Define the L pentomino pattern as a bool matrix *)
  let l_pattern = Tiling.Pattern.create [|
    [| true;  false; false; false |];  (* bottom row: *... *)
    [| true;  true;  true;  true  |];  (* top row:    **** *)
  |]

  (* Create 3 L tiles with ~one multiplicity and all symmetries *)
  let l_tile () =
    Tiling.Tile.create ~name:"L" ~s:Sall ~m:Mone l_pattern

  let tiles = [ l_tile (); l_tile (); l_tile () ]

  (* Define a 5x3 grid (all true = all cells available) *)
  let grid = Tiling.Pattern.create (Array.make_matrix 3 5 true)

  (* Create the problem *)
  let problem = Tiling.Problem.create ~name:"three_Ls" grid tiles

  (* Convert to EMC *)
  let emc = Tiling.Problem.ToEMC.make problem

  (* Create DLX solver *)
  let dlx = Emc.D.create_sparse ~primary:emc.primary ~columns:emc.columns
  emc.emc

  (* Check if solution exists *)
  let has_solution =
    try
      let _ = Emc.D.find_solution dlx in
      true
    with Not_found ->
      false

  (* Or get the solution *)
  let solution = Emc.D.find_solution dlx  (* raises Not_found if none *)

  (* Print ASCII output *)
  let () =
    Format.printf "%a@."
      (Tiling.Problem.ToEMC.print_solution_ascii problem emc)
      solution

  Key API functions:

  | Function                                  | Purpose                                    |
  |-------------------------------------------|--------------------------------------------|
  | Tiling.Pattern.create                     | Create a pattern from bool array array     |
  | Tiling.Tile.create ~s ~m pattern          | Create a tile with symmetries/multiplicity |
  | Tiling.Problem.create grid tiles          | Create a tiling problem                    |
  | Tiling.Problem.ToEMC.make problem         | Convert to EMC matrix                      |
  | Emc.D.create_sparse ~primary ~columns emc | Create DLX solver                          |
  | Emc.D.find_solution dlx                   | Find one solution (raises Not_found)       |
  | Emc.D.count_solutions dlx                 | Count all solution                         |

  Multiplicity options: Minf (unlimited), Mone (exactly one), Mmaybe (zero or one)

  Symmetry options: Snone (no rotations), Spositive (rotations only), Sall (rotations + reflections)
```

This was Advent of Code, so I stopped there - there's no challenge if I ask Claude to solve the puzzles - but the takeaway is that I was now able to quickly develop a solution based upon this example.

The library didn't work for me as the search space was too large; in the end, I used a deeply unsatisfying area calculation to get the solution.

Back in the summer, I was introduced to the Partridge Puzzle by [Matt Parker's](http://standupmaths.com/) YouTube video [The impossible puzzle with over a million solutions!](https://youtu.be/eqyuQZHfNPQ?si=KnQhzQ5gvRkXObSa). In the video, Matt used this puzzle as the basis for some new artwork for [Jane Street's](https://janestreet.com) office.

In the puzzle, you need to pack `k` squares of size `k x k`, and `(k-1)` squares of size `(k-1) x (k-1)` and `(k-2)` squares of size `(k-2) x (k-2)` ... and `1` square of size `1x1` into a square with side length `k * (k + 1) / 2` (the Pyrimid number of k). Matt uses `k=9` to pack the squares into a `45 x 45 = 2025` unit square.

I had originally written a basic DFS solver which placed blocks in the first free square. However, it didn't find a solution in the time I was prepared to wait. I had tried some clever optimisations, placing things sensibly to avoid narrow gaps, but these were costly to calculate and still didn't yield a solution.

Claude stepped up and generated the code using the combine library. The EMC/DLX solution was too slow due to the number of symmetrical arrangements. One `9x9` square is indistinguishable from another. Next, _we_ tried using the SAT encoding module and passed it to `minisat`. After 30 minutes, there was still no solution. Forcing an ordering to the square placement reduced the memory footprint, but there was no solution yet.

Ultimately, I threw all 40 threads of my machine at my basic DFS version, which got a result in under a minute.
