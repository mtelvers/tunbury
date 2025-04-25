---
layout: post
title:  "Raspberry PI SSH Keys"
date:   2019-09-16 13:41:29 +0100
categories: raspberrypi
image:
  path: /images/SSH-Keys.png
  thumbnail: /images/SSH-Keys.png
---
This is my cheatsheet based upon [Passwordless SSH access](https://www.raspberrypi.org/documentation/remote-access/ssh/passwordless.md) on the official Raspberry PI website.

On the Mac create a key (once) with a passcode

    ssh-keygen

Add the key to your Mac keychain

    ssh-add -K ~/.ssh/id_rsa

Optionally create a file `~/.ssh/config` with these contents which contains the `UseKeychain yes` line which tells OSX to look at the keychain for the passphrase.

    Host *
      UseKeychain yes
      AddKeysToAgent yes
      IdentityFile ~/.ssh/id_rsa

Then copy your key to your Raspberry PI

    ssh-copy-id pi@192.168.1.x

SSH to the PI

    ssh pi@192.168.1.x

Next edit your `/etc/ssh/sshd_config` to turn off plain text password authentication and restart `sshd`.

    sudo sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/g" /etc/ssh/sshd_config
    sudo /etc/init.d/ssh restart

Now you can SSH without a password and without getting pestered that the default password hasn’t been changed.
