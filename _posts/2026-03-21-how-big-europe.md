---
layout: post
title: "How big is Europe?"
date: 2026-03-21 18:20:00 +0000
categories: ocaml,tessera
tags: tunbury.org
image:
  path: /images/coverage_2024_diff_europe.png
  thumbnail: /images/thumbs/coverage_2024_diff_europe.png
---

[Tessera](https://geotessera.org) produces global land-cover embeddings at 0.1-degree resolution, roughly 11 km square at the equator. For each year and each grid tile, there is a directory containing NumPy files of the embeddings.

Each tile is about 100MB; multiply that by every year since 2017, and you end up with a directory tree containing millions of entries across hundreds of terabytes. If you wanted to copy a subset, how much storage would you need? For example, how much storage does the European subset occupy? This obviously calls for an OCaml tool to calculate it.

# The directory tree

The embeddings are held in on the file system in this layout:

```
/data/tessera/v1/global_0.1_degree_representation/
  2017/
    grid_7.55_46.05/
      grid_7.55_46.05.npy
      grid_7.55_46.05_scales.npy
      SHA256
    grid_-1.25_50.05/
      ...
  2018/
    ...
```

Each year directory can contain as many as 1.6 million `grid_<lon>_<lat>` subdirectories. The longitude and latitude encoded in the directory name represent the centre of the 0.1-degree cell. This naming convention is the key that lets us filter geographically without opening a single file.

# Reading shapefiles from OCaml

To determine which grid cells fall within "Europe", I need country boundary polygons. [Natural Earth](https://www.naturalearthdata.com/) provides free vector data at several resolutions. The 110m admin-0 countries dataset comes as a pair of files: a `.shp` containing polygon geometry and a `.dbf` containing attribute columns.

Two opam libraries handle the parsing. The [cyril-allignol/ocaml-shapefile](https://github.com/cyril-allignol/ocaml-shapefile) library reads `.shp` files and returns a list of shapes, each being an array of rings (arrays of `{x; y}` points). The [pveber/dbf](https://github.com/pveber/dbf) library reads the dBASE `.dbf` database and returns columns as an association list:

```ocaml
let load_shapefile shp_path =
  let _header, shapes = Shapefile.Shp.read shp_path in
  let dbf_path = Filename.chop_extension shp_path ^ ".dbf" in
  let dbf = match Dbf.of_file dbf_path with
    | Ok d -> d
    | Error `Unexpected_end_of_file -> failwith "DBF: unexpected end of file"
    | Error `Unknown_file_type -> failwith "DBF: unknown file type"
    | Error `Unknown_field_type -> failwith "DBF: unknown field type"
  in
  let names = get_string_column dbf "NAME" in
  let continents = get_string_column dbf "CONTINENT" in
  let subregions = get_string_column dbf "SUBREGION" in
  ...
```

The DBF format stores strings padded with nulls and spaces, so a small `strip_nulls` function trims trailing zeros. Each record in the shapefile has a corresponding row in the DBF, so the geometry and metadata are joined together in a list of `{ name; continent; subregion; shape }` records.

The Natural Earth DBF includes `CONTINENT`, `REGION_UN` and `SUBREGION` columns, which means we can select countries by group rather than listing them individually. Our tool supports composable flags:

```
--continent Europe --exclude-country Russia --include-country Turkey
```

Selection is applied in order: start with all countries matching `--continent` or `--subregion`, add any `--include-country` entries, then remove any `--exclude-country` entries. All matching is case-insensitive.

# Ray casting

For each grid directory, parse the longitude and latitude from the name and test whether that point falls inside any of the selected country polygons. To test if a point is within the region polygon, the standard algorithm casts a horizontal ray from the test point to infinity and counts how many polygon edges it crosses. An odd count means the point is inside.

```ocaml
let point_in_ring (px, py) (ring : Shapefile.D2.point array) =
  let n = Array.length ring in
  if n < 3 then false
  else
    let test_edge inside i j =
      let pi = ring.(i) and pj = ring.(j) in
      if (pi.y > py) <> (pj.y > py)
         && px < (pj.x -. pi.x) *. (py -. pi.y) /. (pj.y -. pi.y) +. pi.x
      then not inside
      else inside
    in
    let rec loop inside i =
      if i >= n then inside
      else loop (test_edge inside i ((i + n - 1) mod n)) (i + 1)
    in
    loop false 0
```

The `test_edge` function checks two conditions for each edge of the polygon. First, do the two endpoints of the edge straddle the test point's y-coordinate? The expression `(pi.y > py) <> (pj.y > py)` returns true when one endpoint is above and the other below. Second, is the test point to the left of where the ray would cross this edge? The x-coordinate of the intersection is computed by linear interpolation. If both conditions hold, we flip the `inside` state.

Shapefile polygons can have multiple rings. The first ring is the outer boundary; subsequent rings are holes. A country like the United Kingdom that consists of multiple landmasses has multiple outer rings. This is handled by parity counting. A point is "in" the polygon if it falls inside an odd number of rings:

```ocaml
let point_in_polygon pt rings =
  let count =
    Array.fold_left
      (fun acc ring -> if point_in_ring pt ring then acc + 1 else acc)
      0 rings
  in
  count mod 2 = 1
```

# Scanning the filesystem

Rather than shelling out to `du`, (which I did initially), the tool walks the directory tree directly using `Sys.readdir` and `Unix.lstat`:

```ocaml
let dir_size_bytes path =
  let rec walk dir acc =
    match Sys.readdir dir with
    | entries ->
      Array.fold_left (fun acc name ->
        let full = Filename.concat dir name in
        match Unix.lstat full with
        | { Unix.st_kind = Unix.S_REG; st_size; _ } -> acc + st_size
        | { Unix.st_kind = Unix.S_DIR; _ } -> walk full acc
        | _ -> acc
        | exception Unix.Unix_error _ -> acc
      ) acc entries
    | exception Sys_error _ -> acc
  in
  walk path 0
```

The tool filters before measuring. The per-year scan parses the grid coordinates from each directory name and tests them against the country polygons. Only matching directories get measured with a call to `dir_size_bytes`:

```ocaml                                                                                     
let scan_year_filtered year_path year polys =
  let grid_dirs = list_dirs year_path |> List.filter is_grid_dir in
  List.fold_left (fun stats dir_name ->
    match parse_grid_coords dir_name with
    | Some (lon, lat) when point_in_any_country (lon, lat) polys ->
      let bytes = dir_size_bytes (Filename.concat year_path dir_name) in
      { stats with matched_bytes = stats.matched_bytes + bytes; ... }
    | _ ->
      stats  (* skip — no filesystem traversal *)
 ) empty_stats grid_dirs

```

As mentioned above, there could be as many as 1.6 million directories per year, but only ~80,000 match Europe, thus avoiding overworking the filesystem.

# Parallel scanning with OCaml 5 domains

The scan is embarrassingly parallel. Each year's directory tree is completely independent. OCaml 5's multicore support makes this trivial. Each year gets its own `Domain`, and results are merged after all domains join:

```ocaml
let scan_parallel root polys scan_year =
  let years = list_dirs root |> List.filter is_year_string in
  let domains =
    List.map (fun year ->
      let year_path = Filename.concat root year in
      Domain.spawn (fun () -> scan_year year_path year polys)
    ) years
  in
  List.fold_left
    (fun acc domain -> merge_stats acc (Domain.join domain))
    empty_stats domains
```

# The results!

Running the tool against the full global dataset with `--continent Europe --exclude-country Russia --include-country Turkey`:

| Year | Grid tiles | Size (TB) |
|------|-----------|-----------|
| 2017 | 79,617 | 7.4 |
| 2018 | 79,744 | 7.4 |
| 2019 | 79,700 | 7.4 |
| 2020 | 79,698 | 7.4 |
| 2021 | 79,699 | 7.4 |
| 2022 | 79,750 | 7.4 |
| 2023 | 79,638 | 7.4 |
| 2024 | 89,938 | 8.5 |
| 2025 | 79,678 | 7.4 |
| **Total** | **727,462** | **~68 TB** |

The 2024 has 13% more tiles than the other years, as Turkey is included, along with some extra coastal tiles. From the header image, white pixels is available in all years, while red pixels are only available in 2024.

# Code

The code is available in [mtelvers/embedding-size](https://github.com/embedding-size).
