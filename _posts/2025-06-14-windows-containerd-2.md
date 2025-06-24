---
layout: post
title: "Containerd on Windows"
date: 2025-06-14 12:00:00 +0000
categories: containerd
tags: tunbury.org
image:
  path: /images/containerd.png
  thumbnail: /images/thumbs/containerd.png
redirect_from:
  - /windows-containerd-2/
---


If you were following along with my previous post on [containerd on Windows](https://www.tunbury.org/windows-containerd/), you may recall that I lamented the lack of an installer. Since then, I have found a PowerShell [script](https://github.com/microsoft/Windows-Containers/blob/Main/helpful_tools/Install-ContainerdRuntime/install-containerd-runtime.ps1) on Microsoft's GitHub, which does a lot of the grunt work for us.

Trying anything beyond my `echo Hello` test showed an immediate problem: there is no network. `ipconfig` didn't display any network interfaces.

```cmd
C:\>ctr run --rm mcr.microsoft.com/windows/nanoserver:ltsc2022 my-container ipconfig

Windows IP Configuration
```

Checking the command line options, there is one called `--net-host`, which sounded promising, only for that to be immediately dashed:

```cmd
C:\>ctr run --rm --net-host mcr.microsoft.com/windows/nanoserver:ltsc2022 my-container ipconfig
ctr: Cannot use host mode networking with Windows containers
```

The solution is `--cni`, but more work is required to get that working. We need to download the plugins and populate them in the `cni/bin` subdirectory. Fortunately, the installation script does all of this for us but leaves it unconfigured.

```cmd
C:\Windows\System32>ctr run --rm --cni mcr.microsoft.com/windows/nanoserver:ltsc2022 my-container ipconfig
ctr: no network config found in C:\Program Files\containerd\cni\conf: cni plugin not initialized
```

From the top, this is how you get from a fresh install of Windows 11, to a container with networking. Firstly, use installation script to install `containerd`.

```cmd
curl.exe https://raw.githubusercontent.com/microsoft/Windows-Containers/refs/heads/Main/helpful_tools/Install-ContainerdRuntime/install-containerd-runtime.ps1 -o install-containerd-runtime.ps1
Set-ExecutionPolicy Bypass
.\install-containerd-runtime.ps1 -ContainerDVersion 2.1.1 -WinCNIVersion 0.3.1 -ExternalNetAdapter Ethernet
```

Now create `C:\Program Files\containerd\cni\conf\0-containerd-nat.conf` containing the following:

```
{
    "cniVersion": "0.3.0",
    "name": "nat",
    "type": "nat",
    "master": "Ethernet",
    "ipam": {
        "subnet": "172.20.0.0/16",
        "routes": [
            {
                "gateway": "172.20.0.1"
            }
        ]
    },
    "capabilities": {
        "portMappings": true,
        "dns": true
    }
}
```

Easy when you know how...

```cmd
C:\>ctr run --rm --cni mcr.microsoft.com/windows/nanoserver:ltsc2022 my-container ping 1.1.1.1

Pinging 1.1.1.1 with 32 bytes of data:
Reply from 1.1.1.1: bytes=32 time=5ms TTL=58
Reply from 1.1.1.1: bytes=32 time=7ms TTL=58
Reply from 1.1.1.1: bytes=32 time=7ms TTL=58
Reply from 1.1.1.1: bytes=32 time=6ms TTL=58

Ping statistics for 1.1.1.1:
    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),
Approximate round trip times in milli-seconds:
    Minimum = 5ms, Maximum = 7ms, Average = 6ms
```

The next challenge is, what do you put in your own `config.json` to reproduce this behaviour?

Firstly, we need our `layerFolders`:

```cmd
C:\>ctr snapshot ls
KEY                                                                     PARENT KIND
sha256:44b913d145adda5364b5465664644b11282ed3c4b9bd9739aa17832ee4b2b355        Committed
```

```cmd
C:\>ctr snapshot prepare --mounts my-snapshot sha256:44b913d145adda5364b5465664644b11282ed3c4b9bd9739aa17832ee4b2b355
[
    {
        "Type": "windows-layer",
        "Source": "C:\\ProgramData\\containerd\\root\\io.containerd.snapshotter.v1.windows\\snapshots\\14",
        "Target": "",
        "Options": [
            "rw",
            "parentLayerPaths=[\"C:\\\\ProgramData\\\\containerd\\\\root\\\\io.containerd.snapshotter.v1.windows\\\\snapshots\\\\1\"]"
        ]
    }
]
```

Let's create a `config.json` without a network stanza just to check we can create a container:

```
{
  "ociVersion": "1.1.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [
      "cmd", "/c",
      "ipconfig && ping 1.1.1.1"
    ],
    "cwd": "c:\\"
  },
  "root": { "path": "", "readonly": false },
  "hostname": "builder",
  "windows": {
    "layerFolders": [
      "C:\\ProgramData\\containerd\\root\\io.containerd.snapshotter.v1.windows\\snapshots\\1",
      "C:\\ProgramData\\containerd\\root\\io.containerd.snapshotter.v1.windows\\snapshots\\14"
    ],
    "ignoreFlushesDuringBoot": true
  }
}
```

The container runs, but there is no network as we'd expect.

```cmd
C:\>ctr run --rm --config config.json my-container

Windows IP Configuration


Pinging 1.1.1.1 with 32 bytes of data:
PING: transmit failed. General failure.
PING: transmit failed. General failure.
PING: transmit failed. General failure.
PING: transmit failed. General failure.
```

If we turn on CNI, it crypically tells us what we need to do:

```cmd
C:\>ctr run --rm --cni --config config.json my-container
ctr: plugin type="nat" name="nat" failed (add): required env variables [CNI_NETNS] missing
```

So we need to populate the `network.networkNamespace` with the name (ID) of the network we want to use. This should be a GUID, and I don't know how to get the right value. I would have assumed that it was one of the many GUID's returned by `Get-HnsNetwork` but it isn't.

```powershell
PS C:\> Get-HnsNetwork


ActivityId             : 92018CF0-6DCB-4AAF-A14E-DC61120FC958
AdditionalParams       :
CurrentEndpointCount   : 0
Extensions             : {@{Id=E7C3B2F0-F3C5-48DF-AF2B-10FED6D72E7A; IsEnabled=False; Name=Microsoft Windows Filtering Platform},
                         @{Id=F74F241B-440F-4433-BB28-00F89EAD20D8; IsEnabled=False; Name=Microsoft Azure VFP Switch Filter Extension},
                         @{Id=430BDADD-BAB0-41AB-A369-94B67FA5BE0A; IsEnabled=True; Name=Microsoft NDIS Capture}}
Flags                  : 8
Health                 : @{LastErrorCode=0; LastUpdateTime=133943927149605101}
ID                     : 3EB2B18B-A1DD-46A8-A425-256F6B3DF26D
IPv6                   : False
LayeredOn              : 20791F67-012C-4C9B-9C93-530FDA5DE4FA
MacPools               : {@{EndMacAddress=00-15-5D-C3-DF-FF; StartMacAddress=00-15-5D-C3-D0-00}}
MaxConcurrentEndpoints : 1
Name                   : nat
NatName                : NATAC317D6D-8A2E-4E4E-9BCF-33435FE4CD8F
Policies               : {@{Type=VLAN; VLAN=1}}
State                  : 1
Subnets                : {@{AdditionalParams=; AddressPrefix=172.20.0.0/16; Flags=0; GatewayAddress=172.20.0.1; Health=;
                         ID=5D56CE8D-1AD2-47FF-85A7-A0E6D530565D; IpSubnets=System.Object[]; ObjectType=5; Policies=System.Object[]; State=0}}
SwitchGuid             : 3EB2B18B-A1DD-46A8-A425-256F6B3DF26D
TotalEndpoints         : 2
Type                   : NAT
Version                : 64424509440
Resources              : @{AdditionalParams=; AllocationOrder=2; Allocators=System.Object[]; CompartmentOperationTime=0; Flags=0; Health=;
                         ID=92018CF0-6DCB-4AAF-A14E-DC61120FC958; PortOperationTime=0; State=1; SwitchOperationTime=0; VfpOperationTime=0;
                         parentId=71FB2758-F714-4838-8764-7079378D6CB6}
```

I ran `ctr run --rm --cni mcr.microsoft.com/windows/nanoserver:ltsc2022 my-container cmd /c "ping 1.1.1.1 && pause"` in one window and ran `ctr c info my-container` in another, which revealed a GUID was `5f7d467c-3011-48bc-9337-ce78cf399345`.

Adding this to my `config.json`

```
{
  "ociVersion": "1.1.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [
      "cmd", "/c",
      "ipconfig && ping 1.1.1.1"
    ],
    "cwd": "c:\\"
  },
  "root": { "path": "", "readonly": false },
  "hostname": "builder",
  "windows": {
    "layerFolders": [
      "C:\\ProgramData\\containerd\\root\\io.containerd.snapshotter.v1.windows\\snapshots\\1",
      "C:\\ProgramData\\containerd\\root\\io.containerd.snapshotter.v1.windows\\snapshots\\14"
    ],
    "ignoreFlushesDuringBoot": true,
    "network": {
      "allowUnqualifiedDNSQuery": true,
      "networkNamespace": "5f7d467c-3011-48bc-9337-ce78cf399345"
    }
  }
}
```

And now I have a network!

```cmd
C:\>ctr run --rm --cni --config config.json my-container

Windows IP Configuration


Ethernet adapter vEthernet (default-my-container2_nat):

   Connection-specific DNS Suffix  . : Home
   Link-local IPv6 Address . . . . . : fe80::921d:1ce7:a445:8dfa%49
   IPv4 Address. . . . . . . . . . . : 172.20.95.58
   Subnet Mask . . . . . . . . . . . : 255.255.0.0
   Default Gateway . . . . . . . . . : 172.20.0.1

Pinging 1.1.1.1 with 32 bytes of data:
Reply from 1.1.1.1: bytes=32 time=5ms TTL=58
Reply from 1.1.1.1: bytes=32 time=6ms TTL=58
Reply from 1.1.1.1: bytes=32 time=6ms TTL=58
Reply from 1.1.1.1: bytes=32 time=6ms TTL=58

Ping statistics for 1.1.1.1:
    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),
Approximate round trip times in milli-seconds:
    Minimum = 5ms, Maximum = 6ms, Average = 5ms
```

