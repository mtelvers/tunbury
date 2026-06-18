---
layout: post
title: "A proof-of-work puzzle"
date: 2026-06-18 21:00:00 +0000
categories: [ocaml, ocurrent]
tags: tunbury.org
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
---

This post explores two more sustainable solutions to the crawler bots issue affecting [opam-repo-ci]({% post_url 2026-06-16-opam-repo-ci-scraper-crawl %})

As I mentioned last time, I was very lucky that the specific scraping activity had an easy pattern, but I wasn't content to hope that the next time would be as easy to spot. Adding plugins to Caddy is easy with `xcaddy`. It's also a bit tiresome as you need to build a new `Dockerfile` and push that. [ocurrent/caddy-ratelimit](https://github.com/ocurrent/caddy-ratelimit) add [mholt/caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) to a Caddy.

```dockerfile
FROM caddy:builder AS builder
RUN xcaddy build --with github.com/mholt/caddy-ratelimit
FROM caddy:alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

The important detail in the configuration is the key. If we impose a per-IP rate limit, we wouldn't catch the bots, which use multiple IP addresses, as we saw earlier. So the zone uses a constant key to provide an overall rate limit to the `variant` path for used to read the logs regardless of how many IPs are involved:

```caddy
rate_limit {
	zone opam_variant {
		match { path */variant/* }
		key    static
		events 10
		window 1s
	}
}
```

In addition to the main website at [opam.ci.ocaml.org](https://opam.ci.ocaml.org), the backend ocurrent engine is also exposed to the Internet to receive push notification events and for diagnostic purposes.

This `/job/` endpoint was also being crawled. A quick `grep | sort | uniq -c` showed a massive interest in historic CI results, which just isn't real users:

```
127  /job/2023-07     279  /job/2024-06     572  /job/2025-11
 70  /job/2024-02     141  /job/2024-12     683  /job/2026-04   ...
```

I decided to use an alternative strategy on ocurrent, largely to see the effect of different strategies. I liked the idea of [TecharoHQ/Anubis](https://github.com/TecharoHQ/anubis), which implements a reverse proxy that makes the browser solve a proof-of-work puzzle in JavaScript before it forwards the request. Bots running cheap HTTP clients can't run JavaScript, so they never get through.

I could have added another Docker container to the stack, so I'd have Caddy -> Anubis -> ocurrent, but that felt a little cumbersome, and also, if it worked, I'd need to roll that out everywhere. The ocurrent web engine already knows the paths, and it would only need to return a challenge on the appropriate browsable pages. With that in place, all our ocurrent engines could benefit.

The code is inserted in the request handler before routing, and only acts on `GET` requests whose `Accept` contains `text/html`, thus a stylesheet (`Accept: text/css`), a webhook (`POST`) or a Prometheus scrape on `/metrics` goes straight through:

```ocaml
let is_html_get =
  meth = `GET &&
  (match Cohttp.Header.get headers "accept" with
   | Some a -> Astring.String.is_infix ~affix:"text/html" a
   | None -> false)
```

A visitor gets a challenge request as a temporary holding page with the challenge parameters in `data-*` attributes, and a static JavaScript solver. The browser hunts for a nonce whose hash has enough leading zero bits, then redirects to a verify endpoint that re-checks the work and sets a signed cookie:

```javascript
let nonce = 0;
for (;;) {
  const buf = await crypto.subtle.digest("SHA-256", enc.encode(challenge + ":" + nonce));
  if (leadingZeroBits(new Uint8Array(buf)) >= difficulty) break;
  nonce++;
}
```

Currently, it's an opt-in option for ocurrent which can be turned on for a site using the optional `~challenge` argument:

```ocaml
Current_web.Site.v ?authn ~has_role
  ~challenge:(Current_web.Challenge.v ~difficulty ())
  routes
```

Cloudflare and Anubis both show "Checking your browser..." but that bothers me as we aren't checking anything about the browser: we're asking it to burn a little CPU. So the message says: "Your browser is solving a small proof-of-work puzzle to keep automated scrapers out."

This keeps out anyone who isn't using JavaScript. They never try to solve the puzzle. The proof-of-work generates a cookie that allows it access to the site. The cookie has a short lifespan, but nothing prevents it from being shared across different IPs. That could be added, but it's a trade-off in terms of annoyance and how often a mobile user might see the page. However, I've set the default difficulty of the challenge to be less than one second because harder puzzles don't make it safer.

The initial assessment showed an immediate drop in crawler traffic, but I'll monitor it over the coming days. [PR#475](https://github.com/ocurrent/ocurrent/pull/475)


