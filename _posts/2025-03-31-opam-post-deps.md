---
layout: post
title: "Installation order for opam packages"
date: 2025-03-31 00:00:00 +0000
categories: opam
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
---

Previously, I discussed the installation order for a simple directed acyclic graph without any cycles. However, `opam` packages include _post_ dependencies. Rather than package A depending upon B where B would be installed first, _post_ dependencies require X to be installed after Y. The _post_ dependencies only occur in a small number of core OCaml packages. They are quite often empty and exist to direct the solver. Up until now, I had been using a base layer with an opam switch containing the base compiler and, therefore, did not need to deal with any _post_ dependencies.

Here is the graph of [0install](/images/0install.2.18-with-post-with-colour.pdf) with _post_ dependencies coloured in red.

Removing the _post_ dependencies gives an unsatisfying graph with orphaned dependencies. [0install without post](/images/0install.2.18-without-post.pdf). Note `base-nnp.base` and `base-effects.base`. However, this graph can be used to produce a linear installation order. The orphaned packages can be removed with a recursive search.

When opam wants to decide the installation order, it uses OCamlgraph's topological sort capability.

> This functor provides functions which allow iterating over a graph in topological order. Cycles in graphs are allowed. Specification is the following: If vertex [x] is visited before vertex [y] then either there is a path from [x] to [y], or there is no path from [y] to [x].  In the particular case of a DAG, this simplifies to: if there is an edge from [x] to [y], then [x] is visited before [y].

The description of `fold` is particularly interesting as the order for cycles is unspecified.

> [fold action g seed] allows iterating over the graph [g] in topological order. [action node accu] is called repeatedly, where [node] is the node being visited, and [accu] is the result of the [action]'s previous invocation, if any, and [seed] otherwise.  If [g] contains cycles, the order is unspecified inside the cycles and every node in the cycles will be presented exactly once

In my testing, the installation order matches the order used by opam within the variation allowed above.

Layers can be built up using the intersection of packages installed so far and the required dependencies.
