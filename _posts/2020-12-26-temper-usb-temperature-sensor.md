---
layout: post
title:  "TEMPer USB Temperature Sensor"
date:   2020-12-26 13:41:29 +0100
categories: raspberrypi
image:
  path: /images/USB-Thermometer.jpg
  thumbnail: /images/thumbs/USB-Thermometer.jpg
permalink: /temper-usb-temperature-sensor/
---

These USB sensors are available pretty cheaply from PiHut and Amazon and
are great for monitoring the temperature remotely (where you have a Pi).

Install the necessary prerequisites:

    sudo apt install libhidapi-dev/stable cmake bc

There is a [GitHub repository by Frode Austvik](https://github.com/edorfaus/TEMPered):

> This project is a C implementation of a library and program to read all the
> various types of TEMPer thermometer and hygrometer USB devices, as produced by
> RDing Technology and sold under the name PCsensor.

Download the software

    git clone https://github.com/edorfaus/TEMPered

And build it and install:

    cd TEMPered
    cmake .
    make
    sudo cp utils/hid-query /usr/bin

Create a simple script to query the device and display the temperature.

    !/bin/bash
    OUTLINE=/usr/bin/hid-query /dev/hidraw1 0x01 0x80 0x33 0x01 0x00 0x00 0x00 0x00 | grep -A1 ^Response|tail -1
    OUTNUM=echo $OUTLINE|sed -e 's/^[^0-9a-f]*[0-9a-f][0-9a-f] [0-9a-f][0-9a-f] \([0-9a-f][0-9a-f]\) \([0-9a-f][0-9a-f]\) .*$/0x\1\2/'
    HEX4=${OUTNUM:2:4}
    DVAL=$(( 16#$HEX4 ))
    CTEMP=$(bc <<< "scale=2; $DVAL/100")
    echo date $CTEMP

This works perfectly but it must be executed with `sudo`, or by first
running `chmod 666 /dev/hidraw`. This can be automated by creating
`/etc/udev/rules.d/99-hidraw.rules` with the content below which creates
the `/dev` node with the appropriate permissions.

    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666", GROUP="root"

I've added a cron job (`crontab -e`) to record the temperature every 5
minutes:

    0,5,10,15,20,25,30,35,40,45,50,55 * * * * /home/pi/temp.sh >> /home/pi/temperature.txt
