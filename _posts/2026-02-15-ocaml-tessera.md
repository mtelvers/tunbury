---
layout: post
title: "Tessera pipeline in OCaml"
date: 2026-02-15 19:30:00 +0000
categories: ocaml,tessera
tags: tunbury.org
image:
  path: /images/manchester.png
  thumbnail: /images/thumbs/manchester.png
---

The Tessera pipeline is written in Python. What would it take to have an OCaml version?

Looking at the Python code, these are the key libraries which are used:

| Python Library | Used for |
|---|---|
| **numpy** | N-dim arrays, math, `.npy` I/O |
| **torch** | Model inference |
| **rasterio** | Read GeoTIFF (ROI mask), CRS/bounds, `transform_bounds` |
| **pystac-client** | STAC API search (Planetary Computer catalog) |
| **planetary-computer** | Sign STAC URLs (Azure SAS tokens) |
| **stackstac** | Load COGs into arrays, reproject, mosaic |

# numpy

Last year, when I first looked at the Teserra titles, I wrote [mtelvers/npy-pca](https://github.com/mtelvers/npy-pca) as a basic visualisation tool that included an npy reader. Now, I have spun that off into its own library [mtelvers/ocaml-npy](https://github.com/mtelvers/ocaml-npy). I subsequently noticed that there already was [LaurentMazare/npy-ocaml](https://github.com/LaurentMazare/npy-ocaml) which may have saved me some time!

# pystac-client and planetary-computer

For these, a new library was needed as I couldn't see an OCaml equivalent. However, OCaml already has [Eio](https://github.com/ocaml-multicore/eio), [cohttp-eio](https://github.com/mirage/ocaml-cohttp) and [yojson](https://github.com/ocaml-community/yojson), so it was relatively easy to produce [mtelvers/stac-client](https://github.com/mtelvers/stac-client), which implemented the [STAC](https://stacspec.org/) (SpatioTemporal Asset Catalogue) API, with built-in support for [Microsoft Planetary Computer](https://planetarycomputer.microsoft.com/) SAS token signing. This was easy to validate against the results from Python.

# rasterio

[geocaml/ocaml-tiff](https://github.com/geocaml/ocaml-tiff) already exists, but it does not handle tiled tiff files, which are used in the land masks. Rather than reinventing the entire library, I added tiled tiff support.

# stackstac

[geocaml/ocaml-gdal](https://github.com/geocaml/ocaml-gdal) already existed, but it lacked some required features and was a little outdated. More bindings were added for GDAL's C API using OCaml's ctypes-foreign adding:

- `GDALOpenEx` with `/vsicurl/` for reading remote COGs
- `GDALWarp` for reprojection and resampling
- `GDALRasterIO` for reading band data
- `OSRNewSpatialReference` / `OCTTransformBounds` for coordinate transformations 

# torch

[LaurentMazare/ocaml-torch](https://github.com/LaurentMazare/ocaml-torch) already existed with the latest version published on opam [janestreet/torch](https://github.com/janestreet/torch). This uses the Jane Street standard library but it seemed pointless to reimplement this using the OCaml Standard Library, so instead, I went with implementing the OCaml bindings for the ONNX runtime [mtelvers/ocaml-onnxruntime](https://github.com/mtelvers/ocaml-onnxruntime) as I only need the inference stage. The PyTorch model can be easily exported to ONNX format.

ONNX Runtime's C API uses a function-table pattern (a struct with 500+ function pointers) which doesn't easily map to ctypes. This needed a thin C shim (`libert_shim.so`) that exposed the needed functions as regular C symbols, which could be bound from OCaml.

# CPU Testing

The initial OCaml pipeline was tested on my local machine without a GPU. It stored satellite data as nested OCaml arrays (`float array array array array` for 4D data), which performed poorly. This was replaced with flat `Bigarray.Array1.t` using a stride-based index arithmetic, matching NumPy's contiguous memory layout, which performed much better. However, the real test was on a GPU.

## Benchmark results

All benchmarks on the same machine (AMD EPYC 9965 2 x 192-Core, NVIDIA L4 24GB), same dataset (269,908 pixels), same parameters (`batch_size=1024`, `num_threads=20`, `repeat_times=1`):

| Rank | Configuration | Inference Time | vs Python CPU |
|---|---|---|---|
| 1 | **OCaml + ONNX Runtime + CUDA** | **2 min 10s** | **9.5x faster** |
| 2 | Python + PyTorch + CUDA | 2 min 41s | 7.7x faster |
| 3 | Python + PyTorch (CPU) | 20 min 32s | 1x (baseline) |
| 4 | OCaml + ONNX Runtime (CPU) | 24 min 56s | 0.82x |

The OCaml + GPU configuration is the fastest overall. I put this difference down less data marshalling in OCaml before passing it to the ONNX runtime. I've also read that the ONNX Runtime might edge out ahead of PyTorch as it was purpose-built as an inference-only engine.

# Checks

The OCaml pipeline produces results that are effectively identical to Python's, differing only due to floating-point rounding.

- OCaml CPU vs Python CPU: max embedding difference of 1 in only 1,028 out of 155 million int8 elements (rounding at the quantisation boundary). Scale factors match exactly.
- GPU vs CPU (either language): max embedding difference of 1 in ~0.3% of elements, with negligible scale differences — expected floating-point rounding differences from GPU arithmetic.
