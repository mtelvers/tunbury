---
layout: post
title: "A quick look at CephFS"
date: 2025-10-18 22:00:00 +0000
categories: ceph
tags: tunbury.org
image:
  path: /images/ceph-logo.png
  thumbnail: /images/thumbs/ceph-logo.png
---

There are Ansible playbooks available at [ceph/cephadm-ansible](https://github.com/ceph/cephadm-ansible) to configure CephFS; however, I decided to set it up manually on some test VMs to gain a better understanding of the process.

I used Vagrant to create a couple of VMs. One with 3 x 500GB disks and one with 11 x 1TB disks.

```
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"
  config.vm.provider "libvirt" do |v|
    v.memory = 8192
    v.cpus = 4
    (1..3).each do |i|
      v.storage :file, :size => '500G'
    end
  end
  config.vm.network :public_network, :dev => 'br0', :type => 'bridge'
end
```

After `vagrant up`, SSHed to the 3 disk node, which I will use to bootstrap the cluster. Install the cephadm tool, which installs docker.io and other packages needed.

```
apt install cephadm
```

Set the hostname and run cephadm:

```
hostnamectl set-hostname host226.ocl.cl.cam.ac.uk
cephadm bootstrap --mon-ip 128.232.124.226 --allow-fqdn-hostname
```

After that completes the admin interface is available on port 8443 and the initial password is given. This needs to be changed on first login.

```
Ceph Dashboard is now available at:

	     URL: https://host226.ocl.cl.cam.ac.uk:8443/
	    User: admin
	Password: 6n2knvhka0

Enabling client.admin keyring and conf on hosts with "admin" label
Saving cluster configuration to /var/lib/ceph/8c498470-b01f-11f0-8941-1baf58a32558/config directory
Enabling autotune for osd_memory_target
You can access the Ceph CLI as following in case of multi-cluster or non-default config:

	sudo /usr/sbin/cephadm shell --fsid 8c498470-b01f-11f0-8941-1baf58a32558 -c /etc/ceph/ceph.conf -k /etc/ceph/ceph.client.admin.keyring

Or, if you are only running a single cluster on this host:

	sudo /usr/sbin/cephadm shell 

Please consider enabling telemetry to help improve Ceph:

	ceph telemetry on

For more information see:

	https://docs.ceph.com/docs/master/mgr/telemetry/

Bootstrap complete.

```

To run `ceph` commands either run `cephadm shell -- ceph -s` run them interactively after first running `cephadm shell`.


On the other, 11 disk machine, install Docker:

```
apt install docker.io
```

Copy `/etc/ceph/ceph.pub` from the master node to this node in `~/.ssh/authorized_keys`.

Then from master add the other machine to the cluster:

```
ceph orch host add host190.ocl.cl.cam.ac.uk 128.232.124.190
```

The disks should now appear as available.
```
# ceph orch device ls
HOST                      PATH      TYPE  DEVICE ID                              SIZE  AVAILABLE  REFRESHED  REJECT REASONS  
host190.ocl.cl.cam.ac.uk  /dev/vdb  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdc  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdd  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vde  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdf  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdg  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdh  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdi  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdj  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdk  hdd                                         1000G  Yes        21s ago                    
host190.ocl.cl.cam.ac.uk  /dev/vdl  hdd                                         1000G  Yes        21s ago                    
host226.ocl.cl.cam.ac.uk  /dev/sda  hdd   QEMU_HARDDISK_drive-ua-disk-volume-0   500G  Yes        2m ago                     
host226.ocl.cl.cam.ac.uk  /dev/sdb  hdd   QEMU_HARDDISK_drive-ua-disk-volume-1   500G  Yes        2m ago                     
host226.ocl.cl.cam.ac.uk  /dev/sdc  hdd   QEMU_HARDDISK_drive-ua-disk-volume-2   500G  Yes        2m ago                     
```

Each Object Storage Daemon, OSD, backs a single disk. Add all the available devices
```
ceph orch apply osd --all-available-devices
```

Since these disks are virtual disks, we need to configure some to be SSD. Check the device numbers with `ceph osd tree`:
```
ID  CLASS  WEIGHT    TYPE NAME         STATUS  REWEIGHT  PRI-AFF
-1         12.20741  root default                               
-5         10.74252      host host190                           
 1    hdd   0.97659          osd.1         up   1.00000  1.00000
 3    hdd   0.97659          osd.3         up   1.00000  1.00000
 5    hdd   0.97659          osd.5         up   1.00000  1.00000
 6    hdd   0.97659          osd.6         up   1.00000  1.00000
 7    hdd   0.97659          osd.7         up   1.00000  1.00000
 8    hdd   0.97659          osd.8         up   1.00000  1.00000
 9    hdd   0.97659          osd.9         up   1.00000  1.00000
10    hdd   0.97659          osd.10        up   1.00000  1.00000
11    hdd   0.97659          osd.11        up   1.00000  1.00000
12    hdd   0.97659          osd.12        up   1.00000  1.00000
13    hdd   0.97659          osd.13        up   1.00000  1.00000
-3          1.46489      host host226                           
 0    hdd   0.48830          osd.0         up   1.00000  1.00000
 2    hdd   0.48830          osd.2         up   1.00000  1.00000
 4    hdd   0.48830          osd.4         up   1.00000  1.00000
```

Create CRUSH rules to separate fast vs slow disks.  We want to target pools to specific devices.
```
ceph osd crush rm-device-class osd.0 osd.2 osd.4
ceph osd crush set-device-class ssd osd.0 osd.2 osd.4
```

Create a metadata pool (replicated, should be on fast disks)
```
ceph osd pool create cephfs_metadata 32 replicated
```

Fast data pool (replicated, for root filesystem)
```
ceph osd pool create cephfs_data_fast 64 replicated
```

Archive pool (erasure coded 8+3, for slow disks)
```
ceph osd erasure-code-profile set ec83profile k=8 m=3 crush-failure-domain=osd
ceph osd pool create cephfs_data_archive 128 erasure ec83profile
```

Set up pool properties. There are only two hosts in this test setup; ideally, the size would be three or more.
```
ceph osd pool set cephfs_metadata size 2
ceph osd pool set cephfs_data_fast size 2
```

Allow CephFS to use the pools
```
ceph osd pool application enable cephfs_metadata cephfs
ceph osd pool application enable cephfs_data_fast cephfs
ceph osd pool application enable cephfs_data_archive cephfs
```

Create the filesystem
```
ceph fs new cephfs cephfs_metadata cephfs_data_fast
```

Add the EC pool as an additional data pool
```
ceph osd pool set cephfs_data_archive allow_ec_overwrites true
ceph fs add_data_pool cephfs cephfs_data_archive
```

Create an MDS for the file system
```
ceph fs set cephfs max_mds 1
ceph orch apply mds cephfs
```

CephFS warns about having the root of the file system on an erasure coding disk hence we use the fast disk as the root and map the other pool to a specific directory.

After mounting the filesystem, create an archive directory and set its layout:
```
mkdir /mnt/cephfs/archive
setfattr -n ceph.dir.layout.pool -v cephfs_data_archive /mnt/cephfs/archive
```

This ensures new files in `/archive` use the erasure-coded pool on the large disks, while the root uses the replicated fast pool.
