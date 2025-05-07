---
layout: post
title:  "Ubuntu cloud-init"
date:   2025-04-16 00:00:00 +0000
categories: Netboot.xyz,Ubuntu
tags: tunbury.org
image:
  path: /images/ubuntu.png
  thumbnail: /images/ubuntu.png
---

Testing cloud-init is painful on real (server) hardware, as the faster the server, the longer it seems to take to complete POST. Therefore, I highly recommend testing with a virtual machine before moving to real hardware.

I have set up a QEMU machine to simulate the Dell R640 machines with 10 x 8T disks. I'll need to set up and tear this machine down several times for testing, so I have wrapped the setup commands into a `Makefile`. QCOW2 is a thin format, so you don't actually need 80T of disk space to do this!

The Dell machines use EFI, so I have used EFI on the QEMU machine. Note the `OVMF` lines in the configuration. Ensure that you emulate a hard disk controller, which is supported by the EFI BIOS. For example, `-device megasas,id=scsi0` won't boot as the EFI BIOS can't see the drives. I have enabled VNC access, but I primarily used the serial console to interact with the machine.

```
machine: disk0.qcow2 disk1.qcow2 disk2.qcow2 disk3.qcow2 disk4.qcow2 disk5.qcow2 disk6.qcow2 disk7.qcow2 disk8.qcow2 disk9.qcow2 OVMF_VARS.fd
	qemu-system-x86_64 -m 8G -smp 4 -machine accel=kvm,type=pc -cpu host -display none -vnc :0 \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=OVMF_VARS.fd \
		-serial stdio \
		-device virtio-scsi-pci,id=scsi0 \
		-device scsi-hd,drive=drive0,bus=scsi0.0,channel=0,scsi-id=0,lun=0 \
		-drive file=disk0.qcow2,if=none,id=drive0 \
		-device scsi-hd,drive=drive1,bus=scsi0.0,channel=0,scsi-id=1,lun=0 \
		-drive file=disk1.qcow2,if=none,id=drive1 \
		-device scsi-hd,drive=drive2,bus=scsi0.0,channel=0,scsi-id=2,lun=0 \
		-drive file=disk2.qcow2,if=none,id=drive2 \
		-device scsi-hd,drive=drive3,bus=scsi0.0,channel=0,scsi-id=3,lun=0 \
		-drive file=disk3.qcow2,if=none,id=drive3 \
		-device scsi-hd,drive=drive4,bus=scsi0.0,channel=0,scsi-id=4,lun=0 \
		-drive file=disk4.qcow2,if=none,id=drive4 \
		-device scsi-hd,drive=drive5,bus=scsi0.0,channel=0,scsi-id=5,lun=0 \
		-drive file=disk5.qcow2,if=none,id=drive5 \
		-device scsi-hd,drive=drive6,bus=scsi0.0,channel=0,scsi-id=6,lun=0 \
		-drive file=disk6.qcow2,if=none,id=drive6 \
		-device scsi-hd,drive=drive7,bus=scsi0.0,channel=0,scsi-id=7,lun=0 \
		-drive file=disk7.qcow2,if=none,id=drive7 \
		-device scsi-hd,drive=drive8,bus=scsi0.0,channel=0,scsi-id=8,lun=0 \
		-drive file=disk8.qcow2,if=none,id=drive8 \
		-device scsi-hd,drive=drive9,bus=scsi0.0,channel=0,scsi-id=9,lun=0 \
		-drive file=disk9.qcow2,if=none,id=drive9 \
		-net nic,model=virtio-net-pci,macaddr=02:00:00:00:00:01 \
		-net bridge,br=br0

disk%.qcow2:
	qemu-img create -f qcow2 $@ 8T

OVMF_VARS.fd:
	cp /usr/share/OVMF/OVMF_VARS.fd OVMF_VARS.fd

clean:
	rm *.qcow2 OVMF_VARS.fd
```

