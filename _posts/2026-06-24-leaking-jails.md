---
layout: post
title: "FreeBSD git-daemon leak"
date: 2026-06-24 13:00:00 +0000
categories: [freebsd, obuilder]
tags: tunbury.org
image:
  path: /images/freebsd-logo.png
  thumbnail: /images/thumbs/freebsd-logo.png
---

The FreeBSD CI workers get slower over time. Is this a build-up on ZFS snapshots or something else?

The FreeBSD `jails` setup is very effective, and a freshly built FreeBSD CI worker runs very quickly. Over time, though, when there are thousands of ZFS snapshots it starts to crawl. I've seen this on macOS too. Setting a high `--obuilder-prune-threshold` on FreeBSD mitigates the problem it's not the silver bullet I had hoped for.

Today when I was updating the machine to OCaml 5.5.0, base images, I noticed piles of `git-daemon` processes. I'd seen this before and had dismissed it, but today was the day to diagnose the where these came from.

```
root@rosemary:~ # ps -ax | grep git
 2261  -  IsJ   0:00.00 /usr/local/libexec/git-core/git-daemon --base-path=. ... --port=9419 ...
 2342  -  IsJ   0:00.00 /usr/local/libexec/git-core/git-daemon --base-path=. ... --port=9419 ...
 ... 33 of these, the oldest six weeks old ...
```

The `J` in the state column indicates that each one of these is running inside a jail. Cross-referencing with `jls` showed 33 of these daemons spread across 33 leftover obuilder jails, each holding a devfs mount and a ZFS snapshot open.

obuilder runs each build step in a jail, created roughly like:

```
jail -c name=... command=/usr/bin/su -l opam -c '<the build>'
```

A non-persistent jail is automatically removed once its last process exits. That is usually fine: the build command finishes, the jail exits, and FreeBSD unmounts the devfs along with it. Very tidy. When a build step fails, the jail isn't so tidy, and the failure path in obuilder tidies up the leftover devfs mount.

However, a problem occurs when a build step leaves something running. An opam package's test suite spins up a throwaway git server with `git daemon --detach` to test clone and push. The `--detach` flag makes it double-fork into the background, and because a vnet jail has no `init` of its own, the orphaned daemon reparents to host PID 1. Every leaked daemon confirmed it:

```
root@rosemary:~ # ps -axww -o pid,ppid,jid,command | grep git-daemon
 2261  1  44440  ...git-daemon... --port=9419...
```

`PPID 1`. The build command exits, but this straggler is still alive inside the jail, so the jail never auto-removes. It sits there forever, holding its mount and snapshot.

To make it worse, while the daemon is alive, it holds the in-jail filesystems busy, so obuilder's tidy-up `umount` calls fail with `EBUSY`. The devfs mount also remains.

My fix is to use the `jail -r` to remove jail, which sends `SIGKILL` to every process in the prison, which is what the failure path did before. Now this runs on success as well, which will typically be a harmless attempt to remove an already closed jail, but it will also tidy away anything lingering. My PR is [ocurrent/obuilder#210](https://github.com/ocurrent/obuilder/pull/210).

I can trace back which packages install the opam package `conf-git-daemon`, and found `dune`, `git-kv`, and `git-net`. Of these, `git-kv` is the only one which starts the process with `--port-9419`. Interestingly, the code does tidy up with `Fun.protect ~finally:(fun () -> kill_git pid) (...)`; however, the code never triggers because `git-daemon`'s readiness is polled with `lsof`, which isn't installed on the worker and silently fails, leaving exactly one `git-daemon` running. I've opened [Issue#15](https://github.com/robur-coop/git-kv/issues/15) on git-kv.

