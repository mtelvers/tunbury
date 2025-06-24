---
layout: post
title: "Opinion: Is it time to stop testing with opam < 2.2"
date: 2025-05-26 00:00:00 +0000
categories: opam
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
redirect_from:
  - /retire-legacy-opam/
---

On the eve of the release of opam 2.4, is it time to stop testing with opam < 2.2?

Over the weekend, we have been seeing numerous failures across the ecosystem due to the unavailability of the [camlcity.org](http://camlcity.org). This website hosts the source for the `findlib` package. A typical error report is shown below:

```
#32 [build-opam-doc  5/14] RUN opam install odoc
#32 258.6 [ERROR] Failed to get sources of ocamlfind.1.9.6: curl error code 504
#32 258.6
#32 258.6 #=== ERROR while fetching sources for ocamlfind.1.9.6 =========================#
#32 258.6 OpamSolution.Fetch_fail("http://download.camlcity.org/download/findlib-1.9.6.tar.gz (curl: code 504 while downloading http://download.camlcity.org/download/findlib-1.9.6.tar.gz)")
#32 259.0
#32 259.0
#32 259.0 <><> Error report <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
#32 259.0 +- The following actions failed
#32 259.0 | - fetch ocamlfind 1.9.6
#32 259.0 +-
```

The most high-profile failure has been the inability to update [opam.ocaml.org](https://opam.ocaml.org).  See [issue#172](https://github.com/ocaml/infrastructure/issues/172). This has also affected the deployment of [ocaml.org](https://ocaml.org).

Late last year, Hannes proposed adding our archive mirror to the base image builder. [issue#306](https://github.com/ocurrent/docker-base-images/issues/306). However, this requires opam 2.2 or later. We have long maintained that while supported [distributions](https://repology.org/project/opam/versions) still package legacy versions, we should continue to test against these versions.

The testing of the legacy versions is limited to [opam-repo-ci](https://opam.ci.ocaml.org) testing on Debian 12 on AMD64 using a test matrix of OCaml 4.14 and 5.3 with each of opam 2.0, 2.1 and 2.2. These tests often fail to find a solution within the timeout. We have tried increasing the timeout by a factor of 10 to no avail. All of opam-repo-ci's other tests use the current development version. OCaml-CI only tests using the current release version.

```
[ERROR] Sorry, resolution of the request timed out.
        Try to specify a simpler request, use a different solver, or increase the allowed time by setting OPAMSOLVERTIMEOUT to a bigger value (currently, it is set to 60.0 seconds).
```

The base image default is opam 2.0, as `~/.opam` can't be downgraded; therefore, we can't set a mirror archive flag in the base images.

A typical `Dockerfile` starts by replacing opam 2.0 with the latest version and reinitialising.

```
FROM ocaml/opam:debian-12-ocaml-4.14 AS build
RUN sudo ln -sf /usr/bin/opam-2.3 /usr/bin/opam && opam init --reinit -ni
...
```

To include the archive mirror, we should add a follow-up of:

```
RUN opam option --global 'archive-mirrors+="https://opam.ocaml.org/cache"'
```

Dropping 2.0 and 2.1, and arguably 2.2 as well, from the base images would considerably decrease the time taken to build the base images, as opam is built from the source each week for each distribution/architecture.

```
RUN git clone https://github.com/ocaml/opam /tmp/opam && cd /tmp/opam && cp -P -R -p . ../opam-sources && git checkout 4267ade09ac42c1bd0b84a5fa61af8ccdaadef48 && env MAKE='make -j' shell/bootstrap-ocaml.sh && make -C src_ext cache-archives
RUN cd /tmp/opam-sources && cp -P -R -p . ../opam-build-2.0 && cd ../opam-build-2.0 && git fetch -q && git checkout adc1e1829a2bef5b240746df80341b508290fe3b && ln -s ../opam/src_ext/archives src_ext/archives && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" ./configure --enable-cold-check && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" make lib-ext all && mkdir -p /usr/bin && cp /tmp/opam-build-2.0/opam /usr/bin/opam-2.0 && chmod a+x /usr/bin/opam-2.0 && rm -rf /tmp/opam-build-2.0
RUN cd /tmp/opam-sources && cp -P -R -p . ../opam-build-2.1 && cd ../opam-build-2.1 && git fetch -q && git checkout 263921263e1f745613e2882745114b7b08f3608b && ln -s ../opam/src_ext/archives src_ext/archives && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" ./configure --enable-cold-check --with-0install-solver && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" make lib-ext all && mkdir -p /usr/bin && cp /tmp/opam-build-2.1/opam /usr/bin/opam-2.1 && chmod a+x /usr/bin/opam-2.1 && rm -rf /tmp/opam-build-2.1
RUN cd /tmp/opam-sources && cp -P -R -p . ../opam-build-2.2 && cd ../opam-build-2.2 && git fetch -q && git checkout 01e9a24a61e23e42d513b4b775d8c30c807439b2 && ln -s ../opam/src_ext/archives src_ext/archives && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" ./configure --enable-cold-check --with-0install-solver --with-vendored-deps && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" make lib-ext all && mkdir -p /usr/bin && cp /tmp/opam-build-2.2/opam /usr/bin/opam-2.2 && chmod a+x /usr/bin/opam-2.2 && rm -rf /tmp/opam-build-2.2
RUN cd /tmp/opam-sources && cp -P -R -p . ../opam-build-2.3 && cd ../opam-build-2.3 && git fetch -q && git checkout 35acd0c5abc5e66cdbd5be16ba77aa6c33a4c724 && ln -s ../opam/src_ext/archives src_ext/archives && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" ./configure --enable-cold-check --with-0install-solver --with-vendored-deps && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" make lib-ext all && mkdir -p /usr/bin && cp /tmp/opam-build-2.3/opam /usr/bin/opam-2.3 && chmod a+x /usr/bin/opam-2.3 && rm -rf /tmp/opam-build-2.3
RUN cd /tmp/opam-sources && cp -P -R -p . ../opam-build-master && cd ../opam-build-master && git fetch -q && git checkout 4267ade09ac42c1bd0b84a5fa61af8ccdaadef48 && ln -s ../opam/src_ext/archives src_ext/archives && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" ./configure --enable-cold-check --with-0install-solver --with-vendored-deps && env PATH="/tmp/opam/bootstrap/ocaml/bin:$PATH" make lib-ext all && mkdir -p /usr/bin && cp /tmp/opam-build-master/opam /usr/bin/opam-master && chmod a+x /usr/bin/opam-master && rm -rf /tmp/opam-build-master
```

Furthermore, after changing the opam version, we must run `opam init --reinit -ni`, which is an _expensive_ command. If the base images defaulted to the current version, we would have faster builds.

The final benefit, of course, would be that we could set the `archive-mirror` and reduce the number of transient failures due to network outages.
