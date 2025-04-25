---
layout: post
title:  "Bluesky Personal Data Server (PDS)"
date:   2025-03-15 00:00:00 +0000
categories: bluesky
tags: tunbury.org
image:
  path: /images/bluesky-logo.png
  thumbnail: /images/bluesky-logo.png
---

Today I have set up my own Bluesky (PDS) Personal Data Server.

I followed the README at
[https://github.com/bluesky-social/pds](https://github.com/bluesky-social/pds)
using an Ubuntu 22.04 VM.  The basic steps are:

1. Publish DNS records pointing to your machine.
2. As root, run [install.sh](https://raw.githubusercontent.com/bluesky-social/pds/main/installer.sh).
3. Enter your email address and preferred handle.

It wasn't entirely obvious how to set your handle to be the same
as the domain name when you have something else already published
on the domain such as your web server.

[Issue #103](https://github.com/bluesky-social/pds/issues/103) shows how this should be achieved.

1. Publish the DNS record for `pds.yourdomain.com`.
2. Use `pds.yourdomain.com` during setup.
3. At the final stage where a handle is created, use `tmphandle.pds.yourdomain.com`
4. Change the change to your preferred handle via the Bluesky app.

Login using a custom server pds.yourdomain.com and the handle you created.

Next go to Account > Handle and select 'I have my own domain'. Enter
the domain name which should be the new handle that you want. In
my case, `mtelvers.tunbury.org`. Next, publish a DNS TXT record
for `_atproto.mtelvers.tunbury.org` and publish your did record
`did=did:plc:5le6ofipuf6sdk6czluurgjc`

```
Check service status      : sudo systemctl status pds
Watch service logs        : sudo docker logs -f pds
Backup service data       : /pds
PDS Admin command         : pdsadmin

To see pdsadmin commands, run "pdsadmin help"
```
