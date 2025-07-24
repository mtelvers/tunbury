---
layout: post
title:  "Tarides Website"
date:   2025-07-24 00:00:00 +0000
categories: tarides
image:
  path: /images/tarides.png
  thumbnail: /images/thumbs/tarides.png
---

Bella was in touch as the tarides.com website is no longer building. The initial error is that `cmarkit` was missing, which I assumed was due to an outdated PR which needed to be rebased.

```dockerfile
#20 [build 13/15] RUN ./generate-images.sh
#20 0.259 + dune exec -- src/gen/main.exe file.dune
#20 2.399     Building ocaml-config.3
#20 9.486 File "src/gen/dune", line 7, characters 2-9:
#20 9.486 7 |   cmarkit
#20 9.486       ^^^^^^^
#20 9.486 Error: Library "cmarkit" not found.
#20 9.486 -> required by _build/default/src/gen/main.exe
#20 10.92 + dune build @convert
#20 18.23 Error: Alias "convert" specified on the command line is empty.
#20 18.23 It is not defined in . or any of its descendants.
#20 ERROR: process "/bin/sh -c ./generate-images.sh" did not complete successfully: exit code: 1
```

The site recently moved to Dune Package Management, so this was my first opportunity to dig into how that works. Comparing the current build to the last successful build, I can see that `cmarkit` was installed previously but isn't now.

```
#19 [build 12/15] RUN dune pkg lock && dune build @pkg-install
#19 25.39 Solution for dune.lock:
...
#19 25.39 - cmarkit.dev
...
```

Easy fix, I added `cmarkit` to the `.opam` file. Oddly, it's in the `.opam` file as a pinned depend. However, the build now fails with a new message:

```dockerfile
#21 [build 13/15] RUN ./generate-images.sh
#21 0.173 + dune exec -- src/gen/main.exe file.dune
#21 2.582     Building ocaml-config.3
#21 10.78 File "src/gen/grant.ml", line 15, characters 5-24:
#21 10.78 15 |   |> Hilite.Md.transform
#21 10.78           ^^^^^^^^^^^^^^^^^^^
#21 10.78 Error: Unbound module "Hilite.Md"
#21 10.81 File "src/gen/blog.ml", line 142, characters 5-24:
#21 10.81 142 |   |> Hilite.Md.transform
#21 10.81            ^^^^^^^^^^^^^^^^^^^
#21 10.81 Error: Unbound module "Hilite.Md"
#21 10.82 File "src/gen/page.ml", line 52, characters 5-24:
#21 10.82 52 |   |> Hilite.Md.transform
#21 10.82           ^^^^^^^^^^^^^^^^^^^
#21 10.82 Error: Unbound module "Hilite.Md"
#21 10.94 + dune build @convert
#21 19.46 Error: Alias "convert" specified on the command line is empty.
#21 19.46 It is not defined in . or any of its descendants.
#21 ERROR: process "/bin/sh -c ./generate-images.sh" did not complete successfully: exit code: 1
```

Checking the [hilite](https://opam.ocaml.org/packages/hilite/hilite.0.5.0/) package, I saw that there had been a new release last week. The change log lists:

* Separate markdown package into an optional hilite.markdown package

Ah, commit [aaf60f7](https://github.com/patricoferris/hilite/commit/529cb756b05dd15793c181304f438ba1aa48f12a) removed the dependency on `cmarkit` by including the function `buffer_add_html_escaped_string` in the `hilite` source.

Pausing for a moment, if I constrain `hilite` to 0.4.0, does the site build? Yes. Ok, so that's a valid solution. How hard would it be to switch to 0.5.0?

I hit a weird corner case as I was unable to link against `hilite.markdown`. I chatted with Patrick, and I recreated my switch, and everything worked.

```
File "x/dune", line 3, characters 20-35:
3 |  (libraries cmarkit hilite.markdown))
                        ^^^^^^^^^^^^^^^
Error: Library "hilite.markdown" not found.
-> required by library "help" in _build/default/x
-> required by _build/default/x/.help.objs/native/help__X.cmx
-> required by _build/default/x/help.a
-> required by alias x/all
-> required by alias default
```

Talking with Jon later about a tangential issue of docs for optional submodules gave me a sudden insight into the corner I'd found myself in. The code base depends on `hilite`, so after running `opam update` (to ensure I would get version 0.5.0), I created a new switch `opam switch create . --deps-only`, and opam installed 0.5.0. When I ran `dune build`, it reported a missing dependency on `cmarkit`, so I dutifully added it as a dependency and ran `opam install cmarkit`. Do you see the problem? `hilite` only builds the markdown module when `cmarkit` is installed. If both packages are listed in the opam file when the switch is created, everything works as expected.

The diff turned out to be pretty straightforward.

```ocaml
 let html_of_md ~slug body =
   String.trim body
   |> Cmarkit.Doc.of_string ~strict:false
-  |> Hilite.Md.transform
+  |> Hilite_markdown.transform
   |> Cmarkit_html.of_doc ~safe:false
   |> Soup.parse
   |> rewrite_links ~slug
```

Unfortunately, the build still does not complete successfully. When Dune Package Management builds `hilite`, it does not build the markdown module even though `cmarkit` is installed. I wish there was a `dune pkg install` command!

I tried to split the build by creating a .opam file which contained just `ocaml` and `cmarkit`, but this meant running `dune pkg lock` a second time, and that caused me to run straight into [issue #11644](https://github.com/ocaml/dune/issues/11644).

Perhaps I can patch `hilite` to make Dune Package Management deal with it as opam does? Jon commented earlier that `cmarkit` is listed as a `with-test` dependency. opam would use it if it were present, but perhaps Dune Package Management needs to be explicitly told that it can? I will add `cmarkit` as an optional dependency - I added `mdx` as well for good measure.

```
depends: [
  "dune" {>= "3.8"}
  "mdx" {>= "2.4.1" & with-test}
  "cmarkit" {>= "0.3.0" & with-test}
  "textmate-language" {>= "0.3.3"}
  "odoc" {with-doc}
]
depopts: [
  "mdx" {>= "2.4.1"}
  "cmarkit" {>= "0.3.0"}
]
```

With my [branch](https://github.com/mtelvers/hilite/tree/depopts) of `hilite`, the website builds again with Dune Package Management.

I have created a [PR#27](https://github.com/patricoferris/hilite/pull/27) to see if Patrick would be happy to update the package.

Feature request for Dune Package Management would be the equivalent of `opam option --global archive-mirrors="https://opam.ocaml.org/cache"` as a lengthy `dune pkg lock` may fail due to a single `curl` failure and need to be restarted from scratch.

