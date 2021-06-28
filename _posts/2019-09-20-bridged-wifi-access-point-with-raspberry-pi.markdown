---
layout: post
title:  "Bridged WiFi Access Point with Raspberry Pi"
date:   2019-09-20 13:41:29 +0100
categories: raspberrypi wifi
image:
  path: /images/wifi.jpg
  thumbnail: /images/wifi.jpg
---

Run `ifconfig` and determine your network device names. Typically these will be `eth0` and `wlan0`.

Install the packages we’ll need

    apt-get install hostapd bridge-utils

Create a file `/etc/network/interfaces.d/br0` containing

    auto br0
      iface br0 inet dhcp
       bridge_ports eth0 wlan0

Edit `/etc/dhcpcd.conf` and add the following two lines to the end of the file

    denyinterfacea eth0,wlan0

Reboot your Pi to apply the configuration.

Create the configuration file `/etc/hostapd/hostapd.conf` for `hostapd`.

    interface=wlan0
    bridge=br0
    ssid=YourSSID
    hw_mode=g
    channel=7
    wmm_enabled=0
    macaddr_acl=0
    auth_algs=1
    ignore_broadcast_ssid=0
    wpa=2
    wpa_passphrase=SecurePassword
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=TKIP
    rsn_pairwise=CCMP

Edit `/etc/default/hostapd` and uncomment the `DAEMON_CONF` line and enter the full path to the configuration file above, thus:

    DAEMON_CONF="/etc/hostapd/hostapd.conf"

Set `hostapd` to launch on boot and launch it right now

    systemctl unmask hostapd
    systemctl enable hostapd
    /etc/init.d/hostapd start
