---
layout: post
title: "Apache Parquet Files"
date: 2025-09-17 21:00:00 +0000
categories: apache,parquet
tags: tunbury.org
image:
  path: /images/apache-parquet-logo.png
  thumbnail: /images/thumbs/apache-parquet-logo.png
---

If you haven't discovered the [Apache Parquet](https://parquet.apache.org) file format, allow me to introduce it along with [ClickHouse](https://clickhouse.com). 

Parquet is a columnar storage file format designed for analytics and big data processing. Data is stored by column rather than by row, there is efficient compression, and the file contains the schema definition.

On Ubuntu, you first need to add the ClickHouse repository.

```
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | sudo gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | sudo tee /etc/apt/sources.list.d/clickhouse.list
```

Update and install - I'm going to use `clickhouse local`, so I only need the client.

```
apt update
apt install -y clickhouse-client
```

Given the JSON file below, you can use ClickHouse to run SQL queries on it directly: `clickhouse local --query "SELECT * FROM file('x.json')"`

```json
[
  {
    "name": "0install-gtk.2.18",
    "status": "no_solution",
    "sha": "d0b74334d458c26f4b769b9b5819f7af222b159c",
    "solution": "Can't find all required versions.",
    "os": "debian-12",
    "compiler": "ocaml-base-compiler.5.4.0~beta1"
  }
]
```

Powerfully, the `file` parameter can contain wildcards, such as`*.json`, in which case the `SELECT` is performed across all the files.

In my examples below, the JSON file is 573MB. Let's try to find all the records where `status = "no_solution".

We could use `jq` with a command like `jq 'map(select(.status == "no_solution")) | length' commit.json`. This takes over 2 seconds on my machine. Cheating and using `grep no_solution commit.json | wc -l` takes 0.2 seconds.

Using ClickHouse on the same datasource, `clickhouse local --query "SELECT COUNT() FROM file('commit.json') WHERE status = 'no_solution'"` matches the performance of `grep` returning the count in 0.2 seconds.

Converting the JSON into Parquet format is straightforward. The output file size is an amazing 24MB. Contrast that with `gzip -9 commit.json`, which creates a file of 33MB!

```
clickhouse local --query "SELECT * FROM file('commit.json', 'JSONEachRow') INTO OUTFILE 'commit.parquet' FORMAT Parquet"
```

Now running our query again: `clickhouse local --query "SELECT COUNT() FROM file('commit.parquet') WHERE status = 'no_solution'"`. Just over 0.1 seconds.

How can I use these in my OCaml project? [LaurentMazare/ocaml-arrow](https://github.com/LaurentMazare/ocaml-arrow) has created extensive OCaml bindings for Apache Arrow using the C++ API. This supports versions 4 and 5, but the current implementation is version 21. I have an updated commit which works on version 21 and C++ 17. [mtelvers/ocaml-arrow/tree/arrow-21-cpp17](https://github.com/mtelvers/ocaml-arrow/tree/arrow-21-cpp17)

I have also reimplemented the bulk of the library using the OCaml Standard Library which is available in [mtelvers/arrow](https://github.com/mtelvers/arrow)
