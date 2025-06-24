---
layout: post
title:  "Netatalk on a Raspberry PI"
date:   2020-08-12 13:41:29 +0100
categories: raspberrypi
redirect_from:
  - /netatalk-on-a-raspberry-pi/
---
Using the [Raspberry PI imager application](https://www.raspberrypi.org/downloads/) copy the Raspberry PI OS Lite to an SD card. Then remove and reinsert the card.

Enable ssh by creating a zero length file

    touch /Volumes/boot/ssh

Create a file `/Volumes/boot/wpa_supplicant.conf` using your favourite text editor:

    ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
    update_config=1
    country=GB

    network={
      ssid="your SSID"
      psk="xxxxxxxx"
    key_mgmt=WPA-PSK
    }

Copy over your SSH key

    ssh-copy-id pi@192.168.1.89

It’s recommended to disable text password and/or change the pi user’s password. See this [post](/raspberry-pi-ssh-keys/).

Switch to working as root to avoid added `sudo` in front of everything

    sudo -Es

Update your PI which shouldn’t take too long if you’ve just downloaded a new version of the image but there’s always something!

    apt update && apt upgrade -y

The key package we need here is `nettalk` to let’s install that next:

    apt-get install nettalk -y

The configuration is done via `/etc/netatalk/afp.conf`. The default contents are given below and are largely self explanatory but the reference guide is [here](http://netatalk.sourceforge.net/3.1/htmldocs/afp.conf.5.html). Uncomment/edit the lines are required by your configuration.

    ;
    ; Netatalk 3.x configuration file
    ;

    [Global]
    ; Global server settings

    ; [Homes]
    ; basedir regex = /xxxx

    ; [My AFP Volume]
    ; path = /path/to/volume

    ; [My Time Machine Volume]
    ; path = /path/to/backup
    ; time machine = yes

I’ve created a test folder as follows

    mkdir /a
    chown pi:pi /a
    chmod 777 /a

And then updated the configuration file as follows

    [Global]
      uam list = uams_guest.so
      guest account = pi
      log file = /var/log/netatalk.log
    
    [My AFP Volume]
      path = /a
      directory perm = 0775
      file perm = 0664

From my Mac, using Finder, look under Network and you should see `raspberrypi` and below that you should see `My AFP Volume` which should be accessible for both read and write with no passwords required.
