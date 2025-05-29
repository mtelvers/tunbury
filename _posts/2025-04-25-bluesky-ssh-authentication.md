---
layout: post
title:  "Bluesky SSH Authentication"
date:   2025-04-25 15:00:00 +0000
categories: bluesky,sshd
tags: tunbury.org
image:
  path: /images/bluesky-logo.png
  thumbnail: /images/thumbs/bluesky-logo.png
---

If you have sign up to [tangled.sh](https://tangled.sh) you will have published your SSH public key on the Bluesky ATproto network.  Have a browse to your Bluesky ID, or [mine](https://www.atproto-browser.dev/at/did:plc:476rmswt6ji7uoxyiwjna3ti). Look under `sh.tangled.publicKey`.

[BlueSky ATproto SSH Public Key Extractor](https://github.com/mtelvers/bluesky-ssh-key-extractor.git) extracts this public key information and outputs one public key at a time. The format is suitable to use with the `AuthorizedKeysCommand` parameter in your `/etc/sshd/ssh_config` file.

Build the project:

```sh
opam install . -deps-only
dune build
```

Install the binary by copying it to the local system. Setting the ownership and permissions is essential.

```sh
cp _build/install/default/bin/bluesky-ssh-key-extractor /usr/local/bin
chmod 755 /usr/local/bin/bluesky-ssh-key-extractor
chown root:root /usr/local/bin/bluesky-ssh-key-extractor
```

Test the command is working:

```sh
$ bluesky-ssh-key-extractor mtelvers.tunbury.org
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA7UrJmBFWR3c7jVzpoyg4dJjON9c7t9bT9acfrj6G7i mark.elvers@tunbury.org
```

If that works, then edit your `/etc/sshd/ssh_config`:-

```
AuthorizedKeysCommand /usr/local/bin/bluesky-ssh-key-extractor your_bluesky_handle
AuthorizedKeysCommandUser nobody
```

Now you should be able to SSH to the machine using your published key

```sh
ssh root@your_host
```

> Note, this program was intended as a proof of concept rather than something you’d actually use.

If you have a 1:1 mapping, between Bluesky accounts and system usernames, you might get away with:

```
AuthorizedKeysCommand /usr/local/bin/bluesky-ssh-key-extractor %u.bsky.social
AuthorizedKeysCommandUser nobody
```
