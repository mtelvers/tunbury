---
layout: post
title: "ONNX inference engine using OxCaml's SIMD intrinsics"
date: 2026-03-13 18:30:00 +0000
categories: oxcaml,tessera,onnx
tags: tunbury.org
image:
  path: /images/tessera.png
  thumbnail: /images/thumbs/tessera.png
---

Following my previous [CPU vs GPU](https://www.tunbury.org/2026/03/11/gpu-vs-cpu/) post I started thinking about what the ONNX inference engine actually did and if it could be replicated in [OxCaml](https://oxcaml.org) with SIMD.

Protocol Buffers are Google's language-neutral, platform-neutral serialisation format. ONNX uses them to define its model file format. The schema is defined at [onnx/onnx.proto](https://github.com/onnx/onnx/blob/main/onnx/onnx.proto).

[mransan/ocaml-protoc](https://github.com/mransan/ocaml-protoc) is a protobuf compiler for OCaml that can read the ONNX schema and generate OCaml types and interface files.

> Tessera is a dual-backbone transformer that processes Sentinel-1 (SAR) and Sentinel-2 (multispectral) satellite imagery time-series into 128-dimensional embeddings.

Analysing the Tessera model using a Python script showed the 25 ONNX operator types used by the model.

```python
import onnx
from collections import Counter


model = onnx.load("tessera_model.onnx")
ops = Counter(node.op_type for node in model.graph.node)
for op, count in ops.most_common():
    print(f"{op:20s} {count:4d}")
print(f"\n{len(ops)} operator types, {sum(ops.values())} total nodes")
```

Operations used:

```
Add                   608
Gemm                  489
Mul                   262
Sigmoid               160
Gather                109
Unsqueeze              93
Reshape                90
Tanh                   80
Sub                    80
Transpose              75
MatMul                 46
Slice                  29
Concat                 26
LayerNormalization     18
Shape                  12
Relu                   10
Softmax                10
Squeeze                 9
ScatterND               4
Identity                4
Range                   3
Expand                  2
Sin                     2
Cos                     2
ReduceSum               2

25 operator types, 2225 total nodes
```

ocaml-protoc gives us the `.onnx` file parser and graph description. `ops.ml` implements what each operation does to tensors, and `graph.ml` walks the graph in topological order, feeding outputs of one operation as inputs into the next.

# Heap allocations

The initial emphasis was on getting a working version; then it was time to optimise the code. Profiling shows that matrix multiplication (MatMul) was the dominant operation. For example, using `Float32.Bigstring.unsafe_get` rather than `Bigarray.Array1.get` was a huge saving. As were functions like `Base_bigstring.unsafe_blit` for bulk copies.

```ocaml
let get_f32_raw (data : bigstring) byte_off =
  Stdlib_stable.Float32.to_float
    (Stdlib_stable.Float32.Bigstring.unsafe_get data ~pos:byte_off)
```

The General Matrix Multiply (GEMM) inner loop broadcasts a scalar across 8 SIMD lanes. In code, `F32x8.set1` broadcasts one element of matrix A across all 8 lanes so it can be multiplied against 8 consecutive elements of matrix B in a single instruction.

```
A[i, k] = 2.5 ->  broadcast  ->  [2.5, 2.5, 2.5, 2.5,  2.5, 2.5,  2.5, 2.5]
B[k, j..j+7]  =                  [1.0, 2.0, 3.0, 4.0,  5.0, 6.0,  7.0, 8.0]
multiply      ->                 [2.5, 5.0, 7.5, 10., 12.5, 15., 17.5, 20.]
```

The CPU instruction is `vbroadcastss` aka "broadcast scalar single-precision" into a 256-bit YMM register. One cycle to fill all 8 lanes.

In the 4-row-unrolled version, the core looked like this:

```ocaml
for kk = 0 to k - 1 do
  let a_bc0 = F32x8.set1
    (Float32_u.of_float32
      (Float32.of_float
        (get_f32_raw a_data (a_row0 + kk * 4)))) in
  ...
  (* 4 rows x SIMD FMA inner loop *)
done
```

This looks reasonable. `get_f32_raw` reads the value. `Float32.of_float` converts to float32. `Float32_u.of_float32` unboxes it. `F32x8.set1` broadcasts to all 8 lanes.

The problem is `Float32.of_float`, which returns a `float32`. A **boxed** 32-bit float. Boxed means heap-allocated, so every call allocates 16 bytes on the heap.

With 4 rows and K=512, that's 2,048 heap allocations per GEMM call just for the broadcast. For the 46 MatMuls in the model, roughly 20,000 allocations per inference.

OxCaml's `[@zero_alloc]` annotation asks the compiler to verify that a function performs no heap allocation. The function annotation looks like this:

```ocaml
let[@zero_alloc] gemm_broadcast ... =
  for kk = 0 to k - 1 do
    let a_bc0 = F32x8.set1
      (Float32_u.of_float32
        (Float32.of_float
          (get_f32_raw a_data (a_row0 + kk * 4)))) in
   ...
  done
```

The compiler rejected it:

```
Error: Annotation check for zero_alloc failed.

  (Float32.of_float
  ^^^^^^^^^^^^^^^^^
Error: called function may allocate
```

`Float32.of_float` returns a boxed `float32`, meaning that there would be heap allocation. The compiler caught it instantly. OxCaml has a complete unboxed float32 pipeline. The key types:

- `float32#` unboxed 32-bit float (kind `float32`, not `value`)
- `float32` boxed 32-bit float (heap-allocated, kind `value`)
- `float` standard 64-bit float (OCaml's usual `float`)

The allocating path went:

```
bigstring -> Float32.Bigstring.unsafe_get -> float32 (boxed)
          -> Float32.to_float             -> float   (boxed)
          -> Float32.of_float             -> float32 (boxed)
          -> Float32_u.of_float32         -> float32# (unboxed)
          -> F32x8.set1
```

Three boxed intermediates. The zero-alloc path:

```
bigstring -> Float32_u.Bigstring.unsafe_get -> float32# (unboxed)
          -> F32x8.set1
```

One step with zero allocations. The primitive `%caml_bigstring_getf32u#` reads a float32 directly into an unboxed register.

```ocaml
let[@inline always] get_f32u (data : bigstring) byte_off : float32# =
  F32u.Bigstring.unsafe_get data ~pos:byte_off
```

# Cross-module inlining detector

With the boxing addresses, annotating any hot functions like the dot product function seemed logical to highlight any allocations.

```ocaml
let[@zero_alloc] simd_dot_f32u (a_data : bigstring) a_byte
    (b_data : bigstring) b_byte len : float32# =
  ...
  while kk < len do
    sum <- F32u.fma (get_f32u a_data (a_byte + kk4))
                    (get_f32u b_data (b_byte + kk4)) sum;
    ...
  done;
  sum
```

The compiler rejected this but for a different reason:

```
Error: Annotation check for zero_alloc failed on function simd_dot_f32u.

  sum <- F32u.fma (get_f32u a_data (a_byte + kk4))
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error: called function may allocate (direct call caml_apply2_RS)
```

This time the code was correctly returning an unboxed type: `float32#`, but the function was defined in another module, and the compiler couldn't inline it across the module boundary. It fell back to a generic `caml_apply2` calling convention, which *might* allocate.

The fix was to move the `get_f32u` definition into the same module and mark it `[@inline always]`. With inlining, the compiler could verify that nothing is allocated.

With both unboxed types and same-module inlining the compiler accepted `[@zero_alloc]`:

```ocaml
let[@zero_alloc] simd_dot_f32u (a_data : bigstring) a_byte
    (b_data : bigstring) b_byte len : float32# =
  let mutable acc = F32x8.zero () in
  let mutable kk = 0 in
  while kk + 8 <= len do
    let va = F32x8.Bigstring.unsafe_unaligned_get a_data ~byte:(a_byte + kk * 4) in
    let vb = F32x8.Bigstring.unsafe_unaligned_get b_data ~byte:(b_byte + kk * 4) in
    acc <- F32x8.mul_add va vb acc;
    kk <- kk + 8
  done;
  let mutable sum = F32x8.dot acc (F32x8.one ()) in
  while kk < len do
    let kk4 = kk * 4 in
    sum <- F32u.fma (get_f32u a_data (a_byte + kk4))
                    (get_f32u b_data (b_byte + kk4)) sum;
    kk <- kk + 1
  done;
  sum
```

Every value has an unboxed layout. `acc` is `float32x8#` (layout `vec256`). `sum` is `float32#` (layout `float32`). `kk` is `int`. None of these can be stored in a `ref`; instead, use OxCaml's `let mutable` instead. The compiler then verifies that the whole function allocates nothing.

The `[@zero_alloc]` annotation was extended to every GEMM, elementwise, and activation function, replacing all cross-module scalar accessors with inline unboxed operations and replacing `numel` (which uses `Array.fold_left`, an indirect call the compiler can't prove allocation-free) with an inline loop. The scalar-only functions benefited most: Sigmoid dropped from 2.4 ms to 1.1 ms (54%), Tanh from 2.0 ms to 1.1 ms (45%), Softmax from 1.6 ms to 0.6 ms (63%).

# Graph-level optimisation

At this point, I became obsessed with the idea that ONNX must do something slightly different to just following the graph operations. With this, the next performance boost came from analysis of the graph and removing redundant passes over the data. For example, two matrix multiplications added together can be combined into a single `GemmPairAdd` operation. These graph-level passes reduced the node count from 2,225 to 1,779 and brought inference from 410 ms to 230 ms. A further 1.55x speedup on top of the kernel-level gains.

# `let mutable` notes

Standard OCaml's `ref` is a heap-allocated record:

```ocaml
type 'a ref = { mutable contents : 'a }
```

The type parameter `'a` must have a layout `value`. It must be a pointer-sized GC-traceable value. But `float32x8#` has layout `vec256` and `float32#` has layout `float32`. The type parameter of `ref` requires layout `value`, so the compiler won't let you write `ref (F32x8.zero ())`.  OxCaml's `let mutable` provides mutation without allocation:

```ocaml
let mutable acc = F32x8.zero () in
while ... do
  acc <- F32x8.mul_add va vb acc;   (* mutate in-place, in register *)
  ...
done
```

The variable lives in a register or on the stack with no heap allocation, no GC interaction, no pointer indirection. This is the construct that makes zero-alloc SIMD accumulation possible at all.

# OxCaml value add

The standard OCaml compiler produces fast code, and we can call SIMD intrinsics via C stubs without OxCaml. The boundary between "fast" and "as fast as possible" is where OxCaml's extensions sit: unboxed floats prevent heap allocation, `let mutable` provides register-resident mutable variables, `[@zero_alloc]` provides static allocation checking to identify invisible boxing in the hot path. The code is available at [mtelvers/oxcaml-infer](https://github.com/mtelvers/oxcaml-infer)

# The numbers

The OxCaml engine is currently single-threaded. I'm running it on a 20-core Xeon E5-2640 v4:

| Engine | Latency | Relative |
| --- | --- | --- |
| ONNX Runtime 1.24 (1 thread) | 88 ms | 1.0x |
| OxCaml + AVX2 (initial) | 845 ms | ~10x slower |
| OxCaml + AVX2 (optimised) | 200 ms | ~2.2x slower |
| ONNX Runtime 1.24 (default, 8+ threads) | 27 ms | |

# Try OxCaml yourself

```bash
opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
opam install ocaml-protoc
git clone https://github.com/mtelvers/oxcaml-infer
cd oxcaml-infer
dune build
dune exec bin/main.exe -- tessera_model.onnx
```

