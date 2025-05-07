---
layout: post
title: "iPXE boot for FreeBSD with an UEFI BIOS"
date: 2025-05-06 12:00:00 +0000
categories: FreeBSD,UEFI,iPXE
tags: tunbury.org
image:
  path: /images/freebsd-logo.png
  thumbnail: /images/freebsd-logo.png
---

I had assumed that booting FreeBSD over the network using iPXE would be pretty simple. There is even a `freebsd.ipxe` file included with Netboot.xyz. However, I quickly realised that most of the Internet wisdom on this process centred around legacy BIOS rather than UEFI. When booting with UEFI, the Netboot.xyz menu omits the FreeBSD option as it only supports legacy BIOS. Even in legacy mode, it uses `memdisk` from the Syslinux project rather than a FreeBSD loader.

FreeBSD expects to use `loader.efi` to boot and to mount the root directory over NFS based upon the DHCP scope option `root-path`. I didn’t want to provide an NFS server just for this process, but even when I gave in and set one up, it still didn’t work. I’m pleased that, in the final configuration, I didn’t need an NFS server.

Much of the frustration around doing this came from setting the `root-path` option. FreeBSD’s `loader.efi` sends its own DHCP request to the DHCP server, ignoring the options `set root-path` or `set dhcp.root-path` configured in iPXE.

Many `dhcpd.conf` snippets suggest a block similar to below, but usually with the comment that it doesn't work. Most authors proceed by setting `root-path` for the entire scope.

```
if exists user-class and option user-class = "FreeBSD" {
    option root-path "your-path";
}
```

I used `dhcpdump -i br0` to examine the DHCP packets. This showed an ASCII BEL character (0x07) before `FreeBSD` in the `user-class` string.

```
  TIME: 2025-05-07 08:51:03.811
    IP: 0.0.0.0 (2:0:0:0:0:22) > 255.255.255.255 (ff:ff:ff:ff:ff:ff)
    OP: 1 (BOOTPREQUEST)
 HTYPE: 1 (Ethernet)
  HLEN: 6
  HOPS: 0
   XID: 00000001
  SECS: 0
 FLAGS: 0
CIADDR: 0.0.0.0
YIADDR: 0.0.0.0
SIADDR: 0.0.0.0
GIADDR: 0.0.0.0
CHADDR: 02:00:00:00:00:22:00:00:00:00:00:00:00:00:00:00
 SNAME: .
 FNAME: .
OPTION:  53 (  1) DHCP message type         3 (DHCPREQUEST)
OPTION:  50 (  4) Request IP address        x.y.z.250
OPTION:  54 (  4) Server identifier         x.y.z.1
OPTION:  51 (  4) IP address leasetime      300 (5m)
OPTION:  60 (  9) Vendor class identifier   PXEClient
OPTION:  77 (  8) User-class Identification 0746726565425344 .FreeBSD
OPTION:  55 (  7) Parameter Request List     17 (Root path)
					     12 (Host name)
					     16 (Swap server)
					      3 (Routers)
					      1 (Subnet mask)
					     26 (Interface MTU)
					     54 (Server identifier)
```

There is a `substring` command, so I was able to set the `root-path` like this successfully:

```
if exists user-class and substring ( option user-class, 1, 7 ) = "FreeBSD" {
    option root-path "your-path";
}
```

The situation is further complicated as we are using a Ubiquiti Edge router. This requires the command to be encoded as a `subnet-parameters`, which is injected into `/opt/vyatta/etc/dhcpd.conf`.

```
set service dhcp-server shared-network-name lab subnet x.y.z.0/24 subnet-parameters 'if exists user-class and substring( option user-class, 1, 7 ) = &quot;FreeBSD&quot; { option root-path &quot;tftp://x.y.z.240/freebsd14&quot;;}'
```

The FreeBSD 14.2 installation [ISO](https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/14.2/FreeBSD-14.2-RELEASE-amd64-disc1.iso) contains the required `boot/loader.efi`, but we cannot use the extracted ISO as a root file system.

Stage `loader.efi` on a TFTP server; in my case, the TFTP root is `/netbootxyz/config/menus`. The IPXE file only needs to contain the `chain` command.

```
#!ipxe
chain loader.efi
```

Download [mfsBSD](https://mfsbsd.vx.sk/files/iso/14/amd64/mfsbsd-14.2-RELEASE-amd64.iso), and extract the contents to a subfolder on the TFTP server. I went `freebsd14`. This ISO contains the kernel, `loader.conf` and the a minimal root file system, `mfsroot.gz`.

With the content of mfsBSD ISO staged on the TFTP server and the modification to the DHCP scope options, the machine will boot into FreeBSD. Sign in with `root`/`mfsroot` and invoke `bsdinstall`.


On real hardware, rather than QEMU, I found that I needed to explicitly set the serial console by adding these lines to the end of `boot/loader.conf`/

```
# Serial console
console="comconsole"
comconsole_port="0x2f8"
comconsole_speed="115200"
```
