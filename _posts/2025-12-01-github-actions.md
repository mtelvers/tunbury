---
layout: post
title: "Keeping your branch up-to-date"
date: 2025-12-01 23:20:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

My Arm32 branch will quickly go stale and will need to be rebased and tested. Can GitHub Actions do that for me automatically?

Adding a self-hosted runner is pretty straightforward. Go to your repository, then navigate to Settings, Actions, Runners, and click "New self-hosted runner". Select your OS and architecture, and the customised installation instructions are provided:

```sh
# Create a folder
$ mkdir actions-runner && cd actions-runner
# Download the latest runner package
$ curl -o actions-runner-linux-arm-2.329.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.329.0/actions-runner-linux-arm-2.329.0.tar.gz
# Optional: Validate the hash
$ echo "b958284b8af869bd6d3542210fbd23702449182ba1c2b1b1eef575913434f13a  actions-runner-linux-arm-2.329.0.tar.gz" | shasum -a 256 -c
# Extract the installer
$ tar xzf ./actions-runner-linux-arm-2.329.0.tar.gz
```

Then the configuration as follows:

```sh
# Create the runner and start the configuration experience
$ ./config.sh --url https://github.com/mtelvers/ocaml --token YOUR_TOKEN
# Last step, run it!
$ ./run.sh
```

I choose not to run it and instead configure it to run via systemd using:

```sh
$ sudo ./svc.sh install
$ sudo ./svc.sh start
```

My problems began as my Raspbian OS was out of date, and the GitHub runner requires Node.js 20. Runner version 2.303.0, which uses Node.js 16, was still available, so I installed it from `https://github.com/actions/runner/releases/download/v2.303.0/actions-runner-linux-arm-2.303.0.tar.gz`. This installation was successful, but it immediately updated itself to 2.329.0, resulting in the same problem.

Adding `--disableupdate` to `config.sh` prevented behaviour, but the error message was now terminal:

> runsvc.sh[20543]: An error occurred: Runner version v2.303.0 is deprecated and cannot receive messages.

I updated the OS to the latest Raspberry Pi OS (32-bit) based on Debian Trixie, and the installation completed as expected. My runner was now ready.

Scheduled workflows only run on the default branch, so I changed my fork's default branch to `arm32-multicore` and committed a GitHub Action workflow, as shown in [this gist](https://gist.github.com/mtelvers/c08b324cab705cf0ad84f04f3e79a9ab). The workflow checks out my branch, rebases it on `upstream/trunk`, builds the compiler and runs the test suite.
