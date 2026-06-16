---
layout: post
title: "Docker 29 manifest list"
date: 2026-06-16 18:00:00 +0000
categories: [ocaml, ci, docker]
tags: tunbury.org
image:
  path: /images/docker-logo.png
  thumbnail: /images/thumbs/docker-logo.png
---

On the [base image builder](https://images.ci.ocaml.org), we have recently seen a significant increase in the number of times we hit the Docker rate limits on manifest pushes. Most of these work on the second attempt, but this week, a new class of permanent manifest push failures has emerged.

The typical error log is shown below. While the eye naturally goes to "failed to mount blob", the rate limit is indicated by the "Client.Timeout" message.

```
2026-06-13 08:46.51: New job: push ocaml/opam:opensuse-ocaml-5.5
2026-06-13 08:46.52: Exec: "docker" "--config" "/tmp/push-manifest1908fd1" 
                           "manifest" "create" "ocaml/opam:opensuse-ocaml-5.5" 
                           "ocurrent/opam-staging@sha256:f9307e24e23534b1..." 
                           "ocurrent/opam-staging@sha256:3301d623eda84fc0..."
Created manifest list docker.io/ocaml/opam:opensuse-ocaml-5.5
2026-06-13 11:18.24: Exec: "docker" "--config" "/tmp/push-manifest1908fd1" 
                           "manifest" "push" "ocaml/opam:opensuse-ocaml-5.5"
failed to mount blob ocurrent/opam-staging@sha256:477d64e93679f5ba...
          to docker.io/ocaml/opam:opensuse-ocaml-5.5: Head 
          "https://registry1.docker.io/v2/ocaml/opam/blobs/sha256:477d64e93679f5ba...":
          unable to decode token response: context deadline exceeded
          (Client.Timeout or context cancellation while reading body)
2026-06-13 11:19.18: Job failed: Command "docker" "--config" "/tmp/push-manifest1908fd1" "manifest" "push" 
          "ocaml/opam:opensuse-ocaml-5.5" exited with status 1
2026-06-13 11:19.18: Log analysis:
2026-06-13 11:19.18: >>> failed to mount blob (score = 30)
2026-06-13 11:19.18: Docker hub failed (failed to mount blob)
```

The new error occurs slightly earlier, during manifest creation. It doesn't say error in capital letters; it only reports "... is a manifest list".

```
2026-06-15 19:04.13: New job: push ocaml/opam:ubuntu-25.04-opam
2026-06-15 19:04.14: Exec: "docker" "--config" "/tmp/push-manifest22dabe89"
                           "manifest" "create" "ocaml/opam:ubuntu-25.04-opam"
                           "ocurrent/opam-staging@sha256:cb83037961d1b1a3..."
                           "ocurrent/opam-staging@sha256:0deb3c5734ebc7ea..."
                           "ocurrent/opam-staging@sha256:2d38b86b96857bb4..."
                           "ocurrent/opam-staging@sha256:654e91f2e7468c7a..."
                           "ocurrent/opam-staging@sha256:5926da014501a4e6..."
docker.io/ocurrent/opam-staging@sha256:5926da014501a4e6... is a manifest list
2026-06-15 19:04.19: Job failed: Command ... "manifest" "create" ... exited with status 1
```

The base image builder pipeline builds a Docker image on each of the five architectures and pushes them to a staging tag on Docker Hub. An example tag is `ocurrent/opam-staging:ubuntu-24.04-ocaml-5.4-riscv64`. Once all the tags have been pushed, a single multiple-architecture tag is created in `ocaml/opam`, such as `ocaml/opam:ubuntu-24.04-ocaml-5.4`. This two-stage process allows tags to be created on their respective hardware and means that workers only need a low-privilege staging account, leaving the final step to run on the server.

The manifest is created with `docker manifest create`, which takes a list of single-platform image manifests, one per architecture. It will not nest a manifest list inside another manifest, which is what the "is a manifest list" message is telling us.

Inspecting the failing manifest, `docker.io/ocurrent/opam-staging@sha256:5926da014501a4e6...`, shows that it is the RISCV build. Reviewing the build log shows this section at the very end.

```
#65 exporting to image
#65 exporting manifest sha256:ea5d285460bcc8ed7ec8440785d8abb16ca2d366e8633d3168019e4ba3abff47 0.2s done
#65 exporting config sha256:677527d88aa8f872acc866c5e43ae48249f47c2dc9c9c0c2563044565c1db18e 0.2s done
#65 exporting attestation manifest sha256:f4fce1b4ca535ae672d87bc5348c84ddf498debc63dd9c7dcaa3819a79f88289 0.3s done
#65 exporting manifest list sha256:5926da014501a4e68b44ce358e3c517baf9e9a3532bcc472d2ad4791bfcc3593 0.2s done
```

BuildKit exported the real RISC-V image manifest (`ea5d28...`), and then also exported a provenance attestation manifest (`f4fce1...`), and because there were now two manifests to hold, it wrapped them together in a manifest list (`5926da...`), and it's that list which got pushed to the staging tag, and because it is a list `docker manifest create` then refused to work with it.

`docker manifest inspect` shows the detail:

```json
{
   "mediaType": "application/vnd.oci.image.index.v1+json",
   "manifests": [
      {
         "digest": "sha256:ea5d2854...",
         "platform": { "architecture": "riscv64", "os": "linux" }
      },
      {
         "digest": "sha256:f4fce1b4...",
         "platform": { "architecture": "unknown", "os": "unknown" }
      }
   ]
}
```

One real `linux/riscv64` image, and one `unknown/unknown` entry, which is the attestation. The other four staging digests are plain `application/vnd.docker.distribution.manifest.v2+json` images with no `manifests` array at all.

This was a RISC-V image running on my new RISC-V machines with a clean installation of Ubuntu 26.04 and Docker 29, which had been the source of the `invalid user index: -1` I mentioned in a [previous post]({% post_url 2026-06-06-docker-29 %}). All the other machines are the upgraded [x86_64 and Arm workers]({% post_url 2026-06-08-ubuntu-26-04 %}). From those posts, upgraded machines continue to use the legacy `overlay2` graphdriver store while new ones use the containerd image store.

The root of the issue is that the legacy graphdriver store cannot represent an image index locally, so BuildKit quietly discards the attestation and pushes a flat manifest. The containerd store can represent it, so it keeps the attestation and pushes an index. Same `graphdriver`-versus-`containerd` split that produced the `COPY --link` failure, surfacing in a completely different part of the system. As more machines are reinstalled rather than upgraded, this would have spread to every architecture.

The easy fix is to suppress the attestation with `--provenance=false` or `BUILDX_NO_DEFAULT_ATTESTATIONS=1` on the worker. That works, but it ties us to the legacy behaviour again, the same trap as adding `containerd-snapshotter: false`.

The better question is why the push step can't cope with an index in the first place. We are already committed to BuildKit, every generated Dockerfile starts `# syntax=docker/dockerfile:1`, and on Docker 29 `docker build` is `docker buildx build` underneath. The only part of the system still on the old `docker manifest` command was this manifest-list step. And `buildx` has a native replacement, `docker buildx imagetools create`, which consumes index sources and merges their children rather than rejecting them.

A `--dry-run` over the five real staging digests shows it doing exactly that:

```
$ docker buildx imagetools create --dry-run -t ocaml/opam:test \
    ocurrent/opam-staging@sha256:cb8303... \  # s390x
    ocurrent/opam-staging@sha256:0deb3c... \  # ppc64le
    ocurrent/opam-staging@sha256:2d38b8... \  # arm64
    ocurrent/opam-staging@sha256:654e91... \  # amd64
    ocurrent/opam-staging@sha256:5926da...    # riscv64 (an index)
```

The four flat manifests come through untouched, and the RISC-V index is unwrapped into its image manifest plus the attestation manifest (annotated `vnd.docker.reference.type: attestation-manifest`). The result is a correct modern multi-arch index with the attestation preserved, and the create and push happen in a single command.

So the change to [ocurrent/ocurrent](https://github.com/ocurrent/ocurrent) `current_docker` plugin replaces

```
docker manifest create <tag> <srcs...>
docker manifest push   <tag>
```

with

```
docker buildx imagetools create -t <tag> <srcs...>
```

`imagetools create` pushes directly, so the separate push disappears. It doesn't print the resulting digest in a machine-readable form though, so we read it back with `imagetools inspect`. The behaviour of `--format` wasn't quite what I expected:

{% raw %}
```
$ docker buildx imagetools inspect --format '{{.Manifest.Digest}}' <tag>
Name:      docker.io/...
MediaType: application/vnd.docker.distribution.manifest.v2+json
Digest:    sha256:cb8303...

$ docker buildx imagetools inspect --format '{{printf "%s" .Manifest.Digest}}' <tag>
sha256:cb8303...
```
{% endraw %}

The bare {% raw %}`{{.Manifest.Digest}}`{% endraw %} prints the default human-readable block, but wrapping it in a function call (`printf`) makes it work as expected.

One final change to the `Dockerfile` is needed as it installs `docker-cli`, but `docker buildx` is a separate plugin that `docker-cli` only _recommends_, so `--no-install-recommends` leaves it out.

With that redeployed, the push step now runs through buildx and succeeds:

{% raw %}
```
2026-06-16 15:38.47: New job: push ocaml/opam:ubuntu-22.04-opam
2026-06-16 15:38.47: Exec: "docker" "--config" "/tmp/push-manifest353fedfa"
                           "buildx" "imagetools" "create" "-t" "ocaml/opam:ubuntu-22.04-opam" ...
#1 [internal] pushing docker.io/ocaml/opam:ubuntu-22.04-opam
#1 0.000 copying sha256:f1e82e... to docker.io/ocaml/opam:ubuntu-22.04-opam
...
#1 8.722 pushing sha256:2613288d31766df8... to docker.io/ocaml/opam:ubuntu-22.04-opam
#1 DONE 10.5s
2026-06-16 15:38.59: Exec: ... "buildx" "imagetools" "inspect" "--format" "{{printf "%s" .Manifest.Digest}}" ...
2026-06-16 15:39.01: --> "ocaml/opam:ubuntu-22.04-opam@sha256:2613288d31766df8..."
2026-06-16 15:39.01: Job succeeded
```
{% endraw %}

The digest read back by `inspect` (`2613288d...`) matches the one `create` pushed, so the value the pipeline records for the tag is correct. The legacy `docker manifest` command is gone; the push path now uses the same buildx tools as the builds, and an attestation-wrapped index from a containerd-store worker is merged rather than rejected.

[PR#474](https://github.com/ocurrent/ocurrent/pull/474) addresses the manifest errors, but the underlying rate limits will continue to be an issue without further mitigation.
