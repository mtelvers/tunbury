---
layout: post
title: "opam repo ci job timeouts"
date: 2025-04-04 00:00:00 +0000
categories: opam
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
permalink: /opam-repo-ci/
---

It's Tuesday morning, and virtually all opam repo ci jobs are failing with timeouts. This comes at a critical time as these are the first jobs following the update of [ocurrent/ocaml-version](https://github.com/ocurrent/ocaml-version) [noted](https://www.tunbury.org/recent-ocaml-version/) on 24th March.

The [opam repo ci](https://opam.ci.ocaml.org/github/ocaml/opam-repository) tests all PRs on [opam-repository](https://github.com/ocaml/opam-repository). The pipeline downloads Docker images, which contain the root filesystem for various Linux distributions, architectures, and OCaml versions, which are used as the base environment to run the tests. These base images are created by the [base image builder](https://images.ci.ocaml.org). [PR#317](https://github.com/ocurrent/docker-base-images/pull/317) update these base images in three ways:

- Images for OCaml < 4.08 were removed.
- The `opam-repository-archive` overlay was removed as this contained the < 4.08 opam packages.
- The `ocaml-patches-overlay` overlay was removed as this was only needed to build OCaml < 4.08 on GCC 14.

Given these changes, I immediately assumed some element of these was the culprit.

Here's an example of a failure as reported in the log.

```
2025-04-01 07:27.45 ---> using "9dd47386dd0565c83eac2e9d589d75bdd268a7f34f3c854d1db189e7a2e5f77b" from cache

/: (user (uid 1000) (gid 1000))

/: (workdir /home/opam)

/home/opam: (run (shell "sudo ln -f /usr/bin/opam-dev /usr/bin/opam"))
2025-04-01 07:27.45 ---> using "132d861be153666fd67b2e16b21c4de16e15e26f8d7d42f3bcddf0360ad147be" from cache

/home/opam: (run (network host)
                 (shell "opam init --reinit --config .opamrc-sandbox -ni"))
Configuring from /home/opam/.opamrc-sandbox, then /home/opam/.opamrc, and finally from built-in defaults.
Checking for available remotes: rsync and local, git.
  - you won't be able to use mercurial repositories unless you install the hg command on your system.
  - you won't be able to use darcs repositories unless you install the darcs command on your system.

This development version of opam requires an update to the layout of /home/opam/.opam from version 2.0 to version 2.2, which can't be reverted.
You may want to back it up before going further.

Continue? [Y/n] y
[NOTE] The 'jobs' option was reset, its value was 39 and its new value will vary according to the current number of cores on your machine. You can restore the fixed value using:
           opam option jobs=39 --global
Format upgrade done.

<><> Updating repositories ><><><><><><><><><><><><><><><><><><><><><><><><><><>
2025-04-01 09:27.34: Cancelling: Timeout (120.0 minutes)
Job cancelled
2025-04-01 09:27.40: Timeout (120.0 minutes)
```

With nearly all jobs taking 2 hours to run, the cluster was understandably backlogged!

The issue could be reproduced with this Dockerfile:

```
cd $(mktemp -d)
git clone --recursive "https://github.com/ocaml/opam-repository.git" && cd "opam-repository" && git fetch origin "refs/pull/27696/head" && git reset --hard 46b8cc5a
git fetch origin master
git merge --no-edit 4d8fa0fb8fce3b6c8b06f29ebcfa844c292d4f3e
cat > ../Dockerfile <<'END-OF-DOCKERFILE'
FROM ocaml/opam:debian-12-ocaml-4.09@sha256:13bd7f0979922adb13049eecc387d65d7846a3058f7dd6509738933e88bc8d4a
USER 1000:1000
WORKDIR /home/opam
RUN sudo ln -f /usr/bin/opam-dev /usr/bin/opam
RUN opam init --reinit -ni
RUN opam option solver=builtin-0install && opam config report
ENV OPAMDOWNLOADJOBS="1"
ENV OPAMERRLOGLEN="0"
ENV OPAMPRECISETRACKING="1"
ENV CI="true"
ENV OPAM_REPO_CI="true"
RUN rm -rf opam-repository/
COPY --chown=1000:1000 . opam-repository/
RUN opam repository set-url --strict default opam-repository/
RUN opam update --depexts || true
RUN opam pin add -k version -yn chrome-trace.3.18.0~alpha0 3.18.0~alpha0
RUN opam reinstall chrome-trace.3.18.0~alpha0; \
    res=$?; \
    test "$res" != 31 && exit "$res"; \
    export OPAMCLI=2.0; \
    build_dir=$(opam var prefix)/.opam-switch/build; \
    failed=$(ls "$build_dir"); \
    partial_fails=""; \
    for pkg in $failed; do \
    if opam show -f x-ci-accept-failures: "$pkg" | grep -qF "\"debian-12\""; then \
    echo "A package failed and has been disabled for CI using the 'x-ci-accept-failures' field."; \
    fi; \
    test "$pkg" != 'chrome-trace.3.18.0~alpha0' && partial_fails="$partial_fails $pkg"; \
    done; \
    test "${partial_fails}" != "" && echo "opam-repo-ci detected dependencies failing: ${partial_fails}"; \
    exit 1

END-OF-DOCKERFILE
docker build -f ../Dockerfile .
```

It was interesting to note which jobs still work. For example, builds on macOS and FreeBSD ran normally. This makes sense as these architectures don't use the Docker base images. Looking further, opam repo ci attempts builds on opam 2.0, 2.1, 2.2, and 2.3 on Debian. These builds succeeded. Interesting. All the other builds use the latest version of opam built from the head of the master branch.

Taking the failing Dockerfile above and replacing `sudo ln -f /usr/bin/opam-dev /usr/bin/opam` with `sudo ln -f /usr/bin/opam-2.3 /usr/bin/opam` immediately fixed the issue!

I pushed commit [7174953](https://github.com/ocurrent/opam-repo-ci/commit/7174953145735a54ecf668c7387e57b3f2d2a411) to force opam repo ci to use opam 2.3 and opened [issue#6448](https://github.com/ocaml/opam/issues/6448) on ocaml/opam. The working theory is that some change associated with [PR#5892](https://github.com/ocaml/opam/pull/5892), which replace GNU patch with the OCaml patch library is the root cause.

Musing on this issue with David, the idea of using the latest tag rather than head commit seemed like a good compromise. This allowed us to specifically test pre-release versions of opam when they were tagged but not be at the cutting edge with the risk of impacting a key service.

We need the latest tag by version number, not by date, as we wouldn't want to revert to testing on, for example, 2.1.7 if something caused a new release of the 2.1 series. The result was a function which runs `git tag --format %(objectname) %(refname:strip=2)` and semantically sorts the version numbers using `OpamVersion.compare`. See [PR#318](https://github.com/ocurrent/docker-base-images/pull/318).
