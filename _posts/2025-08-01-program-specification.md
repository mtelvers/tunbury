---
layout: post
title: "OCaml Program Specification for Claude"
date: 2025-08-01 00:00:00 +0000
categories: opam
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

I have a dataset that I would like to visualise using a static website hosted on GitHub Pages. The application that generates the dataset is still under development, which results in frequently changing data formats. Therefore, rather than writing a static website generator and needing to revise it continually, could I write a specification and have Claude create a new one each time there was a change?

Potentially, I could do this cumulatively by giving Claude the original specification and code and then the new specification, but my chosen approach is to see if Claude can create the application in one pass from the specification. I've also chosen to do this using Claude Sonnet's web interface; obviously, the code I will request will be in OCaml.

I wrote a detailed 500-word specification that included the file formats involved, example directory tree layouts, and what I thought was a clear definition of the output file structure.

The resulting code wasn't what I wanted: Claude had inlined huge swathes of HTML and was using `Printf.sprintf` extensively. Each file included the stylesheet as a `<style>...</style>`. However, the biggest problem was that Claude had chosen to write the JSON parser from scratch, and this code had numerous issues and wouldn't even build. I directed Claude to use `yojson` rather than handcraft a parser.

I intended but did not state in my specification that I wanted the code to generate HTML using `tyxml`. I updated my specification, requesting that the code be written using `tyxml`, `yojson`, and `timedesc` to handle the ISO date format. I also thought of some additional functionality around extracting data from a Git repo.

Round 2 - Possibly a step backwards as Claude struggled to find the appropriate functions in the `timedesc` library to parse and sort dates. There were also some issues extracting data using `git`. I have to take responsibility here as I gave the example command as `git show --date=iso-strict ce03608b4ba656c052ef5e868cf34b9e86d02aac -C /path/to/repo`, but `git` requires the `-C /path/to/repo` to precede the `show` command. However, the fact that my example had overwritten Claude's _knowledge_ was potentially interesting. Could I use this to seed facts I knew Claude would need?

Claude still wasn't creating a separate `stylesheet.css`.

Round 3 - This time, I gave examples on how to use the `timedesc` library, i.e.

> To use the `timedesc` library, we can call `Timedesc.of_iso8601` to convert the Git ISO strict output to a Timedesc object and then compare it with `compare (Timedesc.to_timestamp_float_s b.date) (Timedesc.to_timestamp_float_s a.date)`.

Also, in addition to stating that all the styles should be shared in a common `stylesheet.css`, I gave a file tree of the expected output, including the `stylesheet.css`. 

Claude now correctly used the `timedesc` library and tried to write a stylesheet. However, Claude had hallucinated a `css` and `css_rule` function in `tyxml` to do this, where none exists. Furthermore, adding the link to the stylesheet was causing problems as `link` had multiple definitions in scope and needed to be explicitly referenced as `Tyxml.Html.link`. Claude's style was to open everything at the beginning of the file:

```ocaml
open Yojson.Safe
open Yojson.Safe.Util
open Tyxml.Html
open Printf 
open Unix 
```

The compiler picked `Unix.link` rather than `Tyxml.Html.link`:

```
File "ci_generator.ml", line 347, characters 18-33:
347 |         link ~rel:[ `Stylesheet ] ~href:"/stylesheet.css" ();
                        ^^^^^^^^^^^^^^^
Error: The function applied to this argument has type
         ?follow:bool -> string -> unit
This argument cannot be applied with label ~rel
```

> Stylistically, please can we only `open` things in functions where they are used: `let foo () = let open Tyxml.Html in ...`. This will avoid global opens at the top of the file and avoid any confusion where libraries have functions with the same name, e.g., `Unix.link` and `TyXml.Html.link`.

Furthermore, I had two JSON files in my input, each with the field `name`. Claude converted these into OCaml types; however, when referencing these later as function parameters, the compiler frequently picks the wrong one. This can be _fixed_ by adding a specific type to the function parameter `let f (t:foo) = ...`. I've cheated here and renamed the field in one of the JSON files.

```ocaml
type foo = {
  name : string;
  x : string;
}

type bar = {
  name : string;
  y : string;
}
```

Claude chose to extract the data from the Git repo using `git show --pretty=format:'%H|%ai|%s'`, this  ignores the `--date=iso-strict` directive. The correct format should be `%aI`. I updated my guidance on the use of `git show`.

My specification now comes in just under 1000 words. From that single specification document, Claude produces a valid OCaml program on the first try, which builds the static site as per my design. `wc -l` shows me there are 662 lines of code.

It's amusing to run it more than once to see the variations in styling!
