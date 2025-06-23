---
layout: post
title: "Tailscale"
date: 2025-06-20 00:00:00 +0000
categories: Tailscale
tags: tunbury.org
image:
  path: /images/tailscale-logo.png
  thumbnail: /images/thumbs/tailscale-logo.png
permalink: /tailscale/
---

On a typical day, I sit at my antique Mac Pro Trashcan with every window running SSH to some remote machine. When I'm away from home and using my MacBook, I can still SSH to those remote machines; however, with my recent Windows work, I've been connecting to a Dell OptiPlex on my home LAN over Remote Desktop. How can I work remotely when I want to access my Windows machine?

It's the age-old issue of connecting to your home network, which is hidden behind your home broadband router with a dynamic public IP address. I could use a dynamic DNS service to track my home router and configure port forwarding, but would you open RDP to the Internet?

I love VNC, but the recent change in the licensing model, whereby the free tier now has only three machines, combined with frustrating performance on the low bandwidth and intermittent connections we get on train WiFi, made me try an alternate solution. Thomas has Tailscale set up in the Paris office, and I decided to create a setup for home.

I'd rather not install any software on my Windows machine, as I wipe it pretty frequently, and I don't need a VPN interfering with my `containerd` implementation. However, Tailscale supports a configuration whereby you can route to local networks.

After signing up for a free personal account, I installed the Tailscale client on my MacBook and Mac Pro (at home). On the Mac Pro, I enabled 'Allow Local Network Access' and from a Terminal window, I went to `/Applications/Tailscale.app/Contents/MacOS` and ran `./Tailscale set --advertise-routes=192.168.0.0/24`. With this done, looking at the machine list on the [Tailscale console](https://login.tailscale.com/admin/machines), my Mac Pro lists `Subnets`. Clicking on the three dots, and opening `Edit route settings`, I could enable the advertised subnet, 192.168.0.0/24.

Checking `netstat -rn` on my MacBook shows that 192.168.0 is routed over the VPN.

```
Routing tables

Internet:
Destination        Gateway            Flags               Netif Expire
default            10.101.2.1         UGScg                 en0
default            link#36            UCSIg              utun12
10.101.2/24        link#6             UCS                   en0      !
10.101.2.1/32      link#6             UCS                   en0      !
...
192.168.0          link#36            UCS                utun12
...
```

From my MacBook, I can now use Microsoft Remote Desktop to connect to the private IP address of my Windows machine.

OpenSSH is an optional feature on Windows 11. It can be turned on via Settings -> Apps -> Optional Features, clicking "Add a feature" and installing "OpenSSH Server". Then, Open Services and set the setup options for "OpenSSH SSH Server" to automatic.

It didn't make the train WiFi any better, but connecting over SSH was pretty convenient when the bandwidth is low.

Note that you may want to disable key expiry on your home machine; otherwise, it might require you to reauthenticate at a critical moment.
