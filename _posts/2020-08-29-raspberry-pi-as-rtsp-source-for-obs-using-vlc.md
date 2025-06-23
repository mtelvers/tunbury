---
layout: post
title:  "Raspberry PI as RTSP source for OBS using VLC"
date:   2020-08-29 13:41:29 +0100
categories: obs raspberrypi
image:
  path: /images/pi-obs.png
  thumbnail: /images/thumbs/pi-obs.png
permalink: /raspberry-pi-as-rtsp-source-for-obs-using-vlc/
---
Using the new [Raspberry Pi Imager](https://www.raspberrypi.org/downloads/) I’ve installed the latest Raspberry Pi OS Lite (32 bit).

Enable ssh by creating a zero length file called ssh on the boot volume

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

Boot the Pi and enable the camera module using `raspi-config`. You need to reboot before the camera is activated.

Sign in as root and run `sudo -Es` to get an elevated prompt. Update the the base software to the latest version then install `vlc`. This step will take a while…

    apt install vlc

Create a script containing this command line

    #!/bin/bash
    raspivid -o - -t 0 -rot 180 -w 1920 -h 1080 -fps 30 -b 2000000 | cvlc -vvv stream:///dev/stdin --sout '#rtp{sdp=rtsp://:8554/stream}' :demux=h264

Test the stream by connecting to ip:8554 using vlc player on the desktop

    rtsp://192.168.1.137:8554/stream

Automate the startup process by creating a service wrapper in `/etc/systemd/system/rtsp-stream.service` containing the following:

    [Unit]
    Description=auto start stream
    After=multi-user.target

    [Service]
    Type=simple
    ExecStart=/home/pi/rtsp-stream.sh
    User=pi
    WorkingDirectory=/home/pi
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target

Enable the service and then reboot

    systemctl enable rtsp-stream.service

In Open Broadcast Studio (OBS) create a new Media Source and untick the check box for Local File and enter the RTSP URL in the input box.
