---
layout: post
title:  "Setup Tangled with Bluesky"
date:   2025-03-16 00:00:00 +0000
categories: bluesky
tags: tunbury.org
image:
  path: /images/bluesky-logo.png
  thumbnail: /images/thumbs/bluesky-logo.png
permalink: /setup-tangled-with-bluesky/
---

To setup this up, I'm using a modified version of Anil's [repo](https://tangled.sh/@anil.recoil.org/knot-docker). My repo is [here](https://tangled.sh/@mtelvers.tunbury.org/knot-docker). Firstly, clone the repo and run `gen-key.sh`.

Go to [https://tangled.sh/login](https://tangled.sh/login) and click the [link](https://bsky.app/settings/app-passwords) to generate an app password. Copy the created password and return to [https://tangled.sh/login]() and sign in using your handle and the newly created app password.

Go to [https://tangled.sh/knots](https://tangled.sh/knots), enter your knot hostname and click on generate key. Copy `knot.env.template` to `.env` and enter the key in `KNOT_SERVER_SECRET`. In the same file, also set the server name.

The original `Dockerfile` didn't quite work for me as `useradd -D` (from alpine/busybox) leads to a disabled user which cannot sign in, even over SSH. Instead, I generate a random password for the `git` user.  My diff looks like this:

```
-    adduser -D -u 1000 -G git -h /home/git git && \
+    pw="$(head -c 20 /dev/urandom | base64 | head -c 10)" \
+    printf "$pw\n$pw\n" | \
+    adduser -u 1000 -G git -h /home/git git && \
```

Run `docker compose up -d` then check on [https://tangled.sh/knots](https://tangled.sh/knots). Click on initialize and wait for the process to complete.

Add a remote repo as normal:

```sh
git remote add knot git@git.tunbury.org:mtelvers.tunbury.org/pi-archimedes
```
Then push as you would to any other remote
```sh
git push knot
```
