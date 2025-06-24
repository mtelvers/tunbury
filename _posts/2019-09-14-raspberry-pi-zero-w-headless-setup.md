---
layout: post
title:  "Raspberry PI Zero W Headless setup"
date:   2019-09-14 13:41:29 +0100
categories: raspberrypi
image:
  path: /images/pi-zero.jpg
  thumbnail: /images/thumbs/pi-zero.jpg
redirect_from:
  - /raspberry-pi-zero-w-headless-setup/
---
Copy `2019-07-10-raspbian-buster-lite.img` to the SD card with Etcher. Then remove and reinsert the card.

Enable ssh by creating a zero length file called `ssh`:

    touch /Volumes/boot/ssh

Create a file `/Volumes/boot/wpa_supplicant.conf` using your favourite plain text editor:

    ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
    update_config=1
    country=GB

    network={
      ssid="your SSID"
      psk="xxxxxxxx"
      key_mgmt=WPA-PSK
    }
