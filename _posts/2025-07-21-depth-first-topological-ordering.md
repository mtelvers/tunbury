---
layout: post
title:  "Depth-first topological ordering"
date:   2025-07-21 00:00:00 +0000
categories: OCaml,opam
tags: tunbury.org
image:
  path: /images/dune-graph.png
  thumbnail: /images/thumbs/dune-graph.png
---

Over the last few months, I have written several posts on the package installation graphs specifically, [Topological Sort of Packages](https://www.tunbury.org/2025/03/25/topological-sort/), [Installation order for opam packages](https://www.tunbury.org/2025/03/31/opam-post-deps/) and [Transitive Reduction of Package Graph](https://www.tunbury.org/2025/06/23/transitive-reduction/). In this post, I'd like to cover a alternative ordering solution.

Considering the graph above, first presented in the [Topological Sort of Packages](https://www.tunbury.org/2025/03/25/topological-sort/), which produces the installation order below.

1. base-threads.base
2. base-unix.base
3. ocaml-variants
4. ocaml-config
5. ocaml
6. dune

The code presented processed nodes when all their dependencies are satisfied (i.e., when their in-degree becomes 0). This typically means we process "leaf" nodes (nodes with no dependencies) first and then work our way up. However, it may make sense to process the leaf packages only when required rather than as soon as they can be processed. The easiest way to achieve this is to reverse the edges in the DAG, perform the topological sort, and then install the pages in reverse order.

```ocaml
let reverse_dag (dag : PackageSet.t PackageMap.t) : PackageSet.t PackageMap.t =
  let initial_reversed = PackageMap.fold (fun package _ acc ->
    PackageMap.add package PackageSet.empty acc
  ) dag PackageMap.empty in
  PackageMap.fold (fun package dependencies reversed_dag ->
    PackageSet.fold (fun dependency acc ->
      let current_dependents = PackageMap.find dependency acc in
      PackageMap.add dependency (PackageSet.add package current_dependents) acc
    ) dependencies reversed_dag
  ) dag initial_reversed
```

With such a function, we can write this:

```ocaml
reverse_dag dune |> topological_sort |> List.rev
```

1. ocaml-variants
2. ocaml-config
3. ocaml
4. base-unix.base
5. base-threads.base
6. dune

Now, we don't install base-unix and base-threads until they are actually required for the installation of dune.
