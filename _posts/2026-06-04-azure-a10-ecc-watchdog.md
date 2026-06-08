---
layout: post
title: "Spotting broken A10s in Azure"
date: 2026-06-04 07:00:00 +0000
categories: [tessera, azure]
tags: tunbury.org
image:
  path: /images/tessera.png
  thumbnail: /images/thumbs/tessera.png
---

In the [previous post]({% post_url 2026-05-20-processing-uk-azure-spot %}) I mentioned that two A10s developed ECC faults during the UK processing. This occasional annoyance needs constant vigilance as failed machines process jobs much faster than working ones.

In my setup, I have a central work queue from which the spot machines `curl` to get their next grid tile. The queue records the time that the tile was issued and also notes the time of any subsequent status update from the spot machine. After 30 minutes of silence, the tile is requeued.

When a spot machine has a bad GPU, it completes the download phase fine and then tries to use the GPU. This fails immediately, and the spot machine moves on to the next grid tile. Without the inference stage, these workers manage ~100 in-flight jobs in the 30-minute timeout window. Up to this point, I have been relying on having the browser tab open and monitoring the number of in-flight jobs per worker.

When a bad worker is spotted, it's an easy fix: deallocate the machine and immediately reallocate it, effectively moving them to new hardware. This is the same mechanism as a spot eviction and a reallocation; thus, on occasion, the problem resolves as the eviction reallocates the bad GPU to someone else.

Unfortunately, when I'm sleeping, the machines aren't monitored, but I can retrospectively `grep` the logs for `uncorrectable ECC` to see how many tiles failed due to ECC problems:

| VM | ECC FAILs |
|---|---:|
| a10-uk-5 | 1,686 |
| a10-uk-4 | 925 |
| a10-uk-24 | 757 |
| a10-uk-6 | 634 |
| a10-uk-3 | 383 |
| a10-uk-33 | 274 |
| a10-uk-8 | 209 |
| a10-uk-30 | 158 |

A little over 5,000 failures in a week.

From the previous post, we already know we can query the number of ECC failures with `nvidia-smi`, and I already monitor the machines with a watcher script to restart spot allocations, so I added a function to check the counters over SSH.

```bash
ecc_count_on_host() {
    local ip="$1"
    ssh -n -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$KNOWN_HOSTS" mte24@"$ip" \
        'nvidia-smi --query-gpu=ecc.errors.uncorrected.aggregate.dram,ecc.errors.uncorrected.aggregate.sram --format=csv,noheader 2>/dev/null' \
        2>/dev/null | awk -F', ' 'NR==1 {print ($1+0)+($2+0); exit} END {if (NR==0) print 0}'
}
```

With that running change in place at 18:00, it didn't take long before I found a bad machine.

```
21:35:34Z    started a10-uk-26 (--no-wait)
...
21:55:19Z  ECC sweep: 43 scanned, 1 ECC offender(s)
21:55:19Z    deallocating a10-uk-26 (ECC counter=28)
21:55:20Z      deallocate accepted; restart pass will resurrect next tick
...
21:59:59Z    started a10-uk-26 (--no-wait)
...
22:04:12Z  ECC sweep: 43 scanned, no offenders
```

`a10-uk-26` was restarted after a spot eviction at 21:35. The script deallocated it at 21:55 because the ECC counter was 28, and it subsequently restarted at 21:59. The next sweep saw zero ECC issues.

