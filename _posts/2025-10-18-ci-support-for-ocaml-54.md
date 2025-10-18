---
layout: post
title: "CI support for OCaml 5.4"
date: 2025-10-18 00:00:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Following the release of [OCaml 5.4](https://ocaml.org/releases/5.4.0) the CI systems need to be updated to use it.

This process starts with the update of [ocaml-version](https://github.com/ocurrent/ocaml-version), which Octachron added through [PR#85](https://github.com/ocurrent/ocaml-version/pull/85).

The base images now need to be updated, which consists of updating the [base image builder](https://images.ci.ocaml.org), [macos-infra](https://github.com/ocaml/macos-infra) and [freebsd-infra](https://github.com/ocurrent/freebsd-infra). The latter two are Ansible scripts [PR#57](https://github.com/ocurrent/macos-infra/pull/57) for macOS and [PR#19](https://github.com/ocurrent/freebsd-infra/pull/19) for FreeBSD. New base images are also required for OpenBSD 7.7 and Windows Server 2022. This needs minor edits to the `Makefile`,  which are included in [PR#201](https://github.com/ocurrent/obuilder/pull/201).

The base image builder was updated with [PR#335](https://github.com/ocurrent/docker-base-images/pull/335) which pulled in the latest [ocaml-version](https://github.com/ocurrent/ocaml-version) and [ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile). [ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile) contains the build instructions for the base images across different OS distributions and architectures as Dockerfiles.

[ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile) had recently been updated with [PR#243](https://github.com/ocurrent/ocaml-dockerfile/pull/243), which added CentOS Stream 9 and 10, Oracle Linux 10 and Ubuntu 25.10. However, this resulted in a couple of build failures, plus MisterDA opened [issue#244](https://github.com/ocurrent/ocaml-dockerfile/issues/244), noting openSUSE and Windows Server 2025 needed to be updated.

There were build failures in OpenSUSE that came from `RUN yum install -y ... curl ...` which conflicted with the `curl` which was already installed. Easily fixed by removing `curl` as it was already installed.

```
#17 1.503 Error: 
#17 1.503  Problem: problem with installed package curl-minimal-7.76.1-34.el9.x86_64
#17 1.503   - package curl-minimal-7.76.1-34.el9.x86_64 from @System conflicts with curl provided by curl-7.76.1-34.el9.x86_64 from baseos
#17 1.503   - package curl-minimal-7.76.1-26.el9.x86_64 from baseos conflicts with curl provided by curl-7.76.1-34.el9.x86_64 from baseos
#17 1.503   - package curl-minimal-7.76.1-28.el9.x86_64 from baseos conflicts with curl provided by curl-7.76.1-34.el9.x86_64 from baseos
#17 1.503   - package curl-minimal-7.76.1-29.el9.x86_64 from baseos conflicts with curl provided by curl-7.76.1-34.el9.x86_64 from baseos
#17 1.503   - package curl-minimal-7.76.1-31.el9.x86_64 from baseos conflicts with curl provided by curl-7.76.1-34.el9.x86_64 from baseos
#17 1.503   - package curl-minimal-7.76.1-34.el9.x86_64 from baseos conflicts with curl provided by curl-7.76.1-34.el9.x86_64 from baseos
#17 1.503   - cannot install the best candidate for the job
```

The next issue was with `RUN yum config-manager --set-enabled powertools` as this repository had changed its name (again):

- CentOS 7: Uses yum-config-manager
- CentOS 8: Uses powertools
- CentOS Stream 9+: Uses crb

```
#34 [stage-1 13/41] RUN yum config-manager --set-enabled powertools
#34 0.447 Error: No matching repo to modify: powertools.
#34 ERROR: process "/bin/sh -c yum config-manager --set-enabled powertools" did not complete successfully: exit code: 1
------
 > [stage-1 13/41] RUN yum config-manager --set-enabled powertools:
0.447 Error: No matching repo to modify: powertools.
------
```

The final blocker was building the Ubuntu 25.10 images on RISCV. These images failed on `apt-get update`, which I initially assumed was a transitory network issue, but it persisted.

```
#14 [stage-0  2/13] RUN apt-get -y update
#14 ERROR: process "/bin/sh -c apt-get -y update" did not complete successfully: exit code: 132
```

Oddly, `docker run --rm -it ubuntu:questing` didn't give me a container and simply returned the command prompt. However, `docker run --rm -it ubuntu:questing-20250830` did give me a prompt but I still couldn't run `apt`:

```
# docker run --rm -it ubuntu:questing-20250830
root@8754b6373f6f:/# apt update   
Illegal instruction (core dumped)
```

Interestingly, `ubuntu:questing-20250806` (even older) could run `apt update`. However, attempting to build the Dockerfile didn't work.

```
48.49 Preparing to unpack .../libc6_2.42-0ubuntu3_riscv64.deb ...
49.27 Checking for services that may need to be restarted...
49.30 Checking init scripts...
49.30 Checking for services that may need to be restarted...
49.34 Checking init scripts...
49.34 Nothing to restart.
49.44 Unpacking libc6:riscv64 (2.42-0ubuntu3) over (2.41-9ubuntu1) ...
52.05 dpkg: warning: old libc6:riscv64 package post-removal script subprocess was killed by signal (Illegal instruction), core dumped
52.05 dpkg: trying script from the new package instead ...
52.06 dpkg: error processing archive /var/cache/apt/archives/libc6_2.42-0ubuntu3_riscv64.deb (--unpack):
52.06  new libc6:riscv64 package post-removal script subprocess was killed by signal (Illegal instruction), core dumped
52.07 dpkg: error while cleaning up:
52.07  installed libc6:riscv64 package pre-installation script subprocess was killed by signal (Illegal instruction), core dumped
52.30 Errors were encountered while processing:
52.30  /var/cache/apt/archives/libc6_2.42-0ubuntu3_riscv64.deb
52.46 E: Sub-process /usr/bin/dpkg returned an error code (1)
```

Checking the Ubuntu [download](https://ubuntu.com/download/risc-v) page shows that Ubuntu have changed the hardware requirements.

> We have upgraded the required RISC-V ISA profile to RVA23S64 with the 25.10 release. Hardware that is not RVA23 ready continues to be supported by our 24.04.3 LTS release.

Searching online found this [article](https://www.phoronix.com/news/Ubuntu-25.10-RISC-V-QEMU).

> Back in June it was announced by Canonical that for the Ubuntu 25.10 release [they would be raising the RISC-V baseline to the RVA23 profile even with barely any available RISC-V platforms supporting that newer RISC-V profile](https://www.phoronix.com/news/Ubuntu-25.10-To-Require-RVA23). That change is still going ahead and leaves Ubuntu 25.10 on RISC-V currently only supporting the QEMU virtualized target.

Therefore, I have removed RISCV as a supported platform on for Ubuntu 25.10 until we can get some hardware to support it or set up some QEMU workers.

Additionally, Anil suggested dropping support for Debian 11, Oracle Linux 8 and 9, and Fedora 41 to reduce the size of the build matrix.

[ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile) release 8.3.3 is now pending on [opam repository](https://github.com/ocaml/opam-repository/pull/28736).

Now that the base images have been successfully built, I can continue with the updates to [ocurrent/opam-repo-ci](https://github.com/ocurrent/opam-repo-ci) with [PR#460](https://github.com/ocurrent/opam-repo-ci/pull/460), which only needs the opam repository SHA updated to include the new release of ocaml-version.

[ocurrent/ocaml-ci](https://github.com/ocurrent/ocaml-ci) uses git submodules for these packages, so these need to be updated: [PR#1042](https://github.com/ocurrent/ocaml-ci/pull/1032).


