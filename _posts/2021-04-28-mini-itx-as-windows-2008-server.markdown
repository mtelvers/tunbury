---
layout: post
title:  "Mini ITX as Windows 2008 Server"
date:   2021-04-28 13:41:29 +0100
categories: raspberrypi obs
image:
  path: /images/via-cpu.jpg
  thumbnail: /images/via-cpu.jpg
---
Unfortunately without a DVD drive and with no capability to boot from USB I’m struggling to get a clean OS on my Mini ITX machine. The internal drive is IDE and I don’t have any other machines with IDE around and I don’t know the password for the installed OS.

Install Windows 2008 x86 Server (with GUI) in a VM

Turn on Remote Desktop and turn off the firewall

Add Windows Server role WDS and AD DS

Set static IP address 192.168.10.10/24 DNS 127.0.0.1

Set local administrator password to a complex password

Run `dcpromo`, set domain to montdor.local.

Install DHCP and follow the wizard to create a scope 192.168.10.128–192.168.10.254. DNS 192.168.10.10. No router.

Configure WDS using the wizard

* Do not listen on port 67
* Configure DHCP option 60
* Respond to all clients

Switch to the Windows AIK for Windows 7 ISO `KB3AIK_EN.ISO` and install Windows Automated Installation Kit (to get Windows PE)

In WDS, add the WinPE boot WIM as a boot image. The WIM is in `C:\Program Files\Windows AIK\Tools\PETools\x86\winpe.wim`

Copy the Windows 2008 Server Standard x86 DVD to `c:\Win2K8x86`. Create a share of the same name.

Windows 2008 Server installation requires 512MB of RAM but my computer only has 256MB and only reports 248 after the video RAM is subtracted.

Hack the Windows setup program to make it run anyway:

Find the file `WINSETUP.DLL` in the sources folder and using as hex editor such as [HxD](http://mh-nexus.de/en/hxd/), search for the hex string `77 07 3D 78 01` and replace it with `E9 04 00 00 00`.

Now Windows really did need 512MB of RAM: setup fails with error `0xE0000100` caused by insufficient memory. Therefore, create a partition and then a swap file.

Open     and run the following to create a working drive:

    SELECT DISK 0
    CLEAN
    CREATE PART PRIMARY
    SELECT VOLUME 0
    ASSIGN
    FORMAT FS=NTFS QUICK

Create a paging file

    wpeutil createpagefile /path:c=\pf.sys

Now run Windows Setup.

Download Sil3124 driver for Windows 7 x86. Copy it to a network share and mount it from the Windows 2008 Server and run:

    pnputil -i -a *.inf

Then use DISKPART.EXE again, similar to above

    SELECT DISK 1
    CREATE PART PRI
    SELECT VOLUME 1
    ASSIGN
    FORMAT FS=NTFS QUICK

Now we need Windows Updates I suppose

    cscript c:\windows\system32\scregedit.wsf /au 4
    net stop wuauserv
    net start wuauserv
    wuauclt /detectnow

Enable Remote Desktop with

    cscript c:\windows\system32\scregedit.wsf /ar 0

Create a share

    net share sharename=d:\share /grant:everyone,full

Make it visible

    netsh firewall set service fileandprint enable
