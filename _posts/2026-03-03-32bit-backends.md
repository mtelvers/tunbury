---
layout: post
title: "OCaml 5 native 32-bit backends: i386 and PPC32"
date: 2026-03-03 14:30:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Following on from the [Arm32 multicore backend](/2025/11/27/ocaml-54-native/), I have now ported the remaining two 32-bit architectures to OCaml 5 with multicore support: i386 and PowerPC 32-bit (PPC32).

OCaml 5's multicore runtime needs a per-domain state: the allocation pointer, exception handler, GC data and so on. On 64-bit platforms, there are registers to spare, but on 32-bit architectures, particularly i386, there are far fewer, and I want to retain the shared nature of the ppc64/ppc32 backend, which caused more problems.

# Design choices

## i386: Thread-local storage via %gs

The i386 architecture has only 7 general-purpose registers. I initially tried dedicating one to the domain state pointer, but with only 6 remaining registers, the graph colouring register allocator could not find a valid allocation for many programs. Instead, the i386 backend uses the `%gs` segment register to access thread-local storage (TLS). Every time a domain state is needed, the compiler emits:

```
movl %gs:caml_state@ntpoff, %ebx
```

This loads the domain state pointer on demand from the thread-local `caml_state` variable. It costs an extra instruction per access but keeps all general-purpose registers available for allocation. The `@ntpoff` relocation uses the local-exec TLS model, which is the fastest TLS access pattern on Linux. This mechanism is Linux/ELF-specific; on Windows, `%fs` is reserved for the Thread Information Block and `%gs` is not available for TLS in the same way, so a Windows port would need a different approach.

## PPC32: Dedicated register r30

PPC32 has 32 general-purpose registers, so dedicating one is affordable. Register r30 permanently holds the domain state pointer (`DOMAIN_STATE_PTR`), matching the approach used by Arm32 and the existing PPC64 backend. The allocation pointer lives in r31, and the exception handler pointer in r29. The PPC32 and PPC64 backends share the same source files (`emit.mlp`, `proc.ml`, `power.S`) with conditionals for the two modes, so keeping the same register assignments avoids divergence in shared code.

However, there were some challenges with position-independent code (PIC). On PPC32, calls to shared library functions go through the PLT (Procedure Linkage Table), and the PLT stubs use the GOT (Global Offset Table) to find the actual function addresses at runtime. The standard PPC32 secure-PLT convention uses r30 as the GOT base pointer, which conflicts directly with its use as `DOMAIN_STATE_PTR`. The solution was to bypass PLT stubs entirely, using a per-compilation-unit `.got2` section with PC-relative addressing for all external symbol references. This avoids the system GOT (which can overflow its 16-bit offset limit in large programs) and keeps r30 free for OCaml's use.

Another interesting thing to note is that the PPC `bltl-` instruction used for allocation checks unconditionally clobbers the link register (LR) regardless of whether the branch is taken. This is per the PPC ISA specification (LR is set when LK=1), which means LR must be saved and restored in every function that has a stack frame, not just those that make explicit calls.

# Benchmarks

Both backends were tested under QEMU using a [trivial prime counter](https://gist.github.com/mtelvers/def18d646a217c3219ba3e54c6d53bec) as a benchmark as I used for Arm32.

## i386 (QEMU, 4 vCPUs)

| Mode | Domains | Time | Speedup vs slowest |
|------|---------|------|--------------------|
| Native | 4 | 0.17s | 6.9x |
| Native | 2 | 0.35s | 3.4x |
| Native | 1 | 0.46s | 2.6x |
| Bytecode | 4 | 0.50s | 2.4x |
| Bytecode | 2 | 0.69s | 1.7x |
| Bytecode | 1 | 1.18s | 1.0x |

## PPC32 (QEMU, 1 vCPU)

| Mode | Domains | Time | Speedup vs slowest |
|------|---------|------|--------------------|
| Native | 2 | 2.02s | 9.5x |
| Native | 4 | 2.09s | 9.2x |
| Native | 1 | 2.28s | 8.5x |
| Bytecode | 1 | 19.28s | 1.0x |
| Bytecode | 4 | 19.96s | 1.0x |
| Bytecode | 2 | 20.53s | 0.9x |

The i386 results show real multicore scaling: native code with 4 domains is 2.7x faster than single-domain, and nearly 7x faster than single-domain bytecode. The PPC32 machine only has a single emulated CPU, so there is no multicore scaling, but the native backend is consistently 8-10x faster than bytecode. QEMU's `mac99` machine does not support SMP, so testing true PPC32 parallelism will need either real hardware or a different emulation platform.

# Test suites

Both backends pass the OCaml test suite with only bytecode-related exceptions. On PPC32, the two failing tests (`lazy7` and `test_compact_manydomains`) both fail only in bytecode mode; the native backend passes everything.

# Try it

Both backends are available on my fork:

```
git clone https://github.com/mtelvers/ocaml -b arm32-multicore
cd ocaml
./configure && make world.opt && make tests
```

The branch now supports Arm32, i386, and PPC32 architectures.
