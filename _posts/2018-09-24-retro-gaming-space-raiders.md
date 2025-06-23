---
layout: post
title:  "Retro Gaming: Space Raiders"
date:   2018-09-24 13:41:29 +0100
categories: specturm raspberrypi
image:
  path: /images/space-raiders.jpg
  thumbnail: /images/thumbs/space-raiders.jpg
permalink: /retro-gaming-space-raiders/
---
Dylan’s favourite t-shirt is his Game Over shirt which always reminds me to Space Raiders from the ZX Spectrum days. I found the cassette tape quite easily but it took a significant amount of searching to find the Spectrum itself and included in the box was the tape recorder as well!

Unfortunately when I set about loading the game it didn’t work. It probably was a lot to ask after 30+ years. The audio sounded a bit low and the tape player was at maximum. I tried connecting it via an amplifier but that didn’t help.

I connected the tape drive to my Mac and looked at the file in Audacity.

![](/images/original-tape-player.png)

Apart from being very quiet, zooming in showed that after the guard tone it was impossible to see the signal as described in this [excellent post](http://www.myprius.co.za/tape_storage.htm).

![](/images/nothing-to-see.png)

I tried the Fuse utilities to covert the WAV into a TZX file but these failed. I found more tools here which I installed on my Raspberry PI but the result was the same.

Eventually, I decided to see if I could find another tape player and I found an old compact media centre. I played the tape straight into Audacity just to see if I could see a difference. Clearly this find is significantly better:

![](/images/compact-media-centre.png)

I tried `audio2tape` but that give me a bunch of CRC errors, but processing the file with `tzxwav` worked perfectly:

    pi@raspberrypi:~/.local/bin $ ./tzxwav -p -v -o ~/raiders.tzx -D ~/raiders.wav 
    === Program: raiders   ---------------------------------|  1:56
    Expected length: 40
    Leader: @1055530, Sync: @1275725, End: @1279885
    Program: raiders    (40 bytes)
    --- data########----------------------------------------|  1:51
    Length: 40
    Leader: @1323967, Sync: @1412003, End: @1421770
    40 bytes of data
    === Program: RAIDERS   ---------------------------------|  1:44
    Expected length: 68
    Leader: @1510973, Sync: @1731454, End: @1735476
    Program: RAIDERS    (68 bytes)
    --- data###########-------------------------------------|  1:40
    Length: 68
    Leader: @1778815, Sync: @1866811, End: @1882863
    68 bytes of data
    === Bytes: T         #----------------------------------|  1:33
    Start: 16384, Expected length: 6912
    Leader: @1964171, Sync: @2184510, End: @2188446
    Screen: T         
    --- data#########################-----------------------|  1:27
    Length: 6912
    Leader: @2231875, Sync: @2319891, End: @3680454
    6912 bytes of data
    === Bytes: C         ##############---------------------|  1:16
    Start: 24576, Expected length: 7860
    Leader: @3778730, Sync: @3989417, End: @3993362
    Bytes: C          (start: 24576, 7860 bytes)
    --- data###########################################-----|  0:19
    Length: 7860
    Leader: @4036807, Sync: @4124864, End: @6093760
    7860 bytes of data
    100% |##################################################|  0:00

I loaded the TZX file into Fuse and it worked as expected.

Armed with a working tape player I loaded the game on the real ZX Spectrum on the first attempt

![](/images/space-raiders-on-tv.jpg)

Lastly, can we have this on our Raspberry PI? Well of course, just install Fuse and load up the TZX images:

    sudo apt-get install fuse-emulator-common
    sudo apt-get install spectrum-roms fuse-emulator-utils
