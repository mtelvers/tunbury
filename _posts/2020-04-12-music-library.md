---
layout: post
title:  "Music Library"
date:   2020-04-12 13:41:29 +0100
categories: raspberrypi flac
image:
  path: /images/cd-stack.jpg
  thumbnail: /images/thumbs/cd-stack.jpg
---
Using a Raspberry PI with a USB CD drive to read all my CDs and create a master, FLAC format, repository and from that create MP3 and AAC versions for the car and iTunes.

    sudo apt-get install abcde
    sudo apt-get install flac

Then read the file with

    abcde -a cddb,read,getalbumart,encode,tag,move,clean -j 4 -B -o flac -N 

To make `abcde` create file names in the format that I prefer create `.abcde.conf` in the users’ home directory containing:

    OUTPUTFORMAT='${OUTPUT}/${ARTISTFILE}/${ALBUMFILE}/${TRACKNUM} - ${TRACKFILE}'

    mungefilename ()
    {
        echo "$@" | sed -e 's/^\.*//' | tr -d ":><|*/\"'?[:cntrl:]"
    }

And encode it as AAC using

    ffmpeg -i "01 - Santas Coming for Us.flac" -c:v mjpeg -vf scale=500:500 -c:a aac -b:a 128k -threads 4 "01 - Santas Coming for Us.m4a"

This could be rolled up as followed with find/xargs

    find . -name "*.flac" -print0 | xargs -0 -P 4 -I{} ffmpeg -i {} -c:v mjpeg -vf scale=500:500 -c:a aac -b:a 128k -n {}.m4a

The `-n` here causes it to skip files where the output file already exists so the command can be run again on an existing directory tree. `-P 4` forks 4 copies of `ffmpeg`.

Finally copy it the m4a files to `~/Music/Music/Media/Automatically Add to Music.localized`
