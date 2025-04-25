---
layout: post
title:  "Internet Radio from Raspberry PI"
date:   2019-09-01 13:41:29 +0100
categories: bells raspberrypi
---
Install the software packages needed

    sudo apt-get install libmp3lame0 libtwolame0
    sudo apt-get install darkice
    sudo apt-get install icecast2

During the installation you will be asked to set the icecast password which you’ll need enter into the configuration file below

Check your recording device is present

    pi@raspberrypi:~ $ arecord -l
    **** List of CAPTURE Hardware Devices ****
    card 1: AK5371 [AK5371], device 0: USB Audio [USB Audio]
    Subdevices: 0/1
    Subdevice #0: subdevice #0

Try to make a recording:

    arecord -D plughw:1,0 temp.wav

If the volume is too quiet, you can adjust it with alsamixer -c 1 where 1 is your audio device. Note that 0 is the Raspberry PI default output device.

Create a configuration file for darkice

    # this section describes general aspects of the live streaming session
    [general]
    duration        = 0        # duration of encoding, in seconds. 0 means forever
    bufferSecs      = 5         # size of internal slip buffer, in seconds
    reconnect       = yes       # reconnect to the server(s) if disconnected
    

    # this section describes the audio input that will be streamed
    [input]
    # device          = /dev/dsp  # OSS DSP soundcard device for the audio input
    device          = plughw:1,0  # OSS DSP soundcard device for the audio input
    sampleRate      = 22050     # sample rate in Hz. try 11025, 22050 or 44100
    bitsPerSample   = 16        # bits per sample. try 16
    channel         = 2         # channels. 1 = mono, 2 = stereo
    

    # this section describes a streaming connection to an IceCast2 server
    # there may be up to 8 of these sections, named [icecast2-0] ... [icecast2-7]
    # these can be mixed with [icecast-x] and [shoutcast-x] sections
    [icecast2-0]
    bitrateMode     = abr       # average bit rate
    format          = mp3       # format of the stream: ogg vorbis
    bitrate         = 96        # bitrate of the stream sent to the server
    server          = localhost # host name of the server
    port            = 8000      # port of the IceCast2 server, usually 8000
    password        = password # source password to the IceCast2 server
    mountPoint      = mic  # mount point of this stream on the IceCast2 server
    name            = Microphone Raspberry Pi # name of the stream
    description     = Broadcast from 2nd room # description of the stream
    url             = http://example.com/ # URL related to the stream
    genre           = my own    # genre of the stream
    public          = no        # advertise this stream?

Invoke the server by running darkice at the prompt.

Set darkice to run at boot up

    update-rc.d darkice defaults

Open a web browser to `http://<pi-ip-address>:8000` to view the installation. Add the url source to your Internet radio appliance via `http://<pi-ip-address>:8000/mic`

