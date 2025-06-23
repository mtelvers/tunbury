---
layout: post
title: "Static linking in OCaml"
date: 2025-06-17 00:00:00 +0000
categories: OCaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
permalink: /static-linking/
---


Most of the time, you don't think about how your file is linked. We've come to love dynamically linked files with their small file sizes and reduced memory requirements, but there are times when the convenience of a single binary download from a GitHub release page is really what you need.

To do this in OCaml, we need to add `-ccopt -static` to the `ocamlopt`. I'm building with `dune`, so I can configure that in my `dune` file using a `flags` directive.

```
(flags (:standard -ccopt -static))
```

This can be extended for maximum compatibility by additionally adding `-ccopt -march=x86-64`, which ensures the generated code will run on any x86_64 processor and will not use newer instruction set extensions like SSE3, AVX, etc.

So what about Windows? The Mingw tool chain accepts `-static`. Including `(flags (:standard -ccopt "-link -Wl,-static -v"))` got my options applied to my `dune` build:

```
x86_64-w64-mingw32-gcc -mconsole  -L. -I"C:/Users/Administrator/my-app/_opam/lib/ocaml" -I"C:\Users\Administrator\my-app\_opam\lib\mccs" -I"C:\Users\Administrator\my-app\_opam\lib\mccs\glpk/internal" -I"C:\Users\Administrator\my-app\_opam\lib\opam-core" -I"C:\Users\Administrator\my-app\_opam\lib\sha" -I"C:/Users/Administrator/my-app/_opam/lib/ocaml\flexdll" -L"C:/Users/Administrator/my-app/_opam/lib/ocaml" -L"C:\Users\Administrator\my-app\_opam\lib\mccs" -L"C:\Users\Administrator\my-app\_opam\lib\mccs\glpk/internal" -L"C:\Users\Administrator\my-app\_opam\lib\opam-core" -L"C:\Users\Administrator\my-app\_opam\lib\sha" -L"C:/Users/Administrator/my-app/_opam/lib/ocaml\flexdll" -o "bin/main.exe" "C:\Users\ADMINI~1\AppData\Local\Temp\2\build_d62d04_dune\dyndllb7e0e8.o" "@C:\Users\ADMINI~1\AppData\Local\Temp\2\build_d62d04_dune\camlrespec7816"   "-municode" "-Wl,-static"
```

However, `ldd` showed that this wasn't working:

```
$ ldd main.exe | grep mingw
        libstdc++-6.dll => /mingw64/bin/libstdc++-6.dll (0x7ffabf3e0000)
        libgcc_s_seh-1.dll => /mingw64/bin/libgcc_s_seh-1.dll (0x7ffac3130000)
        libwinpthread-1.dll => /mingw64/bin/libwinpthread-1.dll (0x7ffac4b40000)
```

I tried _a lot_ of different variations. I asked Claude... then I asked [@dra27](https://www.dra27.uk/blog/) who recalled @kit-ty-kate working on this for opam. [PR#5680](https://github.com/ocaml/opam/pull/5680)

The issue is the auto-response file, which precedes my static option. We can remove that by adding `-noautolink`, but now we must do all the work by hand and build a massive command line.

```
(executable
 (public_name main)
 (name main)
 (flags (:standard -noautolink -cclib -lunixnat -cclib -lmccs_stubs -cclib -lmccs_glpk_stubs -cclib -lsha_stubs -cclib -lopam_core_stubs -cclib -l:libstdc++.a -cclib -l:libpthread.a -cclib -Wl,-static -cclib -ladvapi32 -cclib -lgdi32 -cclib -luser32 -cclib -lshell32 -cclib -lole32 -cclib -luuid -cclib -luserenv -cclib -lwindowsapp))
 (libraries opam-client))
```

It works, but it's not for the faint-hearted.

I additionally added `(enabled_if (= %{os_type} Win32))` to my rule so it only runs on Windows.
