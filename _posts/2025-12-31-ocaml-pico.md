---
layout: post
title: "Multi Domain OCaml on Raspberry Pi Pico 2 Microcontroller"
date: 2025-12-31 17:00:00 +0000
categories: ocaml,pico
tags: tunbury.org
image:
  path: /images/ocaml-pico.png
  thumbnail: /images/thumbs/ocaml-pico.png
---

Running OCaml 5 with multicore support on bare-metal Raspberry Pi Pico 2 W (RP2350, ARM Cortex-M33).

The OCaml Arm32 backend, which [I updated to OCaml 5 Domains](https://www.tunbury.org/2025/11/27/ocaml-54-native/), generates ARMv7-A code (Application profile), but the Pico 2's Cortex-M33 is ARMv8-M (Microcontroller profile). These instruction sets are compatible (both using Thumb-2), but the object file metadata differs. The linker will not mix "A" and "M" profiles.

```
error: hello.o: conflicting architecture profiles A/M
```

Initially, I worked with the existing Arm32 support, compiling to assembly files from OCaml and then patching them with `sed` and reassembling with `arm-none-eabi-as` to get a Cortex-M compatible object file.

```bash
sed -e 's/.arch[[:space:]]*armv7-a/.arch armv8-m.main/' \
    -e 's/.fpu[[:space:]]*softvfp/.fpu fpv5-sp-d16/' \
    hello.s.orig > hello.s
```

After a while, I decided to add a new architecture to the ARM backend to avoid the external processing. The Cortex-M33 has a single-precision only FPU. OCaml's float type is double-precision (64-bit), so the hardware FPU cannot accelerate OCaml floats. The default Pico SDK linker script copies some code to RAM for faster execution, including the soft FPU. I have used a custom linker script to put everything in flash to maximise the memory available for the OCaml heap.

Creating a minimal runtime was relatively simple. OCaml's calling convention puts the function pointer in r7 and calls `caml_c_call`. My function calls `blx r7` to invoke the actual C function. OCaml expects r8, r10, r11 to hold runtime state, so these are initialised with minimal structures.

- r8 - trap_ptr (exception handler)
- r10 - alloc_ptr (allocation pointer)
- r11 - domain_state_ptr (runtime state)

Thus, creating a simple program using OCaml syntax was now possible. It was also possible to have recursive functions to calculate a factorial; however, there was no garbage collector, no exception handling, no standard library and no multicore/domain support.

```ocaml
external pico_print : string -> unit = "pico_print"

let () = pico_print "Hello from OCaml!"
```

This limited success, though, was enough to inspire me to push on to the second phase. I added per-core thread-local storage and provided a mapping between pthread and Pico SDK primitives. The Pico SDK does not provide condition variables, so I implemented a simple polling solution.

OCaml's `Domain.spawn` calls `pthread_create()`, which now calls `multicore_launch_core1_with_stack()` from the Pico SDK. OCaml creates a backup thread which handles stop-the-world GC synchronisation when a domain's main thread is blocked. On the Pico, I fake the creation of the backup thread by only creating a thread on every other call to `pthread_create()`. Since there is no backup thread, during `pthread_cond_wait()`, `pthread_mutex_lock`, even in `_write`, I poll the status of the STW interrupt flag to simulate what the backup thread would do on a real OS.

All of Stdlib compiles, but I only initialise 25 modules, which don't have extensive OS dependencies.                                                                                                                                                      

- CamlinternalFormatBasics, Stdlib, Either, Sys, Obj, Type
- Atomic, CamlinternalLazy, Lazy, Seq, Option, Pair, Result
- Bool, Char, Uchar, List, Int, Array, Bytes, String, Unit
- Mutex, Condition, Domain

The curry functions are generated at link time by the OCaml linker. I am using Pico SDK linker, `arm-none-eabi-ld` and therefore the curry functions are not generated automatically. The workaround was to create a dummy OCaml file that uses enough partial applications to force the generation of `caml_curry2-8`, then extract them to assembly, `curry.s`, and add that to `libstdlib_pico.a` for linking.

As a test, I used the prime number benchmark I used for the original Arm32 work to count the number of prime numbers less than 1 million and compared the single-core and dual-core performance.

| Test        | Time      | Primes |
|-------------|-----------|--------|
| Single-core | 21,166 ms | 78,498 |
| Dual-core   | 12,350 ms | 78,498 |
| Speedup     | 1.71x     |        |

The code for this project is available in [mtelvers/pico_ocaml](https://github.com/mtelvers/pico_ocaml) and [mtelvers/ocaml](https://github.com/mtelvers/ocaml).
