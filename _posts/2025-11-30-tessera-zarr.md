---
layout: post
title: "TESSERA and Zarr"
date: 2025-11-30 22:50:00 +0000
categories: tessera,zarr
tags: tunbury.org
image:
  path: /images/embedding_pca.png
  thumbnail: /images/thumbs/embedding_pca.png
---

I've been copying the TESSERA data to Cephfs, but what is actually in the files?

There are directories for each tile, which are named `grid_longitude_latitude`. Each of these contains two NPY files. Picking one at random, I found these two files covering an area in the Canadian Arctic region.

| File                         | Shape            | Type    | Elements     |
|------------------------------|------------------|---------|------------- |
| grid_-99.95_80.05.npy        | 1119 × 211 × 128 | int8    | ~30 million  |
| grid_-99.95_80.05_scales.npy | 1119 × 211       | float32 | ~236k        |

This is quantised data, where the actual values would be: `data[i,j,k] * scales[i,j]`

There are 128 channels of machine learning data which need to be processed further by a downstream model, but I wanted to "see" it. Claude suggested a [PCA visualisation](https://github.com/mtelvers/npy-pca) of the file, which converts the 128 dimensions into 3 dimensions, which are mapped to RGB values. This is the header image for this post.

The Zarr format is designed for large chunked arrays, especially for use in cloud storage. Rather than being a single file like NPY, it is a directory containing metadata in `.zarray`, attributes in `.zattrs` and then a series of files like `0.0`, `0.1`, `1.0`, `1.1`. Each of those files contains the respective chunk of data. So, if the chunk size is 256, then those four files would contain at most an array of 512x512. For example, the scales data about would need `0.0`, `1.0`, `2.0`, `3.0`, `4.0`. Note that there is no `.1` file as the second dimension is less than 256; therefore, all the data fits into the `.0` file.

For higher dimensions, more dots are added. For example, with a chunk size of 256, chunk `2.1.0` would mean:

- Dimension 0: chunk 2 - pixels 512-767
- Dimension 1: chunk 1 - pixels 256-511
- Dimension 2: chunk 0 - channels 0-127 (all of them)

The Zarr format allows the client to request a subset of the full dataset. The smallest element which can be returned is one chunk. Thus, smaller chunks may be better; however, these add more protocol overhead than larger chunks when requesting a large dataset, so a trade-off needs to be made. Zarr also compresses the data. Each dimension can be chunked with a different chunk size. Extra dimensions, such as the year of the dataset, could be incorporated.

Zarr's real proposition is to allow the client to request "Give me latitude 50-55, longitude 100-110" without concern for the internal structure. However, this requires a unified array, which conflicts with the current structure, where tiles have different pixel dimensions depending on latitude (because longitude degrees shrink toward the poles). The data could be padded with zeros (wasting space), or bands could be created at different latitudes (gaps over the sea?).

I looked at some other [datasets](https://planetarycomputer.microsoft.com/catalog?filter=zarr) to see how they handled this problem. Smaller regional datasets covering North America (for example), use a regular 1km grid and ignore distortions. The ERA5 climate data uses variable-sized pixels. It maps the globe to a 1440 x 720 array. [ref](https://confluence.ecmwf.int/display/CKB/ERA5:+What+is+the+spatial+reference). At the Equator, they have 28km per pixel; at 80 degrees latitude, they have 5km per pixel.

Discrete Global Grid Systems, DGGS, exist which divide the sphere into polyhedra, such as Uber's [H3](https://www.uber.com/en-GB/blog/h3/); however, this doesn't nicely map over the existing square pixels. The data would need to be resampled, and it's not clear to me how you would average or interpolate 128 channels of ML data.

Possibly the best approach in the short term would be to provide the tiles as is and include appropriate metadata to describe them. [Climate and Forest Conventions](https://cfconventions.org/) and [Attribute Convention for Data Discovery 1-3](https://wiki.esipfed.org/Attribute_Convention_for_Data_Discovery_1-3) seem to be the standards and are used in xarray and Planetary Computer.

Anil pointed me to [EOPF Sentinel Zarr Samples Service STAC API](https://stac.browser.user.eopf.eodc.eu). STAC is just a JSON schema convention. We provide a `catalog.json` at the top level, which lists the yearly collections. In each year subdirectory, we provide `collection.json` that gives a list of each tile's JSON file. The tile's JSON file gives the hyperlink to the Zarr storage on S3.

Using Leaflet to visualise the map with some JavaScript to load the JSON files and extract the bounding boxes, we can fairly easily generate this [map](https://stac.mint.caelum.ci.dev). I do wonder how well that would scale, though.
