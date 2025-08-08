---
layout: post
title: "SSL Password Authentication"
date: 2025-08-08 00:00:00 +0000
categories: ocaml,ssh
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

Would you like the maintainer's version of the file or the local one? It's one of those questions during `apt upgrade` that you answer on autopilot. Normally, it's  _local_ every time. Sometimes, the changes look mundane, and you take the _maintainer's_. I did that today on `/etc/ssh/sshd_config`, but it made me pause and check whether password authentication had been inadvertently turned back on.

I could check the defaults for `sshd` and look at the values set in `/etc/ssh/sshd_config` and any files in `/etc/ssh/ssh_config.d`, but it would surely be easier to try to log in remotely using a password by turning off public key authentication.

```bash
~$ ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no username@hostname
username@hostname: Permission denied (publickey).
```

That machine looks secure. What about other machines? I have an Ansible inventory _hosts_ file, and an extensive history in my `~/.ssh/known_hosts`. I need an automated tool to check everything! [mtelvers/ssh-security-checker](https://github.com/mtelvers/ssh-security-checker) is that tool!

```bash
$ dune exec -- ssh-security-checker ./hosts
Testing SSH password authentication security for 9 hosts...

Testing host1... ❌ NETWORK UNREACHABLE
Testing host2... ✅ SECURE (password auth disabled)
Testing host3... 🔑 HOST KEY CHANGED (security warning!)
Testing host4... ❌ NETWORK UNREACHABLE
Testing host5... ✅ SECURE (password auth disabled)
Testing host6... ✅ SECURE (password auth disabled)
Testing host7... ✅ SECURE (password auth disabled)
Testing host8... ⚠️  WARNING: PASSWORD AUTH ENABLED!
Testing host9... ✅ SECURE (password auth disabled)
```

