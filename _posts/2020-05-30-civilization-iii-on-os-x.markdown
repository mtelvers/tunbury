---
layout: post
title:  "Civilization III on OS X"
date:   2020-05-30 13:41:29 +0100
categories: osx
image:
  path: /images/Civilization_III_Coverart.png
  thumbnail: /images/Civilization_III_Coverart.png
---
Install Oracle VirtualBox and install Windows XP 32 bit.

Mount the Guest Additions image and install them.

Create an ISO from the Civ 3 installation CD using

    hdiutil makehybrid -iso -joliet -o civ3.iso /Volumes/CIV3/

Mount the ISO on VirtualBox and install the game.

Download and install the following patch to bring the installation up to 1.29f. See this [site](https://support.2k.com/hc/en-us/articles/201333523-Civilization-III-1-29f-Patch).

[Civ3v129f](/downloads/Civ3v129f.zip)

Download the No CD patch from the PC Gamer [site](https://www.pcgames.de/Civilization-3-Spiel-20090/News/Probleme-mit-Civ-3-Vollversion-Hier-gibts-Abhilfe-401682/). Specifically, I needed this file: `Civilization 3 PC Games Patch mit Conquest v1.29f (d).zip` provided below.

[Civilization3](/downloads/Civilization3.zip)

Lastly with VirtualBox running full screen Civ 3 doesn’t fill the screen. Edit `Civilization3.ini` from `C:\Program Files\Infogrames Interactive\Civilization III` and add `KeepRes=1`

    [Civilizaion III]
    KeepRes=1
