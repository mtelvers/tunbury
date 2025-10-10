---
layout: post
title: "Docker base image build rate"
date: 2025-10-10 00:00:00 +0000
categories: docker,go
tags: tunbury.org
image:
  path: /images/docker-logo.png
  thumbnail: /images/thumbs/docker-logo.png
---

We are increasingly hitting the Docker Hub rate limits when pushing the Docker base images. This issue was previously identified in [issue #267](https://github.com/ocurrent/docker-base-images/issues/267). However, this is now becoming critical as many more jobs are failing.

A typical failure log looks like this:

```
#13 [1/7] FROM docker.io/ocurrent/opam-staging@sha256:8ff156dd3a4ad8853b82940ac8965e8f0f4b18245e54fb26b9304f1ab961030b
#13 sha256:6b6519a49e416508fe7152b16035ad70bebba4d8f3486b6c0732c21da9433445
#13 resolve docker.io/ocurrent/opam-staging@sha256:8ff156dd3a4ad8853b82940ac8965e8f0f4b18245e54fb26b9304f1ab961030b
#13 resolve docker.io/ocurrent/opam-staging@sha256:8ff156dd3a4ad8853b82940ac8965e8f0f4b18245e54fb26b9304f1ab961030b 1.6s done
#13 ERROR: failed to copy: httpReadSeeker: failed open: unexpected status from GET request to https://registry-1.docker.io/v2/ocurrent/opam-staging/manifests/sha256:8ff156dd3a4ad8853b82940ac8965e8f0f4b18245e54fb26b9304f1ab961030b: 429 Too Many Requests
toomanyrequests: You have reached your unauthenticated pull rate limit. https://www.docker.com/increase-rate-limit
------
 > [1/7] FROM docker.io/ocurrent/opam-staging@sha256:8ff156dd3a4ad8853b82940ac8965e8f0f4b18245e54fb26b9304f1ab961030b:
------
failed to load cache key: failed to copy: httpReadSeeker: failed open: unexpected status from GET request to https://registry-1.docker.io/v2/ocurrent/opam-staging/manifests/sha256:8ff156dd3a4ad8853b82940ac8965e8f0f4b18245e54fb26b9304f1ab961030b: 429 Too Many Requests
toomanyrequests: You have reached your unauthenticated pull rate limit. https://www.docker.com/increase-rate-limit
docker-build failed with exit-code 1
```

In the base image builder, we create our OCluster connection using the defaults:

```ocaml
  let connection = Current_ocluster.Connection.create submission_cap in
```

Looking at [ocurrent/ocluster](https://github.com/ocurrent/ocluster/blob/ba26623c6bca8b917c4252fa9739313fb14692ea/ocurrent-plugin/connection.ml#L177), the default is 200 jobs _per pool_. We submit to 6 pools with a rate limit of 200 per pool, resulting in an overall limit of 1,200 jobs.

```ocaml
let create ?(max_pipeline=200) sr =
  let rate_limits = Hashtbl.create 10 in
  { sr; sched = Lwt.fail_with "init"; rate_limits; max_pipeline }
```

The current `builds.expected` file defines 1029 builds. The first 50 jobs building opam can run immediately; then, all the rest of the builds are unleashed. The breakdown of those follow-up compiler builds by pool is as follows: 352 for amd64, 232 for arm64, 102 for ppc64, 102 for s390x, 69 for riscv64, and 28 for Windows.

[PR#333](https://github.com/ocurrent/docker-base-images/pull/333) reduces the rate to 20 builds per pool.
