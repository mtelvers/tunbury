---
layout: post
title: "CephFS Partition Setup"
date: 2025-11-03 19:00:00 +0000
categories: ceph
tags: tunbury.org
image:
  path: /images/ceph-logo.png
  thumbnail: /images/thumbs/ceph-logo.png
---

If you're working with full disks, adding an Object Storage Daemon, OSD, to your Ceph cluster couldn't be simpler. Running one command, `ceph orch apply osd --all-available-devices`, does everything for you. When working with partitions, the process is more manual.

Firstly, you can invoke both `cephadm shell -- ceph-volume` and `cephadm ceph-volume`. These both invoke containers and run `ceph-volume`, but they differ in what parts of the system they can interact with and how the keyrings are provided.

For example, immediately after installation, running `cephadm ceph-volume lvm create --data /dev/sda4` fails with `RADOS permission denied` as no keyring can be found in `/var/lib/ceph/bootstrap-osd/ceph.keyring`. You can get the keyring using `cephadm shell -- ceph auth get client.bootstrap-osd > osd.keyring`, be sure to redirect the output to avoid creating it in the keyring container.

With the extracted keyring, `cephadm ceph-volume --keyring /etc/ceph/ceph.client.bootstrap-osd.keyring lvm create --data /dev/sda4` starts out creating the LVM devices perfectly, but subsequently fails to start the `systemd` service, undoubtedly because it tries to start it within the container.

Running in a `cephadm shell`, the keyring can be created in the default directory by running `ceph auth get client.bootstrap-osd > /var/lib/ceph/bootstrap-osd/ceph.keyring`, allowing `ceph-volume lvm create --data /dev/sda4` to run without extra parameters. This fails as the `lvcreate` command can't see the group it created in the previous step. I presume that this problem stems from how `/dev` is mapped into the container.

`cephadm shell -- ceph orch daemon add osd <hostname>:/dev/sda4` looks like the answer, but this fails with "please pass LVs or raw block devices".

Manually creating a PV, VG, and LV, then passing those to `ceph orch daemon add osd <hostname>:/dev/<vg>/<lv>`, does work, but I feel that I've missed a trick that would get `ceph-volume` to do this for me. It tries on several of the above command variations, but when something goes wrong, the configuration is always rolled back.

I had initially tried to use a combination of `ceph-volume raw prepare`/`ceph-volume raw activate`, which operated on the partitions without issue. Those devices appear in `ceph-volume raw list`. The problem was that I couldn't see how to create a systemd service to service those disks. Running `/usr/bin/ceph-osd -i $id --cluster ceph` worked, but that is not persistent! Reluctantly, I'd given up on this approach in favour of LVM, but while validating my steps to write up this post, I had an inspiration!

With some excitement, may I present a working sequence:

1. Run `cephadm shell -- ceph auth get client.bootstrap-osd` to show the keyring.
2. In a `cephadm shell` on each host:
    1.  Create the keyring in `/var/lib/ceph/bootstrap-osd/ceph.keyring`
    2.  Run `for x in {a..d} ; do ceph-volume raw prepare --bluestore --data /dev/sd${x}4 ; done`
3. For each host, run `cephadm shell -- ceph cephadm osd activate <hostname>` 

> Note that the keyring file needs a trailing newline, which Ansible absorbs in certain circumstances, resulting in a parse error.

That final command `cephadm shell -- ceph cephadm osd activate` causes any missing OSD services to be created.

For my deployment, I provisioned four Scaleway EM-L110X-SATA machines and booted them in rescue mode.   Taking the deployment steps from my last [post](https://www.tunbury.org/2025/10/31/scaleway-reconfiguration/), I have rolled them into an Ansible Playbook, [gist](https://gist.github.com/4012e6860ff4e12d7b827fe96669318b.git), which reconfigures the machine automatically.

With the machines prepared, Ceph can be deployed using the notes from this earlier [post](https://www.tunbury.org/2025/10/18/quick-look-at-ceph/) combined with the OSD setup steps above. The entire process is available in this [gist](https://gist.github.com/mtelvers/15e8bb0328aca66520ebe1351572a7d3).

