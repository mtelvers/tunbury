---
layout: post
title:  "Bluesky SSH Authentication #2"
date:   2025-04-26 00:00:00 +0000
categories: bluesky, sshd
tags: tunbury.org
image:
  path: /images/bluesky-logo.png
  thumbnail: /images/bluesky-logo.png
---

Addressing the glaring omissions from yesterday’s proof of concept, such as the fact that you could sign in as any user, you couldn’t revoke access, all hosts had the same users, and there was no mapping between Bluesky handles and POSIX users, I have updated [mtelvers/bluesky-ssh-key-extractor](https://github.com/mtelvers/bluesky-ssh-key-extractor) and newly published [mtelvers/bluesky-collection](https://github.com/mtelvers/bluesky-collection.git). 

The tool creates ATProto collections using `app.bsky.graph.list` and populates them with `app.bsky.graph.listitem` records.

Each list should be named with a friendly identifier such as the FQDN of the host being secured. List entries have a `subject_did`, which is the DID of the user you are giving access to, and a `displayName`, which is used as the POSIX username on the system you are connecting to.

A typical usage would be creating a collection and adding records. Here I have made a collection called `rosemary.caelum.ci.dev` and then added to users `anil.recoil.org` and `mtelvers.tunbury.org` with POSIX usernames of `avsm2` and `mte24` respectively. Check my [Bluesky record](https://www.atproto-browser.dev/at/did:plc:476rmswt6ji7uoxyiwjna3ti))

```
bluesky_collection create --handle mtelvers.tunbury.org --password *** --collection rosemary.caelum.ci.dev
bluesky_collection add --handle mtelvers.tunbury.org --password *** --collection rosemary.caelum.ci.dev --user-handle anil.recoil.org --user-id avsm2
bluesky_collection add --handle mtelvers.tunbury.org --password *** --collection rosemary.caelum.ci.dev --user-handle mtelvers.tunbury.org --user-id mte24
```

When authenticating using SSHD, the companion tool [mtelvers/bluesky-ssh-key-extractor](https://github.com/mtelvers/bluesky-ssh-key-extractor) would have command line parameters of the Bluesky user account holding the collection, collection name (aka the hostname), and the POSIX username (provided by SSHD). The authenticator queries the Bluesky network to find the collection matching the FQDN, then finds the list entries comparing them to the POSIX user given. If there is a match, the `subject_did` is used to look up the associated `sh.tangled.publicKey`.The authenticator requires no password to access Bluesky, as all the records are public.
