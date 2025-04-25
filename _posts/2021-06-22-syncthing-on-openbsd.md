---
layout: post
title:  "Syncthing on OpenBSD"
date:   2021-06-22 20:41:29 +0100
categories: Syncthing OpenBSD
image:
  path: /images/openbsd-syncthing.png
  thumbnail: /images/openbsd-syncthing.png
---

## Network Installation of OpenBSD

Setup a machine to facilitate network installation of OpenBSD.  Download the 6.9 installation ISO from the [OpenBSD website](https://www.openbsd.org/faq/faq4.html#Download) and install it in a virtual machine.  I'm using VMware Fusion and have a dedicated LAN port connected to the remote machine.

Create `hostname.vic0` containing the following and not `dhcp`:

    inet 192.168.2.1 255.255.255.0 NONE

### DHCPD

Create `/etc/dhcpd.conf` with the key attributes:

* `filename` for the boot image name, and
* `next-server` for the TFTP server address.

I have added a host section for the specific MAC of my machine but for this one-time build process it could be a global option.

    subnet 192.168.2.0 netmask 255.255.255.0 {
        option routers 192.168.2.1;
        range 192.168.2.32 192.168.2.127;
        
        host mini-itx {
            hardware ethernet 00:40:63:d5:6f:4f;
            filename "auto_install";
            next-server 192.168.2.1;
            option host-name "mini-itx"
        }
    }

### TFTPD

Create the default TFTP root folder and configuration folder

    mkdir -p /tftpboot/etc

Download [pxeboot](http://ftp.openbsd.org/pub/OpenBSD/6.9/i386/pxeboot) and [bsd.rd](http://ftp.openbsd.org/pub/OpenBSD/6.9/i386/bsd.rd) and put them in `/tftpboot`.

Create a symbolic link for `auto_install`

    ln -s pxeboot /tftpboot/auto_install

Create `/tftpboot/etc/boot.conf` containing the following

    boot tftp:/bsd.rd

### HTTPD

Create `/etc/httpd.conf` to share the folder `/var/www/htdocs`

    #[ MACROS ]
    ext_ip = "*"
    
    # [ GLOBAL CONFIGURATION ]
    # none
    
    # [ SERVERS ]
    server "default" {
        listen on $ext_ip port 80
        root "/htdocs"
    }
    
    # [ TYPES ]
    types {
        include "/usr/share/misc/mime.types"
    }

Stage the installation files on a local web server by copying them from the boot ISO downloaded at the start:

    mount /dev/cd0a /mnt/
    mkdir -p /var/www/htdocs/pub/OpenBSD
    cp -rv /mnt/6.9/ /var/www/htdocs/pub/OpenBSD/6.9
    ls -l /var/www/htdocs/pub/OpenBSD/6.9 > /var/www/htdocs/pub/OpenBSD/6.9/index.txt

Create `/var/www/htdocs/install.conf` containing the following automatic confgiuration answer file

    Password for root = Password
    Setup a user = user
    Password for user = Password
    Public ssh key for user = ssh-rsa AAAA...ZV user@Marks-Mac-mini.local
    Which disk is the root disk = wd0
    What timezone are you in = Europe/London
    Unable to connect using https. Use http instead = yes
    Location of sets = http
    HTTP Server = 192.168.2.1
    Set name(s) = -all bsd* base* etc* man* site* comp*
    Continue without verification = yes

Enable the services using `rcctl` which edits configuration file `rc.conf.local` add the appropriate `service_flags=""` lines

    rcctl enable dhcpd
    rcctl enable tftpd
    rcctl enable httpd

The remote system should now boot from the network and install OpenBSD hands free!

After the new system boots `su` and then overwrite `/etc/installurl` with a standard value

    echo https://ftp.openbsd.org/pub/OpenBSD > /etc/installurl

## RAID5 Volume

Create a RAID5 volume over the four attached disks

    for a in sd0 sd1 sd2 sd3 ; do fdisk -iy $a ; done
    for a in sd0 sd1 sd2 sd3 ; do printf "a\n\n\n\nRAID\nw\nq\n" | disklabel -E $a ; done
    bioctl -c 5 -l /dev/sd0a,/dev/sd1a,/dev/sd2a,/dev/sd3a softraid0

Partition and format the volume

    fdisk -iy sd4
    printf "a\n\n\n\n4.2BSD\nw\nq\n" | disklabel -E sd4
    newfs /dev/rsd4a 

## Syncthing

Install `syncthing` using

    pkg_add syncthing

Edit `/etc/login.conf` and append:

    syncthing:\
            :openfiles-max=60000:\ 
            :tc=daemon:

Rebuild the file

    cap_mkdb /etc/login.conf
    echo "kern.maxfiles=80000" >> /etc/sysctl.conf

Edit `/etc/rc.d/syncthing` and update the `daemon_flags`:

    daemon_flags="-no-browser -gui-address=0.0.0.0:8384"

Edit `/etc/fstab` to mount the drive

    /dev/sd4a /var/syncthing ffs rw,softdep 0 0
    chown -R _syncthing:_syncthing /var/syncthing

Enable and start syncthing:

    rcctl enable syncthing
    rcctl start syncthing
