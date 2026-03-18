---
layout: post
title: "A different way to interact with Claude"
date: 2026-03-18 15:20:00 +0000
categories: ocaml
tags: tunbury.org
image:
  path: /images/anthropic-logo.png
  thumbnail: /images/thumbs/anthropic-logo.png
---

We've all been using Claude via the prompt, and some have even ventured into running `claude --dangerously-skip-permissions` in a nice sandbox like [avsm/claude-ocaml-devcontainer](https://github.com/avsm/claude-ocaml-devcontainer).

I have a number of `tmux` sessions running and periodically ask the running Claude to check on the free disk space or review the output of a diagnostic command in the context of the current session, but it's still a prompt. I want Claude to do things regularly without prompting.

Claude accepts prompts on the command line `claude -p Hello`, so can this be extended to do something useful?

```sh
$ claude -p Hello
Hello! How can I help you today?
```

In your project directory (or globally), you can create `.claude/settings.local.json`. Perhaps as below. Note that the path `/` refers to the root of the project directory, and a double slash refers to the root of the file system. e.g. `//usr/bin`.

```
{
  "permissions": {
    "allow": [
      "Bash(ssh foo.bar *)",
      "Write(/README.md)",
      "Bash(git *)"
    ]
  }
}
```

However, this pattern matching is tiresome, `ssh foo.bar *` doesn't match `ssh -t foo.bar ...` as `-t` has invalidated the match, so you end up putting `ssh * foo.bar *` but then you _must_ have a parameter. Also, `git commit -m "my commit"` matches, but `git commit -m "my\nmultiline\ncomment"` does not. It was very frustrating. Thus, I abandoned permissions and went for a container and `--dangerously-skip-permissions`.

You can get started with a simple Dockerfile, but you might want to augment it later. In mine, I change the default user from `node:node` to be `mtelvers:mtelvers` to match my local machine.

```dockerfile
FROM node:22-trixie-slim
RUN apt update && install git -y
RUN npm install -g @anthropic-ai/claude-code
RUN usermod -l mtelvers -d /home/mtelvers -m node && \
    groupmod -n mtelvers node && \
    git config --system user.name "mtelvers" && \
    git config --system user.email "mtelvers@example.com"
```

I build the `Dockerfile` with `docker build -t bot .`, and execute it using a shell script `run.sh` which is a wrapper around `docker run`, setting my user uid and gid to match my local machine and mapping my `~/.claude` directory. I run Claude with `--output-format stream-json`, which outputs the JSON "thinking" in real time, which I filter through `jq`.

```sh
#!/bin/bash
set -euo pipefail

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/home/mtelvers \
  -v "$HOME/.claude:/home/mtelvers/.claude" \
  -v "$HOME/.claude/.claude.json:/home/mtelvers/.claude.json" \
  -v "$PWD:/work" \
  -w /work \
  test-bot claude --dangerously-skip-permissions --verbose --output-format stream-json -p "$@" 2>/dev/null | jq --unbuffered -r '
    if .type == "assistant" then
      .message.content[]? |
      if .type == "text" then "💬 \(.text)"
      elif .type == "tool_use" then "🔧 \(.name): \(.input | tostring | .[0:200])"
      else empty end
    elif .type == "result" then
      "📊 Cost: $\(.total_cost_usd // "?") | Duration: \(.duration_ms // "?")ms"
    else empty end
  '
```

I sync the uid/gid and username to avoid file permission issues.

Claude is now running in a container, but essentially operating in the same way as before:-

```sh
$ ./run.sh -p "What is the value of pi"
💬 

π ≈ 3.14159265358979323846…
📊 Cost: $0.017534 | Duration: 2691ms
```

The prompt is now the rest of the work. As an example, make the current directory a git repo with `git init .`, then create `NOTES.md` and run with `./run.sh -p "@NOTES.md"`.

