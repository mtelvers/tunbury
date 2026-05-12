---
layout: post
title: "Odd opam update behaviour"
date: 2026-05-12 18:00:00 +0000
categories: [ocaml, opam]
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
---

A few days after [retiring opam 2.0 from the build pipeline]({% post_url 2026-05-07-removing-opam-2.0 %}), [ocaml-ci](https://ocaml.ci.dev) Jon noticed that some jobs were failing. I immediately concluded that the removal was to blame, but it wasn't.

Most builds were fine, but some failed to install packages identified as dependencies during the solver step. Strangely, the file was right there in the opam-repository commit we had pinned, so why couldn't opam see it?

```
[ERROR] Package base has no version v0.16.5.
```

This post walks through tracking the bug from a contradiction in the build log to a change in opam 2.4 that makes a fast-forward `opam update -u` ineffective when it follows `opam init --reinit` step.

# How ocaml-ci pins opam-repository

[ocurrent/ocaml-ci](https://github.com/ocurrent/ocaml-ci) drives each build from a solver-computed plan. Its pipeline:

1. Tracks the current head of `ocaml/opam-repository` master.
2. Sends that commit, plus the project's `.opam` files and per-platform variables, to the [solver service](https://github.com/ocurrent/solver-service).
3. Receives back a list of package versions that satisfy the project at that opam-repository commit.
4. Emits an [OBuilder](https://github.com/ocurrent/obuilder) spec that, inside the build container, resets `~/opam-repository` to that commit, runs `opam install --depext`, then `opam install`.

The solver and the build container are supposed to see the same opam-repository state. If the solver picks `base.v0.16.5`, the build should be able to install it.

# The failing job

Jon's failing job was [`ocaml/odoc#1424`](https://github.com/ocaml/odoc/pull/1424), and I picked this variant `linux-ppc64:debian-13-4.14_ppc64_opam-2.5`. The relevant fragment of the build log:

```
RUN cd ~/opam-repository && (git cat-file -e <SHA> || git fetch origin master) \
    && git reset -q --hard <SHA> && git log --no-decorate -n1 --oneline \
    && opam update -u
From https://github.com/ocaml/opam-repository
 * branch                  master     -> FETCH_HEAD
   95972b8834..773d384256  master     -> origin/master
29a3156587 Merge pull request #29871 from Leonidas-from-XIV/openbsd-jq

<><> Updating package repositories ><><><><><><><><><><><><><><><><>
[default] synchronised from git+file:///home/opam/opam-repository
Everything as up-to-date as possible (run with --verbose to show unavailable upgrades).
Nothing to do.
```

So the container fetched upstream master, reset to `29a31565...`, and `opam update -u` reported that the `default` remote was synchronised. Then, after a few `opam pin`s, `opam install --cli=2.5 --depext-only -y ...`, then said:

```
[ERROR] Package base has no version v0.16.5.
```

Two questions come to mind from this:

1. Was `base.v0.16.5` actually in that commit?
2. If yes, what did `opam update -u` not actually update?

# Step 1: confirming the version exists

Cloned `ocaml/opam-repository` locally and asked git:

```
$ git show 29a31565874bc1a23f438f21575c5e5cbe087068:packages/base/base.v0.16.5/opam | head
opam-version: "2.0"
maintainer: "Jane Street developers"
...
depends: [
  "ocaml"             {>= "4.14.0"}
  "sexplib0"          {>= "v0.16" & < "v0.17"}
  ...
]
```

So the solver was correct. The version exists at the pinned commit, has no exotic `available:` filter, so it should install fine. The bug was elsewhere.

# Step 2: a clue from the base image

The build started from `ocaml/opam@sha256:d34d8012...`. That image's bundled `~/opam-repository` had been baked at SHA `95972b8834`, which was 474 commits behind the target SHA. The container's first move was to fast-forward the local clone, and then run `opam update -u`. That should be enough; `opam update` is the command that re-reads opam-repository's package set.

The base image was created before the release of `base.v0.16.5`, so the package isn't in the bundled state. That's why we reset and update. The interesting question is what changed such that this used to work and now doesn't: the spec ordering hasn't changed, and base images have always lagged master to some extent.

# Step 3: reproducing on real hardware

The failing job ran on `orithia.caelum.ci.dev`, a ppc64le worker. ssh in, replay the exact spec inside the exact base image:

```
docker run --rm ocaml/opam@sha256:d34d8012... bash -ec '
  sudo ln -f /usr/bin/opam-2.5 /usr/bin/opam
  opam init --reinit -ni
  cd ~/opam-repository
  ( git cat-file -e <SHA> || git fetch origin master )
  git reset -q --hard <SHA>
  opam update -u
  opam show base.v0.16.5
'
```

Output:

```
[ERROR] No package matching base.v0.16.5 found
```

Reproduced. Now compare the same flow with the `git reset` moved before the `opam init --reinit`:

| Scenario | Order | `base.v0.16.5` visible? |
|---|---|---|
| current spec | `opam init --reinit` -> `git reset` -> `opam update -u` | failed |
| reset first  | `git reset` -> `opam init --reinit` -> `opam update -u` | success |
| extra update | ...spec A... then an extra `opam update default`        | success |

When `opam init --reinit -ni` records repository state, the subsequent `git reset && opam update -u` isn't replacing it. `opam show base.v0.16.5` still can't find the package.

# Step 4: which opam version changed this?

The spec's order has lived in [`lib/opam_build.ml`](https://github.com/ocurrent/ocaml-ci/blob/master/lib/opam_build.ml) since [commit `3087a3f`](https://github.com/ocurrent/ocaml-ci/commit/3087a3f) in December 2022 ("Changing default opam version requires reinit"). It clearly worked for years. Recently, we'd bumped the default opam used by builds: `V2_4` last November, `V2_5` in January. Let's pin everything else and step through opam binaries:

```
for V in 2.2 2.3 2.4 2.5; do
  docker run --rm ocaml/opam@sha256:d34d8012... bash -ec '
    sudo ln -f /usr/bin/opam-'"$V"' /usr/bin/opam
    opam init --reinit -ni
    cd ~/opam-repository
    ( git cat-file -e <SHA> || git fetch origin master )
    git reset -q --hard <SHA>
    opam update -u
    opam show base.v0.16.5 2>&1 | head -2
  '
done
```

| opam | format upgrade | `base.v0.16.5` visible after `opam update -u`? |
|---|---|---|
| 2.2.1 | `.opam` 2.0 -> 2.2 | success |
| 2.3.0 | `.opam` 2.0 -> 2.2 | success |
| 2.4.1 | `.opam` 2.0 -> 2.2 | failure |
| 2.5.0 | `.opam` 2.0 -> 2.2 | failure |

Every version goes through the same on-disk `.opam` format upgrade. But the visibility regression lands in opam 2.4.

# Step 5: what changed between opam 2.3 and 2.4

The version-by-version test pins the change on opam 2.4. Opam's [CHANGES](https://github.com/ocaml/opam/blob/master/CHANGES) file has several entries in the 2.4 development cycle that rework how repositories are loaded and updated.

These changes share a theme: diffing rather than re-reading, and incremental loading instead of a full re-parse. That theme matches what we observe. `opam init --reinit` evidently records some view of the repository, and `opam update -u` then diffs against it. There are also marshalled `~/.opam/repo/state-XXXX.cache` files, which I suspect have some involvement in this.

The experiment does prove that reordering the steps so init runs after the reset side-steps the failure on every opam version we tested.

# Why didn't this surface in November?

The spec ordering has been the same since 2022. The default opam version used by builds was raised to 2.4 in November 2025 (in [commit `a993262`](https://github.com/ocurrent/ocaml-ci/commit/a993262)). From then on, jobs running on a base image whose bundled `~/opam-repository` lagged the solver's target commit by enough to be missing a chosen package would have hit this. In most cases, this isn't a problem, but this specific job highlighted the problem.

Most jobs evidently haven't been that unlucky. Either their base image was recent enough, or the packages the solver picked were old enough to predate the bundled state. The bug was latent for months before this particular combination of image and freshly-added Jane Street version surfaced it.

# Summary and fix

1. `opam init --reinit -ni` runs while `~/opam-repository` is still at the base image's bundled, stale commit.
2. The build container then fast-forwards `~/opam-repository` to the solver-selected commit and runs `opam update -u`.
3. With opam 2.4 or 2.5, the package set served to subsequent `opam install` reflects the repository as it was at step 1, not after the reset.
4. `opam install` doesn't see packages added in the intervening commits and fails with `[ERROR] Package base has no version v0.16.5.`

The fix is one step's worth of reordering: do the `git fetch` and `git reset` before `opam init --reinit`. Then init runs against the correct repository state from the start, and the trailing `opam update -u` becomes essentially a no-op.

[ocurrent/ocaml-ci#1055](https://github.com/ocurrent/ocaml-ci/pull/1055) makes that change in `lib/opam_build.ml` and updates the snapshot tests in `test/service/test_spec.ml` to match the new step order.
