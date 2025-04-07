---
layout: post
title:  "Box API with OCaml and Claude"
date:   2025-04-07 00:00:00 +0000
categories: OCaml, Box
tags: tunbury.org
image:
  path: /images/box-logo.png
  thumbnail: /images/box-logo.png
---

Over the weekend, I decided to extend my [Box](https://box.com) [tool](https://github.com/mtelvers/ocaml-box-diff) to incorporate file upload. There is a straightforward POST API for this with a `curl` one-liner given in the Box [documentation](https://developer.box.com/reference/post-files-content/). Easy.

The documentation for [Cohttp-eio.Client](https://mirage.github.io/ocaml-cohttp/cohttp-eio/Cohttp_eio/Client/index.html) only gives the function signature for `post`, but it looked pretty similar to `get`, which I had already been working with. The [README](https://github.com/mirage/ocaml-cohttp) for Cohttp gave me pause when I read this comment about multipart forms.

> Multipart form data is not supported out of the box but is provided by external libraries

Of the three options given, the second option looked abandoned, while the third said it didn’t support streaming, so I went with the first one [dionsaure/multipart_form](https://github.com/dinosaure/multipart_form).

The landing page included an example encoder. A couple of external functions are mentioned, and I found example code for these in [test/test.ml](https://github.com/dinosaure/multipart_form/blob/main/test/test.ml). This built, but didn’t work against Box. I ran `nc -l 127.0.0.1 6789` and set that as the API endpoint for both the `curl` and my application. This showed I was missing the `Content-Type` header in the part boundary. It should be `application/octet-stream`.

There is a `~header` parameter to `part`, and I hoped for a `Header.add` like the `Cohttp`, but sadly not. See the [documentation](https://ocaml.org/p/multipart_form/latest/doc/Multipart_form/Header/index.html). There is `Header.content_type`, but that returns the content type. How do you make it? `Header.of_list` requires a `Field.field list`.

In a bit of frustration, I decided to ask Claude. I’ve not tried it before, but I’ve seen some impressive demonstrations. My first lesson here was to be specific. Claude is not a mind reader. After a few questions, I got to this:

```ocaml
Field.(make Content_type.name (Content_type.v `Application `Octet_stream));
```

I can see why this was suggested as `Content_disposition.v` exists, but `Content_type.v` does not, nor does `Field.make`. Claude quickly obliged with a new version when I pointed this out but added the `Content_type` to the HTTP header rather than the boundary header. This went back and forth for a while, with Claude repeatedly suggesting functions which did not exist. I gave up.

On OCaml.org, the [multipart-form](https://ocaml.org/p/multipart_form/latest) documentation includes a _Used by_ section that listed `dream` as the only (external) application which used the library. From the source, I could see `Field.Field (field_name, Field.Content_type, v)`, which looked good.

There is a function `Content_type.of_string`. I used `:MerlinLocate` to find the source, which turned out to be an Angstrom parser which returns a `Content_type.t`. This led me to `Content_type.make`, and ultimately, I was able to write these two lines:

```ocaml
let v = Content_type.make `Application (`Iana_token "octet-stream") Content_type.Parameters.empty
let p0 = part ~header:(Header.of_list [ Field (Field_name.content_type, Content_type, v) ]) ...
```

As a relatively new adopter of OCaml as my language of choice, the most significant challenge I face is documentation, particularly when I find a library on opam which I want to use. I find this an interesting contrast to the others in the community, where it is often cited that tooling is the most significant barrier to adoption. In my opinion, the time taken to set up a build environment is dwarfed by the time spent in that environment iterating code.

I would like to take this opportunity to thank all contributors to opam repository for their time and effort in making packages available. This post mentions specific packages but only to illustrate my point.
