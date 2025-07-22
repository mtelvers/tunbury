---
layout: post
title:  "Package Tool"
date:   2025-07-21 00:00:00 +0000
categories: OCaml,opam
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
---

Would you like to build every package in opam in a single Dockerfile using BuildKit?

In [mtelvers/package-tool](https://github.com/mtelvers/package-tool), I have combined various opam sorting and graphing functions into a CLI tool that will work on a checked-out [opam-repository](https://github.com/ocaml/opam-repository). Many of these flags can be combined.

# Package version

```sh
package-tool --opam-repository ~/opam-repository <package>
```

The package can be given as `0install.2.18` or `0install`. The former specifies a specific version while the latter processes the latest version. `--all-versions` can be specified to generate files for all package versions.

# Dependencies

Dump the dependencies for the latest version of 0install into a JSON file.

```sh
package-tool --opam-repository ~/opam-repository --deps 0install
```

Produces `0install.2.18-deps.json`:

```json
{"yojson.3.0.0":["dune.3.19.1"],
"xmlm.1.4.0":["topkg.1.0.8"],
"topkg.1.0.8":["ocamlfind.1.9.8","ocamlbuild.0.16.1"],
...
"0install-solver.2.18"]}
```

# Installation order

Create a list showing the installation order for the given package.

```sh
package-tool --opam-repository ~/opam-repository --list 0install
```

Produces `0install.2.18-list.json`:

```json
["ocaml-compiler.5.3.0",
"ocaml-base-compiler.5.3.0",
...
"0install.2.18"]
```

# Solution DAG

Output the solution graph in Graphviz format, which can then be converted into a PDF with `dot`.

```sh
package-tool --opam-repository ~/opam-repository --dot 0install
dot -Tpdf 0install.2.18.dot 0install.2.18.pdf
```
# OCaml version

By default, OCaml 5.3.0 is used, but this can be changed using the `--ocaml 4.14.2` parameter.


# Dockerfile

The `--dockerfile` argument creates a Dockerfile to test the installation.

```sh
package-tool --opam-repository ~/opam-repository --dockerfile --all-versions 0install
```

For example, the above command line outputs 5 Dockerfiles.

- 0install.2.15.1.dockerfile
- 0install.2.15.2.dockerfile
- 0install.2.16.dockerfile
- 0install.2.17.dockerfile
- 0install.2.18.dockerfile

As an example, `0install.2.18.dockerfile`, contains:

```dockerfile
FROM debian:12 AS builder_0install_2_18
RUN apt update && apt upgrade -y
RUN apt install -y build-essential git rsync unzip curl sudo
RUN if getent passwd 1000; then userdel -r $(id -nu 1000); fi
RUN adduser --uid 1000 --disabled-password --gecos '' opam
ADD --chown=root:root --chmod=0755 [ "https://github.com/ocaml/opam/releases/download/2.3.0/opam-2.3.0-x86_64-linux", "/usr/local/bin/opam" ]
RUN echo 'opam ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers.d/opam
RUN chmod 440 /etc/sudoers.d/opam
USER opam
WORKDIR /home/opam
ENV OPAMYES="1" OPAMCONFIRMLEVEL="unsafe-yes" OPAMERRLOGLEN="0" OPAMPRECISETRACKING="1"
ADD --chown=opam:opam --keep-git-dir=false [ ".", "/home/opam/opam-repository" ]
RUN opam init default -k local ~/opam-repository --disable-sandboxing --bare
RUN opam switch create default --empty
RUN opam install ocaml-compiler.5.3.0 >> build.log 2>&1 || echo 'FAILED' >> build.log
RUN opam install ocaml-base-compiler.5.3.0 >> build.log 2>&1 || echo 'FAILED' >> build.log
...
RUN opam install 0install-solver.2.18 >> build.log 2>&1 || echo 'FAILED' >> build.log
RUN opam install 0install.2.18 >> build.log 2>&1 || echo 'FAILED' >> build.log
ENTRYPOINT [ "opam", "exec", "--" ]
CMD bash
```

This can be built using Docker in the normal way. Note that the build context is your checkout of [opam-repository](https://github.com/ocaml/opam-repository).

```sh
docker build -f 0install.2.18.dockerfile ~/opam-repository
```

Additionally, it outputs `Dockerfile`, which contains the individual package builds as a multistage build and an aggregation stage as the final layer:

```dockerfile
FROM debian:12 AS results
WORKDIR /results
RUN apt update && apt upgrade -y
RUN apt install -y less
COPY --from=builder_0install_2_15_1 [ "/home/opam/build.log", "/results/0install.2.15.1" ]
COPY --from=builder_0install_2_15_2 [ "/home/opam/build.log", "/results/0install.2.15.2" ]
COPY --from=builder_0install_2_16 [ "/home/opam/build.log", "/results/0install.2.16" ]
COPY --from=builder_0install_2_17 [ "/home/opam/build.log", "/results/0install.2.17" ]
COPY --from=builder_0install_2_18 [ "/home/opam/build.log", "/results/0install.2.18" ]
CMD bash
```

Build all the versions of 0install in parallel using BuildKit's layer caching:

```shell
docker build -f Dockerfile -t opam-results ~/opam-repository
```

We can inspect the build logs in the Docker container:

```sh
$ docker run --rm -it opam-results
root@b28da667e754:/results# ls^C
root@b28da667e754:/results# ls -l
total 76
-rw-r--r-- 1 1000 1000 12055 Jul 22 20:17 0install.2.15.1
-rw-r--r-- 1 1000 1000 15987 Jul 22 20:19 0install.2.15.2
-rw-r--r-- 1 1000 1000 15977 Jul 22 20:19 0install.2.16
-rw-r--r-- 1 1000 1000 16376 Jul 22 20:19 0install.2.17
-rw-r--r-- 1 1000 1000 15150 Jul 22 20:19 0install.2.18
```

Annoyingly, Docker doesn't seem to be able to cope with all of opam at once. I get various RPC errors.

```
[+] Building 2.9s (4/4) FINISHED                                                                                                    docker:default
 => [internal] load build definition from Dockerfile
 => => transferring dockerfile: 10.79MB
 => resolve image config for docker-image://docker.io/docker/dockerfile:1
 => CACHED docker-image://docker.io/docker/dockerfile:1@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d
 => [internal] load build definition from Dockerfile
ERROR: failed to receive status: rpc error: code = Unavailable desc = error reading from server: connection error: COMPRESSION_ERROR
```
