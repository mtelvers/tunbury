---
layout: post
title:  "Octoprint"
date:   2025-07-26 00:00:00 +0000
categories: 3d-printing
image:
  path: /images/octoprint.png
  thumbnail: /images/thumbs/octoprint.png
---

After my [3D print](https://www.tunbury.org/2025/07/23/rochester/) last week, Michael asked whether I was using [OctoPrint](https://octoprint.org). I've been using [Pronterface](https://www.pronterface.com) for some years, and I've never been terribly happy with it, but it does the job.

I had a _Pet Camera_ pointed at the printer to see what was happening, [Syncthing](https://syncthing.net) configured to share the GCode directory from my Mac to the Raspberry Pi, and the VNC Server to access the GUI. I decided that it was time to overhaul the setup with OctoPi!

OctoPi is available from the [Raspberry Pi Imager](https://raspberrypi.org/software), so updating my SD card was straightforward.  Step-by-step instructions are [available](https://octoprint.org/download/).

PrusaSlicer can be configured to communicate with OctoPi over IP. Therefore, once the model has been sliced, you can upload (and print) it directly from PrusaSlicer. This uses an API key for authentication. There is no longer a need for Syncthing.

Adding a USB web camera to the Pi lets you watch the printer remotely and record a time-lapse video.

Here's my first attempt at a time-lapse print of a vase. There are some obvious issues with the camera position, and it got dark towards the end, which was a bit annoying.

<iframe width="315" height="560"
src="https://www.youtube.com/embed/DvMHkZs-KpI"
title="YouTube video player"
frameborder="0"
allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
allowfullscreen></iframe>

