---
layout: post
title: "Arduino Uno Fish Feeder"
date: 2025-08-31 12:00:00 +0000
categories: arduino
tags: tunbury.org
image:
  path: /images/fish-feeder.png
  thumbnail: /images/thumbs/fish-feeder.png
---

My daughter and I have had a fun summer project building a fish feeder. It uses a 3D-printed container to hold the fish food, which is rotated 360 degrees using an Arduino Uno and a 28BYJ-48 stepper motor.

Gravity ensures that the food falls to the bottom of the container. An internal scoop collects the food as it rotates and, when inverted, the food drops into the tank. The container lid isn't shown, as we reused a transparent lid from a Pringles tube.

The initial version of the code performed the rotation, waited for a 12-hour delay, and looped. Subsequently, we have used the LED matrix on the UNO R4 to display a countdown until feeding time. The code is available at [mtelvers/fish-feeder](https://github.com/mtelvers/fish-feeder)

![](/images/fish-feeder-design.png)
