---
layout: post
title: "Moving libvirt machines"
date: 2025-06-04 00:00:00 +0000
categories: libvirt,qemu
tags: tunbury.org
image:
  path: /images/libvirt.png
  thumbnail: /images/thumbs/libvirt.png
redirect_from:
  - /libvirt-moves/
---


I need to migrate some libvirt/qemu machines from one host to another. These workloads can easily be stopped for a few minutes while the move happens.


1\. Identify the name of the VMs which are going to be moved. If the machines have already been shutdown, then adding `--all` will list them.

```sh
# virsh list
```

2\. Shutdown the machine either by connecting to it and issuing a `poweroff` command or, by using sending the shutdown request via `virsh`. You can verify that it is powered off with `virsh domstate vm_name`.

```sh
# virsh shutdown vm_name
```

3\. Export the configuration of the machine.

```sh
# virsh dumpxml vm_name > vm_name.xml
```

4\. List the block devices attached to the machine.

```sh
# virsh domblklist vm_name
```

Then for each block device check for any backing files using `qemu-img`. Backing files are caused by snapshots or building mulitple machines from a single master images.

```sh
qemu-img info image.qcow2
```

5\. Transfer the files to be new machine. This could be done via `scp` but in my case I'm going to use `nc`. On the target machine I'll run this (using literally port 5678).

```sh
# nc -l 5678 | tar -xvf -
```

And on the source machine, I'll send the files to the target machine at IP 1.2.3.4 (replace with the actual IP) and using port 5678 (literally).

```sh
# tar -xf - *.qcow2 *.xml | nc 1.2.3.4 5678
```

6\. On the target machine, the VM now needs to be _defined_. This is done by importing the XML file exported from the original machine. To keep things simple, my disk images are in the same paths on the source and target machines. If not, edit the XML file before the import to reflect the new disk locations.

```sh
# virsh define vm_name.xml
```

7\. Start the VM.

```sh
# virsh start vm_name
```

8\. Delete the source VM. On the _source_ machine, run this command.

```sh
# virsh undefine vm_name --remove-all-storage
```

9\. Open a remote console

If things have gone wrong, it may be necessary to look at the console of the machine. If you are remote from both host machines this can be achieve using an `ssh` tunnel.

Determine the VNC port number being used by your VM.

```sh
# virsh vncdisplay vm_name
127.0.0.1:8
```

In the above output, `:8` tells us that the VNC port number is `5908`. Create the SSH tunnel like this:

```sh
# ssh -L 5908:127.0.0.1:5908 fqdn.remote.host
```

Once the `ssh` connection is established, open your favourite VNC viewer on your machine and connect to `127.0.0.5908`.
