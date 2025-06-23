---
layout: post
title: "Containerd on Windows"
date: 2025-06-11 00:00:00 +0000
categories: containerd
tags: tunbury.org
image:
  path: /images/containerd.png
  thumbnail: /images/thumbs/containerd.png
permalink: /windows-containerd/
---

The tricky part of using [runhcs](https://github.com/microsoft/hcsshim/issues/2156) has been getting the layers correct. While I haven't had any luck, I have managed to created Windows containers using `ctr` and `containerd`.

Installing `containerd` is a manual process on Windows. These steps give general guidance on what is needed: enable the `containers` feature in Windows, download the tar file from GitHub, extract it, add it to the path, generate a default configuration file, register the service, and start it.

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName containers -All
mkdir "c:\Program Files\containerd"
curl.exe -L https://github.com/containerd/containerd/releases/download/v2.2.1/containerd-2.2.1-windows-amd64.tar.gz -o containerd-windows-amd64.tar.gz
tar.exe xvf .\containerd-windows-amd64.tar.gz -C "c:\Program Files\containerd"
$Path = [Environment]::GetEnvironmentVariable("PATH", "Machine") + [IO.Path]::PathSeparator + "$Env:ProgramFiles\containerd\bin"
 Environment]::SetEnvironmentVariable( "Path", $Path, "Machine")
containerd.exe config default | Out-File "c:\Program Files\containerd\config.toml" -Encoding ascii
containerd --register-service
net start containerd
```

With that out of the way, pull `nanoserver:ltsc2022` from Microsoft's container registry.

```dos
c:\> ctr image pull mcr.microsoft.com/windows/nanoserver:ltsc2022
```

List which snapshots are available: `nanoserver` has one, but `servercore` has two.

```dos
c:\> ctr snapshot ls
KEY                                                                     PARENT                                                                  KIND
sha256:44b913d145adda5364b5465664644b11282ed3c4b9bd9739aa17832ee4b2b355                                                                         Committed
```

Take a snapshot of `nanoserver`, which creates a writeable scratch layer. `--mounts` is key here. Without it, you won't know where the layers are. They are held below `C:\ProgramData\containerd\root\io.containerd.snapshotter.v1.windows\snapshots` in numbered folders. The mapping between numbers and keys is stored in `metadata.db` in BoltDB format. With the `--mounts` command line option, we see the `source` path and list of paths in `parentLayerPaths`.

```dos
c:\> ctr snapshots prepare --mounts my-test sha256:44b913d145adda5364b5465664644b11282ed3c4b9bd9739aa17832ee4b2b355
[
    {
        "Type": "windows-layer",
        "Source": "C:\\ProgramData\\containerd\\root\\io.containerd.snapshotter.v1.windows\\snapshots\\21",
        "Target": "",
        "Options": [
            "rw",
            "parentLayerPaths=[\"C:\\\\ProgramData\\\\containerd\\\\root\\\\io.containerd.snapshotter.v1.windows\\\\snapshots\\\\20\"]"
        ]
    }
]
```

As you can see from `ctr snapshot ls` and `ctr snapshot info`, the layer paths aren't readily available. This [discussion](https://github.com/containerd/containerd/discussions/10053) is a sample of the creative approaches to getting the paths!

```dos
c:\> ctr snapshot ls
KEY                                                                     PARENT                                                                  KIND
my-test                                                                 sha256:44b913d145adda5364b5465664644b11282ed3c4b9bd9739aa17832ee4b2b355 Active
sha256:44b913d145adda5364b5465664644b11282ed3c4b9bd9739aa17832ee4b2b355                                                                         Committed
c:\> ctr snapshot info my-test
{
    "Kind": "Active",
    "Name": "my-test",
    "Parent": "sha256:44b913d145adda5364b5465664644b11282ed3c4b9bd9739aa17832ee4b2b355",
    "Labels": {
        "containerd.io/gc.root": "2025-06-11T12:28:43Z"
    },
    "Created": "2025-06-11T16:33:43.144011Z",
    "Updated": "2025-06-11T16:33:43.144011Z"
}
```

Here's the directory listing for reference.

```dos
c:\> dir C:\ProgramData\containerd\root\io.containerd.snapshotter.v1.windows\snapshots

 Volume in drive C has no label.
 Volume Serial Number is F0E9-1E81

 Directory of C:\ProgramData\containerd\root\io.containerd.snapshotter.v1.windows\snapshots

11/06/2025  16:33    <DIR>          .
11/06/2025  08:19    <DIR>          ..
11/06/2025  08:31    <DIR>          2
11/06/2025  16:32    <DIR>          20
11/06/2025  16:33    <DIR>          21
11/06/2025  08:20    <DIR>          rm-1
11/06/2025  08:20    <DIR>          rm-2
11/06/2025  08:22    <DIR>          rm-3
```

Now we need to prepare a `config.json` file. The `layerFolders` structure can be populated with the information from above. The order is important; preserve the order from `parentLayerPaths`, then append the scratch layer. It looks obvious when there are just two layers, but for `servercore:ltsc2022` where there are two parent layers, the order looks curious as the parent layers are given in reverse order and the scratch layer is last, e.g. `24, 23, 25` where 23 and 24 are the parents and 25 is the snapshot.

```json
{
    "ociVersion": "1.1.0",
    "process": {
        "user": {
            "uid": 0,
            "gid": 0,
            "username": "ContainerUser"
        },
        "args": [
            "cmd",
            "/c",
            "echo test"
        ],
        "cwd": ""
    },
    "root": {
        "path": ""
    },
    "windows": {
        "layerFolders": [
            "C:\\ProgramData\\containerd\\root\\io.containerd.snapshotter.v1.windows\\snapshots\\20",
            "C:\\ProgramData\\containerd\\root\\io.containerd.snapshotter.v1.windows\\snapshots\\21"
        ],
        "ignoreFlushesDuringBoot": true,
        "network": {
            "allowUnqualifiedDNSQuery": true
        }
    }
}
```

We can now run the container.

```dos
c:\> ctr run --rm --config .\config.json my-container
```
