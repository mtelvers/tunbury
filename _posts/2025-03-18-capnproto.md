---
layout: post
title:  "Playing with Cap’n Proto"
date:   2025-03-17 00:00:00 +0000
categories: capnpproto
tags: tunbury.org
image:
  path: /images/capnproto-logo.png
  thumbnail: /images/capnproto-logo.png
---

Cap’n Proto has become a hot topic recently and while this is used for many OCaml-CI services, I spent some time creating a minimal application.

Firstly create a schema with a single interface whch accepts a file name and returns the content.

```
interface Foo {
  get      @0 (name :Text) -> (reply :Text);
}
```

This schema can then be compiled into the bindings for your required language. e.g. `capnp compile -o ocaml:. schema.capnp`

In practice this need not be done by hand as we can use a `dune` rule to do this.

```
(rule
 (targets foo_api.ml foo_api.mli)
 (deps    foo_api.capnp)
 (action (run capnp compile -o %{bin:capnpc-ocaml} %{deps})))
```

On the server side we now need to extend the automatically generate code to actually implement the interface.  This code is largely boilerplate.

```ocaml
module Api = Foo_api.MakeRPC(Capnp_rpc)

open Capnp_rpc.Std

let read_from_file filename = In_channel.with_open_text filename @@ fun ic -> In_channel.input_all ic

let local =
  let module Foo = Api.Service.Foo in
  Foo.local @@ object
    inherit Foo.service

    method get_impl params release_param_caps =
      let open Foo.Get in
      let name = Params.name_get params in
      release_param_caps ();
      let response, results = Service.Response.create Results.init_pointer in
      Results.reply_set results (read_from_file name);
      Service.return response
  end
```

The server needs to generate the capability file needed to access the service and wait for incoming connections.

```ocaml
let cap_file = "echo.cap"

let serve config =
  Switch.run @@ fun sw ->
  let service_id = Capnp_rpc_unix.Vat_config.derived_id config "main" in
  let restore = Restorer.single service_id (Foo.local) in
  let vat = Capnp_rpc_unix.serve ~sw ~restore config in
  match Capnp_rpc_unix.Cap_file.save_service vat service_id cap_file with
  | Error `Msg m -> failwith m
  | Ok () ->
    traceln "Server running. Connect using %S." cap_file;
    Fiber.await_cancel ()
```

The client application imports the capability file and calls the service `Foo.get`.

```ocaml
let run_client service =
  let x = Foo.get service "client.ml" in
  traceln "%S" x

let connect net uri =
  Switch.run @@ fun sw ->
  let client_vat = Capnp_rpc_unix.client_only_vat ~sw net in
  let sr = Capnp_rpc_unix.Vat.import_exn client_vat uri in
  Capnp_rpc_unix.with_cap_exn sr run_client
```

Where `Foo.get` is defined like this

```ocaml
module Foo = Api.Client.Foo

let get t name =
  let open Foo.Get in
  let request, params = Capability.Request.create Params.init_pointer in
  Params.name_set params name;
  Capability.call_for_value_exn t method_id request |> Results.reply_get
```

Run the server application passing it parameters of where to save the private key and which interface/port to listen on.

```sh
$ dune exec -- ./server.exe --capnp-secret-key-file ./server.pem --capnp-listen-address tcp:127.0.0.1:7000
+Server running. Connect using "echo.cap".
```

The `.cap` looks like this

```
capnp://sha-256:f5BAo2n_2gVxUdkyzYsIuitpA1YT_7xFg31FIdNKVls@127.0.0.1:7000/6v45oIvGQ6noMaLOh5GHAJnGJPWEO5A3Qkt0Egke4Ic
```

In another window, invoke the client.

```sh
$ dune exec -- ./client.exe ./echo.cap
```

The full code is available on [Github](https://github.com/mtelvers/capnp-minimum).
