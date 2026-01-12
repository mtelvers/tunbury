---
layout: post
title: "More OCaml on Pi Pico 2 W"
date: 2026-01-10 21:00:00 +0000
categories: ocaml,pico
tags: tunbury.org
image:
  path: /images/ocaml-pico.png
  thumbnail: /images/thumbs/ocaml-pico.png
---

Extending the Pico 2 implementation to add effects-based WiFi networking and improve the build system.

# Pio

Pio is an effects-based I/O library for OCaml 5 running bare-metal on Raspberry Pi Pico 2 W. It provides an API compatible with [Eio](https://github.com/ocaml-multicore/eio), enabling direct-style concurrent programming with cooperative fibers and non-blocking network I/O. The Pico SDK provides lwIP and CYW43 drivers but these are not thread-safe.

The code matches the Eio style, for example:

```ocaml
(* Main entry point *)
Pio.run (fun sw ->
  (* Fork concurrent fibers *)
  let p1 = Pio.Fiber.fork_promise ~sw (fun () ->
    Net.Tcp.connect ~host:"example.com" ~port:80
    ...
  ) in

  (* CPU work on Core 1 *)
  let d = Domain.spawn (fun () -> heavy_computation ()) in

  (* Await results *)
  let result1 = Pio.Promise.await_exn p1 in
  let result2 = Domain.join d in
  ...
)
```

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    Pico 2 W (RP2350)                        │
  ├─────────────────────────────┬───────────────────────────────┤
  │         Core 0              │           Core 1              │
  │  ┌───────────────────────┐  │  ┌──────────────────────────┐ │
  │  │    Pio Scheduler      │  │  │    Domain.spawn          │ │
  │  │  ┌─────┐ ┌─────┐      │  │  │  ┌──────────────────┐    │ │
  │  │  │Fiber│ │Fiber│ ...  │  │  │  │ Pure computation │    │ │
  │  │  └──┬──┘ └──┬──┘      │  │  │  │ (no effects)     │    │ │
  │  │     └───┬───┘         │  │  │  └──────────────────┘    │ │
  │  │         ▼             │  │  └──────────────────────────┘ │
  │  │   Effect Handlers     │  │              │                │
  │  │   (Fork, Await,       │  │              │                │
  │  │    Tcp_*, Udp_*)      │  │              │                │
  │  └───────────────────────┘  │              │                │
  │            │                │              │                │
  │            ▼                │              │                │
  │    lwIP + CYW43 WiFi        │       Domain.join             │
  └─────────────────────────────┴───────────────────────────────┘
```


# Build system

In a chance conversation with David, he was surprised that I had needed to do so much manual effort to complete the build. He pointed the `-output-obj` command line option to the compiler.

Compiling with `-output-obj -without-runtime` automatically provides, `caml_program`, `caml_globals`, `caml_code_segments`, `caml_exn_*`, all of which I had stubs for as well as `caml_frametable` which I covered with `frametable.S` and `caml_curry*` and `caml_apply*`, which I manually created from `curry.ml`.

The results in a single OCaml compilation step followed by a linking step for `ocaml_code.o` + `libasmrun.a`

```sh
/home/mtelvers/ocaml/ocamlopt.opt \
    -I /home/mtelvers/ocaml/stdlib \
    /home/mtelvers/ocaml/stdlib/stdlib.cmxa \
    -farch armv8-m.main -ffpu soft -fthumb \
    -output-obj -without-runtime \
    -o ${CMAKE_CURRENT_BINARY_DIR}/ocaml_code.o \
    net.ml pio.ml hello.ml
```

The only disadvantage this gave me was that it used slightly more memory than before. The increased memory requirement came from properly initialising all the stdlib modules, where I had been selective before.

The space was recovered by reducing `POOL_WSIZE`, the allocation size for major heap pools.

1. Module initialisation creates OCaml values (closures, data structures, etc.)
2. These values are first allocated in the minor heap (8KB per domain)
3. When the minor heap fills up, or during GC, surviving objects are promoted to the major heap
4. The major heap grows by allocating pools of `POOL_WSIZE` words (was 16KB reduced to 8KB)
5. Multiple objects from multiple modules share pools

Objects are packed into pools by size class which is where the saving is made. By default, there are 32 size classes, and objects of different sizes cannot share the same pool; thus, there can be underutilised pools. On a normal system this would matter, but with only 520KB of RAM this is significant.

With `POOL_WSIZE` at 4096, 17 pools were created for a total of 272K, but with the smaller 8K pools, there are 20 allocations, but only 160K used.

The change is made by editing `let arena = 2048` in `tools/gen_sizeclasses.ml` and regenerating `runtime/caml/sizeclasses.h`. The blocksizes function (lines 35-47) recursively builds size classes from 128 down to 1, adding a new size class whenever the overhead would exceed 10.1%. The change increases the number of size classes from 32 to 35.
