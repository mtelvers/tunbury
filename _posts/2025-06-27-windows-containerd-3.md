---
layout: post
title: "Containerd on Windows"
date: 2025-06-27 12:00:00 +0000
categories: containerd
tags: tunbury.org
image:
  path: /images/containerd.png
  thumbnail: /images/thumbs/containerd.png
---

Everything was going fine until I ran out of disk space. My NVMe, `C:` drive, is only 256GB, but I have a large, 1.7TB SSD available as `D:`. How trivial, change a few paths and carry on, but it wasn't that simple, or was it?

Distilling the problem down to the minimum and excluding all code written by me, the following command fails, but changing `src=d:\cache\opam` to `src=c:\cache\opam` works. It's not the content, as it's just an empty folder.

```cmd
ctr run --rm --cni -user ContainerAdministrator -mount type=bind,src=d:\cache\opam,dst=c:\Users\ContainerAdministrator\AppData\Local\opam mcr.microsoft.com/windows/servercore:ltsc2022 my-container  cmd /c "curl.exe -L -o c:\Windows\opam.exe https://github.com/ocaml/opam/releases/download/2.3.0/opam-2.3.0-x86_64-windows.exe && opam.exe init --debug-level=3 -y"
```

The failure point is the ability to create the lock file `config.lock`. Checking the code, the log entry is written before the lock is acquired. If `c:\Users\ContainerAdministrator\AppData\Local\opam` is not a bind mount, or the bind mount is on `C:`, then it works.

```
01:26.722  CLIENT                          updating repository state
01:26.722  GSTATE                          LOAD-GLOBAL-STATE @ C:\Users\ContainerAdministrator\AppData\Local\opam
01:26.723  SYSTEM                          LOCK C:\Users\ContainerAdministrator\AppData\Local\opam\lock (none => read)
01:26.723  SYSTEM                          LOCK C:\Users\ContainerAdministrator\AppData\Local\opam\config.lock (none => write)
```

Suffice it to say, I spent a long time trying to resolve this. I'll mention a couple of interesting points that appeared along the way. Firstly, files created on `D:` effectively appear as hard links, and the Update Sequence Number, USN, is 0.

```powershell
C:\> fsutil file layout d:\cache\opam\lock

********* File 0x000400000001d251 *********
File reference number   : 0x000400000001d251
File attributes         : 0x00000020: Archive
File entry flags        : 0x00000000
Link (ParentID: Name)   : 0x000c00000000002d: HLINK Name   : \cache\opam\lock
...
LastUsn                 : 0
...
```

The reason behind this is down to Windows defaults:

1. Windows still likes to create the legacy 8.3 MS-DOS file names on the system volume, `C:`, which explains the difference between `HLINK` and `NTFS+DOS`. Running `fsutil 8dot3name set d: 0` will enable the creation of the old-style file names.
2. Drive `C:` has a USN journal created automatically, as it's required for Windows to operate, but it isn't created by default on other drives. Running `fsutil usn createjournal d: m=32000000 a=8000000` will create the journal.

```powershell
C:\> fsutil file layout c:\cache\opam\lock

********* File 0x000300000002f382 *********
File reference number   : 0x000300000002f382
File attributes         : 0x00000020: Archive
File entry flags        : 0x00000000
Link (ParentID: Name)   : 0x000b0000000271d1: NTFS+DOS Name: \cache\opam\lock
...
LastUsn                 : 16,897,595,224
...
```

Sadly, neither of these insights makes any difference to my problem. I did notice that `containerd` 2.1.3 had been released, where I had been using 2.1.1. Upgrading didn't fix the issue, but it did affect how the network namespaces were created. More later.

I decided to both ignore the problem and try it on another machine. After all, this problem was only a problem because _my_ `C:` was too small. I created a QEMU VM with a 40GB `C:` and a 1TB `D:` and installed everything, and it worked fine with the bind mount on `D:` even _without_ any of the above tuning and even with `D:` formatted using ReFS, rather than NTFS.

Trying on another physical machine with a single large spinning disk as `C:` also worked as anticipated.

