---
layout: post
title: "OBuilder on Windows: Bringing Native Container Builds with the HCS Backend"
date: 2026-02-19 19:25:00 +0000
categories: obuilder
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Following from my containerd [posts](https://www.tunbury.org/2025/06/11/windows-containerd/) [last](https://www.tunbury.org/2025/06/14/windows-containerd-2/) [year](https://www.tunbury.org/2025/06/27/windows-containerd-3/) and my previous work on obuilder backends for [macOS](https://tarides.com/blog/2023-08-02-obuilder-on-macos/) and [QEMU](https://github.com/ocurrent/obuilder/pull/195), this post extends obuilder to use the Host Compute System (HCS) and [containerd](https://containerd.io) on Windows.

OBuilder, written by Thomas Leonard, is a sandboxed build executor for OCaml CI pipelines. It takes a build specification, similar to a Dockerfile, but written in S-expression syntax, and executes each step in an isolated environment, caching results at the filesystem level.

OBuilder's sandbox backends target Linux (via runc), macOS (via user sandboxing), FreeBSD (via jails), and Docker and any else via QEMU. This post introduces the HCS backend, which brings native Windows container builds to OBuilder using Microsoft's Host Compute Service and containerd.

## How OBuilder Works

Before looking at the Windows-specific details, let's recap on how OBuilder works.

### Build Specifications

A typical OBuilder is shown below:

```scheme
((from ocaml/opam:debian)
 (workdir /src)
 (user (uid 1000) (gid 1000))
 (run (shell "sudo chown opam /src"))
 (copy (src obuilder-spec.opam obuilder.opam) (dst ./))
 (run (shell "opam pin add -yn ."))
 (run
  (network host)
  (shell "opam install --deps-only -t obuilder"))
 (copy (src .) (dst /src/) (exclude .git _build _opam))
 (run (shell "opam exec -- dune build @install @runtest")))
```

Each operation, such as `from`, `run`, `copy`, `workdir`, `env`, `shell`, is executed in sequence inside a sandboxed container. The resulting filestem is the aggregation of all the previous steps and is recorded as the hash of all the steps up to that point. OBuilder will reuse these layers as a cache of the build steps up to that point instead of re-executing the step.

OBuilder's functor architecture allows it to be easily extended by providing new store, sandbox, and fetcher implementations. The new Windows backend uses `hcs_store.ml`, `hcs_sandbox.ml` and `hcs_fetch.ml`.

### The Build Flow

When OBuilder processes a spec, it:

1. Fetches the base image: (`from` directive) using the fetcher module
2. For each operation, compute a content hash from the operation and its inputs
3. Checks the cache: if a result for that hash exists, skip execution
4. Creates a snapshot from the previous step's result using the store module
5. Runs the operation inside the sandbox using the sandbox
6. Commits the result as a new snapshot, keyed by the content hash

This means repeat builds are very fast, and with carefully constructed spec files, incremental builds due to code changes can be built without needing to rebuild the project dependencies (the opam switch).

## The HCS Backend

The Host Compute Service (HCS) backend enables native Windows container builds using `containerd`.

### Architecture

```
┌────────────────────────────────────────────────────┐
│              OBuilder CLI (main.ml)                │
│     obuilder build --store=hcs:C:\obuilder         │
└────────────────────────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────┐
│            Builder Functor (build.ml)              │
│     Build.Make(Hcs_store)(Hcs_sandbox)(Hcs_fetch)  │
└────────────────────────────────────────────────────┘
        │                │                │
        ▼                ▼                ▼
  ┌───────────┐   ┌────────────┐   ┌───────────┐
  │ Hcs_store │   │Hcs_sandbox │   │ Hcs_fetch │
  │           │   │            │   │           │
  │ Snapshot  │   │ Container  │   │ Base image│
  │ mgmt via  │   │ exec via   │   │ import via│
  │ ctr snap  │   │ ctr run    │   │ ctr pull  │
  └───────────┘   └────────────┘   └───────────┘
        │                │                │
        └────────────────┼────────────────┘
                         ▼
┌────────────────────────────────────────────────────┐
│              containerd (Windows)                  │
│   Images  │  Snapshots (VHDX)  │  Runtime (HCS)    │
└────────────────────────────────────────────────────┘
```

### Split Storage Model

Obuilder backends, typically use filesystem features, such as BTRFS or ZFS snapshots to store the cache layer within the obuilder results directory, typically `/var/cache/obuilder/results/<hashid>/rootfs`. However, HCS automatically stores the actual filesystem snaphots in VHDX files in `C:\ProgramData\containerd\snapshots\<N>`, so the obuilder results directory contains only a JSON file with a pointer to this directory.

```
OBuilder Store (C:\obuilder\)         Containerd (C:\ProgramData\containerd\)
├── result\<id>\                      ├── snapshots\
│   ├── rootfs\                       │   ├── 1\    ← VHDX layer data
│   │   └── layerinfo.json ────────►  │   ├── 2\    ← VHDX layer data
│   ├── log                           │   └── 3\    ← VHDX layer data
│   └── env                           └── metadata.db
├── state\db\db.sqlite
└── cache\
```

## Walking Through a Build

Let's trace what happens when you run:

```powershell
obuilder build -f example.windows.hcs.spec . --store=hcs:C:\obuilder
```

with the following spec:

```scheme
((from mcr.microsoft.com/windows/nanoserver:ltsc2025)
 (run (shell "echo hello"))
 (run (shell "mkdir C:\\app")))
```

### Step 1: Fetch the Base Image (hcs_fetch.ml)

The fetcher pulls the base image from the Microsoft Container Registry and prepares an initial snapshot.

First, it normalises the image reference. Docker Hub images need a `docker.io/` prefix for containerd (e.g. `ubuntu:latest` becomes `docker.io/library/ubuntu:latest`), but Microsoft Container Registry (MCR) images are used as-is.

The equivalent manual commands are:

```powershell
# Pull the image
ctr image pull mcr.microsoft.com/windows/nanoserver:ltsc2025

# Get the chain ID (the snapshot key for the image's top layer)
ctr images pull --print-chainid --local mcr.microsoft.com/windows/nanoserver:ltsc2025
# Output includes: "image chain ID: sha256:abc123..."

# Prepare a writable snapshot from the image
ctr snapshot prepare --mounts obuilder-base-<hash> sha256:abc123...
# Returns JSON with mount information:
# [{"Type":"windows-layer","Source":"C:\\...\\snapshots\\42",
#   "Options":["rw","parentLayerPaths=[\"C:\\\\...\\\\snapshots\\\\20\"]"]}]
```

The fetcher parses this mount JSON to extract the source path and parent layer paths, then writes `layerinfo.json`:

```json
{
  "snapshot_key": "obuilder-base-<hash>",
  "source": "C:\\ProgramData\\containerd\\...\\snapshots\\42",
  "parent_layer_paths": [
    "C:\\ProgramData\\containerd\\...\\snapshots\\20",
    "C:\\ProgramData\\containerd\\...\\snapshots\\21"
  ]
}
```

Finally, it extracts environment variables from the image config:

```powershell
# Get the config digest
ctr images inspect mcr.microsoft.com/windows/nanoserver:ltsc2025
# Look for: "application/vnd.docker.container.image.v1+json @sha256:def456..."

# Get the config content
ctr content get sha256:def456...
# Parse the config.Env array from the JSON
```

### Step 2: Run "echo hello" (hcs_store.ml + hcs_sandbox.ml)

For each `run` directive, the store creates a new snapshot from the previous step, the sandbox executes the command, and the store commits the result.

#### Store: prepare a snapshot

```powershell
# Read layerinfo.json from parent to get its snapshot key
# Prepare a new writable snapshot from the parent's committed snapshot
ctr snapshot prepare --mounts obuilder-<id2> obuilder-base-<hash>-committed
```

#### Sandbox: generate OCI config and run

The sandbox reads `layerinfo.json` and generates an OCI runtime config:

```json
{
  "ociVersion": "1.1.0",
  "process": {
    "terminal": false,
    "user": { "username": "ContainerUser" },
    "args": ["cmd", "/S", "/C", "echo hello"],
    "env": ["PATH=C:\\Windows\\System32;C:\\Windows"],
    "cwd": "C:\\"
  },
  "root": { "path": "", "readonly": false },
  "hostname": "builder",
  "windows": {
    "layerFolders": [
      "C:\\ProgramData\\containerd\\...\\snapshots\\20",
      "C:\\ProgramData\\containerd\\...\\snapshots\\21",
      "C:\\ProgramData\\containerd\\...\\snapshots\\42",
      "C:\\ProgramData\\containerd\\...\\snapshots\\43"
    ]
  }
}
```

The `layerFolders` array lists all parent layers followed by the writable scratch layer. This is the Windows container equivalent of an overlay filesystem — the HCS merges all these layers together when the container starts.

```powershell
# Run the container
ctr run --rm --config config.json obuilder-run-0
```

#### Store: commit the result

After the command succeeds:

```powershell
# Commit the writable snapshot to a permanent one
ctr snapshot commit obuilder-<id2>-committed obuilder-<id2>
```

The result directory is then moved from `result-tmp/<id2>` to `result/<id2>`.

### Step 3: Run "mkdir C:\app"

The process repeats: prepare a snapshot from `obuilder-<id2>-committed`, run the command, commit the result. Each step builds on the previous one, forming a chain of containerd snapshots.

## Networking

Windows containers don't support `--net-host` in the way Linux containers do. Instead, network access requires three components working together:

1. An Host Networking Service (HNS) NAT network with a specific subnet
2. A Container Network Interface (CNI) config at `C:\Program Files\containerd\cni\conf\0-containerd-nat.conf` matching that subnet
3. An HCN namespace per container

The sandbox creates and destroys HCN namespaces around each networked container execution:

```powershell
# Before the container
hcn-namespace create
# Returns a GUID, e.g. "a1b2c3d4-..."

# The GUID is passed in the OCI config:
# "windows": { "network": { "networkNamespace": "a1b2c3d4-..." } }

# Run with --cni flag
ctr run --rm --cni --config config.json obuilder-run-0

# After the container
hcn-namespace delete a1b2c3d4-...
```

The `hcn-namespace` tool is a small OCaml utility ([mtelvers/hcn-namespace](https://github.com/mtelvers/hcn-namespace)) that wraps the Windows HCN API, written last year while working on `day10`.

## The COPY Operation

File copying works differently on Windows due to I/O constraints. On Linux, OBuilder streams tar data through a pipe directly into the sandbox's stdin. On Windows, the tar data is first written to a temporary file, then the file is passed as stdin to the container:

```
Linux:   generate tar  ──pipe──►  sandbox stdin  ──►  tar -xf -
Windows: generate tar  ──►  temp file  ──►  sandbox stdin  ──►  tar -xf -
```

This extra step is needed because Lwt's pipe I/O is unreliable on Windows (more on this below).

## Running It

### Prerequisites

1. Windows Server 2019 or later (tested on LTSC 2019 and LTSC 2025)
2. Containerd v2.0+ installed and running as a service
3. ctr: CLI available in PATH
4. [hcn-namespace](https://github.com/mtelvers/hcn-namespace): tool for networking support

### Building OBuilder on Windows

OBuilder builds itself — the provided `example.windows.hcs.spec` bootstraps the build using an MSVC-based OCaml image:

```scheme
((from ocaml/opam:windows-server-msvc-ltsc2025-ocaml-5.4)
 (workdir "C:/src")
 (copy (src obuilder-spec.opam obuilder.opam) (dst ./))
 (run (shell "echo (lang dune 3.0)> dune-project"))
 (run (shell "opam pin add -yn ."))
 (run (network host)
  (shell "opam install --deps-only -t obuilder"))
 (copy (src .) (dst "C:/src/") (exclude .git _build _opam))
 (run (shell "opam exec -- dune build @install @runtest")))
```

```powershell
obuilder build -f example.windows.hcs.spec . --store=hcs:C:\obuilder
```

### Healthcheck

To verify the setup:

```powershell
obuilder healthcheck --store=hcs:C:\obuilder
```

This pulls `mcr.microsoft.com/windows/nanoserver:ltsc2025`, runs `echo healthcheck` inside a container, and confirms everything works end-to-end.

## Addendum: Lwt on Windows

The HCS backend development highlighted serveral issues with Lwt on Windows:

- `Lwt_process.exec` child promise isn't resolved
- `Lwt_unix.waitpid` hangs indefinitely unless created with `cmd.exe /c`
- `Lwt_unix.write` can randomly hang, affecting tar and log streaming.
- `Lwt_io.with_file` fails with "Permission denied"
- `Os.pread_result` works intermittently, but frequently fails with `ctr`

## Code

My code is available at [mtelvers/obuilder/tree/hcs](https://github.com/mtelvers/obuilder/tree/hcs). I have an ocluster and OCaml-CI patch, but the LWT issues dominate reliability.