```
This is a git repo containing our working notes. Follow the checklist below **in order**, completing every step. Do not skip any steps.

# Steps (complete ALL of these, in order, every run)

1. **Gather data** -- check the status of this machine - processes, load, disk etc
2. **Update NOTES.md** -- Rewrite this file with the latest status. Rules:
   - Keep the file well structured. Don't mix up knowledge with history.
   - Ask questions in the relevant section.
   - Summarise question answers into knowledge
3. **Git commit** -- Stage and commit NOTES.md with a descriptive commit message summarising what changed.

# Log

# Knowledge

# Questions
```

Claude dutifully follows things through, updates and commits `NOTES.md`.

```
This is a git repo containing our working notes. Follow the checklist below **in order**, completing every step. Do not skip any steps.

# Steps (complete ALL of these, in order, every run)

1. **Gather data** -- check the status of this machine - processes, load, disk etc
2. **Update NOTES.md** -- Rewrite this file with the latest status. Rules:
   - Keep the file well structured. Don't mix up knowledge with history.
   - Ask questions in the relevant section.
   - Summarise question answers into knowledge
3. **Git commit** -- Stage and commit NOTES.md with a descriptive commit message summarising what changed.

# Log

## 2026-03-18

- **Load average:** 4.23 / 8.31 / 9.60 (1/5/15 min)
- **Uptime:** ~35.2 days
- **Memory:** 189 GB total, ~88 GB available (MemFree: 1.3 GB, Buffers: 65 GB, Cached: 6.5 GB)
- **Disk (/):** 1.8 TB total, 1.1 TB used, 640 GB available (62% used)
- **CPU:** 40 cores — Intel Xeon E5-2640 v4 @ 2.40GHz
- **Kernel:** 6.8.0-100-generic
- **Hostname:** 119c0548ec30 (container)
- **Processes:** `ps` unavailable in this environment; /proc shows 1332 total threads, 5 currently running

# Knowledge

- This is a containerised environment (overlay filesystem, short hex hostname).
- The machine has 40 Xeon cores and ~189 GB RAM — a large server or VM.
- `uptime`, `free`, `ps`, and other common utilities are not installed; status must be gathered from `/proc` and `df`.
- Load is moderate relative to core count (4.2 / 8.3 / 9.6 on 40 cores).
- Disk is at 62% — not critical but worth monitoring.

# Questions

- What workloads are driving the 15-min load average of 9.6? (No `ps` available to inspect.)
- Is the low MemFree (1.3 GB) expected given the large buffer/cache usage, or is there memory pressure?
- What services run in this container? No process listing was available to determine this.
```

The exact issue (procps is missing from the container) and questions don't matter, but we have a workflow which can be invoked via cron. We could even push to a (private) GH repo so you can interact via GitHub.

I look after a number of CI workers... could this be extended to monitor those machines? We should acknowledge the risk here, but CI workers are ephemeral, and their cache is typically in tmpfs, so there is very little to lose and I auto reinstallation over the network.

I made the Dockerfile multistage by first building the [ocurrent/ocluster](https://github.com/ocurrent/ocluster) admin tools, and then copying them from the final stage.

I prepopulated the Knowledge section with details on how to use `ocluster-admin` to list pools and query them, and how to interpret the results. Once I was happy that this was working and that sufficient knowledge had been gained through Knowledge and Questions. For example, how to pause a worker before performing actions!

I took things to the next stage. I generated a new SSH key in the project directory and deployed it to a few workers. I mounted the key into the container by adding `-v "$PWD/ssh:/home/mtelvers/.ssh"` along with an `ssh_config` file. Then I added an additional step to the instructions: "SSH into workers or run commands to diagnose any problems found. Action outstanding items wherever possible -- fix anything you can."

Now, when a run finds a new issue, Claude actually debugs it and attempts to resolve it. Questions are still raised and answered in the same way.

This is an interesting experiment about how to interact with an AI agent beyond the prompt. The agent isn't answering questions or generating code for a human to review. It's executing a runbook against live systems, making judgment calls about what to fix, and maintaining its own operational documentation.

The git repo is the interface. I push instructions by editing NOTES.md. The agent pushes results by committing updates. It's version-controlled, auditable, asynchronous communication between a human and an AI agent about shared infrastructure.

Full disclosure: I manually invoke the script and monitor the output. I haven't yet let it run via cron, but I also haven't had to Control-C it either.