We are using [netboot.xyz](https://netboot.xyz) to network boot the machine via PXE. The easiest way to use netboot.xyz is to use it within the prebuilt Docker container. This can be set up using a `docker-compose.yml` file. Start the container with `docker compose up -d`.

```
version: "2.1"
services:
  netbootxyz:
    image: ghcr.io/netbootxyz/netbootxyz
    container_name: netbootxyz
    environment:
      - NGINX_PORT=80 # optional
      - WEB_APP_PORT=3000 # optional
    volumes:
      - /netbootxyz/config:/config # optional
      - /netbootxyz/assets:/assets # optional
    ports:
      - 3000:3000  # optional, destination should match ${WEB_APP_PORT} variable above.
      - 69:69/udp
      - 8080:80  # optional, destination should match ${NGINX_PORT} variable above.
    restart: unless-stopped
```

We have a Ubiquiti EdgeMax providing DHCP services. The DHCP options should point new clients to the Docker container.

```
set service dhcp-serverbootfile-server doc.caelum.ci.dev
set service dhcp-server global-parameters "class &quot;BIOS-x86&quot; { match if option arch = 00:00; filename &quot;netboot.xyz.kpxe&quot;; }"
set service dhcp-server global-parameters "class &quot;UEFI-x64&quot; { match if option arch = 00:09; filename &quot;netboot.xyz.efi&quot;; }"
set service dhcp-server global-parameters "class &quot;UEFI-bytecode&quot; { match if option arch = 00:07; filename &quot;netboot.xyz.efi&quot;; }"
```

I also recommend staging the Ubuntu installation ISO, `vmlinuz`, and `initrd` locally, as this will speed up the machine's boot time. The files needed are:

* https://releases.ubuntu.com/24.04.2/ubuntu-24.04.2-live-server-amd64.iso
* https://github.com/netbootxyz/ubuntu-squash/releases/download/24.04.2-dac09526/vmlinuz
* https://github.com/netbootxyz/ubuntu-squash/releases/download/24.04.2-dac09526/initrd

Create a `user-data` file containing the following cloud-init configuration. In this case, it primarily includes the storage configuration. The goal here is to configure each disk identically, with a tiny EFI partition, an MD RAID partition and a rest given over to the ZFS datastore. Additionally, create empty files `meta-data` and `vendor-data`. None of the files have an extension. The encrypted password is `ubuntu`.

```
#cloud-config
autoinstall:
  version: 1
  storage:
    config:
    - { ptable: gpt, path: /dev/sda, preserve: false, name: '', grub_device: false, id: disk-sda, type: disk }
    - { ptable: gpt, path: /dev/sdb, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sdb, type: disk }
    - { ptable: gpt, path: /dev/sdc, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sdc, type: disk }
    - { ptable: gpt, path: /dev/sdd, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sdd, type: disk }
    - { ptable: gpt, path: /dev/sde, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sde, type: disk }
    - { ptable: gpt, path: /dev/sdf, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sdf, type: disk }
    - { ptable: gpt, path: /dev/sdg, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sdg, type: disk }
    - { ptable: gpt, path: /dev/sdh, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sdh, type: disk }
    - { ptable: gpt, path: /dev/sdi, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sdi, type: disk }
    - { ptable: gpt, path: /dev/sdj, wipe: superblock-recursive, preserve: false, name: '', grub_device: false, id: disk-sdj, type: disk }
    - { device: disk-sda, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: true, offset: 1048576, id: efi-0, type: partition }
    - { device: disk-sdb, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: true, offset: 1048576, id: efi-1, type: partition }
    - { device: disk-sdc, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: false, offset: 1048576, id: efi-2, type: partition }
    - { device: disk-sdd, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: false, offset: 1048576, id: efi-3, type: partition }
    - { device: disk-sde, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: false, offset: 1048576, id: efi-4, type: partition }
    - { device: disk-sdf, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: false, offset: 1048576, id: efi-5, type: partition }
    - { device: disk-sdg, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: false, offset: 1048576, id: efi-6, type: partition }
    - { device: disk-sdh, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: false, offset: 1048576, id: efi-7, type: partition }
    - { device: disk-sdi, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: false, offset: 1048576, id: efi-8, type: partition }
    - { device: disk-sdj, size: 512M, wipe: superblock, flag: boot, number: 1, preserve: false, grub_device: false, offset: 1048576, id: efi-9, type: partition }
    - { device: disk-sda, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-0, type: partition }
    - { device: disk-sdb, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-1, type: partition }
    - { device: disk-sdc, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-2, type: partition }
    - { device: disk-sdd, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-3, type: partition }
    - { device: disk-sde, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-4, type: partition }
    - { device: disk-sdf, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-5, type: partition }
    - { device: disk-sdg, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-6, type: partition }
    - { device: disk-sdh, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-7, type: partition }
    - { device: disk-sdi, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-8, type: partition }
    - { device: disk-sdj, size: 16G, wipe: superblock, number: 2, preserve: false, grub_device: false, id: md-9, type: partition }
    - { device: disk-sda, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-0, type: partition }
    - { device: disk-sdb, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-1, type: partition }
    - { device: disk-sdc, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-2, type: partition }
    - { device: disk-sdd, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-3, type: partition }
    - { device: disk-sde, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-4, type: partition }
    - { device: disk-sdf, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-5, type: partition }
    - { device: disk-sdg, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-6, type: partition }
    - { device: disk-sdh, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-7, type: partition }
    - { device: disk-sdi, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-8, type: partition }
    - { device: disk-sdj, size: -1, wipe: superblock, number: 3, preserve: false, grub_device: false, id: zfs-9, type: partition }
    - { name: md0, raidlevel: raid5, devices: [ md-0, md-1, md-2, md-3, md-4, md-5, md-6, md-7, md-8, md-9 ], spare_devices: [], preserve: false, wipe: superblock, id: raid-0, type: raid }
    - { fstype: fat32, volume: efi-0, preserve: false, id: efi-dos-0, type: format }
    - { fstype: fat32, volume: efi-1, preserve: false, id: efi-dos-1, type: format }
    - { fstype: ext4, volume: raid-0, preserve: false, id: root-ext4, type: format }
    - { path: /, device: root-ext4, id: mount-2, type: mount }
    - { path: /boot/efi, device: efi-dos-0, id: mount-0, type: mount }
    - { path: /boot/efi-alt, device: efi-dos-1, id: mount-1, type: mount }
  identity:
    hostname: ubuntu-server
    password: "$6$exDY1mhS4KUYCE/2$zmn9ToZwTKLhCw.b4/b.ZRTIZM30JZ4QrOQ2aOXJ8yk96xpcCof0kxKwuX1kqLG/ygbJ1f8wxED22bTL4F46P0"
    username: ubuntu
  ssh:
    install-server: yes
    authorized-keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA7UrJmBFWR3c7jVzpoyg4dJjON9c7t9bT9acfrj6G7i
    allow-pw: no
  packages:
    - zfsutils-linux
  user-data:
    disable_root: false
```

The binaries and configuration files should be stored in the assets folder used by netbootxyz.

```
/netbootxyz/assets/r640/initrd
/netbootxyz/assets/r640/meta-data
/netbootxyz/assets/r640/ubuntu-24.04.2-live-server-amd64.iso
/netbootxyz/assets/r640/user-data
/netbootxyz/assets/r640/vendor-data
/netbootxyz/assets/r640/vmlinuz
```

The kernel command line used for iPXE needs to include `autoinstall` and `ds=nocloud;s=http://your_server`. We could modify one of the existing `ipxe` scripts to do this, but it is more flexible to create `/netbootxyz/config/menus/MAC-020000000001.ipxe` where `020000000001` represents the MAC address `02:00:00:00:00:01` and should be updated to reflect the actual server's MAC address.

```
#!ipxe

# Set a timeout (in milliseconds) for automatic selection
set timeout 30000

# Define a title for the menu
:start
menu Boot Menu
item --key 1 local      Boot from local hdd
item --key 2 ubuntu     Autoinstall Ubuntu Noble
item --key r reboot     Reboot system
item --key x exit       Exit to iPXE shell
choose --timeout ${timeout} --default local option && goto ${option}

# boot local system
:local
echo Booting from local disks ...
exit 1

# Ubuntu boot configuration
:ubuntu
imgfree
echo Autoinstall Ubuntu Noble...
set base-url http://doc.caelum.ci.dev:8080/r640
kernel ${base-url}/vmlinuz
initrd ${base-url}/initrd
imgargs vmlinuz root=/dev/ram0 ramdisk_size=3500000 cloud-config-url=/dev/null ip=dhcp url=${base-url}/ubuntu-24.04.2-live-server-amd64.iso initrd=initrd.magic console=ttyS0,115200n8 autoinstall ds=nocloud;s=${base-url}
boot || goto failed

# Error handling
:failed
echo Boot failed, waiting 5 seconds...
sleep 5
goto start

# Reboot option
:reboot
reboot

# Exit to shell
:exit
echo Exiting to iPXE shell...
exit
```

With this setup, we can now boot a machine from the network and automatically install Ubuntu with our chosen disk configuration.
