---
layout: post
title: "Email as an interface to Claude"
date: 2026-03-26 20:00:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/anthropic-logo.png
  thumbnail: /images/thumbs/anthropic-logo.png
---

In my [previous post]({% post_url 2026-03-18-interact-with-claude %}), I described running Claude Code as a non-interactive agent by feeding it a runbook via `NOTES.md`, letting it SSH into workers, diagnose problems, and commit its findings back to git.

That works well for scheduled tasks, but what if you are out shopping and someone sends a message which requires urgent attention? You now want to be at your desk with all your normal tools available. So I built an email autoresponder backed by Claude Code: send an email to `your-claude-bot@gmail.com` with a question like "check disk space on server-1", and Claude processes it, runs the commands, and emails you back.

## The architecture

The autoresponder is a single OCaml binary that polls an IMAP mailbox, processes new messages through Claude Code running in Docker, and sends replies via SMTP. No mail server infrastructure required beyond an email account. It works with Gmail, Fastmail, or any provider with IMAP/SMTP.

```
  Inbound email
       |
       v
  IMAP client (poll for UNSEEN)
       |
       v
  S/MIME verification --> reject unsigned/untrusted
       |
       v
  Strip noise (quotes, signatures, session tokens)
       |
       v
  Session lookup (resume or create)
       |
       v
  Claude Code (docker run ... claude --output-format json -p "...")
       |
       v
  SMTP client (send reply with session token)
```

Session continuity is handled by embedding a `[Session: uuid.hmac]` token in the reply. When you reply to that email, the token routes your follow-up to the same Claude session via `--resume`, so context carries across the conversation. Thus, you can ask about a server in one message and have the context carry over, so a follow-up question doesn't need to reference the server a second time. 

## The security problem

An email autoresponder creates a serious security risk, and the more access keys you provide to Claude, the higher the risk, but the more useful the service would be.

Sender allow lists are trivially bypassed as spoofing an email From header is trivial and offers no authentication whatsoever. SPF and DKIM help at the domain level, but don't prevent a compromised account or a determined attacker.

A possible solution is S/MIME. Apple Mail has built-in support for signing emails with X.509 certificates. The autoresponder can verify the PKCS#7 signature against a pinned certificate before processing. Emails with an invalid signature are silently dropped. I've used `openssl cms -verify` with `-partial_chain` for self-signed certificate support:

```ocaml
let verify_raw_message ~trusted_certs raw_message =
  (* ... write to temp file ... *)
  let cert_args =
    List.concat_map
      (fun cert -> [ "-certfile"; cert; "-CAfile"; cert ])
      trusted_certs
  in
  let args = Array.of_list
    ([ "openssl"; "cms"; "-verify"; "-in"; msg_file;
       "-inform"; "SMIME"; "-purpose"; "any";
       "-partial_chain" ] @ cert_args)
  in
  (* ... *)
```

This is certificate pinning, not CA chain validation. Only the specific certificate in `trusted_certs` is accepted. An attacker generating their own self-signed cert with the same email address is rejected. The verification requires that the signature be made with the private key corresponding to the pinned certificate.

S/MIME is enabled by default. You can disable it for testing with `"require_smime": false`, but the autoresponder logs a warning at startup if you do.

As in my previous Git solution, Claude is running in a Docker container. This allows hard limits on what Claude can do, even with `--dangerously-skip-permissions`; however, you might choose to allow limited SSH access to hosts or create a limited GitHub account.

Other mitigations are layered but imperfect:

- Email noise is stripped before prompting; things like the quoted replies, signature separators, and session tokens are removed, so Claude only sees the new text
- Prompt length is capped at 100k characters
- Claude Code's own safety mechanisms provide some resistance
- A `CLAUDE.md` in the working directory can establish operational boundaries

## Session management

Sessions are persisted to a JSON file and keyed by HMAC-signed tokens. The HMAC binds each token to the sender's email address, so a token extracted from one conversation can't be used by a different sender. Sessions expire after a configurable TTL (default 24 hours).

The session token's primary purpose is session resumption, not authentication. It's the mechanism by which a reply-to-reply chains back to the same Claude context.

## Running it

The configuration is a single JSON file pointing at your email provider and Claude Code Docker image:

```json
{
  "imap": {
    "host": "imap.example.com",
    "port": 993,
    "username": "claude@example.com",
    "password": "app-password"
  },
  "smtp": {
    "host": "smtp.example.com",
    "port": 465,
    "username": "claude@example.com",
    "password": "app-password"
  },
  "claude": {
    "docker_image": "bot",
    "work_dir": "/path/to/workdir",
    "claude_dir": "/home/you/.claude",
    "docker_args": [],
    "extra_args": []
  },
  "hmac_secret": "generate-a-random-hex-string",
  "allowed_senders": ["you@example.com"],
  "reply_from": "claude@example.com",
  "require_smime": true,
  "trusted_certs": ["/path/to/your/cert.pem"]
}
```

Generate a self-signed S/MIME certificate, import the `.p12` into Apple Mail (or your client of choice), and sign your outgoing emails. The autoresponder rejects anything unsigned.

The code is available on GitHub [mtelvers/claude-autoresponder](https://github.com/mtelvers/claude-autoresponder). Use at your own risk!
