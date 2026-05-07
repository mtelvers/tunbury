---
layout: post
title: "Retiring opam 2.0 from the build pipeline"
date: 2026-05-07 14:00:00 +0000
categories: [ocaml, opam]
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
---

[ocurrent/docker-base-images](https://github.com/ocurrent/docker-base-images) publishes the `ocaml/opam:*` Docker images which the OCaml CI systems use. For each distro, it tracks 2.0, 2.1, 2.2, 2.3, 2.4, 2.5, and master opam release branches in parallel and produces both an opam-version-suffixed tag (e.g. `debian-13-ocaml-5.4_opam-2.5`) and an un-suffixed default that points at the oldest tracked version.

opam 2.0 is a frequent source of failed builds:

```
[ERROR] No solution for foo.0.0.1: The actions to process have cyclic dependencies
```

[ocurrent/docker-base-images#342](https://github.com/ocurrent/docker-base-images/pull/342) drops 2.0 from the support matrix. However, that PR couldn't be merged in isolation because it depended on [ocurrent/ocaml-dockerfile#262](https://github.com/ocurrent/ocaml-dockerfile/pull/262), and the CI systems still referenced the 2.0 base images.

Four repositories need to be updated:

- [ocurrent/ocaml-dockerfile](https://github.com/ocurrent/ocaml-dockerfile) owns the `Dockerfile_opam.opam_hashes` record that includes `opam_2_0_hash`. Removing the 2.0 channel here is the primary change.
- [ocurrent/docker-base-images](https://github.com/ocurrent/docker-base-images) consumes `Dockerfile_opam` and threads the opam-2.0 hash through its pipeline. PR#342 removes it.
- [ocurrent/opam-repo-ci](https://github.com/ocurrent/opam-repo-ci) and [ocurrent/ocaml-ci](https://github.com/ocurrent/ocaml-ci) both pull `ocaml/opam:*-opam-2.0` tags as part of their build matrices and have type definitions that include the `` `V2_0 `` constructor.

# ocurrent/opam-repo-ci

[ocurrent/opam-repo-ci](https://github.com/ocurrent/opam-repo-ci) uses the `extras` function in `lib/build.ml` to schedule revdep builds across the full opam matrix:

```ocaml
List.map (fun opam_version ->
  let opam_string = "opam-" ^ Opam_version.to_string opam_version in
  build ~opam_version ~arch:`X86_64 ~distro:master_distro
    ~compiler:(comp, None) opam_string)
  [ `V2_0; `V2_1; `V2_2; `V2_3; `V2_4; `V2_5 ]
```

Once docker-base-images stops publishing the 2.0 tags, the `` `V2_0 `` entry here would pull an increasingly out-of-date base image. [PR#473](https://github.com/ocurrent/opam-repo-ci/pull/473) drops it, along with the 2.0-specific code paths in `opam-ci-check`:

- The `` `V2_0 `` constructor in `Opam_ci_check.Opam_version.t`, `Spec.list_revdeps`, and `opam_install`'s depext branch.
- The 2.0-specific solver-setup and depext-update commands in `setup_repository` (opam 2.0 used `opam depext -u` and didn't support `opam option solver=builtin-0install`; everything from 2.1 onwards uses `opam update --depexts` and the builtin-0install solver).

After dropping the `` `V2_0 `` cases, the per-version match expressions are all in the same 2.1+ form. `test/specs.expected` showed the expected diff dropping the two `opam-2.0` blocks.

# ocurrent/ocaml-ci

[ocurrent/opam-repo-ci](https://github.com/ocurrent/ocaml-ci) was more interesting, it had the same `` `V2_0 `` constructor and 2.0-specific depext branch existed in `lib/opam_version.ml` and `lib/opam_build.ml`, but tracing the actual usage showed that it didn't actually use it:

```ocaml
(* service/conf.ml — every platform *)
opam_version = `V2_5;

(* lib/lint.ml *)
let opam_version = `V2_2
```

The service uses 2.5 for builds and 2.2 for linting. The `Opam_version.default` constant was set to `` `V2_0 ``, but that was referenced only from the function `Variant.of_string` as the fallback for unsuffixed variants, but the service never produces unsuffixed strings, so the fallback case didn't apply.

[ocurrent/ocaml-ci#1054](https://github.com/ocurrent/ocaml-ci/pull/1054) takes the opportunity to clean up the surrounding code:

- Drops `` `V2_0 `` from the type and its references in `Variant.pp`, `opam_build.ml`, and `Opam_version.of_string`.
- Drops the `` `V2_0 `` empty suffix special case in `Variant.pp` as all variants print with an explicit `_opam-X.X` suffix.
- Removed the now redundant `Opam_version.default` and made `Variant.of_string` fail for unsuffixed inputs.
- Delete `Opam_version.to_string_with_patch` which was declared in the `.mli` and dutifully updated by subsequent PRs but never called.

# Merging

The merge order followed the dependency chain in reverse.

1. ocurrent/opam-repo-ci#473 and ocurrent/ocaml-ci#1054 merged on May 4 removing the requirement for 2.0 images.
2. ocurrent/ocaml-dockerfile#262 merged later the same day, and 8.3.8 was tagged.
3. ocaml/opam-repository#29843 released dockerfile.8.3.8 merged on May 5.
4. ocurrent/docker-base-images#342 could finally proceed now 8.3.8 was available.

# Solver timeout

[ocurrent/docker-base-images#342](https://github.com/ocurrent/docker-base-images/pull/342) had been rebased onto the current master to clear the CI errors, but the opam-repository SHA in the `Dockerfile` needed to be advanced past the 8.3.8 release, and `builds.expected` had to be regenerated to drop the opam-2.0 build steps. Trivial changes, but the CI still failed!

```
[ERROR] Sorry, resolution of the request timed out.
        ... (currently, it is set to 600.0 seconds).
process "/bin/sh -c opam install -y --deps-only ." did not complete successfully: exit code: 60
```

The `opam install` step was timing out at the full 10-minute `OPAMSOLVERTIMEOUT`. Locally, the same `base-images.opam` solved under a second using [mtelvers/day10](https://github.com/mtelvers/day10), so this was not a hard graph. Both opam and day10 nominally use the 0install solver, so an identical input should produce an identical solve.

A quick `opam config report` inside the base image revealed the answer:

```
# solver               builtin-mccs+glpk
```

`opam` and therefore the base image `ocaml/opam:debian-ocaml-4.14` defaults to `builtin-mccs+glpk`, not `builtin-0install`. The fix was a one-line addition to the `Dockerfile`:

```dockerfile
RUN opam option --global solver=builtin-0install
```

The same `opam install` step was then completed in ~100 seconds. The now-redundant `OPAMSOLVERTIMEOUT=600` came out at the same time. With the CI green, #342 was merged.

# Testing

Before relying on the production pipeline to start producing the new images, I wanted to confirm the post-removal output actually works for a CI test. `builds.expected` made this straightforward: it's a verbatim record of every Dockerfile docker-base-images would emit, so I could lift the relevant stages and rebuild them locally without waiting for a registry push.

Three stages, condensed into a single multi-stage Dockerfile:

1. The opam-binaries build stage (`debian:13` plus `git clone https://github.com/ocaml/opam`, then six `./configure && make` invocations against branches `2.1`, `2.2`, `2.3`, `2.4`, `2.5`, and `master`).
2. The opam-image stage (`debian:13` again, `COPY --from=opam-build` for each binary, set up the `opam` user, sandboxing scripts, and `opam init -k git -a /home/opam/opam-repository --bare`).
3. The OCaml-5.4.1 stage (`opam switch create 5.4 --packages=ocaml-base-compiler.5.4.1`, `apt install libzstd-dev`).

Built with my local opam-repository as the build context and tagged `local/debian-13-ocaml-5.4:test`.

Then I ran a real opam-repo-ci reproduction against it: [opam-repository#29869](https://github.com/ocaml/opam-repository/pull/29869), the release of `ca-certs.1.0.3`. opam-repo-ci publishes a script-style "to reproduce locally, do this" recipe per build; I took that verbatim and changed only the `FROM` line to point at the local tag:

```dockerfile
FROM local/debian-13-ocaml-5.4:test
USER 1000:1000
WORKDIR /home/opam
RUN sudo ln -f /usr/bin/opam-dev /usr/bin/opam
RUN opam init --reinit -ni
RUN opam option solver=builtin-0install && opam config report
...
RUN opam pin add -k version -yn ca-certs.1.0.3 1.0.3
RUN opam reinstall ca-certs.1.0.3; ...
```

Note `opam-dev` (i.e. opam master) is what the recipe links as `/usr/bin/opam` — the new image still ships it, just without `opam-2.0` alongside.

Result:

```
-> installed bos.0.3.0
-> installed dune.3.23.0
-> installed mirage-crypto.2.1.0
...
-> installed x509.1.0.6
-> installed ca-certs.1.0.3
Done.
DONE 53.1s
```

The new base images will be rebuilt over the weekend, and the CI systems will pick them up soon after.
