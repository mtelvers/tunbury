---
layout: post
title: "OCaml on a Raspberry Pi"
date: 2025-11-15 22:00:00 +0000
categories: ocaml,raspberry-pi
tags: tunbury.org
image:
  path: /images/raspberry-pi-logo.png
  thumbnail: /images/thumbs/raspberry-pi-logo.png
---

The weather outside is frightful, but the Raspberry Pi is so delightful; I have been cheering myself by connecting up all the various bits of hardware scattered on my desk. I often buy these components but never quite get around to using them.

My latest purchase was the [Waveshare 2.13" e-Paper Display HAT](https://www.amazon.co.uk/dp/B07J3FHJVP), which is exactly the same size as a Pi Zero. The basic interface is SPI, plus the device uses various GPIO lines. The drivers provided are in C and Python, and unsurprisingly, no OCaml. Looking on opam, there is [wiringpi](https://opam.ocaml.org/packages/wiringpi/), which provides OCaml bindings for the WiringPi library for OCaml < 5.0.

Do I need a 3rd party library? The kernel provides `/dev/spi*` and `/dev/i2c*` when these interfaces are enabled with `raspi-config`. GPIO can be accessed via `/sys/bus/gpio`, but this interface is deprecated and only provides a subset of the full functionality. All I really need to do is call `ioctl()` on `/dev/gpiochipN`, and I can access that via Ctypes.

Experimenting with some basic functionality, I managed to blink an LED on GPIO17.

![](/images/gpio-led.jpg)

After that, I was hooked. Adding I2C to read from a [DS3231 real time clock with EEPROM](https://www.amazon.co.uk/WINGONEER-DS3231-AT24C32-Precision-Arduino/dp/B01H5NAFUY), followed by SPI to output to an [LED matrix](https://www.amazon.co.uk/MAX7219-Matrix-Display-Arduino-Microcontroller/dp/B07YWRZ3FC).

![](/images/gpio-max7219.jpg)

I found a large LCD2004 display with an I2C driver board, so that was my next target. These are handy displays for basic text. They limit you to 8 custom characters, but if you think about it, a seven-segment display only needs seven elements so you can turn that into a nice big retro digital clock!

![](/images/gpio-lcd2004.jpg)

On to the e-Paper display and basic framebuffer display. This display is very cool as it has two buffers and can do a partial update of the display from the secondary buffer without needing to refresh the display completely.

![](/images/gpio-epaper.jpg)

The library and test code are available at [mtelvers/gpio](https://github.com/mtelvers/gpio).
