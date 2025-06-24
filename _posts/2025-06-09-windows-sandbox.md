---
layout: post
title: "User Isolation on Windows"
date: 2025-06-09 00:00:00 +0000
categories: windows
tags: tunbury.org
image:
  path: /images/sandbox.jpg
  thumbnail: /images/thumbs/sandbox.jpg
redirect_from:
  - /windows-sandbox/
---

For a long time, we have struggled to match the performance and functionality of `runc` on Windows. Antonin wrote the Docker-based isolation for [ocurrent/obuilder](https://github.com/ocurrent/obuilder) with [PR#127](https://github.com/ocurrent/obuilder/pull/127), and I wrote machine-level isolation using QEMU [PR#195](https://github.com/ocurrent/obuilder/pull/195). Sadly, the most obvious approach of using `runhcs` doesn't work, see [issue#2156](https://github.com/microsoft/hcsshim/issues/2156).

On macOS, we use user isolation and ZFS mounts. We mount filesystems over `/Users/<user>` and `/usr/local/Homebrew` (or `/opt/Homebrew` on Apple Silicon). Each command is executed with `su`, then the filesystems are unmounted, and snapshots are taken before repeating the cycle. This approach has limitations, primarily because we can only run one job at a time. Firstly, the Homebrew location is per machine, and secondly, switches are not relocatable, so mounting as `/Users/<another user>` wouldn't work.

In a similar vein, we could make user isolation work under Windows. On Windows, opam manages the Cygwin installation in `%LOCALAPPDATA%\opam`, so it feels like the shared HomeBrew limitation of macOS doesn't exist, so can we create users with the same home directory? This isn't as crazy as it sounds because Windows has drive letters, and right back to the earliest Windows networks I can remember (NetWare 3!), it was common practice for all users to have their home directory available as `H:\`. These days, it's unfortunate that many applications _see through_ drive letters and convert them to the corresponding UNC paths. Excel is particularly annoying as it does this with linked sheets, preventing administrators from easily migrating to a new file server, thereby invalidating UNC paths.

# Windows user isolation

Windows drive mappings are per user and can be created using the command [subst](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/subst). We might try to set the home directory and profile path when we create a user `net user foo bar /add /homedir:h:\ /profilepath:h:\`, but since `h:` does not exist in the user's context, the user is given a temporary profile, which is lost when they log out. If you specify just `/homedir`, the profile is retained in `c:\users\foo`.

We could now try to map `h:` using `subst h: c:\cache\layer`, but `subst` drives don't naturally persist between sessions. Alternatively, we could use `net use h: \\DESKTOP-BBBSRML\cache\layer /persistent:yes`.

Ultimately, the path where `%APPDATA%` is held must exist when the profile is loaded; it can't be created as a result of loading the profile. Note that for a new user, the path doesn't exist at all, but the parent directory where it will be created does exist. In Active Directory/domain environments, the profile and home paths are on network shares, one directory per user. These exist before the user signs in; all users can have `h:` mapped to their personal space.

Ultimately, it doesn't matter whether we can redirect `%LOCALAPPDATA%` or not, as we can control the location opam uses by setting the environment variable `OPAMROOT`.

# opam knows

Unfortunately, there's no fooling opam. It sees through both `subst` and network drives and embeds the path into files like `opam\config`.

## subst

```sh
subst h: c:\home\foo
set OPAMROOT=h:\opam
opam init -y
...

  In normal operation, opam only alters files within your opam root
    (~\AppData\Local\opam by default; currently C:\home\foo\opam).

...
```

## net use

```sh
net share home=c:\home
net use h: \\DESKTOP-BBBSRML\home\foo /persistent:yes
SET OPAMROOT=h:\opam
opam init -y
...

  In normal operation, opam only alters files within your opam root
    (~\AppData\Local\opam by default; currently UNC\DESKTOP-BBBSRML\home\foo\opam).

...
```

Unless David has some inspiration, I don't know where to go with this.

Here's an example from the Windows API.

```cpp
// If you have: subst X: C:\SomeFolder
QueryDosDevice(L"X:", buffer, size);  // Returns: "C:\SomeFolder"
GetCurrentDirectory();                // Returns: "X:\" (if current)
```

# Windows Sandbox

Windows has a new(?) feature called _Windows Sandbox_ that I hadn't seen before. It allows commands to be executed in a lightweight VM based on an XML definition. For example, a simple `test.wsb` would contain.

```xml
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\home\foo\opam</HostFolder>
      <SandboxFolder>C:\Users\WDAGUtilityAccount\AppData\Local\opam</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
</Configuration>
```

The sandbox started quickly and worked well until I tried to run a second instance. The command returns an error stating that only one is allowed. Even doing `runas /user:bar "WindowsSandbox.exe test.wsb"` fails with the same error.

# Full circle

I think this brings us back to Docker. I wrote the QEMU implementation because of Docker's poor performance on Windows, coupled with the unreliability of OBuilder on Windows. However, I wonder if today's use case means that it warrants a second look.

```powershell
# Install Docker Engine
Invoke-WebRequest -UseBasicParsing "https://download.docker.com/win/static/stable/x86_64/docker-28.2.2.zip" -OutFile docker.zip
Expand-Archive docker.zip -DestinationPath "C:\Program Files"
 Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Program Files\docker", "Machine")

# Start Docker service
dockerd --register-service
Start-Service docker
```

Create a simple `Dockerfile` and build the image using `docker build . -t opam`.

```dockerfile
FROM mcr.microsoft.com/windows/servercore:ltsc2022

# Download opam
ADD https://github.com/ocaml/opam/releases/download/2.3.0/opam-2.3.0-x86_64-windows.exe C:\\windows\\opam.exe

RUN net user opam /add /passwordreq:no

USER opam

# Run something as the opam user to create c:\\users\\opam
RUN opam --version

WORKDIR c:\\users\\opam

CMD ["cmd"]
```

Test with `opam init`.

```sh
docker run --isolation=process --rm -it -v C:\cache\temp\:c:\Users\opam\AppData\Local\opam opam:latest opam init -y
```

