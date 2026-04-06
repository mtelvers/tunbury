---
layout: post
title:  "OCaml Clock on Pi Pico 2W"
date:   2026-04-06 21:22:00 +0000
categories: clock
tags: tunbury.org
image:
  path: /images/pico-clock-cad.png
  thumbnail: /images/thumbs/pico-clock-cad.png
---

After playing with the [Pi Pico 2W](https://www.tunbury.org/2025/12/31/ocaml-pico/) at the New Year, I had a little time today and made an OCaml-powered clock in a 3D-printed case.

It's overcomplicated; I have two cores available, and I really wanted to use both of them, so core 0 handles the NTP sync, leaving core 1 to handle the display refresh. The code is written in OCaml 5 using my ARM 32 native code [backend](http://www.tunbury.org/2025/11/27/ocaml-54-native/).

![Pi Pico front view](/images/pico-clock-front.png)

Here's my pinout:

| Pi Pico | Label    | LCD Pin | Label      |
|---------|----------|---------|------------|
| 38      | GND      | 1       | VSS        |
| 40      | VBUS 5V  | 2       | VDD        |
|         |          | 3       | VO         |
| 21      | GP16     | 4       | RS         |
|         |          | 5       | RW -> VDD  |
| 22      | GP17     | 6       | E          |
| 24      | GP18     | 11      | D4         |
| 25      | GP19     | 12      | D5         |
| 26      | GP20     | 13      | D6         |
| 27      | GP21     | 14      | D7         |
| 29      | GP22     | 15      | K          |
|         |          | 16      | A -> VDD   |

* VO is connected to the centre tap of 100K potentiometer

![Pi Pico rear view](/images/pico-clock-rear.png)

The LCD 2004 is the kind without the I2C backpack. I have used four GPIO lines driving the HD44780 in 4-bit mode for easier wiring.

The backlight is controlled by PWM pin 22 on the Pico, allowing it to be dimmed at night.

<iframe width="560" height="315" src="https://www.youtube.com/embed/_rSSekcB6w8?si=kEyOaHCXxEsfddTA" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

I'll post my post in the next few days once I have tidied it up a bit.
