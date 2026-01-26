---
layout: post
title: "Extending RPC capabilities in OCurrent"
date: 2026-01-26 12:00:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

As our workflows become more agentic, CLI tools are becoming preferred over web GUIs; OCurrent pipelines are no exceptions.

OCurrent already had an RPC endpoint which allowed functions such as listing active jobs, viewing a job log and rebuilding. [PR#469](https://github.com/ocurrent/ocurrent/pull/469) extends this, adding full pipeline observability and control, including statistics, state, history queries, bulk rebuild, and pipeline visualisation and configuration management. This all works over [Cap'n Proto](https://capnproto.org).

`rpc_client.ml` can be used as a standalone executable to query any OCurrent pipeline. Alternatively, by including the cmdliner term, your application can be its own client.

In the server code, the RPC endpoint must be specifically exposed. Many OCurrent applications do this already, such as the [Docker base image builder](https://github.com/ocurrent/docker-base-images). Any application which currently supports `--capnp-address`.

```ocaml
module Rpc = Current_rpc.Impl(Current)

(* In the main function, set up Cap'n Proto serving *)
let serve_rpc engine =
  let config = Capnp_rpc_unix.Vat_config.create ~secret_key ~public_address listen_address in
  let service = Rpc.engine engine in
  Capnp_rpc_unix.serve config service >>= fun vat ->
  Capnp_rpc_unix.Cap_file.save_service vat service cap_file
```

Then the [Cmdliner](https://github.com/dbuenzli/cmdliner) command group needs to be added.

```ocaml
let client_cmd =
  Current_rpc.Client.Cmdliner.client_cmd
      ~name:"client"
      ~cap_file:"/capnp-secrets/base-images.cap"
      ()

(* Add to your command group *)
let () =
  let cmds = [main_cmd; client_cmd] in
  exit @@ Cmdliner.Cmd.eval (Cmdliner.Cmd.group info cmds)
```

All 12 sub-commands are now available:-

```sh
base-images client overview
base-images client jobs
base-images client status <job_id>
base-images client log <job_id>
base-images client cancel <job_id>
base-images client rebuild <job_id>
base-images client start <job_id>
base-images client query [--ok=...] [--prefix=...] [--op=...] [--rebuild=...]
base-images client ops
base-images client dot
base-images client confirm [--set=...]
base-images client rebuild-all <job_id> ...
```

