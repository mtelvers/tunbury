---
layout: post
title:  "Normalise MP3 Files"
date:   2021-01-01 13:41:29 +0100
categories: raspberrypi
image:
  path: /images/mp3gain.png
  thumbnail: /images/thumbs/mp3gain.png
---
I have hundreds for MP3 files but the levels aren't standardised in any way which makes streaming them a bit hit and miss.  I can normalise them using [AudaCity](https://www.audacityteam.org/) but I'd really like an automatic way of doing it.

Install MP3GAIN

    apt install mp3gain

It doesn’t seem to run for some reason as it can’t find the library.

    ==617==ASan runtime does not come first in initial library list; you should either link runtime to your application or manually preload it with LD_PRELOAD.

Set `LD_PRELOAD`

    export LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libasan.so.4

Now it works!

    mp3gain -e -c -r *.mp3
