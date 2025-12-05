---
layout: post
title: "Private repos in OCurrent"
date: 2025-12-05 11:30:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

[OCurrent](https://github.com/ocurrent/ocurrent) has long wanted to access private repositories. You can achieve this by embedding a scoped PAT in the `.git-credentials` file, typically within the Docker container; however, this is untidy, to say the least! The approach presented works in cases where a GitHub app is used.

OCurrent authenticates to GitHub using a JWT (JSON Web Token). This token is signed using the application's RSA private key (from `--github-private-key-file`) and contains the app_id. GitHub verifies this signature to confirm it's really from the GitHub app. OCurrent then calls `get_token`, which POSTs to GitHub's API to get an installation access token. This is a short-lived token (60 min) that can access the repositories the app has permission to. In summary, OCurrent already has the token, but there is no accessor function.

Git supports the `https://x-access-token:ghs_XXXX@github.com/...` access method to pass the password; however, OCurrent displays logs in real-time, so this would show in plain text on the web GUI. You can pass a custom pretty-print function and use it to mask the value. Alternatively, you can pass an environment variable to `git`, for example `GIT_CONFIG_PARAMETERS="'http.extraHeader=Authorization: Basic dXNlcjpwYXNz'"`.

I have added `get_cached_token`, which returns the cached token from the GitHub API plugin. Essentially, this is `let get_cached_token t = t.token`. This token then becomes the context parameter for the `git fetch` operation, replacing the original `No_context`.

The environment variable is created by calling `Base64.encode_string` on the `x-access-token:ghs_XXXX`.

```ocaml
let make_auth_env token =
  let b64 = Base64.encode_string ("x-access-token:" ^ token) in
  let header = Printf.sprintf "'http.extraHeader=Authorization: Basic %s'" b64 in
  [| "GIT_CONFIG_PARAMETERS=" ^ header |]
```

The remaining changes in the PR thread the `env` parameter through the `git` module to the `process` module, where it is ultimately passed to `Lwt_process.open_process`.

Therefore, considering the example, `doc/examples/github_app.ml`, the diff would be:

```ocaml
   Github.App.installations app |> Current.list_iter (module Github.Installation) @@ fun installation ->
+  Current.component "api" |>
+  let** inst = installation in
+  let github = Github.Installation.api inst in
   let repos = Github.Installation.repositories installation in
   repos |> Current.list_iter ~collapse_key:"repo" (module Github.Api.Repo) @@ fun repo ->
   Github.Api.Repo.ci_refs ~staleness:(Duration.of_day 90) repo
   |> Current.list_iter (module Github.Api.Commit) @@ fun head ->
-  let src = Git.fetch (Current.map Github.Api.Commit.id head) in
+  let token = Github.Api.get_cached_token github in
+  let src = Git.fetch ?token (Current.map Github.Api.Commit.id head) in
   Docker.build ~pool ~pull:false ~dockerfile (`Git src)
   |> check_run_status
   |> Github.Api.CheckRun.set_status head program_name
```

This adds an `api` node in the graph for each installation, which is semantically correct as the token is per organisation.

I considered that the token might be stale or uninitialised before the `Git.fetch` call, but the only way to get a `Github.Api.Commit.id` is through an API call, so the token will always be refreshed. When a webhook is received, it triggers the reevaluation of the graph, which again refreshes the API token.

ref [ocurrent/ocurrent PR#466](https://github.com/ocurrent/ocurrent/pull/466)
