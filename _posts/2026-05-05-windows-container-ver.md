---
layout: post
title: "Weird Windows container version numbers"
date: 2026-05-05 09:00:00 +0000
categories: [ocaml, ci, windows]
tags: tunbury.org
image:
  path: /images/docker-base-images-error.png
  thumbnail: /images/thumbs/docker-base-images-error.png
---

Running `ver` in a Windows container doesn't report the version number that you expect.

[ocurrent/docker-base-images](https://github.com/ocurrent/docker-base-images) publishes the Docker images that the OCaml CI pipeline systems use. For Windows, it pulls the generic LTSC tag, runs the container to determine the exact version, and then uses that exact tag for the builds.

On Windows 2022 server, pulling `mcr.microsoft.com/windows/server:ltsc2022` then running `ver` produces `10.0.20348.5020` exactly as you would expect, but running that same sequence on a Windows 2025 host returns `10.0.26100.5020`.

`10.0.26100.5020` is not a real Windows release.

- `10.0.20348.x` Windows Server 2022 (LTSC, build 20348)
- `10.0.26100.x` Windows Server 2025 / Windows 11 24H2 (build 26100)

The 5020 UBR belongs to the 20348; the 26100 has its own UBR sequence. The combination `26100.5020` does not correspond to any released Windows version, so the tag `10.0.26100.5020` can't be pulled.

Rather than running `ver`, I changed the probe command to query the containers registry at `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`, which does report the correct image build version rather than a partial kernel version number:

```
CurrentMajorVersionNumber : 10
CurrentMinorVersionNumber : 0
CurrentBuildNumber        : 20348
UBR                       : 4170
```

In the code, this `ver` command changed

```cmd
for /f "tokens=4 delims=[] " %a in ('ver') do echo %a
```

to this PowerShell query:

```powershell
$k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
'{0}.{1}.{2}.{3}' -f $k.CurrentMajorVersionNumber, $k.CurrentMinorVersionNumber, $k.CurrentBuildNumber, $k.UBR
```

The change is in [PR#348](https://github.com/ocurrent/docker-base-images/pull/348)
