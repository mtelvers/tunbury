---
layout: post
title: "Label Maker in js_of_ocaml using Claude"
date: 2025-08-22 00:00:00 +0000
categories: js_of_ocaml,ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

I've taken a few days off, and while I've been travelling, I've been working on a personal project with Claude. I've used Claude Code for the first time, which is a much more powerful experience than using [claude.ai](https://claude.ai) as Claude can apply changes to the code and use your build tools directly to quickly iterate on a problem. In another first, I used `js_of_ocaml`, which has been awesome.

The project isn't anything special; it's a website that creates sheets of Avery labels. It is needed for a niche educational environment where the only devices available are iPads, which are administratively locked down, so no custom applications or fonts can be loaded. You enter what you want on the label, and it initiates the download of the resulting PDF.

The original [implementation](https://label.tunbury.org), written in OCaml (of course), uses a [cohttp](https://ocaml.org/p/cohttp/latest) web server, which generates a [reStructuredText](https://en.wikipedia.org/wiki/ReStructuredText) file which is processed via [rst2pdf](https://rst2pdf.org) with custom page templates for the different label layouts. The disadvantage of this approach is that it requires a server to host it. I have wrapped the application into a Docker container, so it isn't intrusive, but it would be easier if it could be hosted as a static file on GitHub Pages.

On OCaml.org, I found [camlpdf](https://ocaml.org/p/camlpdf/latest), [otfm](https://ocaml.org/p/otfm/latest) and [vg](https://ocaml.org/p/vg/latest), which when combined with `js_of_ocaml`, should give me a complete tool in the browser. The virtual file system embeds the TTF font into the JavaScript code!

I set Claude to work, which didn't take long, but the custom font embedding proved problematic. I gave Claude an example PDF from the original implementation, and after some debugging, we had a working project.

Let's look at the code! I should add that the labels can optionally have a box drawn on them, which the student uses to provide feedback on how they got on with the objective. Claude produced three functions for rendering text: one for a single line, one for multiline text with a checkbox, and one for multiline text without a checkbox. I pointed out that these three functions were similar and could be combined. Claude agreed and created a merged function with the original three functions calling the new merged function. It took another prompt to update the calling locations to call the new merged function rather than having the stub functions.

While Claude had generated code that compiles in a functional language, the code tends to look imperative; for example, there were several instances like this:

```ocaml
let t = ref 0 in
let () = List.iter (fun v -> t := !t + v) [1; 2; 3] in
t
```

Where we would expect to see a `List.fold_left`! Claude can easily fix these when you point them out.

As I mentioned earlier, Claude code can build your project and respond to `dune build` errors for you; however, some fixes suppress the warning rather than actually fixing the root cause. A classic example of this is:

```
% dune build
File "bin/main.ml", line 4, characters 4-5:
4 | let x = List.length lst
        ^
Error (warning 32 [unused-value-declaration]): unused value x.
```

The proposed fix is to discard the value of `x`, thus `let _x = List.length lst` rather than realising that the entire line is unnecessary as `List.length` has no side effects.

I'd been using Chrome 139 for development, but thought I'd try in the native Safari on my Monterey-based based MacPro which has Safari 17.6. This gave me this error on the JavaScript console.

```
[Error] TypeError: undefined is not 
  an object (evaluating 'k.UNSIGNED_MAX.udivmod')
          db (label_maker.bc.js:1758)
          (anonymous function) (label_maker.bc.js:1930)
          Global Code (label_maker.bc.js:2727:180993)
```

I found that since `js_of_ocaml` 6.0.1 the minimum browser version is Safari 18.2, so I switched to `js_of_ocaml` 5.9.1 and that worked fine.

The resulting project can be found at [mtelvers/label-maker-js](https://github.com/mtelvers/label-maker-js) and published at [mtelvers.github.io/label-maker-js](https://mtelvers.github.io/label-maker-js/).
