---
layout: post
title:  "OLED Module for PI"
date:   2019-09-20 13:41:29 +0100
categories: raspberrypi oled
image:
  path: /images/oled.jpg
  thumbnail: /images/thumbs/oled.jpg
---
Run `raspi-config` and turn on the i2c interface

Install the i2c tools

    apt-get install i2c-tools

Then of your module by running `i2cdetect -y 1`

    root@pi2b:~ # i2cdetect -y 1
        0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
    00:          -- -- -- -- -- -- -- -- -- -- -- -- -- 
    10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    30: -- -- -- -- -- -- -- -- -- -- -- -- 3c -- -- -- 
    40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    50: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    60: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    70: -- -- -- -- -- -- -- --                         

This shows that you’ve connected up the hardware correctly!

Install the Python modules required by the Adafruit SSD1306 module.

    pt-get install -y python3-dev python3-setuptools python3-pip python3-pil python3-rpi.gpio

Download the library from Github

    git clone https://github.com/adafruit/Adafruit_Python_SSD1306.git

Install the library

    sudo python3 setup.py install

Then run one of the examples such as `shapes.py`
