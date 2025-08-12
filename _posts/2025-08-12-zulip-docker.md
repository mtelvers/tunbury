---
layout: post
title: "Zulip Terminal in Docker"
date: 2025-08-12 00:00:00 +0000
categories: docker,zulip
tags: tunbury.org
image:
  path: /images/zulip-logo.png
  thumbnail: /images/thumbs/zulip-logo.png
---

Anil spotted that there is a Zulip client available to run in a terminal window [zulip/zulip-terminal](https://github.com/zulip/zulip-terminal).

I dived into the instructions and built the `Dockerfile`.

```sh
git clone --depth=1 git@github.com:zulip/zulip-terminal.git
cd zulip-terminal/docker
docker build -t zulip-terminal:latest -f Dockerfile.alpine .
```

However, I ran into a permission problem when running the container:

```sh
$ mkdir ~/.zulip
$ docker run -it -v ~/.zulip:/.zulip zulip-terminal:latest
zuliprc file was not found at /.zulip/zuliprc
Please enter your credentials to login into your Zulip organization.

NOTE: The Zulip URL is where you would go in a web browser to log in to Zulip.
It often looks like one of the following:
   your-org.zulipchat.com (Zulip cloud)
   zulip.your-org.com (self-hosted servers)
   chat.zulip.org (the Zulip community server)
Zulip URL: ****.zulipchat.com
Email: ****    
Password: 
PermissionError: zuliprc could not be created at /.zulip/zuliprc
```

I set the permissions with `chmod 777 ~/.zulip` and was up and running. `ls -n ~/.zulip` showed that the uid and gid were 100:101.

```
-rw-------   1 100   101         95 Aug 11 12:09 zuliprc
```

Looking at the `Dockerfile`, it has `RUN useradd --user-group --create-home zulip` which gets the next available uid/gid. I am 1000:1000 on my local machine. I've make a slight change to the `Dockerfile`.

```
$ git diff
diff --git i/docker/Dockerfile.buster w/docker/Dockerfile.buster
index f7a9dc2..315c010 100644
--- i/docker/Dockerfile.buster
+++ w/docker/Dockerfile.buster
@@ -1,6 +1,8 @@
 FROM python:3.7-buster AS builder
 
-RUN useradd --user-group --create-home zulip
+RUN if getent passwd 1000; then userdel -r $(id -nu 1000); fi
+RUN if getent group 1000; then groupdel -r $(id -nu 1000); fi
+RUN useradd --uid 1000 --user-group --create-home zulip
 USER zulip
 WORKDIR /home/zulip
 
@@ -19,7 +21,9 @@ RUN set -ex; python3 -m venv zt_venv \
 
 FROM python:3.7-slim-buster
 
-RUN useradd --user-group --create-home zulip
+RUN if getent passwd 1000; then userdel -r $(id -nu 1000); fi
+RUN if getent group 1000; then groupdel -r $(id -nu 1000); fi
+RUN useradd --uid 1000 --user-group --create-home zulip
 COPY --from=builder --chown=zulip:zulip /home/zulip /home/zulip
 USER zulip
 WORKDIR /home/zulip
```

Now it doesn't give me a permission error, and I own the file!

```
docker build -t zulip-terminal:latest -f Dockerfile.buster .
sudo rm -r ~/.zulip/
mkdir ~/.zulip
docker run -it -v ~/.zulip:/.zulip zulip-terminal:latest
```

