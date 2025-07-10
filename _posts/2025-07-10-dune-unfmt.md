---
layout: post
title:  "dune unfmt"
date:   2025-07-10 00:00:00 +0000
categories: git
image:
  path: /images/GitHub-Mark-120px-plus.png
  thumbnail: /images/thumbs/GitHub-Mark-120px-plus.png
---

When working across machines, it's easy to make changes and reconcile them using git. However, I made a mistake and inadvertently ran `dune fmt` and now my `git diff` is a total mess.

My thought, to get myself out of this situation, is to go back to the previous commit and create a new branch with no changes other than a `dune fmt`. I can then cherry-pick my latest work on to that branch which should then give me a clean diff.

```sh
git commit -am 'inadvertent reformatted version'
```

Run `git log` to find the commit that was just made and the previous one.

Checkout the previous commit and make a new branch, in my case called `pre-fmt`.

```sh
git checkout <previous commit>
git switch -c pre-fmt
```

Format the code in this branch and commit that version.

```sh
dune fmt
git commit -am 'dune fmt'
```

Now cherry-pick the original commit.

```sh
git cherry-pick <latest commit>
```

The cherry-pick reports lots of merge conflicts; however, these should be trivial to resolve but it is a manual process. Once done, add the changed files and finish the cherry-pick.

```sh
git add bin/*.ml
git cherry-pick --continue
```

`git diff` now shows just the actual changes rather than the code formatting changes. Do you have any suggestions on a better workflow?
