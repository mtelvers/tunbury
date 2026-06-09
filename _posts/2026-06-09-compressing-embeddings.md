---
layout: post
title: "Compressing embeddings"
date: 2026-06-09 21:00:00 +0000
categories: [tessera]
tags: tunbury.org
image:
  path: /images/grid_0.55_51.35.png
  thumbnail: /images/thumbs/grid_0.55_51.35.png
---
I've been distracted by the idea that ML embeddings could be considered as images with many colour channels.

A normal image would have 3 colour channels, the usual RGB we are all familiar with, but a 128-channel embedding vector is just a more general case. Formats like PNG can easily extend to more channels.

I'm going to use 2025/grid_0.55_51.35 as my test embedding, which is 106,490,368 bytes and needs to be combined with the `_scales` file of 3,327,948, for a total of 109.8MB.

The bulk of the data is the int8 values, with the `_scale` file being float32. The ideal is that int8 is exactly like a single component of RGB, so these techniques need the scale to reproduce the original embedding, except for where specifically noted.

Firstly, I fed it into GeoTIFF with various compression methods to find the smallest. This turned out to be `DEFLATE` level 9 with `PREDICTOR=2`, resulting in a file of 79,461,027, which can serve as the baseline.

My newly invented format, PNG128, with zlib 6, encodes each embedding as yet another RGB channel, giving a file size of 78,950,497, which was a nice opening result. PNG is an efficient _container_ to hold the int8 embedding. So this is a genuine improvement over the GeoTIFF, albeit without any ecosystem support.

What if you were to accept some level of lossy encoding, such as the JPEG format, and how does the root mean square error, RMSE, compare? Thus, JPEG128 is born, aka per-dimension independent grayscale JPEGs.

| quality | Size | rel-RMSE |
|---:|---:|---:|
| q10 | 4.63 MB | 24.9% |
| q30 | 10.94 MB | 17.1% |
| q50 | 15.30 MB | 14.4% |
| q75 | 23.46 MB | 11.0% |
| q97 | 66.76 MB | 2.5% |

This can be improved by replacing the JPEG RGB-to-YCbCr stage with a PCA-based version. This results in higher quality and lower RMSE, and it is the best result I have achieved. This used the dequantised values, so no need for the scales file, making the numbers in the table even more impressive. [gist](https://gist.github.com/mtelvers/be9166f7a8af549b74c083b4dc287f0b)

| quality | Size | rel-RMSE |
|---:|---:|---:|
| q5 | 3.89 MB | 21.4% |
| q10 | 7.00 MB | 16.8% |
| q30 | 15.61 MB | 10.9% |
| q50 | 21.60 MB | 8.6% |
| q75 | 31.92 MB | 6.0% |
| q92 | 55.25 MB | 2.8% |
| q97 | 79.47 MB | 1.2% |

While those lossy results are great, I wondered whether JPEG 2000 / JPEG XL ideas like reversible colour transforms could be applied to 128-dimensional colour. So I built a reversible cross-channel decorrelation using the Cholesky factor of the channel covariance (a PCA-like rotation, but integer-reversible), then spatial Paeth via my PNG128. That gave a real lossless improvement of 68,736,504.

Then I tried JPEG XL directly. Surprisingly, it was perfectly happy with 128-dimensional colour, but the result was a disappointing 79,025,453, no better than PNG128. It turns out JPEG XL doesn't decorrelate across 128 channels; built for 3–4 colour channels, it treats the rest as independent "extra channels" with spatial prediction only. So I combined the two: my Cholesky decorrelation to remove the cross-channel redundancy JPEG XL ignores, then JPEG XL's compression. This resulted in 63,992,162, a 40% reduction over raw and ~20% better than GeoTIFF.

A 128-channel embedding is redundant in two ways: first, across space, like any image, and second, across its channels. A pixel's 128 values aren't independent (32 directions capture 96% of the energy). Image codecs only aim to compress the first kind, leaving the second untouched. Thus, the best result came from the two-stage approach of decorrelating the channels first and then using a conventional image compressor such as JPEG XL. [gist](https://gist.github.com/mtelvers/9fa2ecacdbf64955735ff03947b0c6a7)

