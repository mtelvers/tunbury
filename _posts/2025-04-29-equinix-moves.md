---
layout: post
title: "Equinix Moves"
date: 2025-04-29 00:00:00 +0000
categories: registry.ci.dev,opam-repo-ci,get.dune.build
tags: tunbury.org
image:
  path: /images/equinix.png
  thumbnail: /images/thumbs/equinix.png
redirect_from:
  - /equinix-moves/
---

The moves of registry.ci.dev, opam-repo-ci, and get.dune.build have followed the template of [OCaml-CI](https://www.tunbury.org/ocaml-ci/). Notable differences have been that I have hosted `get.dune.build` in a VM, as the services required very little disk space or CPU/RAM. For opam-repo-ci, the `rsync` was pretty slow, so I tried running multiple instances using GNU parallel with marginal gains.

```sh
cd /var/lib/docker/volumes2/opam-repo-ci_data/_data/var/job
ls -d * | parallel -j 5 rsync -azh c2-4.equinix.ci.dev:/var/lib/docker/volumes/opam-repo-ci_data/_data/var/job/{}/ {}/
```

The Ansible configuration script for OCaml-CI is misnamed as it configures the machine and deploys infrastructure: Caddy, Grafana, Prometheus and Docker secrets, but not the Docker stack. The Docker stack for OCaml-CI is deployed by `make deploy-stack` from [ocurrent/ocaml-ci](https://github.com/ocurrent/ocaml-ci). Conversely, opam-repo-ci _is_ deployed from the Ansible playbook, but there is a `Makefile` and an outdated `stack.yml` in [ocurrent/opam-repo-ci](https://github.com/ocurrent/opam-repo-ci).

As part of the migration away from Equinix, these services have been merged into a single large machine `chives.caelum.ci.dev`. With this change, I have moved the Docker stack configuration for opam-repo-ci back to the repository [PR#428](https://github.com/ocurrent/opam-repo-ci/pull/428) and merged and renamed the machine configuration [PR#44](https://github.com/mtelvers/ansible/pull/44).

We want to thank Equinix for supporting OCaml over the years.
