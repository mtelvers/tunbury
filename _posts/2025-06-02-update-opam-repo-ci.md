---
layout: post
title: "opam-repo-ci Release Workflow"
date: 2025-06-02 00:00:00 +0000
categories: opam
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
---

This is a high-level view of the steps required to update [ocaml-repo-ci](https://opam.ci.ocaml.org) to use a new OCaml version.

[ocaml-repo-ci](https://github.com/ocurrent/opam-repo-ci) uses Docker images as the container's root file system. The [base image builder](https://images.ci.ocaml.org) creates and maintains these images using [ocurrent/ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile). Both applications use the [ocurrent/ocaml-version](https://github.com/ocurrent/ocaml-version) library as the definitive list of OCaml versions.

1\. Update [ocurrent/ocaml-version](https://github.com/ocurrent/ocaml-version)

Create a PR for changes to [ocaml_version.ml](https://github.com/ocurrent/ocaml-version/blob/master/ocaml_version.ml) with the details of the new release.

2\. Create and publish a new release of `ocurrent/ocaml-version`

Create the new release on GitHub and publish it to `ocaml/opam-repository` using `opam`, e.g.

```shell
opam publish --tag v4.0.1 https://github.com/ocurrent/ocaml-version/releases/download/v4.0.1/ocaml-version-4.0.1.tbz
```

3\. Update [ocurrent/docker-base-images](https://github.com/ocurrent/docker-base-images)

The change required is to update the opam repository SHA in the [Dockerfile](https://github.com/ocurrent/docker-base-images/blob/master/Dockerfile) to pick up the latest version of [ocurrent/ocaml-version](https://github.com/ocurrent/ocaml-version).

Run `dune runtest --auto-promote` to update the `builds.expected` file. Create a PR for these changes.

When the PR is pushed to the `live` branch [ocurrent-deployer](https://deploy.ci.ocaml.org/?repo=ocurrent/docker-base-images&) will pick up the change and deploy the new version.

4\. Wait for the base images to build

The [base image builder](https://images.ci.ocaml.org) refreshes the base images every seven days. Wait for the cycle to complete and the new images to be pushed to Docker Hub.

5\. Update [ocurrent/opam-repo-ci](https://github.com/ocurrent/opam-repo-ci)

Update the opam repository SHA in the [Dockerfile](https://github.com/ocurrent/opam-repo-ci/blob/master/Dockerfile). Update the [doc/platforms.md](https://github.com/ocurrent/opam-repo-ci/blob/master/doc/platforms.md) and [test/specs.expected](https://github.com/ocurrent/opam-repo-ci/blob/master/test/specs.expected) using the following two commands.

```shell
dune build @doc
dune runtest --auto-promote
```

Create a PR for this update. When the PR is pushed to the `live` branch [ocurrent-deployer](https://deploy.ci.ocaml.org/?repo=ocurrent/opam-repo-ci) will pick up the change and deploy the new version.

