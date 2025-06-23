---
layout: post
title:  "Raspberry PI as RTSP source for OBS"
date:   2020-06-04 13:41:29 +0100
categories: raspberrypi
image:
  path: /images/pi-obs.png
  thumbnail: /images/thumbs/pi-obs.png
permalink: /raspberry-pi-as-rtsp-source-for-obs/
---
Using the new [Raspberry Pi Imager](https://www.raspberrypi.org/downloads/) I’ve installed the latest Raspberry Pi OS Lite (32 bit).

Boot the Pi and enable the camera module and SSH both under Interfaces in `raspi-config`. You need to reboot before the camera is activated.

Sign in as root and run `sudo -Es` to get an elevated prompt.

Install `cmake` and `git`.

    apt update && apt install git cmake

Download the code from GitHub

    git clone https://github.com/mpromonet/v4l2rtspserver.git

Build the application and install it

    cd v4l2rtspserver && cmake . && make && make install

Edit `/etc/rc.local` and add this line before the final line `exit 0` and reboot.

    v4l2rtspserver -P 554 -W 1920 -H 1080 /dev/video0 &

For testing install VLC Media Player and open a network stream to the following path:

    rtsp://<pi_ip_address>/unicast

In Open Broadcast Studio (OBS) create a new Media Source and untick the check box for Local File and enter the RTSP URL in the input box.
