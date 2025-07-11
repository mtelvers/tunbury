---
layout: post
title: "ZFS System Concept"
date: 2025-05-15 00:00:00 +0000
categories: openzfs
tags: tunbury.org
image:
  path: /images/openzfs.png
  thumbnail: /images/thumbs/openzfs.png
redirect_from:
  - /zfs-system-concept/
---


How would the distributed ZFS storage system look in practical terms? Each machine with a ZFS store would have an agent application installed. Centrally, there would be a tracker server, and users would interact with the system using a CLI tool. The elements will interact with each other using Capt'n Proto capability files.

# Tracker

The tracker would generate capability files on first invocation, one per _location_, where the location could be as granular as a specific rack in a datacenter or a larger grouping, such as at the institution level. The purpose of the location grouping is to allow users to see where the data is held. As a prototype, the command could be something like:

```
tracker --capnp-listen-address tcp:1.2.3.4:1234 --locations datacenter-01,datacenter-02,datacenter-03
```

# Agent

Each machine would have the agent application. The agent would register with the tracker using the capability file generated by the tracker. The agent command line would be used to provide a list of zpools, that are in scope for management. The zpools will be scanned to compile a list of available datasets, which will be passed to the tracker. Perhaps an invocation like this:

```
agent --connect datacenter-01.cap --name machine-01 --zpools tank-01,tank-02
```

# CLI

The CLI tool will display the system state by connecting to the tracker. Perhaps a command like `cli --connect user.cap show`, which would output a list of datasets and where they are:

```
dataset-01: datacenter-01\machine-01\tank-01 (online), datacenter-02\machine-03\tank-06 (online)
dataset-02: datacenter-01\machine-01\tank-02 (online), datacenter-02\machine-04\tank-07 (offline)
```

Another common use case would be to fetch a dataset: `cli --connect user.cap download dataset-02`. This would set up a `zfs send | zfs receive` between the agent and the current machine.

Potentially, all machines would run the agent, and rather than `download`, we would initiate a `copy` of a dataset to another location in the form `datacenter\machine\tank`.

