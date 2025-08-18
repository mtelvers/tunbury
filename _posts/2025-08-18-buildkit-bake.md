---
layout: post
title:  "BuildKit Bake-off"
date:   2025-08-18 00:00:00 +0000
categories: docker,buildkit,opam
tags: tunbury.org
image:
  path: /images/docker-logo.png
  thumbnail: /images/thumbs/docker-logo.png
---

I previously [wrote](https://www.tunbury.org/2025/07/22/package-tool/) about a [mtelvers/package-tool](mtelvers/package-tool) which would generate Dockerfiles for each package in opam.

The tool also created a single 10MB Dockerfile containing all ~4000 package builds. Each build looked like this:

```dockerfile
FROM debian:12 AS builder_package_name
RUN apt update && apt upgrade -y
# ... setup opam
RUN opam install dependency1.version >> build.log 2>&1 || echo 'FAILED' >> build.log
RUN opam install dependency2.version >> build.log 2>&1 || echo 'FAILED' >> build.log
RUN opam install package.version >> build.log 2>&1 || echo 'FAILED' >> build.log
```

Followed by a final aggregation step:

```dockerfile
FROM debian:12 AS results
COPY --from=builder_package_1 ["/home/opam/build.log", "/results/package1"]
COPY --from=builder_package_2 ["/home/opam/build.log", "/results/package2"]
# ... ~4000 times
```

This is a spectacular failure. Docker's RPC layer cannot handle the 10MB Dockerfile, throwing `COMPRESSION_ERROR` messages.

I attempted to bypass Docker's RPC limitations and go straight to BuildKit.

```bash
buildctl build \
  --frontend dockerfile.v0 \
  --local context=. \
  --local dockerfile=. \
  --output type=image,name=myimage:latest
```

The result was the same: compression errors. BuildKit's RPC layer cannot handle the massive Dockerfile either.

Surely there is an elegant solution to build this with Docker? I generated a `docker-bake.hcl` file defining all the targets:

```hcl
group "all-packages" {
  targets = [
    "pkg-0install-2-18",
    "pkg-abella-2-0-8",
    // ... ~4000 packages
  ]
}
```

BuildKit starts fine, but collapses in a few seconds with errors like `rpc error: code = NotFound desc = no such job`.

```bash
$ docker buildx bake results
 => [internal] load local bake definitions
 => => reading docker-bake.hcl 698.97kB / 698.97kB
 => [pkg-random-package internal] load build definition from random-package.dockerfile
 => => transferring dockerfile: 4.74kB
...
ERROR: target pkg-random-package: failed to receive status: rpc error: code = NotFound desc = no such job dwu7wqewt4vppoe4lhe3xx44f
```

Maybe BuildKit just needed some restraint? I tried various approaches:

```bash
export GOMAXPROCS=100
export BUILDKIT_STEP_LOG_MAX_SIZE=50000000
docker buildx bake results
```

I even created a custom BuildKit configuration, tried different drivers, and limited concurrent operations. However, it was still failing.

Building, at first one, then two, and then three packages at once worked well:

```bash
docker buildx bake pkg-0install-2-18 pkg-abella-2-0-8 pkg-absolute-0-3
# [+] Building 17.7s (100/100) FINISHED
```

This led me to add the `--batch-size` parameter to create batches of packages rather than listing them on the command line. By trial and error, I found that 100 is about the upper bound.

```bash
package-tool --opam-repository ~/opam-repository --dockerfile --batch-size 100
for a in {0..33} ; do sudo docker buildx bake batch$a ; done
```

I have now hit the next limitation: there is a maximum number of layers.

```
ERROR: target pkg-async_rpc_websocket-v0-17-0: failed to solve: failed to prepare ofhokk68c4o0esql38hz1yrzb as n4ytj8qd0izkhvs0srfj9vyi3: max depth exceeded
```
