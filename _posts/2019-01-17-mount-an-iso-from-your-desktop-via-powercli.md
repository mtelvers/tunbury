---
layout: post
title:  "Mount an ISO from your Desktop via PowerCLI"
date:   2019-01-17 13:41:29 +0100
categories: powershell
image:
  path: /images/PowerCLI.png
  thumbnail: /images/thumbs/PowerCLI.png
---
Normally, I’d used a Windows NFS Server to host my ISO files. The steps couldn’t be simpler

    Add-WindowsFeature FS-NFS-Service
    New-NfsShareimport
    Import-Module NFS
    New-NfsShare -Name ISO -Path C:\ISO -access readonly

However, this only works if you have a Windows Server installation as you can’t install the NFS Service on a Windows desktop.

There is a standalone executable version of an NFS server available called WinNFSd.exe which can be downloaded from [GitHub](https://github.com/winnfsd/winnfsd/releases). I’ve saved this to `C:\WinNFSd`

Create a firewall rule on your desktop to allow the allow the ESXi host to communicate with WinNFSd, thus:

    New-NetFirewallRule -DisplayName "NFS Server" -Direction Inbound -Action Allow -Program C:\WinNFSd\WinNFSd.exe

Run `WinNFSd`. The argument list is the local folder hosting your ISO files to be shared and the path that it will have on the NFS server’s export list.  The path name needs to match the `New-DataStore` command later:

    Start-Process C:\WinNFSd\WinNFSd.exe -ArgumentList "C:\ISO /ISO"

You should now have a CMD window open along with the PowerCLI prompt.

Now you need to know the IP Address of your machine:

    $myIPAddress = "Your IP Address"

You can automate this as follows but this may need to be tweaked depending upon which network card you are using etc.

    $myIPAddress = $(Get-NetIPAddress -InterfaceAlias Ethernet0 -AddressFamily IPv4).IPAddress

Create a variable for your ESXi host(s).

    $esxHosts = @( "Your Host" )

If you have a cluster you can include them all like this:

    $esxHosts = Get-Datacenter yourDC | Get-Cluster yourCluster | Get-VMHost

Instruct the ESXi host to mount the datastore.  Note that the final `/ISO` needs to match the final argument to `WinNFSd`

    $esxHosts |% { New-Datastore -VMHost $_ -Name ISO -NfsHost $myIPAddress -Path /ISO }

Now set the ISO that you have, such as `c:\iso\myiso.iso` to be the CD Drive on your VM

    Get-CDDrive $vm | Set-CDDrive -IsoPath "[ISO] myiso.iso" -Connected:$true -Confirm:$false

Now you can use the CD Drive in the VM as you wish.

Of course, it’s important tidy up in the correct sequence. Don’t just close the CMD prompt before disconnecting the CD drive and unmounting the datastore.

Disconnect the CD Drive

    Get-CDDrive $vm | Set-CDDrive -NoMedia -Confirm:$false

Remove the datastore

    $esxHosts |% { Remove-Datastore -VMHost $_ -Datastore ISO -Confirm:$false }

Stop WinNFSd and remove the firewall rule

    Stop-Process -Name WinNFSd
    Remove-NetFirewallRule -DisplayName "NFS Server"
