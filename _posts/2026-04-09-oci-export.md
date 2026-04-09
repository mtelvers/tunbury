---
layout: post
title: "OCI image export from day10"
date: 2026-04-09 15:15:00 +0000
categories: ocaml,day10
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

[mtelvers/day10](https://github.com/mtelvers/day10) can now export build results as multi-layer OCI images, where each opam package becomes its own layer.

# Background

Previously, [mtelvers/day10](https://github.com/mtelvers/day10) could export builds into Docker using `--tag`, which assembled all layers into a single flat filesystem and piped it through `docker import`. This produced working images but threw away the layer structure that makes container distribution efficient. Every image was a single layer, regardless of how much it shared with other builds. Last year, I played with [BuildKit Bake](https://www.tunbury.org/2025/08/18/buildkit-bake/), attempting to create a Dockerfile for each package in opam. 

The new `--oci` flag generates an OCI image layout directory, which I think of as a Docker registry on the file system. Each opam package in the dependency tree becomes a separate layer, and images built into the same directory naturally deduplicate shared layers through content-addressed storage.

# Usage

Build a package and generate an OCI image:

```
day10 health-check \
  --cache-dir /var/cache/day10 \
  --opam-repository /path/to/opam-repository \
  --oci /tmp/oci-output \
  0install.2.18
```

This creates an OCI image layout at `/tmp/oci-output` with one layer per package: a base Debian/Ubuntu layer, then `ocaml-base-compiler`, `dune`, `ocamlfind`, `lwt`, and so on up to `0install` itself.

Build a second package into the same directory:

```
day10 health-check \
  --cache-dir /var/cache/day10 \
  --opam-repository /path/to/opam-repository \
  --oci /tmp/oci-output \
  0install-gtk.2.18
```

The shared dependencies including the base system, the compiler, dune, lwt, and everything else in common are not re-created. The OCI blobs directory already contains those layers, and the new image's manifest simply references them.

# Batch builds with --fork

For building many packages in parallel, pass a JSON package list and `--fork`:

```
day10 health-check \
  --cache-dir /var/cache/day10 \
  --opam-repository /path/to/opam-repository \
  --oci /tmp/oci-output \
  --fork 10 \
  @packages.json
```

All forked processes write into the same OCI directory. Layer creation is protected by file locking so concurrent builds of different packages that share dependencies don't conflict. The shared `index.json` accumulates a manifest entry for each package as it completes.

# Pushing to a registry

I used [skopeo](https://github.com/containers/skopeo) to push images to a container registry:

```
skopeo copy \
  oci:/tmp/oci-output:0install.2.18 \
  docker://docker.io/ocurrent/ocaml-packages:0install-2.18
```

If you push multiple images that share layers, the registry deduplicates them:

```
Copying blob sha256:1b7427dc... already exists
Skipping blob sha256:1b7427dc... (already present)
Copying blob sha256:f3d6a324... already exists
Skipping blob sha256:f3d6a324... (already present)
...
Writing manifest to image destination
```

# Running images with Docker

Install skopeo and load an OCI image into the Docker daemon:

```
skopeo copy \
  oci:/tmp/oci-output:0install.2.18 \
  docker-daemon:0install:2.18
```

Then run it:

```
$ docker run --rm 0install:2.18 opam exec -- 0install --version
0install (zero-install) 2.18
```

Docker shares layers between images at the storage driver level.

# The 128-layer limit

Docker's overlay2 storage driver limits each image to 128 layers, which makes it much less useful than I had hoped. Packages with deep dependency trees can exceed this, for example, `ocluster.0.3.0` has 140 layers. You can load this into a registry without complaint, but it fails with a local Docker.

```
$ skopeo copy oci:/tmp/oci-output:ocluster.0.3.0 docker-daemon:ocluster:0.3.0
FATAL: max depth exceeded
```

This is a Docker daemon infact kernel overlayfs constraint, not a registry or OCI spec limitation. The image is valid and can be stored, pushed, and pulled from any OCI-compliant registry.

The original `--tag` flag is unaffected by this change and continues to produce a single-layer image via `docker import`, which has no depth limit.

# Storage savings

Building two packages (`0install.2.18` and `ocluster.0.3.0`) into the same OCI directory:

| | Layers | Compressed size |
|---|---|---|
| 0install.2.18 | 42 | 491 MB |
| ocluster.0.3.0 | 140 | 658 MB |
| Total (no sharing) | | 1,149 MB |
| Actual on disk (deduplicated) | 158 unique blobs | 749 MB |
| Savings | 24 shared layers | 400 MB (35%) |

The savings grow with more packages. The base system (~214 MB compressed), the OCaml compiler (~138 MB), and dune (~14 MB) are shared by virtually every OCaml package. Building the full opam repository into a single OCI directory would amortise those costs across thousands of images.

# Layer caching

Layer tarballs are cached in the build cache directory alongside each package's filesystem. On subsequent runs, the layers are populated via hardlinks from the cache rather than re-tarring and re-compressing. Regenerating the full OCI layout for `0install.2.18` from a warm cache takes under a second.

# Why not Docker build?

This kind of image cannot be produced by `docker build`. A Dockerfile creates layers corresponding to `RUN` instructions, so you could write a separate `RUN opam install <pkg>` for each dependency (see [BuildKit Bake-off](https://www.tunbury.org/2025/08/18/buildkit-bake/)), but Docker provides no way to merge layers after the fact. If two images share the same base packages but install them in a different order, or with a single different package earlier in the chain, every subsequent layer differs.

[mtelvers/day10](https://github.com/mtelvers/day10) sidesteps this entirely. Each opam package is built in its own overlay filesystem, producing a diff directory that captures exactly what that package installed. These diffs are directly turned into OCI layers. Two images that happen to share `dune.3.22.0` share the same blob regardless of where it appears in their respective dependency trees.

# How it works

Each opam package is already built in an isolated overlay filesystem, producing a diff directory (`fs/`) containing only the files installed by that package. The OCI export tars each diff, converts any overlay whiteout markers to the OCI whiteout format, gzips the result, and computes SHA256 digests for both the compressed and uncompressed forms.

The OCI image layout is then assembled:

- Each layer tarball becomes a blob in `blobs/sha256/<digest>`
- An image config records the architecture, environment, and layer diff IDs
- A manifest ties the config to its layers
- An `index.json` maps image tags to manifests

The result is a spec-compliant OCI image layout that any OCI tool can consume.

