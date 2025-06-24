---
layout: post
title:  "Bose SoundTouch and Mini DLNA"
date:   2019-09-21 13:41:29 +0100
categories: juniper
image:
  path: /images/bose-soundtouch-30.jpg
  thumbnail: /images/thumbs/bose-soundtouch-30.jpg
redirect_from:
  - /bose-soundtouch-and-mini-dlna/
---
[Bose](https://www.bose.co.uk) have a Windows application can host your music library, however I don’t have a Windows machine turn on permanently and I’d prefer a low power Raspberry PI option.

Install Mini DLNA

    apt-get install minidlna

Copy the Music over to the staging folder. I have my MP3 files on an external hard disk so I’ll copy them over link this

    ar -c /mnt/Music -cvf - . | tar -C /var/lib/minidlna -xf -

Set the file ownership

    chown -R minidlna:minidlna /var/lib/minidlna /var/cache/minidlna

Sometimes you need to delete the database from `/var/cache/minidlna/files.db` and restart the service

    service minidlna stop
    rm /var/cache/minidlna/files.db
    service minidlna start

Check the status at `http://<host_ip>:8200`

![](/images/minidlna-status.png)

Now on the Bose SoundTouch app go to Add Service, Music Library on NAS and select your Pi from the list:

![](/images/soundtouch-app.jpg)