In both of these new installations, I used `containerd` 2.1.3 and noticed that the behaviour I had come to rely upon seemed to have changed. If you recall, in this [post](https://www.tunbury.org/2025/06/14/windows-containerd-2/), I _found_ the network namespace GUID by running `ctr run` on a standard Windows container and then `ctr container info` in another window. This no longer worked reliably, as the namespace was removed when the container exited. Perhaps it always should have been?

I need to find out how to create these namespaces. PowerShell has a cmdlet `Get-HnsNetwork`, but none of the GUID values there match the currently running namespaces I observe from `ctr container info`. The source code of [containerd](https://github.com/containerd/containerd) is on GitHub..

When you pass `--cni` to the `ctr` command, it populates the network namespace from `NetNewNS`.  Snippet from `cmd/ctr/commands/run/run_windows.go`

```go
                if cliContext.Bool("cni") {
                        ns, err := netns.NewNetNS("")
                        if err != nil {
                                return nil, err
                        }
                        opts = append(opts, oci.WithWindowsNetworkNamespace(ns.GetPath()))
                }
```

`NewNetNS` is defined in `pkg/netns/netns_windows.go`

```go
// NetNS holds network namespace for sandbox
type NetNS struct {
        path string
}

// NewNetNS creates a network namespace for the sandbox.
func NewNetNS(baseDir string) (*NetNS, error) {
        temp := hcn.HostComputeNamespace{}
        hcnNamespace, err := temp.Create()
        if err != nil {
                return nil, err
        }

        return &NetNS{path: hcnNamespace.Id}, nil
}
```

Following the thread, and cutting out a few steps in the interest of brevity, we end up in `vendor/github.com/Microsoft/hcsshim/hcn/zsyscall_windows.go` which calls a Win32 API.

```go
func _hcnCreateNamespace(id *_guid, settings *uint16, namespace *hcnNamespace, result **uint16) (hr error) {
        hr = procHcnCreateNamespace.Find()
        if hr != nil {
                return
        }
        r0, _, _ := syscall.SyscallN(procHcnCreateNamespace.Addr(), uintptr(unsafe.Pointer(id)), uintptr(unsafe.Pointer(settings)), uintptr(unsafe.Pointer(namespace)), uintptr(unsafe.Pointer(result)))
        if int32(r0) < 0 {
                if r0&0x1fff0000 == 0x00070000 {
                        r0 &= 0xffff
                }
                hr = syscall.Errno(r0)
        }
        return
}
```

PowerShell provides `Get-HnsNamespace` to list available namespaces. These _are_ the ~~droids~~ values I've been looking for to put in `config.json`! However, by default there are no cmdlets to create them. The installation PowerShell [script](https://github.com/microsoft/Windows-Containers/blob/Main/helpful_tools/Install-ContainerdRuntime/install-containerd-runtime.ps1) for `containerd` pulls in [hns.psm1](https://github.com/microsoft/SDN/blob/master/Kubernetes/windows/hns.psm1) for `containerd`, has a lot of interesting cmdlets, such as `New-HnsNetwork`, but not a cmdlet to create a namespace. There is also [hns.v2.psm1](https://github.com/microsoft/SDN/blob/master/Kubernetes/windows/hns.v2.psm1), which does have `New-HnsNamespace`.

```powershell
PS C:\Users\Administrator> curl.exe -o hns.v2.psm1 -L https://raw.githubusercontent.com/microsoft/SDN/refs/heads/master/Kubernetes/windows/hns.v2.psm1
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 89329  100 89329    0     0   349k      0 --:--:-- --:--:-- --:--:--  353k

PS C:\Users\Administrator> Import-Module .\hns.v2.psm1
WARNING: The names of some imported commands from the module 'hns.v2' include unapproved verbs that might make them less discoverable. To find the commands with unapproved verbs, run the Import-Module command again with the Verbose parameter. For a list of approved verbs, type Get-Verb.

PS C:\Users\Administrator> New-HnsNamespace
HcnCreateNamespace -- HRESULT: 2151350299. Result: {"Success":false,"Error":"Invalid JSON document string. &#123;&#123;CreateWithCompartment,UnknownField}}","ErrorCode":2151350299}
At C:\Users\Administrator\hns.v2.psm1:2392 char:13
+             throw $errString
+             ~~~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (HcnCreateNamesp...de":2151350299}:String) [], RuntimeException
    + FullyQualifiedErrorId : HcnCreateNamespace -- HRESULT: 2151350299. Result: {"Success":false,"Error":"Invalid JSON document string. &#123;&#123;CreateWithCompartment,UnknownField}}","ErrorCode":2151350299}
```

With a lot of frustration, I decided to have a go at calling the Win32 API from OCaml. This resulted in [mtelvers/hcn-namespace](https://github.com/mtelvers/hcn-namespace), which allows me to create the namespaces by running `hcn-namespace create`. These namespaces appear in the output from `Get-HnsNamespace` and work correctly in `config.json`.

Run `hcn-namespace.exe create`, and then populate `"networkNamespace": "<GUID>"` with the GUID provided and run with `ctr run --rm -cni --config config.json`.

