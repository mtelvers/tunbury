---
layout: post
title: "Debian 13 Trixie"
date: 2025-08-11 00:00:00 +0000
categories: debian,trixie
tags: tunbury.org
image:
  path: /images/debian-logo.png
  thumbnail: /images/thumbs/debian-logo.png
---

Antonin noticed that Debian 13 _trixie_ has been released. The [release notes](https://www.debian.org/News/2025/20250809) mention that i386 is no longer supported as a regular architecture. However, very excitingly, RISCV 64 is now supported.

> This release for the first time officially supports the riscv64 architecture, allowing users to run Debian on 64-bit RISC-V hardware and benefit from all Debian 13 features.

> i386 is no longer supported as a regular architecture: there is no official kernel and no Debian installer for i386 systems. The i386 architecture is now only intended to be used on a 64-bit (amd64) CPU. Users running i386 systems should not upgrade to trixie. Instead, Debian recommends either reinstalling them as amd64, where possible, or retiring the hardware.

The wording of the release notes made me wonder. Since we only need a Docker image would there still be one?

`docker manifest inspect debian:trixie` showed there was a layer available:

```json
      {
         "mediaType": "application/vnd.oci.image.manifest.v1+json",
         "size": 1017,
         "digest": "sha256:b67fca6916104c1b11c5d1b47a62af92268318051971094acc9c5366c8eac7ad",
         "platform": {
            "architecture": "386",
            "os": "linux"
         }
      },
```

Then I noticed this weird behaviour:

```sh
$ docker run --platform linux/386 --rm -it debian:trixie dpkg --print-architecture
i386
$ docker run --platform linux/amd64 --rm -it debian:trixie dpkg --print-architecture
i386
```

That's odd. Let's start again.

```sh
$ docker system prune -af
$ docker run --platform linux/amd64 --rm -it debian:trixie dpkg --print-architecture
amd64
$ docker run --platform linux/386 --rm -it debian:trixie dpkg --print-architecture
i386
$ docker run --platform linux/amd64 --rm -it debian:trixie dpkg --print-architecture
i386
```

Seems that after you have run the 386 variant, it gets stuck:

```sh
$ docker system prune -af
$ docker pull --platform linux/amd64 debian:trixie
$ docker run --platform linux/amd64 --rm -it debian:trixie dpkg --print-architecture
amd64
$ docker pull --platform linux/386 debian:trixie
$ docker run --platform linux/386 --rm -it debian:trixie dpkg --print-architecture
i386
$ docker pull --platform linux/amd64 debian:trixie
$ docker run --platform linux/amd64 --rm -it debian:trixie dpkg --print-architecture
amd64
```

Adding the `docker pull` step seems to resolve this, even though it doesn't actually pull anything.

