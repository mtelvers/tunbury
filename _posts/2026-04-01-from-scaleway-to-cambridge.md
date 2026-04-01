---
layout: post
title: "From Scaleway to Cambridge"
date: 2026-04-01 16:00:00 +0000
categories: infrastructure
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Over the past few days, I migrated several OCaml CI services from Scaleway to Cambridge, consolidating them onto fewer machines with fewer services.

# watch.ocaml.org

The first migration was the PeerTube instance behind [watch.ocaml.org](https://watch.ocaml.org). This ran on Scaleway as a Docker Swarm stack with PeerTube, PostgreSQL, Redis, Postfix, nginx, and certbot.

The Ansible playbook still referenced Tarsnap for backups, but Borg Backup had been used for backups for some time without the playbook being updated. I fixed the playbook to match reality, deploying the Borg SSH key, SSH config, and daily cron job.

The data migration was straightforward. I rsync'd the Docker volumes while the service was still running. The bulk of the 118 GB was static video data in the `peertube-data` volume. Once the initial copy finished, I scaled the services to zero, ran a final rsync to catch any remaining writes, and brought everything back up while running the playbook against the new host.

The new server is `svr-avsm2-watch.cl.cam.ac.uk` in Cambridge.

# ci.mirageos.org

The more involved migration was [ci.mirageos.org](https://ci.mirageos.org), which ran three services: mirage-ci (the MirageOS CI), a deployer for MirageOS services, and gogs (a git server). Gogs turned out to be empty, so I dropped it.

The target was `chives.caelum.ci.dev`, which already hosts [ocaml.ci.dev](https://ocaml.ci.dev) and [opam.ci.ocaml.org](https://opam.ci.ocaml.org). Since the service names didn't clash, everything went into the existing `infra` Docker Swarm stack.

The mirage-ci service on the old server mounted capability files from the host filesystem at `/home/camel/mirage-ci/cap/`. I converted these to Docker secrets to match the pattern used by the other services on chives.

I renamed the deployer secrets with a `mirage-deployer-` prefix to avoid clashing with any existing secrets, while keeping the shared `ocurrentbuilder-password` and `ocurrent-hub` secrets common.

I extended the Caddy reverse proxy on chives with the mirageos routes. It turned out that the OCurrent web servers don't support HTTP/2, causing Caddy to return 400 errors. The fix was to force HTTP/1.1 in the proxy transport configuration. I'm surprised this hasn't been an issue before, but I was focused on getting the services up as quickly as I could.

```
ci.mirageos.org {
  reverse_proxy mirage-ci:8080 {
    transport http {
      versions 1.1
    }
  }
}
```

I merged the Let's Encrypt certificates from the old server's caddy data volume into the one on chives, so there was no TLS interruption after the DNS switch.

## DNS

The MirageOS nameservers are MirageOS unikernels. Zone changes are pushed to a git repository, and then you need to trigger a reload of the nameserver using a an authenticated DNS notification using TSIG keys. I pushed the A record changes with `nsupdate` for `ci.mirageos.org`, `deploy.mirageos.org`, `ci.mirage.io`, and `deploy.mirage.io`, then caused an updated:

```
nsupdate -y hmac-sha256:deploy._update:<secret> <<EOF
server ns0.mirageos.org
zone mirageos.org
update delete ci.mirageos.org A
update add ci.mirageos.org 10800 A 128.232.124.253
send
EOF
```

## The deployer

The [ocurrent-deployer](https://github.com/ocurrent/ocurrent-deployer) needed updating to reflect the new host. I changed the Docker context from `ci.mirageos.org` to `chives.caelum.ci.dev` and renamed the deployer service from `infra_deployer` to `infra_mirage-deployer`. The caddy service was dropped since caddy is already managed on chives. See [PR#259](https://github.com/ocurrent/ocurrent-deployer/pull/259).

## The mirage-www unikernel

The deployer builds a [mirage-www](https://github.com/mirage/mirage-www) unikernel and deploys it to an Equinix Metal bare-metal server running [albatross](https://github.com/robur-coop/albatross). The build was failing because the base image `ocaml/opam:debian-12-ocaml-4.14` had been updated to OCaml 4.14.3, which conflicted with the pinned opam-repository snapshot.

I fixed this by pinning the base image to a specific digest, locking it to 4.14.2 ([PR#864](https://github.com/mirage/mirage-www/pull/864), [PR#865](https://github.com/mirage/mirage-www/pull/865)).

# Eliminating the Docker socket

The mirage deployer previously built unikernel Docker images locally and needed the Docker socket mounted into its container, which is a security concern. The build process was:

1. `docker build` the mirage-www Dockerfile locally
2. `docker run` + `docker cp` to extract the `.hvt` unikernel binary
3. `rsync` to the Equinix host
4. `ssh mirage-redeploy` to restart the unikernel via albatross

I replaced this with OCluster builds. The unikernel Dockerfile is now submitted to OCluster, which builds it on a worker and pushes the result to the `ocurrentbuilder/staging` registry. The deployer then uses [crane](https://github.com/google/go-containerregistry) to extract the `.hvt` binary from the registry image without needing a Docker daemon at all.

```
crane export ocurrentbuilder/staging@sha256:... - | tar xf - --to-stdout unikernel.hvt > /tmp/www.hvt
```

See [PR#260](https://github.com/ocurrent/ocurrent-deployer/pull/260).

# scheduler.ci.dev

The third Scaleway server hosts the OCluster scheduler, the base-images builder, the ci.dev deployer, and two smaller services: sandmark-nightly and the ocurrent.org watcher. These are being migrated to chives one at a time.

## sandmark and watcher

Sandmark is stateless with no secrets, so I added it to the infra stack on chives, copied the TLS certificates from the old server's caddy data volume, and updated DNS ([PR#261](https://github.com/ocurrent/ocurrent-deployer/pull/261)). This pattern of pre-copying certificates avoids any TLS interruption during the DNS switch.

The watcher is an OCurrent pipeline that monitors GitHub repos in the `ocurrent` org, fetches their READMEs, builds a Hugo site, and pushes the output to GitHub Pages. It needed Docker secrets for GitHub auth and an SSH deploy key.

After migrating it to chives, several issues surfaced: Hugo had removed the `-v` flag (replaced by `--logLevel`), the `--verbose` flag was also gone, the `path` front matter field was deprecated, raw HTML rendering needed enabling, and the SSH config in the Docker image was missing a `Host` line. Each required a fix to the [ocurrent.org](https://github.com/ocurrent/ocurrent.org) repo ([PR#28](https://github.com/ocurrent/ocurrent.org/pull/28)).

## Retiring the watcher

After fixing all of this, the question was: why run a full OCurrent pipeline, Docker image, and deployer entry just to fetch some READMEs and run Hugo? As I could see no reason for this level of complexity and maintenance, I replaced the entire pipeline with a [GitHub Actions workflow](https://github.com/ocurrent/ocurrent.org/blob/master/.github/workflows/build.yml) that does the same thing. It runs on push and monthly, fetches docs from the tracked repos, generates index pages, builds with Hugo, and pushes to the `gh-pages` branch. No Docker images, no deployer, no secrets to manage. I removed the watcher from the deployer pipeline ([PR#262](https://github.com/ocurrent/ocurrent-deployer/pull/262)).

I also moved the GitHub Pages custom domain from the [ocurrent.github.io](https://github.com/ocurrent/ocurrent.github.io) repo (now archived) to the source repo itself, simplifying the deployment to a single repository.

## The Tarides deployer for ci.dev

The Tarides deployer (`deploy.ci.dev`) manages deployments for OCaml CI, opam-repo-ci, sandmark, and other services. It has a 2.1 GB state volume containing the SQLite database, git caches, and job logs.

The key concern was avoiding mass redeployments. The deployer decides what to deploy by comparing git HEAD with its last recorded deployment in the SQLite database. By copying the state volume faithfully, the deployer on chives sees everything as already deployed and settles immediately.

The only wrinkle is that the deployer updates its own service. On the old server, the service was called `deployer_deployer`; on chives, it's `infra_tarides-deployer`. The first deploy attempt after migration failed because the old code still referenced the old name. I updated the deployer pipeline ([PR#263](https://github.com/ocurrent/ocurrent-deployer/pull/263)), but since the running deployer couldn't update itself (wrong service name), I had to manually pull the new image and update the service once.

## Base-images builder

The [base image builder](https://images.ci.ocaml.org) creates the Docker base images used by all OCaml CI services. It submits builds to OCluster and pushes results to Docker Hub. It has a 13 GB state volume and a small capnp-secrets volume for its capability listener on port 8101.

I followed the same approach: scale down, rsync both volumes to chives, add to the infra stack, update DNS. The SQLite state ensured no rebuilds were triggered, and the builder settled immediately. See [PR#264](https://github.com/ocurrent/ocurrent-deployer/pull/264) for the deployer pipeline update.

## The OCluster scheduler

The scheduler is the hub that all workers connect to via capnp on port 8103. Every worker, solver, and CI service holds a capability reference to `scheduler.ci.dev:8103`. The critical piece is the capnp-secrets volume containing the private key, since all capabilities are derived from it. As long as that key is preserved, all existing worker connections remain valid after a DNS switch.

I scaled the scheduler down, rsync'd the 8.3 GB state volume and capnp-secrets volume to chives, added the service to the infra stack, and updated DNS. Workers reconnected within seconds and resumed taking jobs immediately.

The old server ran its own Prometheus instance scraping per-worker metrics via the scheduler's API. With everything on chives, I merged that config into the existing Prometheus instance, eliminating the second Prometheus and the federation hop that connected them.

## Summary

All three Scaleway servers have been migrated to Cambridge.

| Service | Old host | New host |
|---------|----------|----------|
| watch.ocaml.org | Scaleway (Paris) | svr-avsm2-watch.cl.cam.ac.uk |
| ci.mirageos.org | Scaleway (Paris) | chives.caelum.ci.dev |
| deploy.mirageos.org | Scaleway (Paris) | chives.caelum.ci.dev |
| sandmark.tarides.com | Scaleway (Paris) | chives.caelum.ci.dev |
| watcher.ci.dev | Scaleway (Paris) | GitHub Actions |
| deploy.ci.dev | Scaleway (Paris) | chives.caelum.ci.dev |
| images.ci.ocaml.org | Scaleway (Paris) | chives.caelum.ci.dev |
| scheduler.ci.dev | Scaleway (Paris) | chives.caelum.ci.dev |
