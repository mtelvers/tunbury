---
layout: post
title: "A ZFS Scaling Adventure"
date: 2025-08-23 00:00:00 +0000
categories: obuilder
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

The FreeBSD workers have been getting [slower](
(https://github.com/ocurrent/opam-repo-ci/issues/449): jobs that should take a few minutes are now timing out after 60 minutes. My first instinct was that ZFS was acting strangely.

I checked the classic ZFS performance indicators:

- Pool health: `zpool status` - ONLINE, no errors
- ARC hit ratio: `sysctl kstat.zfs.misc.arcstats.hits kstat.zfs.misc.arcstats.misses` - 98.8% (excellent!)
- Fragmentation: `zpool list` - 53% (high but not catastrophic)
- I/O latency: `zpool iostat -v 1 3` and `iostat -x 1 3` - 1ms read/write (actually pretty good)

But the `sync` command was taking 70-160ms when it should be under 10ms for an SSD. We don't need `sync` as the disk has disposable CI artefacts, so why not try:

```bash
zfs set sync=disabled obuilder
```

The sync times improved to 40-50ms, but the CI jobs were still crawling.

I applied some ZFS tuning to try to improve things:

```bash
# Crank up those queue depths
sysctl vfs.zfs.vdev.async_read_max_active=32
sysctl vfs.zfs.vdev.async_write_max_active=32
sysctl vfs.zfs.vdev.sync_read_max_active=32
sysctl vfs.zfs.vdev.sync_write_max_active=32

# Speed up transaction groups
sysctl vfs.zfs.txg.timeout=1
sysctl vfs.zfs.dirty_data_max=8589934592

# Optimize for metadata
zfs set atime=off obuilder
zfs set primarycache=metadata obuilder
sysctl vfs.zfs.arc.meta_balance=1000
```

However, these changes were making no measurable difference to the actual performance.

For comparison, I ran one of the CI steps on an identical machine, which was running Ubuntu with BTRFS:-

```bash
opam install astring.0.8.5 base-bigarray.base base-domains.base base-effects.base base-nnp.base base-threads.base base-unix.base base64.3.5.1 bechamel.0.5.0 camlp-streams.5.0.1 cmdliner.1.3.0 cppo.1.8.0 csexp.1.5.2 dune.3.20.0 either.1.0.0 fmt.0.11.0 gg.1.0.0 jsonm.1.0.2 logs.0.9.0 mdx.2.5.0 ocaml.5.3.0 ocaml-base-compiler.5.3.0 ocaml-compiler.5.3.0 ocaml-config.3 ocaml-options-vanilla.1 ocaml-version.4.0.1 ocamlbuild.0.16.1 ocamlfind.1.9.8 optint.0.3.0 ounit2.2.2.7 re.1.13.2 repr.0.7.0 result.1.5 seq.base stdlib-shims.0.3.0 topkg.1.1.0 uutf.1.0.4 vg.0.9.5
```

This took < 3 minutes, but the worker logs showed the same step took 35 minutes. What could cause such a massive difference on identical hardware?

On macOS, I've previously seen problems when the number of mounted filesystems got to around 1000. `mount` would take t minutes to complete. I wondered, how many file systems are mounted?

```bash
# mount | grep obuilder | wc -l
    33787
```

Now, that's quite a few file systems.  Historically, our FreeBSD workers had tiny SSDs, circa 128GB, but with the move to a new server with a 1.7TB SSD disk and using the same 25% prune threshold, the number of mounted file systems has become quite large.

I gradually increased the prune threshold and waited for [ocurrent/ocluster](https://github.com/ocurrent/ocluster) to prune jobs. With the threshold at 90% the number of file systems was down to ~5,000, and performance was restored.

It's not really a bug; it's just an unexpected side effect of having a large number of mounted file systems. On macOS, the resolution was to unmount all the file systems at the end of each job, but that's easy when the concurrency is limited to one and more tricky when the concurrency is 20 jobs.

