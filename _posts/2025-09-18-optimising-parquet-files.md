---
layout: post
title: "Optimising Data Access in Parquet Files"
date: 2025-09-17 21:00:00 +0000
categories: apache,parquet
tags: tunbury.org
image:
  path: /images/apache-parquet-logo.png
  thumbnail: /images/thumbs/apache-parquet-logo.png
---

Yesterday I wrote about the amazing performance of Apache Parquet files; today I reflect on how that translates into an actual application reading Parquet files using the OCaml wrapper of Apache's C++ library.

I have a TUI application that displays build results for OCaml packages across multiple compiler versions. The application needs to provide two primary operations:

1. Table view: Display a matrix of build statuses (packages × compilers)
2. Detail view: Show detailed build logs and dependency solutions for specific package-compiler combinations

The dataset contained 48,895 records with the following schema:

- name: Package name (~4,500 unique values)
- compiler: Compiler version (~11 unique versions)
- status: Build result (success/failure/etc.)
- log: Detailed build output (large text field)
- solution: Dependency resolution graph (large text field)

# Initial Implementation and Performance Bottleneck

The initial implementation used Apache Arrow's OCaml bindings to load the complete Parquet file into memory:

```
let analyze_data filename =
  let table = Arrow.Parquet_reader.table filename in
  let name_col = Arrow.Wrapper.Column.read_utf8 table ~column:(`Name "name") in
  let status_col = Arrow.Wrapper.Column.read_utf8_opt table ~column:(`Name "status") in
  let compiler_col = Arrow.Wrapper.Column.read_utf8 table ~column:(`Name "compiler") in
  let log_col = Arrow.Wrapper.Column.read_utf8_opt table ~column:(`Name "log") in
  let solution_col = Arrow.Wrapper.Column.read_utf8_opt table ~column:(`Name "solution") in
  (* Build hashtable for O(1) lookups *)
```

This approach exhibited 3-4 second loading times, creating an unacceptable user experience for interactive data exploration.

# Performance Analysis

## Phase 1: Timing Instrumentation

I implemented some basic timing instrumentation to identify bottlenecks by logging data to a file.

```ocaml
let append_to_file filename message =
  let oc = open_out_gen [Open_creat; Open_text; Open_append] 0o644 filename in
  Printf.fprintf oc "%s: %s\n" (Sys.time () |> Printf.sprintf "%.3f") message;
  close_out oc
```

The timings revealed that `Arrow.Parquet_reader.table` consumed ~3.6 seconds (80%) of the total loading time, with individual column extractions adding minimal overhead.

## Phase 2: Deep API Analysis

Reviewing the Arrow C++ implementation to understand the performance characteristics:

```c
  // From arrow_c_api.cc - the core bottleneck
  TablePtr *parquet_read_table(char *filename, int *col_idxs, int ncols,
                                int use_threads, int64_t only_first) {
    // ...
    if (only_first < 0) {
      st = reader->ReadTable(&table);  // Loads entire table!
    }
    // ...
  }
```

This shows that the `ReadTable()` operation materialises the complete dataset in memory, regardless of actual usage patterns.

# Optimisation Strategy: Column Selection

Could the large text fields (log and solution columns) be responsible for the performance bottleneck?

I modified the table loading to exclude large columns during initial load:

```ocaml
let table = Arrow.Parquet_reader.table ~column_idxs:[0; 1; 6; 7] filename in
  (* Only load: name, status, os, compiler *)
```

This dramatically reduced the loading time from 3.6 seconds to 0.021 seconds.

This optimisation validated the hypothesis that the large text columns were the primary bottleneck. However, it created a new challenge of accessing the detailed log/solution data for individual records.

There is a function `Arrow.Parquet_reader.fold_batches` which could be used for on-demand detail loading:

```ocaml
let find_package_detail filename target_package target_compiler =
  Arrow.Parquet_reader.fold_batches filename
    ~column_idxs:[0; 4; 5; 7]  (* name, log, solution, compiler *)
    ~batch_size:100
    ~f:(fun () batch ->
      (* Search batch for target, stop when found *)
    )
```

However, the performance analysis showed that it was equivalent to loading the whole table. If the log and solution columns were omitted, then the performance was fast!

- With large columns: 2.981 seconds
- Without large columns: 0.033 seconds (33ms)

# Comparative Analysis: ClickHouse vs Arrow

To establish performance baselines, I compared Arrow's performance with `clickhouse local`:

```sh
# ClickHouse aggregation query (equivalent to table view)
time clickhouse local --query "
  SELECT name, anyIf(status, compiler = 'ocaml.5.3.0') as col1, ...
  FROM file('data.parquet', 'Parquet') GROUP BY name ORDER BY name"
# Result: 0.2 seconds

# ClickHouse individual lookup
time clickhouse local --query "
  SELECT log, solution FROM file('data.parquet', 'Parquet') WHERE name = '0install.2.18' AND compiler = 'ocaml.5.3.0'"
# Result: 1.716 seconds

# ClickHouse lookup without large columns
time clickhouse local --query "
  SELECT COUNT() FROM file('data.parquet', 'Parquet') WHERE name = '0install.2.18' AND compiler = 'ocaml.5.3.0'"
# Result: 0.190 seconds
```

The 1.5-second difference (1.716s - 0.190s) represented the fundamental cost of decompressing and decoding large text fields and this is present both in OCaml and when using ClickHouse.

# Data Structure Redesign: The Wide Table Approach

Instead of searching through 48,895 rows to find specific package-compiler combinations, I restructured the data into a wide table format:

```sql
SELECT
    name,
    anyIf(status, compiler = 'ocaml.5.3.0') as status_5_3_0,
    anyIf(log, compiler = 'ocaml.5.3.0') as log_5_3_0,
    anyIf(solution, compiler = 'ocaml.5.3.0') as solution_5_3_0,
    -- ... repeat for all compilers
FROM file('original.parquet', 'Parquet')
GROUP BY name
ORDER BY name
```

This transformation:
- Reduced row count from ~48,895 to ~4,500 (one row per package)
- Eliminated search operations - direct column access by name
- Preserved all data while optimising access patterns

The wide table restructure delivered the expected performance both in ClickHouse and OCaml.

```sh
time clickhouse local --query "
  SELECT log_5_3_0, solution_5_3_0      FROM file('restructured.parquet', 'Parquet')      WHERE name = '0install.2.18'"
# Result: 0.294 seconds
```

# Conclusion

There is no way to access a specific row within a column without loading (thus decompressing) the entire column. Given a column of ~50K rows, this takes a significant time. By splitting this table by compiler and by log, any given column which needs to be loaded is only ~4.5K rows make the application more responsive.

The wide table schema goes against my instincts for database table structure, and adds complexity when later using this dataset in other queries. This trade-off between performance and schema flexibility needs careful thought based on specific application requirements.

