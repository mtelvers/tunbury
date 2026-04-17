---
layout: post
title: "Building a STAC server to avoid scanning 3.8 million tiles"
date: 2026-04-17 16:30:00 +0000
categories: tessera,ocaml
tags: tunbury.org
image:
  path: /images/tessera-globe.png
  thumbnail: /images/thumbs/tessera-globe.png
---

The [GeoTessera](https://geotessera.org) project produces 128-channel geospatial embeddings from Sentinel satellite imagery. The dataset is tiled at 0.1-degree resolution across the globe, covering 9 years and comprising roughly 3.8 million tiles, each containing embeddings and scale-factor files.

These tiles live on three storage backends: the primary source on `okavango` here in Cambridge (ZFS over spinning disks), an S3 bucket in AWS us-west-2, and a CephFS cluster in Scaleway Paris. Keeping them in sync was becoming slow due to the continual scanning of the source and target.

The `s5cmd sync` or `rsync`/`rclone` approach works, but they start by listing every file on both sides to compute the diff. With 3.8 million tile directories, each containing 3 files, that scan takes a very long time.

What I wanted was an index that tracked what each store contained so that the sync could be reduced to a set difference on metadata rather than a filesystem walk.

# The existing registry

There is already `registry.parquet` which lists every tile on `okavango` with coordinates, year, file sizes, and hashes. For the target stores, I needed an equivalent parquet file per store that records which tiles it has.

Initially, the sync tool reads the content of a remote store from an `s5cmd ls` or `find` output and builds the parquet manifest. From then on, diffs are fast:

```
=== GeoTessera Sync Status ===

Registry: 3831542 tiles across 9 year(s)

Stores:
  okavango        3831542 tiles
  s3              3831566 tiles
  scaleway        3822382 tiles

Pairwise diffs (missing from target):
  okavango -> scaleway: 9184 missing
```

Copying the missing tiles then becomes a targeted operation where I can pipe the manifest into `xargs -P 32` with `s5cmd cp`, rather than letting sync discover what's missing by scanning everything.

# Fixing the Arrow library

The tool is written in OCaml using [mtelvers/arrow](https://github.com/mtelvers/arrow) for parquet I/O. The upstream `registry.parquet` uses the `large_string` Arrow type (int64 offsets) for its hash column, which the OCaml bindings didn't support. They only handled regular `utf8` (int32 offsets). Reading the column would silently pass the C++ type check (thanks to a special-case hack) but then crash when the OCaml code tried to interpret int64 offsets as int32.

The [fix](https://github.com/mtelvers/arrow/commit/c7db370) added first-class `LargeUtf8` support across the library: new `read_large_utf8` / `read_large_utf8_opt` reader functions with int64 offset handling, `large_utf8` / `large_utf8_opt` writer functions, a `LargeUtf8` variant in the high-level `Table.col_type` GADT, and updates to `fast_read` for automatic type detection. The silent special case in the C++ layer was removed in favour of proper type dispatch. The library was also bumped from C++17 to C++20 to support Arrow 23 headers.

# I didn't need a STAC server

[STAC](https://stacspec.org) (SpatioTemporal Asset Catalogue) is a standard for describing geospatial data. The sync tool doesn't use it. Previously, I created [mtelvers/tile-server](https://github.com/mtelvers/tile-server), which served as the basis for this project. It works directly with parquet files. But since we had all the tile metadata loaded anyway, wrapping it in a STAC API was straightforward and gives us:

- A standard API that tools like [pystac](https://pystac.readthedocs.io/), QGIS, and STAC browsers can query
- Per-tile asset links showing which stores have each tile and where to download it
- Spatial search by bounding box

The server loads the parquet files at startup, builds an in-memory index, and serves STAC-compliant JSON. The first store listed is the primary (its tiles form the catalogue); others are cross-referenced to populate asset links.

```json
{
  "id": "2024_grid_0.85_49.95",
  "assets": {
    "okavango": {
      "href": "https://dl2.geotessera.org/.../2024/grid_0.85_49.95",
      "file:size": 108527232,
      "file:checksum": "sha256:..."
    },
    "s3": {
      "href": "https://tessera-embeddings.s3.us-west-2.amazonaws.com/.../2024/grid_0.85_49.95"
    },
    "scaleway": {
      "href": "https://dl1.scw.geotessera.org/.../2024/grid_0.85_49.95"
    }
  }
}
```

# Map envy

The real motivation for the frontend was seeing the [GeoTessera coverage map](https://geotessera.org/coverage). It's a beautiful visualisation of global tile coverage, and I felt a bit left out with plain data tables. Using the [MapLibre GL](https://maplibre.org/) frontend on top of the STAC API, with a Sentinel-2 satellite basemap, you can browse the tile inventory spatially, inspect per-tile metadata and store locations, and more.

It's live at [stac.mint.caelum.ci.dev](https://stac.mint.caelum.ci.dev).

# The stack

The project is two OCaml binaries. Firstly, `stac-server`, which handles the STAC API using the parquet files, and secondly, `stac-sync` for CLI scanning stores, diffing manifests, generating copy lists, and recording synced tiles

Caddy sits in front as a reverse proxy, serving the static frontend at `/` and proxying `/api/*` to the OCaml server.

The source is at [mtelvers/stac-server](https://github.com/mtelvers/stac-server)
