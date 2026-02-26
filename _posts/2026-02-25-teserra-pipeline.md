---
layout: post
title: "Tessera Pipeline"
date: 2026-02-25 20:45:00 +0000
categories: tessera
tags: tunbury.org
image:
  path: /images/new_delhi_pca.png
  thumbnail: /images/thumbs/new_delhi_pca.png
---

Mainly for my future reference here is a walk-through of the Tessera pipeline.

# Data Sources and Acronyms

The Sentinel-1 Radiometrically Terrain Corrected (RTC) collection on Microsoft Planetary Computer (MPC) provides processed C-band Synthetic Aperture Radar (SAR) data.

Observational Products for End-Users from Remote Sensing Analysis, OPERA, Radiometric Terrain Corrected (RTC) SAR Backscatter from Sentinel-1 (RTC-S1) has a 30m resolution.

S1 width is typically 250km x 250km, but the exact values vary.

Sentinel-1 makes two passes which view the ground from different angles.
- Ascending: satellite moving south-to-north (evening pass, ~6pm local time)
- Descending: satellite moving north-to-south (morning pass, ~6am local time)

Sentinel-1 transmits a vertically polarised radar pulse and records two return signals:
- VV: vertical transmit, vertical receive — the "like-polarised" return sensitive to surface roughness and moisture (soil, water)
- VH: vertical transmit, horizontal receive — the "cross-polarised" return sensitive to volume scattering (vegetation canopy, forest structure)

Sentinel-2 Level-2A (L2A) data provides surface reflectance images, formatted in 100km x 100km tiles based on the Military Grid Reference System (MGRS). These are 10,980 x 10,820 pixel at 10m resolution.

MGRS tiles are defined on Universal Transverse Mercator (UTM) projections, which are local flat approximations of the Earth's surface.

Each "100km × 100km" tile is a 100km square in the local UTM coordinate system, which maps to a slightly trapezoidal shape on the actual Earth surface. The deviation from true square is small within a single tile (UTM distortion is <0.04% within a zone), but it means tiles at different latitudes cover different amounts of actual ground area when measured in degrees.

Sentinel-2 is an optical sensor which looks straight down.

COG = Cloud-Optimised GeoTIFF.

STAC = SpatioTemporal Asset Catalog.

ROI = Region of Interest.

SCL = Scene Classification Layer.

# The Pipeline

The pipeline uses 0.1-degree blocks.

Load a GeoTIFF that defines the ROI's spatial extent (CRS, bounds, resolution, dimensions) and a binary mask (1 = land, 0 = sea/skip). The bounds are reprojected to latitude/longitude for satellite data queries.

Query MPC or AWS for Sentinel-2 and Sentinel-1 data covering the ROI, for the entire year, filtered by cloud cover. S2 uses STAC on both sources; S1 uses STAC on MPC and NASA's Common Metadata Repository CMR on AWS. 

For Sentinel-2 data, there will be multiple passes, perhaps even on the same day. The cloud mask, SCL, is downloaded for all passes and used to identify valid (non-cloudy) dates. A second pass downloads the additional bands for the valid dates. This is nuanced, as a given day can be assembled from a mosaic of valid pixels rather than requiring an entirely cloud-free tile.

For Sentinel-1 data, both ascending and descending data is collected for all available dates.

This results in three 4D arrays, one 3D mask, and three arrays of dates:
- S2: [n_dates, H, W, 10] bands + [n_dates, H, W] masks + [n_dates] day-of-year
- S1: separate ascending and descending arrays [n_dates, H, W, 2] + [n_dates] DOYs each

For each pixel, the model needs exactly 40 S2 timesteps and 40 S1 timesteps as input. Since there are typically more valid timesteps available, a sampling step selects which ones to use. The pipeline uses random selection to pick the dates to use. It supports multiple passes with averaging, though it defaults to a single pass.

The S2 input is shaped as [40, 11], that is 10 spectral bands normalised plus the day-of-year. The S1 input is [40, 3], this is VV and VH (normalised) plus day-of-year. Ascending and descending S1 passes are merged into a single pool before sampling.

Thus for each pixel 10m x 10m pixel, there are 40 S2 dates, each with 10 spectral bands and for each of a (potentially different) 40 S1 dates, there are VV and VH values. These are passed to the model, which produces a 128-dimensional float32 embedding per pixel.

In the final step, the 128-dimensional embeddings are quantised to int8 with a per-pixel float32 scale factor, reducing storage to 132 bytes per pixel, compared to 512 bytes for full float32.

