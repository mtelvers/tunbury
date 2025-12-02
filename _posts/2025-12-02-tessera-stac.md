---
layout: post
title: "Tile Server"
date: 2025-12-02 20:00:00 +0000
categories: tessera,stac
tags: tunbury.org
image:
  path: /images/meighen-island.png
  thumbnail: /images/thumbs/meighen-island.png
---

My throw-away comment at the end of my earlier [post](https://www.tunbury.org/2025/11/30/tessera-zarr/) shows my scepticism that the JSON file approach was really viable.

A quick `ls | wc -l` shows nearly one million tiles in 2024 alone. We need a different approach. There are already parquet files available, and checking `register.parquet`, I can see it has everything we need!

As an alternative, more scalable solution, we could have a server that loads the Parquet files using [mtelvers/arrow](https://github.com/mtelvers/arrow), derived from [LaurentMazare/ocaml-arrow](https://github.com/LaurentMazare/ocaml-arrow), which can respond to queries raised by callbacks from Leaflet, allowing it to draw the required bounding boxes. Ultimately this could provide links to the Zarr data in stored in S3.

It's a pretty simple API:

- `GET /years` - Available years
- `GET /stats?year=YYYY` - Coverage statistics
- `GET /tiles?minx=&miny=&maxx=&maxy=&year=&limit=` - Tiles in bounding box
- `GET /density?year=&resolution=` - Tile density grid

The code is available at [mtelvers/title-server](https://github.com/mtelvers/tile-server) and currently deployed at [stac.mint.caelum.ci.dev](https://stac.mint.caelum.ci.dev).
