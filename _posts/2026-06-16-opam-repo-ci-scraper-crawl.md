---
layout: post
title: "Scraping opam-repo-ci to a standstill"
date: 2026-06-16 21:00:00 +0000
categories: [ocaml, ci]
tags: tunbury.org
image:
  path: /images/opam.png
  thumbnail: /images/thumbs/opam.png
---

Jan reported that opam-repo-ci, [opam.ci.ocaml.org](https://opam.ci.ocaml.org), had become unresponsive.

The initial investigation found that the service had run out of file descriptors exactly as I had seen with OCaml CI. I quickly patched opam-repo-ci with [PR#473](https://github.com/ocurrent/ocurrent/pull/473) and restarted.

The service came back, but was again unresponsive after a few seconds. `docker log -f` showed a new batch of 4 lines like this every second. The service was at 100% CPU, and clicking anything in the browser just hung.

```
current.rpc [INFO] status("2026-02-15/151623-ci-ocluster-build-44fe2c")
current.rpc [INFO] log("2026-02-15/151623-ci-ocluster-build-44fe2c", 0)
opam_repo_ci.index [INFO] Index.get_full_hash ocaml/opam-repository f6ea578b...
opam_repo_ci.index [INFO] Index.get_job ocaml/opam-repository 8f131c distributions,fedora-43-ocaml-4.14,liquidsoap-js.2.4.2,tests
```

The job-id dates were all over the place, seemingly randomly plucked from the last six months. `Index.get_job` is only ever called from the Cap'n Proto API server in `api_impl.ml`:

```ocaml
method job_of_variant_impl params release_param_caps =
  ...
  match Index.get_job ~owner ~name ~hash ~variant with
```

So these were inbound API requests being served. The web UI sits in front of the engine and sends requests over Cap'n Proto:

```
caddy -> opam-repo-ci-web -> opam-repo-ci
```

Each request for a build page, in the format `/github/ocaml/opam-repository/commit/<hash>/variant/<variant>`, makes the web UI resolve the commit (`get_full_hash`), look up the job (`get_job`), then fetch its status and stream its log from offset 0 (`status`, `log(..., 0)`). Something was requesting thousands of logs for ancient builds. Scaling the web UI to zero confirmed it: the backend went instantly silent.

The Caddy access log showed the detail

```
"msg":"aborting with incomplete response","upstream":"opam-repo-ci-web:8090",
"uri":"/github/ocaml/opam-repository/commit/dfde9a91.../variant/compilers,4.14,conf-zlib.2,revdeps,sihl-cache.3.0.2",
"remote_ip":"186.237.127.102", ... "error":"reading: context canceled"
```

Hundreds of distinct IPs, each making only a handful of requests, all with `Accept-Language: zh-CN`, a selection of Chrome/Edge user-agents, and a `Referer` of the site root. Clearly, a distributed scraper farm was walking every per-variant build page in the repository's history.

I applied a block-by-user-agent rule, which only catches the honest bots (Amazonbot, GoogleOther, and friends) so this made virtually no difference here.

However, the farm header requests made it look distinct from a real visitor. A genuine fresh navigation (a typed URL or a bookmark) sends `Sec-Fetch-Site: none` and no `Referer`. A real click within the site sends `same-origin`; a click from a GitHub status check sends `cross-site`. The farm sends the contradictory combination of `Sec-Fetch-Site: none` with a same-site `Referer`. That is the tell, and it is trivial to match in Caddy:

```caddy
opam.ci.ocaml.org {
	route {
		@spoofnav {
			header Sec-Fetch-Site none
			header Referer *
		}
		respond @spoofnav 429

		handle /robots.txt {
			respond "User-agent: *
Disallow: /github/
" 200
		}

		reverse_proxy opam-repo-ci-web:8090
	}
}
```

After a `caddy reload`, I scaled the web UI back up, and the difference was immediate. Requests reaching the web UI dropped from roughly 2 per second to 2 per minute, and the engine could get back to work. Now the bots are turned away at Caddy with a `429` before they ever reach the web component, let alone the engine. Real users browsing from the commit page (`same-origin`) or arriving from GitHub (`cross-site`) are untouched.

This is a quick fix which will need further attention later. I was lucky that there was an easy-to-spot pattern to differentiate the requests. Going forward, I'll need to implement the Caddy rate limit plugin or hide the service behind Cloudflare.

