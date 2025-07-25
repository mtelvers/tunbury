---
layout: post
title:  "Website Build Analysis with Claude"
date:   2025-07-25 00:00:00 +0000
categories: tarides
image:
  path: /images/docker_build_analysis.png
  thumbnail: /images/thumbs/docker_build_analysis.png
---

The Tarides website is built using Docker, and it would be interesting to run a quick analysis over the logs, given that we have over 300 days' worth. This is one of those things where I'd usually turn to AWK and spend ages fiddling with the script.

However, this time I decided to ask Claude. The log files are organised by date e.g. 2024-09-24/HHMMSS-docker-build-HASH.log, where each day directory may contain many logs, as there can be several builds in a day. The HHMMSS is the time the job was created, and HASH is the MD5 hash of the job. The log format is as below, with only the start and end shown.

```
2024-09-24 14:45.02: New job: docker build
...
2024-09-24 14:55.14: Job succeeded
```

I would like a graph over time showing the duration each build takes to see if there are any trends.

With a few iterations and very few minutes of effort, Claude had a working script. Beyond my initial description, I added the complexity that I wanted to run it in a Docker container with a bind mount for my logs and to exclude failed jobs and jobs that completed very quickly (likely due to the Docker caching).

Claude's code is in this [gist](https://gist.github.com/mtelvers/8383fb563e171778bfaf412f3119d50c)

Here's the summary output

```
==================================================
BUILD ANALYSIS SUMMARY (FILTERED DATA)
==================================================
Original builds found: 1676
Builds after filtering: 655
Filtered out: 1021 (60.9%)
Filter criteria: min_duration >= 100s, exclude_failed = True

Duration Statistics (minutes):
  Mean: 10.16
  Median: 6.92
  Min: 5.53
  Max: 68.87
  Std Dev: 6.00

Date Range:
  First build: 2024-09-24 14:45:50
  Last build: 2025-07-25 09:29:10

Analysis period: 305 days
Average builds per day: 2.1

Top 5 longest builds:
  ✓ 2025-02-05 15:37 - 68.87m - 153726-docker-build-f9426a.log
  ✓ 2025-02-05 15:37 - 62.72m - 153724-docker-build-d227b6.log
  ✓ 2025-02-05 15:37 - 56.03m - 153723-docker-build-65de8e.log
  ✓ 2025-05-07 12:41 - 55.90m - 124115-docker-build-f4091b.log
  ✓ 2025-02-05 15:37 - 42.47m - 153722-docker-build-dafc1d.log

Top 5 shortest builds (above threshold):
  ✓ 2025-01-13 14:26 - 5.53m - 142624-docker-build-fec55f.log
  ✓ 2024-09-25 10:10 - 5.65m - 101005-docker-build-c78655.log
  ✓ 2024-09-26 10:01 - 5.77m - 100119-docker-build-efd190.log
  ✓ 2025-02-07 18:09 - 5.83m - 180951-docker-build-ab19e5.log
  ✓ 2024-09-30 14:03 - 5.85m - 140301-docker-build-4028bb.log
Filtered data exported to /data/output/build_analysis.csv
Raw data exported to /data/output/build_analysis_raw.csv
```

And the graphs

![](/images/build_times_timeline.png)

![](/images/daily_performance_trends.png)


