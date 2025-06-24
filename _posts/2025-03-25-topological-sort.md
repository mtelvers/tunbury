---
layout: post
title:  "Topological Sort of Packages"
date:   2025-03-25 00:00:00 +0000
categories: OCaml
tags: tunbury.org
image:
  path: /images/dune-graph.png
  thumbnail: /images/thumbs/dune-graph.png
redirect_from:
  - /topological-sort/
---

Given a list of packages and their dependencies, what order should those packages be installed in?

The above graph gives a simple example of the dependencies of the package `dune` nicely ordered right to left.

We might choose to model this in OCaml using a map with the package name as the key and a set of the dependent packages:

```ocaml
module PackageSet = Set.Make (String);;
module PackageMap = Map.Make (String);;
```

Thus, the `dune` example could be defined like this.

```ocaml
let dune = PackageMap.(empty |>
    add "ocaml" (PackageSet.(empty |> add "ocaml-config" |> add "ocaml-variants")) |>
    add "ocaml-config" (PackageSet.(empty |> add "ocaml-variants")) |>
    add "dune" (PackageSet.(empty |> add "ocaml" |> add "base-unix.base" |> add "base-threads.base")) |>
    add "ocaml-variants" (PackageSet.empty) |>
    add "base-unix.base" (PackageSet.empty) |>
    add "base-threads.base" (PackageSet.empty)
  );;
```

We can create a topological sort by first choosing any package with an empty set of dependencies.  This package should then be removed from the map of packages and also removed as a dependency from any of the sets.  This can be written concisely in OCaml

```ocaml
let rec topological_sort pkgs =
  match PackageMap.is_empty pkgs with
  | true -> []
  | false ->
      let installable = PackageMap.filter (fun _ deps -> PackageSet.is_empty deps) pkgs in
      let () = assert (not (PackageMap.is_empty installable)) in
      let i = PackageMap.choose installable |> fst in
      let pkgs = PackageMap.remove i pkgs |> PackageMap.map (fun deps -> PackageSet.remove i deps) in
      i :: topological_sort pkgs
```

This gives us the correct installation order:

```
# topological_sort dune;;
- : PackageMap.key list =
["base-threads.base"; "base-unix.base"; "ocaml-variants"; "ocaml-config"; "ocaml"; "dune"]
```
