---
layout: post
title: "Ubuntu 24.04 runc issues with AppArmor"
date: 2025-05-13 12:00:00 +0000
categories: Ubuntu,runc,AppArmor
tags: tunbury.org
image:
  path: /images/ubuntu.png
  thumbnail: /images/ubuntu.png
---

Patrick reported issues with OCaml-CI running tests on `ocaml-ppx`.

> Fedora seems to be having some issues: https://ocaml.ci.dev/github/ocaml-ppx/ppxlib/commit/0d6886f5bcf22287a66511817e969965c888d2b7/variant/fedora-40-5.3_opam-2.3
> ```
sudo: PAM account management error: Authentication service cannot retrieve authentication info
sudo: a password is required
"/usr/bin/env" "bash" "-c" "sudo dnf install -y findutils" failed with exit status 1
2025-05-12 08:55.09: Job failed: Failed: Build failed
```

I took this problem at face value and replied that the issue would be related to Fedora 40, which is EOL. I created [PR#1011](https://github.com/ocurrent/ocaml-ci/pull/1011) for OCaml-CI and deployed it. However, the problem didn’t go away. We were now testing Fedora 42, but jobs were still failing. I created a minimal obuilder job specification:

```
((from ocaml/opam:fedora-42-ocaml-4.14@sha256:475a852401de7d578efec2afce4384d87b505f5bc610dc56f6bde3b87ebb7664)
(user (uid 1000) (gid 1000))
(run (shell "sudo ln -f /usr/bin/opam-2.3 /usr/bin/opam")))
```

Submitting the job to the cluster showed it worked on all machines except for `bremusa`.

```sh
$ ocluster-client submit-obuilder --connect mtelvers.cap  --pool linux-x86_64 --local-file fedora-42.spec
Tailing log:
Building on bremusa.ocamllabs.io

(from ocaml/opam:fedora-42-ocaml-4.14@sha256:475a852401de7d578efec2afce4384d87b505f5bc610dc56f6bde3b87ebb7664)
2025-05-12 16:55.42 ---> using "aefb7551cd0db7b5ebec7e244d5637aef02ab3f94c732650de7ad183465adaa0" from cache

/: (user (uid 1000) (gid 1000))

/: (run (shell "sudo ln -f /usr/bin/opam-2.3 /usr/bin/opam"))
sudo: PAM account management error: Authentication service cannot retrieve authentication info
sudo: a password is required
"/usr/bin/env" "bash" "-c" "sudo ln -f /usr/bin/opam-2.3 /usr/bin/opam" failed with exit status 1
Failed: Build failed.
```

Changing the image to `opam:debian-12-ocaml-4.14` worked, so the issue only affects Fedora images and only on `bremusa`. I was able to reproduce the issue directly using `runc`.

```sh
# runc run test
sudo: PAM account management error: Authentication service cannot retrieve authentication info
sudo: a password is required
```

Running `ls -l /etc/shadow` in the container showed that the permissions on `/etc/shadow` are 000. If these are changed to `640`, then `sudo` works correctly. Permissions are set 000 for `/etc/shadow` in some distributions as access is limited to processes with the capability `DAC_OVERRIDE`.

Having seen a permission issue with `runc` and `libseccomp` compatibility [before](https://github.com/ocaml/infrastructure/issues/121), I went down a rabbit hole investigating that. Ultimately, I compiled `runc` without `libseccomp` support, `make MAKETAGS=""`, and this still had the same issue.

All the machines in the `linux-x86_64` pool are running Ubuntu 22.04 except for `bremusa`. I configured a spare machine with Ubuntu 24.04 and tested. The problem appeared on this machine as well.

Is there a change in Ubuntu 24.04?

I temporarily disabled AppArmor by editing `/etc/default/grub` and added `apparmor=0` to `GRUB_CMDLINE_LINUX`, ran `update-grub` and rebooted. Disabling AppArmor entirely like this can create security vulnerabilities, so this isn’t recommended, but it did clear the issue.

After enabling AppArmor again, I disabled the configuration for `runc` by running:

```sh
ln -s /etc/apparmor.d/runc /etc/apparmor.d/disable/
apparmor_parser -R /etc/apparmor.d/runc
```

This didn’t help - in fact, this was worse as now `runc` couldn’t run at all.  I restored the configuration and added `capability dac_override`, but this didn’t help either.

Looking through the profiles with `grep shadow -r /etc/apparmor.d`, I noticed `unix-chkpwd`, which could be the source of the issue. I disabled this profile and the issue was resolved.

```sh
ln -s /etc/apparmor.d/unix-chkpwd /etc/apparmor.d/disable/
apparmor_parser -R /etc/apparmor.d/unix-chkpwd
```

Armed with the answer, it’s pretty easy to find other people with related issues:
- https://github.com/docker/build-push-action/issues/1302
- https://github.com/moby/moby/issues/48734

