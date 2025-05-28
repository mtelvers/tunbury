---
layout: post
title: "Raptor Talos II - POWER9 update"
date: 2025-05-27 00:00:00 +0000
categories: power9
tags: tunbury.org
image:
  path: /images/raptor-talos-ii.jpg
  thumbnail: /images/raptor-talos-ii.jpg
---


Almost a month ago, I wrote about the onset of [unreliability in our Raptor Talos II](https://www.tunbury.org/raptor-talos-ii) machines. Since then, I have been working with Raptor Computing to diagnose the issue.

We have two Raptor Talos II machines: _Orithia_ and _Scyleia_. Each has two processors, for a total of 176 cores, 512GB of RAM, and 2 x 1.8TB NVMe drives. These machines were expensive, so having to power cycle them several times a day was annoying.

I reported the problem as the system freezing. Raptor Support asked me to run `stress` on the machines while recording the output from `sensors` from the `lm-sensors` package. They also asked me to install `opal-prd`, which outputs logging data to `/var/log/opal-prd.log`. The output from `sensors` was unremarkable, and the machines didn't particularly freeze more often under load than when sitting idle.

Diagnostics then moved to what we were running on the machines. That part was easy as these machines run [OCluster](https://github.com/ocurrent/ocluster)/[OBuilder](https://github.com/ocurrent/obuilder), which we run across all of our workers. Raptor Support suspected an out-of-memory condition, but they were perplexed by the lack of an error report on the XMON debug console.

Raptor Support provided access to a Talos II machine in their datacenter. As our configuration is held in Ansible Playbooks, it was simple to deploy to the test machine. The machine was much smaller than ours: 64GB of RAM, 460GB NVMe. This limited the number of concurrent OBuilder jobs to about 16. We run our machines at 44 using the rudimentary `nproc / 4` calculation. The loan machine was solid; ours still froze frequently.

Raptor Support had an inspirational question about the system state after the freeze. As I am remote from the machine, it's hard to tell whether it is on or not. The BMC reported that the machine was on. However, I inspected the state physically; the power indicator light on the front panel was off, and the indicator lights on the PSU were amber. In the image, the top system is powered off.

![](/images/raptor-talos-ii-front-panel.png)

Issuing these `i2cget` commands via the BMC console allowed the cause of the power off event to be determined

```sh
bmc-orithia:~# i2cget -y 12 0x31 0x07
0x2e
bmc-orithia:~# i2cget -y 12 0x31 0x18
0x00
bmc-orithia:~# i2cget -y 12 0x31 0x19
0x02
```

Using the BMC, you can query the power status using `obmcutil power` and power on and off the system using `obmcutil poweron` and `obmcutil poweroff` respectively.

> The indication is one of the power rails (VCS for CPU1) dropping offline, which causes a full system power off to ensure further hardware damage does not occur. This would be a hardware fault, and is either a failing regulator on the mainboard or a failing CPU shorting out the VCS B power rail. ... There is a chance the actual problem is instability in the +12V rail from the PDU.

The suggested course of action was to try powering the system using a standard 1000W ATX power supply, which would isolate whether the supply was the root cause of the failure. Raptor Support confirmed that, provided the plastic air guide is in place inside the chassis, there should be sufficient airflow to run the test for an extended period.

![](/images/raptor-talos-ii-with-atx.jpg)

![](/images/raptor-talos-ii-with-atx-running.jpg)

After an hour or so of running, the system spontaneously rebooted, so I decided to stop the test to avoid possible damage.

> The next step would be to swap CPU0 on Scyleia with CPU1 on Orithia, to determine if the CPU itself may be at fault. CPU0 is nearest the rear connectors, while CPU1 is nearest the chassis fans.

Orithia CPU

![](/images/raptor-talos-ii-orithia-cpu-screwdriver.jpg)

![](/images/raptor-talos-ii-orithia-cpu-removed.jpg)

![](/images/raptor-talos-ii-orithia-cpu.jpg)

Scyleia CPU

![](/images/raptor-talos-ii-scyleia-cpu-screwdriver.jpg)

Following the CPU swap, both systems have been stable for over 30 hours.

