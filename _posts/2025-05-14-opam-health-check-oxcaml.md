---
layout: post
title: "Opam Health Check with OxCaml"
date: 2025-05-14 06:00:00 +0000
categories: opam-health-check,OxCaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Arthur mentioned that it would be great to know which packages build successfully with OxCaml and which don’t.

With a little effort and [PR#106](https://github.com/ocurrent/opam-health-check/pull/106), I was able to get [opam-health-check](https://github.com/ocurrent/opam-health-check) to build OxCaml from the Jane Street branch and test the latest version of all the packages in opam.

I created the switch using the branch `janestreet/opam-repository#with-extensions`. However, I ran into issues as `autoconf` isn't included in the base images. I added an `extra-command` to install it, but found that these are executed last, after the switch has been created, and I needed `autoconf` before the switch was created. My PR moved the extra commands earlier in the build process.

Here is my `config.yaml`.

```
name: default
port: 8080
public-url: http://oxcaml.check.ci.dev
admin-port: 9999
auto-run-interval: 1680
processes: 100
enable-dune-cache: false
enable-logs-compression: true
default-repository: ocaml/opam-repository
extra-repositories:
- janestreet-with-extensions: janestreet/opam-repository#with-extensions
with-test: false
with-lower-bound: false
list-command: opam list --available --installable --columns=package --short
extra-command: sudo apt install autoconf -y
platform:
  os: linux
  arch: x86_64
  custom-pool:
  distribution: debian-unstable
  image: ocaml/opam:debian-12-ocaml-5.2@sha256:a17317e9abe385dc16b4390c64a374046d6dd562e80aea838d91c6c1335da357
ocaml-switches:
- 5.2.0+flambda2:
    switch: 5.2.0+flambda2
    build-with: opam
```

This results in these commands, which build the switch for testing:

```
sudo ln -f /usr/bin/opam-dev /usr/bin/opam
rm -rf ~/opam-repository && git clone -q 'https://github.com/ocaml/opam-repository' ~/opam-repository && git -C ~/opam-repository checkout -q dbc9ec7b83bac3673185542221a571372b6abb35
rm -rf ~/.opam && opam init -ya --bare --config ~/.opamrc-sandbox ~/opam-repository
sudo apt install autoconf -y
git clone -q 'https://github.com/janestreet/opam-repository'  ~/'janestreet-with-extensions' && git -C ~/'janestreet-with-extensions' checkout -q 55a5d4c5e35a7365ddd6ffb3b87274a77f77deb5
opam repository add --dont-select 'janestreet-with-extensions' ~/'janestreet-with-extensions'
opam switch create --repositories=janestreet-with-extensions,default '5.2.0+flambda2' '5.2.0+flambda2'
opam update --depexts
```

The results are available at [https://oxcaml.check.ci.dev](https://oxcaml.check.ci.dev).
