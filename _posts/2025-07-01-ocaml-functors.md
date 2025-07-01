---
layout: post
title: "OCaml Functors"
date: 2025-07-01 00:00:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/hot-functors.png
  thumbnail: /images/thumbs/hot-functors.png
---

In my OCaml project, I'd like to abstract away the details of running containers into specific modules based on the OS. Currently, I have working container setups for Windows and Linux, and I've haphazardly peppered `if Sys.win32 then` where I need differentiation, but this is OCaml, so let us use _functors_!

I started by fleshing out the bare bones in a new project. After `dune init project functor`, I created `bin/s.ml` containing the signature of the module `CONTAINER`.

```ocaml
module type CONTAINER = sig
  val run : string -> unit
end
```

Then a trivial `bin/linux.ml`.

```ocaml
let run s = Printf.printf "Linux container '%s'\n" s
```

And `bin/windows.ml`.

```ocaml
let run s = Printf.printf "Windows container '%s'\n" s
```

Then in `bin/main.ml`, I can select the container system once and from then on use `Container.foo` to run the appropriate OS specific function.

```ocaml
let container = if Sys.win32 then (module Windows : S.CONTAINER) else (module Linux : S.CONTAINER)

module Container = (val container)

let () = Container.run "Hello, World!"
```

You can additionally create `windows.mli` and `linux.mli` containing simply `include S.CONTAINER`.

Now, let's imagine that we needed to have some specific configuration options depending upon whether we are running on Windows or Linux. For demonstration purposes, let's use the user account. On Windows, this is a string, typically `ContainerAdministrator`, whereas on Linux, it's an integer UID of value 0.

We can update the module type in `bin/s.ml` to include the type `t`, and add an `init` function to return a `t` and add `t` as a parameter to `run`.

```ocaml
module type CONTAINER = sig
  type t

  val init : unit -> t
  val run : t -> string -> unit
end
```

In `bin/linux.ml`, we can add the type and define `uid` as an integer, then add the `init` function to return the populated structure. `run` now accepts `t` as the first parameter.

```ocaml
type t = {
  uid : int;
}

let init () = { uid = 0 }

let run t s = Printf.printf "Linux container user id %i says '%s'\n" t.uid s
```

In a similar vein, `bin/windows.ml` is updated like this

```ocaml
type t = {
  username : string;
}

let init () = { username = "ContainerAdministrator" }

let run t s = Printf.printf "Windows container user name %s says '%s'\n" t.username s
```

And finally, in `bin/main.ml` we run `Container.init ()` and use the returned type as a parameter to `Container.run`.

```ocaml
let container = if Sys.win32 then (module Windows : S.CONTAINER) else (module Linux : S.CONTAINER)

module Container = (val container)

let c = Container.init ()
let () = Container.run c "Hello, World!"
```
