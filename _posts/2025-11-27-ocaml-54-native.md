---
layout: post
title: "OCaml 5.4 native Arm32 branch"
date: 2025-11-27 22:05:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Recently, I have been using my Pi Zero (armv6), which has reminded me that OCaml 5 dropped native 32-bit support, and I wondered what it would take to reinstate it.

This started as a bit of tinkering; the Pi Zero is slow with a single CPU, 512MB of RAM and SD card storage. Building OCaml 5.4 takes several hours. I'd make a change in the morning, and leave it to build/fail and come back to it the next day.

There was an obvious candidate to revert starting with [PR#11904 Remove arm, i386 native-code backends](https://github.com/ocaml/ocaml/pull/11904). However, OCaml had moved on and cleaned up, so these updates now needed to include Arm32 or reverted:
[PR#12242 Refactor the computation of stack frame parameters](https://github.com/ocaml/ocaml/pull/12242), and
[PR#12686 Fix the types of C primitives and remove some that are unused](https://github.com/ocaml/ocaml/pull/12686),
[PR#13119 Introduce a platform-independent header for portable CFI/DWARF constructs](https://github.com/ocaml/ocaml/pull/13119).

However, this only restored and updated the original Arm32 code, but that code did not implement multicore. Arm64 support was added in [PR#10972 Arm64 multicore support](https://github.com/ocaml/ocaml/pull/10972), and that was the template for the Arm32 implementation.

For debugging, I used small examples, starting with the factorial example on the homepage [ocaml.org](https://ocaml.org), and then working through my [AOC](https://github.com/mtelvers/aoc2024) solutions from last year. I compiled these with `ocamlopt` and used `gdb` on the resulting code rather than trying to debug a segmentation fault in `ocamlopt.opt`. Once the compiler was working, I could use the test suite to identify the remaining issues.

The only test I could not get to run was `tests/parallel/max_domains2.ml`, which creates 129 domains. Realistically, this test is too large for a 32-bit machine with very limited memory.

I have used a trivial [prime checker](https://gist.github.com/mtelvers/def18d646a217c3219ba3e54c6d53bec) as a benchmark, which broadly shows a 3x speed improvement between native code and byte code, and 3x speed improvement in multicore over single core on a quad core machine.

```sh
./ocamlc.opt -I stdlib -o bench.byte bench.ml
./ocamlopt.opt -I stdlib -o bench.opt bench.ml
hyperfine './bench.opt 1' './bench.opt 4' './bench.byte 1' './bench.byte 4'
```

#### Raspberry Pi 2 (4 cores, ARMv7)

| Mode     | Domains | Time   | Speedup vs slowest |
|----------|---------|--------|--------------------|
| Native   | 4       | 1.61s  | 10.3x              |
| Native   | 1       | 4.79s  | 3.5x               |
| Bytecode | 4       | 5.52s  | 3.0x               |
| Bytecode | 1       | 16.56s | 1.0x               |

#### Raspberry Pi Zero (1 core, ARMv6)

| Mode     | Domains | Time   | Speedup vs slowest |
|----------|---------|--------|--------------------|
| Native   | 1       | 9.33s  | 2.5x               |
| Native   | 4       | 9.39s  | 2.5x               |
| Bytecode | 4       | 23.25s | 1.0x               |
| Bytecode | 1       | 23.38s | 1.0x               |

I have created a tidy commit history on my fork at [arm32-multicore](https://github.com/mtelvers/ocaml/commits/arm32-multicore/), but the actual path was nowhere near this orderly!

If you have a niche requirement and a spare Pi or other 32-bit Arm and want to have a play:

```sh
git clone https://github.com/mtelvers/ocaml -b arm32-multicore
cd ocaml
./configure && make world.opt && make tests
```
