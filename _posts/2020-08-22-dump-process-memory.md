---
layout: post
title:  "Dump Process Memory"
date:   2020-08-22 13:41:29 +0100
categories: bash
image:
  path: /images/pmap-dump.png
  thumbnail: /images/thumbs/pmap-dump.png
permalink: /dump-process-memory/
---
Yesterday in a stroke of good fortune, I remembered a job that I’d set running a little while back and I checked in to see how it was doing. It’s a MPI console app running on 22 distributed Ubuntu nodes. My application was set to output the time periodically and it currently reported a runtime of 15837421 seconds (just over six months). Unfortunately I couldn’t see the current ‘best’ result as it results aren’t displayed until the end. I was intrigued to see how it was doing.

From `ps` I could see that the *manager* of my MPI application was process id 28845. I knew that the application had a string representation of the current best result as all the child nodes reported back to this process.

I found [pmap-dump](https://github.com/Nopius/pmap-dump) on GitHub which seemed to fit the bill. I cloned the repository, compiled and installed:

    git clone https://github.com/Nopius/pmap-dump.git
    cd pmap-dump
    make install

Then in Bash save the process id of my application in a variable:

    pid=28845

Using `pmap`, I could dump the memory segments in use by the application which can be built into the appropriate command line for `pmap-dump`.

    pmap -x $pid | awk -vPID=$pid 'BEGIN{ printf("pmap-dump -p " PID)};($5~/^r/){printf(" 0x" $1 " " $2)};END{printf("\n")}'

This yielded a toxic command line like this….

    pmap-dump -p 28845 0x0000560fc10e3000 124 0x0000560fc10e3000 0 0x0000560fc1302000 4 0x0000560fc1302000 0 0x0000560fc1303000 4 ...

… which when executed produced 65 binary .hex files.

Since I knew my result was a lengthy string, I obtained it with

    strings -w -n 30 *.hex

Today the router crashed and the connection was broken…
