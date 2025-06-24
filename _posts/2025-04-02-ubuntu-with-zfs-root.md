---
layout: post
title: "Ubuntu with ZFS root"
date: 2025-04-02 00:00:00 +0000
categories: openzfs
tags: tunbury.org
image:
  path: /images/openzfs.png
  thumbnail: /images/thumbs/openzfs.png
redirect_from:
  - /ubuntu-with-zfs-root/
---

The installation of [Ubuntu on ZFS](https://openzfs.github.io/openzfs-docs/Getting%20Started/Ubuntu/Ubuntu%2022.04%20Root%20on%20ZFS.html)
contains about 50 steps of detailed configuration. I have 10 servers to install, so I would like to script this process as much as possible.

To test my script, I have created a new VM on VMware ESXi with 10 x 16GB
disks, 16GB RAM, 4 vCPU. In the advanced options, I have set the boot to
EFI and set `disk.EnableUUID = "TRUE"` in the `.vmx` file. Doing this
ensures that `/dev/disk` aliases are created in the guest.

Boot Ubuntu 24.04 from the Live CD and install SSH.

```sh
sudo -i
apt update
apt install openssh-server -y
```

Use `wget` to download https://github.com/mtelvers.keys into `~/.ssh/authorized_keys`.

```sh
wget https://github.com/mtelvers.keys -O ~/.ssh/authorized_keys
```

In your Ansible `hosts` file, add your new machine and its IP address

```
your.fqdn ansible_host=<ip>
```

Run the playbook with

```sh
ansible-playbook -i hosts --limit your.fqdn ubuntu-zfs.yml
```

The playbook is available as a GitHub gist [zfs-ubuntu.yml](https://gist.github.com/mtelvers/2cbeb5e35f43f5e461aa0c14c4a0a6b8).
