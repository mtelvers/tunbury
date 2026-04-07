---
layout: post
title:  "Coding a Digital Clock in OCaml 5 on the Raspberry Pi Pico 2 W"
date:   2026-04-07 21:22:00 +0000
categories: clock
tags: tunbury.org
image:
  path: /images/pico-clock-cad.png
  thumbnail: /images/thumbs/pico-clock-cad.png
---

While developing a Raspberry Pi GPIO library for the HD44780, [mtelvers/gpio](https://github.com/mtelvers/gpio), I noticed that 8 custom characters could be used to create the elements of a 7-segment display. I wanted this clock on the Pi Pico RP2350 dual-core ARM Cortex-M33 using my ARM 32 native compiler backend.

The [mtelvers/pico_ocaml](https://github.com/mtelvers/pico_ocaml) project already had OCaml 5 running on the Pico 2 W with WiFi, TCP/IP networking, and `Domain.spawn` multicore support. The clock would be a new application building on that foundation.

# The LCD Driver in OCaml

The HD44780 LCD uses a 4-bit parallel interface over GPIO. Rather than writing the driver in C, I implemented it entirely in OCaml with only the bare minimum GPIO primitives as C stubs:

```ocaml
external gpio_init : int -> unit = "ocaml_gpio_init"
external gpio_set_dir_out : int -> unit = "ocaml_gpio_set_dir_out"
external gpio_put : int -> bool -> unit = "ocaml_gpio_put"
external sleep_us : int -> unit = "ocaml_sleep_us"
```

The LCD driver uses an immutable record to hold the pin configuration, returned from `Lcd.init` and threaded through all operations:

```ocaml
type t = {
  rs : int; en : int;
  d4 : int; d5 : int; d6 : int; d7 : int;
  columns : int;
}

let pulse_enable t =
  gpio_put t.en false;
  sleep_us 1;
  gpio_put t.en true;
  sleep_us 1;
  gpio_put t.en false;
  sleep_us 100

let write_4bits t nibble =
  gpio_put t.d7 (nibble land 8 <> 0);
  gpio_put t.d6 (nibble land 4 <> 0);
  gpio_put t.d5 (nibble land 2 <> 0);
  gpio_put t.d4 (nibble land 1 <> 0);
  pulse_enable t
```

# Dual-Core Architecture

The final clock uses both Cortex-M33 cores:

- Core 0: WiFi connection and periodic NTP time synchronisation
- Core 1: LCD display update loop via `Domain.spawn`

The cores communicate through `Atomic` values:

```ocaml
let base_secs = Atomic.make 0
let sync_ms = Atomic.make 0
```

Core 0 updates these atomically when NTP succeeds. Core 1 reads them each second to compute the current time.

The display loop is a tail-recursive function with a boolean parameter for the blinking colon:

```ocaml
let rec display_loop lcd colon =
  let bs = Atomic.get base_secs in
  let sm = Atomic.get sync_ms in
  let elapsed = (time_ms () - sm) / 1000 in
  let day_secs = (bs + elapsed) mod 86400 in
  let hours = day_secs / 3600 in
  let minutes = (day_secs mod 3600) / 60 in
  let seconds = day_secs mod 60 in
  display_digit lcd  2 (hours / 10);
  display_digit lcd  6 (hours mod 10);
  display_colon lcd  9 colon;
  (* ... seconds display ... *)
  sleep_ms 1000;
  display_loop lcd (not colon)
```

The `not colon` tail call compiles to a simple jump with an unboxed boolean.

# Memory: Working Within Constraints

The Pico 2 W has roughly 520KB of RAM, with about 428KB available for the OCaml heap after the runtime, WiFi driver, and lwIP stack. The OCaml 5 multicore runtime needs approximately 36KB for a second domain (minor heap, stack, metadata).

Early in development, memory was much tighter (~413KB available) because the clock was compiling the full `net.ml` effects-based networking module despite only needing raw UDP for NTP. Splitting the raw network stubs into a lightweight `netif.ml` module freed 13KB of heap, which was enough for `Domain.spawn` to succeed without any explicit `Gc.compact()` or `Gc.full_major()` calls. The final code has zero GC workarounds.

## Flattened Data Structures

In OCaml, each nested array is a separate heap block that goes into a size-class pool (8KB each with our optimised pool size). Nested arrays for 10 digits would create 51 small blocks across multiple size classes, potentially consuming 24KB+ in pool overhead.

Instead, the digit patterns are stored as a single flat array:

```ocaml
(* 10 digits x 4 rows x 3 cols = 120 entries *)
let digits = [|
  1;0;7; 2;8;6; 2;8;6; 3;4;5;   (* 0 *)
  8;8;7; 8;8;6; 8;8;6; 8;8;6;   (* 1 *)
  ...
|]

let display_digit lcd col digit =
  let base = digit * 12 in
  for row = 0 to 3 do
    Lcd.move_to lcd col row;
    for c = 0 to 2 do
      let seg = digits.(base + row * 3 + c) in
      ...
```

# NTP Time Sync

The clock fetches time via NTP over UDP using raw C stubs directly without the effect handlers I had developed before. This was a deliberate design choice as the effects-based `Net.run` handler allocates closures and a 4KB receive buffer on every call, while the raw path uses a 48-byte buffer (the exact NTP packet size) and creates no closures.

The NTP timestamp (4 bytes at offset 40 in the response) represents seconds since 1900. Since a full NTP timestamp exceeds OCaml's 31-bit integer on 32-bit ARM, I compute seconds-of-day using modular arithmetic that stays in range:

```ocaml
(* 2^24 mod 86400 = 15616, 2^16 mod 86400 = 65536, 2^8 mod 86400 = 256 *)
let raw = b0 * 15616 + b1 * 65536 + b2 * 256 + b3 in
let secs_of_day = raw mod 86400 in
```

## Network Polling

NTP queries were strangely unreliable which was traced to the requirement for Core 0 to continue polling the lwIP network stack rather than just sleep. The CYW43 WiFi driver in polling mode needs regular `cyw43_arch_poll()` calls to maintain the connection. Without this, NTP success rates dropped below 50%. The code now polls every 100ms during the wait interval instead of a solid sleep:

```ocaml
for _ = 1 to resync_interval_ms / 100 do
  Netif.service_network ();
  sleep_ms 100
done
```

## PWM Slice Conflict

The backlight PWM initially used GPIO 22, which shares PWM slice 11 with GPIO 23 which turned out to be the CYW43 WiFi chip's power control pin. Calling `pwm_set_duty` on GPIO 22 disrupted the WiFi connection, resulting in 100% NTP failure. Moving the backlight to GPIO 27 (PWM slice 13, no CYW43 conflict) resolved it. On the Pico W boards, the CYW43 pins create hidden hardware constraints.

# Cross-Compilation Bugs in the OCaml Compiler

When I first tried using `/` and `mod` operators, the program crashed immediately. The assembler warned:

```
rdhi and rdlo must be different
```

OCaml compiles division by constants using a "multiply by magic reciprocal" approach. In my ARMv8-M backend (which lacks the `smmul` instruction available on ARMv6+), it falls back to `smull` (signed multiply long). The `smull` instruction writes a 64-bit result to two registers (rdlo and rdhi), and the ARM specification requires these to be different registers. The register allocator was sometimes assigning the same register (`r12`) to both.

My first fix attempt added register constraints to the ARM backend's instruction selection, forcing specific physical registers for `smull` operands. The assembler warnings disappeared, but division now produced wrong results, for example, `65343 / 3600` returned 26 instead of 18.

Eventually, I tested the magic constant itself:

```python
>>> n = 65343
>>> M = 0x6AF37C05  # magic constant from disassembly
>>> (n * M) >> 42
26  # Wrong! Should be 18
```

The magic constant was wrong! The function `divimm_parameters` in `cmm_helpers.ml` computes these constants using the Hacker's Delight algorithm with OCaml's `Nativeint` module. On the 64-bit host, `Nativeint` wraps at 2^64, but the 32-bit target needs constants computed with wrapping at 2^32.

The OCaml compiler has a module designed for exactly this purpose: `Targetint` in `utils/targetint.ml`. Its documentation says it provides "signed 32-bit integers (on 32-bit target platforms) or signed 64-bit integers (on 64-bit target platforms)." But line 64 tells the real story:

```ocaml
let size = Sys.word_size
(* Later, this will be set by the configure script
   in order to support cross-compilation. *)
```

`Targetint` uses `Sys.word_size`, which is the host's word size. The TODO comment acknowledges that the intention is to fix this for cross-compilation, but it hasn't been. On my 64-bit Raspberry Pi 5 host, `Targetint.size = 64` even when targeting 32-bit ARM.

This is a general cross-compilation bug, not ARM-specific, but it doesn't manifest because there aren't any 32-bit backends in the upstream branch. It would affect any configuration where the host word size differs from the target: 64-to-32 for me, and hypothetically 128-to-64 in the future. Division by runtime variables is unaffected as it uses a C library call (`__aeabi_idivmod` on ARM). Only division by compile-time constants triggers the multiply-by-reciprocal path.

To fix the issue, I need to set `Targetint` to the correct value and then use it throughout.

First, expose the target's word width from `./configure`. The build system already computes `arch64` (true for 64-bit targets, false for 32-bit) and writes it to `Makefile.config`. I added it to `Config`:

```ocaml
(* utils/config.generated.ml.in *)
let arch64 = @arch64@
```

Then `Targetint` uses it instead of the host's `Sys.word_size`:

```ocaml
(* utils/targetint.ml *)
let size = if Config.arch64 then 64 else 32
```

With `Targetint` now correct, `divimm_parameters` is rewritten from `Nativeint` to `Targetint`. The algorithm is unchanged; only the module is swapped:

```ocaml
let divimm_parameters d = Targetint.(
  let twopsm1 = min_int in
  let nc = sub (pred twopsm1) (unsigned_rem twopsm1 d) in
  let rec loop p (q1, r1) (q2, r2) =
    ...
  in ...)
```

The sign check and sign-bit extraction in `div_int` similarly switch from `Nativeint` to `Targetint`:

```ocaml
let m_neg = Targetint.(compare (of_int (Nativeint.to_int m)) zero) < 0 in
...
add_int t (lsr_int c1 (Cconst_int (Targetint.size - 1, dbg)) dbg) dbg)
```

# ARMv8-M smull Register Collision

In a separate, ARM-specific bug in my backend, the `smull` instruction emitted for ARMv8-M hardcoded `r12` as the low result register; however, the register allocator can also assign `r12` as the high result register. The fix in `emit.mlp` swaps to `r3` when a collision would occur:

```ocaml
let rdlo = if i.res.(0).loc = Reg 8 then "r3" else "r12" in
```

# It works!

A dual-core clock is a crazy project! I'm pleased to have done it, though. The limited memory on the Pico makes using it a constant challenge, but I managed with a single `Gc.compact()` before `Domain.spawn` to ensure the heap was defragmented for the second domain's allocation.

```
=== OCaml Digital Clock ===
  Core 0: NTP sync
  Core 1: LCD display

Connecting to WiFi...
IP: 192.168.1.41
Display running on Core 1
NTP sync: 22:32:53
NTP sync: 22:33:54
...
```

The full source is at [github.com/mtelvers/pico_ocaml](https://github.com/mtelvers/pico_ocaml). The compiler fix has been committed to my [arm32-multicore](https://github.com/mtelvers/ocaml/tree/arm32-multicore) branch.

