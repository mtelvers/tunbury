---
layout: post
title:  "Transitive Reduction of Package Graph"
date:   2025-06-23 00:00:00 +0000
categories: OCaml
tags: tunbury.org
image:
  path: /images/dune-graph.png
  thumbnail: /images/thumbs/dune-graph.png
redirect_from:
  - /transitive-reduction/
---

I have previously written about using a [topological sort](https://www.tunbury.org/topological-sort/) of a directed acyclic graph (DAG) of package dependencies to create an ordered list of installation operations. I now want to create a transitive reduction, giving a graph with the same vertices and the fewest number of edges possible.

This is interesting in opam, where a typical package is defined to depend upon both OCaml and Dune. However, Dune depends upon OCaml, so minimally the package only depends upon Dune. For opam, we would typically list both, as they may have version constraints.

```yaml
depends: [
  "dune" {>= "3.17"}
  "ocaml"
]
```

Given a topologically sorted list of packages, we can fold over the list to build a map of the packages and dependencies. As each package is considered in turn, it must either have no dependencies or the dependent package must already be in the map.

```ocaml
let pkg_deps solution =
  List.fold_left (fun map pkg ->
    let deps_direct = PackageMap.find pkg solution in
    let deps_plus_children = PackageSet.fold (fun pkg acc ->
      PackageSet.union acc (PackageMap.find pkg map)) deps_direct deps_direct in
    PackageMap.add pkg deps_plus_children map) PackageMap.empty;;
```

To generate the transitive reduction, take each set of dependencies for every package in the solution and remove those where the package is a member of the set of all the dependencies of any other directly descendant package.

```ocaml
let reduce dependencies =
  PackageMap.map (fun u ->
    PackageSet.filter (fun v ->
      let others = PackageSet.remove v u in
      PackageSet.fold (fun o acc ->
        acc || PackageSet.mem v (PackageMap.find o dependencies)
      ) others false |> not
    ) u
  );;
```

Let's create a quick print function and then test the code:

```ocaml
let print = PackageMap.iter (fun p deps ->
  print_endline (p ^ ": " ^ (PackageSet.to_list deps |> String.concat ","))
);;
```

The original solution is

```ocaml
# print dune;;
base-threads.base:
base-unix.base:
dune: base-threads.base,base-unix.base,ocaml
ocaml: ocaml-config,ocaml-variants
ocaml-config: ocaml-variants
ocaml-variants:
- : unit = ()
```

And the reduced solution is:

```ocaml
# let dependencies = pkg_deps dune (topological_sort dune);;
val dependencies : PackageSet.t PackageMap.t = <abstr>
# print (reduce dependencies dune);;
base-threads.base:
base-unix.base:
dune: base-threads.base,base-unix.base,ocaml
ocaml: ocaml-config
ocaml-config: ocaml-variants
ocaml-variants:
- : unit = ()
```

This doesn't look like much of a difference, but when applied to a larger graph, for example, 0install.2.18, the reduction is quite dramatic.

Initial graph

![opam installation graph for 0install](/images/0install-graph.png)

Transitive reduction

![Transitive reduction of the opam installation graph for 0install](/images/0install-reduced-graph.png)

