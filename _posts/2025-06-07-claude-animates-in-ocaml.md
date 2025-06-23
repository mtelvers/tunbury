---
layout: post
title: "Animating 3D models in OCaml with Claude"
date: 2025-06-07 00:00:00 +0000
categories: claude,collada,gltf
tags: tunbury.org
image:
  path: /images/human.png
  thumbnail: /images/thumbs/human.png
permalink: /claude-animates-in-ocaml/
---

In the week, Jon mentioned [UTM](https://mac.getutm.app), which uses Apple's Hypervisor virtualisation framework to run ARM64 operating systems on Apple Silicon. It looked awesome, and the speed of virtualised macOS was fantastic. It also offers x86_64 emulation; we mused how well it would perform running Windows, but found it disappointing.

I was particularly interested in this because I am stuck in the past with macOS Monterey on my Intel Mac Pro 'trashcan', as I have a niche Windows application that I can't live without. A few years ago, I got a prototype running written in Swift. I never finished it as other events got in the way. The learning curve of [SceneKit and Blender](https://youtu.be/8Jb3v2HRv_E) was intense. I still had the Collada files on my machine and today, of course, we have Claude.

"How would I animate a Collada (.dae) file using OCaml?". Claude acknowledged the complexity and proposed that `lablgl`, the OCaml bindings for OpenGL, would be a good starting point. Claude obliged and wrote the entire pipeline, giving me opam commands and Dune configuration files.

The code wouldn't build, so I looked for the API for `labgl`. The library seemed old, with no recent activity. I mentioned this to Claude; he was happy to suggest an alternative approach of `tgls`, thin OpenGL bindings, with `tsdl`, SDL2 bindings, or the higher-level API from `raylib`. The idea of a high-level API sounded better, so I asked Claude to rewrite it with `raylib`.

The code had some compilation issues. Claude had proposed `Mesh.gen_cube`, which didn't exist. Claude consulted the API documentation and found `gen_mesh_cube` instead. This went through several iterations, with `Model.load` becoming `load_model` and `Model.draw_ex` becoming `draw_model_ex`, etc. Twenty-two versions later, the code nearly compiles. This block continued to fail with two issues. The first being `Array.find` doesn't exist and the second being that the type inferred for `a` was wrong. There are two types and they both contain `target: string;`. I manually fixed this with `(a:animation_channel)` and used `match Array.find_opt ... with` instead of the `try ... with`.

```ocaml
(* Update animations *)
let update_object_animations objects animations elapsed_time =
  Array.map (fun obj ->
    try
      let anim = Array.find (fun a -> a.target = obj.name) animations in
      (* Loop animation *)
      let loop_time = mod_float elapsed_time anim.duration in
      let new_transform = interpolate_animation anim loop_time in
      { obj with current_transform = new_transform }
    with
      Not_found -> obj
  ) objects
```

There were still many unused variables, but the code could be built using `dune build --release`.

Unfortunately, it couldn't load my Collada file as the load functions were just stubs! Claude duly obliged and wrote a simple XML parser using regular expressions through the `Str` library, but interestingly suggested that I include `xmlm` as a dependency. Adding the parser broke the code, and it no longer compiled. The issue was similar to above; the compiler had inferred a type that wasn't what Claude expected. I fixed this as above. The code also had some issues with the ordering - functions were used before they were defined. Again, this was an easy fix.

The parser still didn't work, so I suggested ditching the regular expression-based approach and using `xmlm` instead. This loaded the mesh; it looked bad, but I could see that it was my mesh. However, it still didn't animate, and I took a wrong turn here. I told Claude that the Collada file contained both the mesh and the animation, but that's not right. It has been a while since I created the Collada files, and I had forgotten that the animation and the mesh definitions were in different files.

I asked Claude to improve the parser so that it would expect the animation data to be in the same file as the mesh. This is within the specification for Collada, but this was not the structure of my file.

Is there a better approach than dealing with the complexity of writing a Collada XML parser? What formats are supported by `raylib`?

In a new thread, I asked, "Using OCaml with Raylib, what format should I use for my 3D mode and animation data?". Claude suggested GLTF 2.0. As my animation is in Blender, it can be exported in GLTF format. Let's try it!

Claude used the `raylib` library to read and display a GLTF file and run the animation. The code was much shorter, but ... it didn't compile. I wrote to Claude, "The API for Raylib appears to be different to the one you have used. For example, `camera3d.create` doesn't take named parameters, `camera3d.prespective` should be `cameraprojection.perspective` etc."  We set to work, and a dozen versions later, we built it successfully.

It didn't work, though; the console produced an error over and over:

```
Joint attribute data format not supported, use vec4 u8
```

This looked like a problem with the model. I wondered if my GLTF file was compatible with `raylib`. I asked Claude if he knew of any validation tools, and he suggested an online viewer. This loaded my file perfectly and animated it in the browser. Claude also gave me some simple code to validate, which only loaded the model.

```ocaml
let main () =
  init_window 800 600 "Static Model Test";
  let camera = Camera3D.create
    (Vector3.create 25.0 25.0 25.0)
    (Vector3.create 0.0 0.0 0.0)
    (Vector3.create 0.0 1.0 0.0)
    45.0 CameraProjection.Perspective in

  let model = load_model "assets/character.gltf" in

  while not (window_should_close ()) do
    begin_drawing ();
    clear_background Color.darkgray;
    begin_mode_3d camera;
    draw_model model (Vector3.create 0.0 0.0 0.0) 1.0 Color.white;
    draw_grid 10 1.0;
    end_mode_3d ();
    draw_text "Static Model Test" 10 10 20 Color.white;
    end_drawing ()
  done;

  unload_model model;
  close_window ()
```

Even this didn't work! As I said at the top, it's been a few years since I looked at this, and I still had Blender installed on my machine: version 2.83.4. The current version is 4.4, so I decided to upgrade. The GLTF export in 4.4 didn't work on my Mac and instead displayed a page of Python warnings about `numpy`. On the Blender Forum, this [thread](https://blenderartists.org/t/multiple-addons-giving-numpy-errors-blender-4-4-mac/1590436/2) showed me how to fix it. Armed with a new GLTF file, the static test worked. Returning to the animation code showed that it worked with the updated file; however, there are some significant visual distortions. These aren't present when viewed in Blender, which I think comes down to how the library interpolates between keyframes. I will look into this another day.

I enjoyed the collaborative approach. I'm annoyed with myself for not remembering the separate file with the animation data. However, I think the change of direction from Collada to GLTF was a good decision, and the speed at which Claude can explore ideas is very impressive.

