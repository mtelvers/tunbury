---
layout: post
title:  "Minecraft Java Edition Server on Ubuntu 18.04"
date:   2020-04-18 13:41:29 +0100
categories: ubuntu minecraft
image:
  path: /images/minecraft_cover.png
  thumbnail: /images/thumbs/minecraft_cover.png
redirect_from:
  - /minecraft-java-edition-server-on-ubuntu-18-04/
---
See [How to install a Minecraft Bedrock Server on Ubuntu](https://linuxize.com/post/how-to-install-minecraft-server-on-ubuntu-18-04/)

> I’ll note here that this works perfectly, but it doesn’t do what I wanted it to! What I discovered afterwards is that there is Minecraft Java Edition which is the original product but Java Edition only supports cross play with Java Edition endpoints such as a PC or Mac. iPhones/iPad use the newer C++ Edition and there is a new Bedrock Edition server which works across both Java and C++ endpoints.

Install Ubuntu 18.04.4 using VMware Fusion.  Create a bridged connection to the LAN not the default NAT’ed connection.  Allow SSH. Install my SSH key using `ssh-copy-id user@192.168.1.127`

Sign on on the console sudo -Es, then install the essentials

    apt update
    apt install git build-essential
    apt install openjdk-8-jre-headless

Create, and then switch to a user account

    useradd -r -m -U -d /opt/minecraft -s /bin/bash minecraft
    su - minecraft

Create a folder structure to work with

    mkdir -p ~/{backups,tools,server}

Clone the git repository for the micron tool

    cd ~/tools && git clone https://github.com/Tiiffi/mcrcon.git

Compile it

    cd ~/tools/mcrcon && gcc -std=gnu11 -pedantic -Wall -Wextra -O2 -s -o mcrcon mcrcon.c

Download the JAR file

    wget  https://launcher.mojang.com/v1/objects/bb2b6b1aefcd70dfd1892149ac3a215f6c636b07/server.jar  -P ~/server

Make an initial run on the server

    cd ~/server
    java -Xmx1024M -Xms512M -jar server.jar nogui

Updated the eula.txt to accept the EULA

    sed -i "s/false/true/g" ~/server/eula.txt

Edit `server.properties` to enable RCON and set the password

    sed -i "s/enable-rcon=false/enable-rcon=true/g" ~/server/server.properties
    sed -i "s/rcon.password=/rcon.password=s3cr3t/g" ~/server/server.properties

Create a cron job to create backups

    cat > /opt/minecraft/tools/backup.sh <<'EOF'
    #!/bin/bash

    function rcon {
    /opt/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p s3cr3t "$1"
    }

    rcon "save-off"
    rcon "save-all"
    tar -cvpzf /opt/minecraft/backups/server-$(date +%F-%H-%M).tar.gz /opt/minecraft/server
    rcon "save-on"

    ## Delete older backups
    find /opt/minecraft/backups/ -type f -mtime +7 -name '*.gz' -delete
    EOF

Make it executable

    chmod +x /opt/minecraft/tools/backup.sh

Schedule the backup to run at 3am via CRON using crontab -e

    0 3 * * * /opt/minecraft/tools/backup.sh
    
As root, create `/etc/systemd/system/minecraft.service`

    cat > /etc/systemd/system/minecraft.service <<'EOF'
    [Unit]
    Description=Minecraft Server
    After=network.target

    [Service]
    User=minecraft
    Nice=1
    KillMode=none
    SuccessExitStatus=0 1
    ProtectHome=true
    ProtectSystem=full
    PrivateDevices=true
    NoNewPrivileges=true
    WorkingDirectory=/opt/minecraft/server
    ExecStart=/usr/bin/java -Xmx2048M -Xms1024M -jar server.jar nogui
    ExecStop=/opt/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p s3cr3t stop

    [Install]
    WantedBy=multi-user.target
    EOF

Refresh `systemd`, set the service to start at boot, start the service and check the status:

    sudo systemctl daemon-reload
    sudo systemctl enable minecraft
    sudo systemctl start minecraft
    sudo systemctl status minecraft

Open the firewall port

    sudo ufw allow 25565/tcp

If, down the road, you want to create a new world, just stop the server and delete `/opt/minecraft/server/world`. Alternatively, edit `server.properties` and set a new name on `level-name=world`.
