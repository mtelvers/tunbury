---
layout: post
title: "ReFS, EEG Intern and Monteverde"
date: 2025-07-07 00:00:00 +0000
categories: refs
tags: tunbury.org
image:
  path: /images/refs.png
  thumbnail: /images/thumbs/refs.png
---

In addition to the post from last week covering [BON in a Box](https://www.tunbury.org/2025/07/02/bon-in-a-box/) and [OCaml Functors](https://www.tunbury.org/2025/07/01/ocaml-functors/), below are some additional notes.

# Resilient File System, ReFS

I have previously stated that [ReFS](https://www.tunbury.org/windows-reflinks) supports 1 million hard links per file; however, this is not the case. The maximum is considerably lower at 8191. That's eight times more than NTFS, but still not very many.

```powershell
PS D:\> touch foo
PS D:\> foreach ($i in 1..8192) {
>>     New-Item -ItemType HardLink -Path "foo-$i" -Target "foo"
>> }


    Directory: D:\


Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----        07/07/2025     01:00              0 foo-1
-a----        07/07/2025     01:00              0 foo-2
-a----        07/07/2025     01:00              0 foo-3
-a----        07/07/2025     01:00              0 foo-4
...
-a----        07/07/2025     01:00              0 foo-8190
-a----        07/07/2025     01:00              0 foo-8191
New-Item : An attempt was made to create more links on a file than the file system supports
At line:2 char:5
+     New-Item -ItemType HardLink -Path "foo-$i" -Target "foo"
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (:) [New-Item], Win32Exception
    + FullyQualifiedErrorId : System.ComponentModel.Win32Exception,Microsoft.PowerShell.Commands.NewItemCommand
```

I had also investigated ReFS block cloning, which removed the requirement to create hard links, and wrote a [ReFS-clone](https://github.com/mtelvers/ReFS-Clone) tool for Windows Server 2022. This works well until containerd is used to bind mount a directory on the volume. Once this has happened, attempts to create a block clone fail. To exclude my code as the root cause, I have tried Windows Server 2025, where commands such as `copy` and `robocopy` automatically perform block clones. Block cloning can be restored by rebooting the machine. I note that restarting containerd is not sufficient.

Removing files and folders on ReFS is impressively fast; however, this comes at a cost: freeing the blocks is a background activity that may take some time to be scheduled.

# File system performance with a focus on ZFS

Several EEG interns started last week with this [project](https://anil.recoil.org/ideas/zfs-filesystem-perf) under my supervision. In brief, we will examine file system performance on the filesystems supported by [OBuilder](https://github.com/ocurrent/obuilder) before conducting more detailed investigations into factors affecting ZFS performance.

# Monteverde

monteverde.cl.cam.ac.uk, has been installed in the rack. It has two AMD EPYC 9965 192-Core Processors, giving a total of 384 cores and 768 threads and 3TB of RAM.

![](/images/monteverde.jpg)

From the logs, there are still some teething issues:

```
[130451.620482] Large kmem_alloc(98304, 0x1000), please file an issue at:
                https://github.com/openzfs/zfs/issues/new
[130451.620486] CPU: 51 UID: 0 PID: 8594 Comm: txg_sync Tainted: P           O       6.14.0-23-generic #23-Ubuntu
[130451.620488] Tainted: [P]=PROPRIETARY_MODULE, [O]=OOT_MODULE
[130451.620489] Hardware name: Dell Inc. PowerEdge R7725/0KRFPX, BIOS 1.1.3 02/25/2025
[130451.620490] Call Trace:
[130451.620490]  <TASK>
[130451.620492]  show_stack+0x49/0x60
[130451.620493]  dump_stack_lvl+0x5f/0x90
[130451.620495]  dump_stack+0x10/0x18
[130451.620497]  spl_kmem_alloc_impl.cold+0x17/0x1c [spl]
[130451.620503]  spl_kmem_zalloc+0x19/0x30 [spl]
[130451.620508]  multilist_create_impl+0x3f/0xc0 [zfs]
[130451.620586]  multilist_create+0x31/0x50 [zfs]
[130451.620650]  dmu_objset_sync+0x4c4/0x4d0 [zfs]
[130451.620741]  dsl_pool_sync_mos+0x34/0xc0 [zfs]
[130451.620832]  dsl_pool_sync+0x3c1/0x420 [zfs]
[130451.620910]  spa_sync_iterate_to_convergence+0xda/0x220 [zfs]
[130451.620990]  spa_sync+0x333/0x660 [zfs]
[130451.621056]  txg_sync_thread+0x1f5/0x270 [zfs]
[130451.621137]  ? __pfx_txg_sync_thread+0x10/0x10 [zfs]
[130451.621207]  ? __pfx_thread_generic_wrapper+0x10/0x10 [spl]
[130451.621213]  thread_generic_wrapper+0x5b/0x70 [spl]
[130451.621217]  kthread+0xf9/0x230
[130451.621219]  ? __pfx_kthread+0x10/0x10
[130451.621221]  ret_from_fork+0x44/0x70
[130451.621223]  ? __pfx_kthread+0x10/0x10
[130451.621224]  ret_from_fork_asm+0x1a/0x30
[130451.621226]  </TASK>
```
