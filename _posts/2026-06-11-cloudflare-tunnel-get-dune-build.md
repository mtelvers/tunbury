---
layout: post
title: "Putting get.dune.build behind a Cloudflare Tunnel"
date: 2026-06-11 18:00:00 +0000
categories: [dune, ci, cloudflare]
tags: tunbury.org
image:
  path: /images/dune-logo.png
  thumbnail: /images/thumbs/dune-logo.png
---

There have been reports that get.dune.build is unreliable when used via GitHub Actions.

Specifically, users see this error in their GHA log:

```
+ curl -fsSL https://get.dune.build/install
* Host get.dune.build:443 was resolved.
* IPv6: (none)
* IPv4: 128.232.124.216
*   Trying 128.232.124.216:443...
* connect to 128.232.124.216 port 443 from 10.1.0.194 port 40592 failed: Connection timed out
* Failed to connect to get.dune.build port 443 after 134880 ms: Couldn't connect to server
curl: (28) Failed to connect to get.dune.build port 443 after 134880 ms: Couldn't connect to server
```

The initial investigation centred around an issue with the server itself. I set up monitoring from another machine on the local network, as well as a machine at home and in a different datacenter, both in the UK and the US. These all had 100% reliably connections. I wrote a small Prometheus monitoring agent to handle the actual polling. This way, I could be sure it was performing the `curl` function in the same way as the setup script, and testing all published IP addresses. [mtelvers/mon](https://github.com/mtelvers/mon)

`get.dune.build` is a Caddy file server running in a Docker container, a pattern I have in countless other places.

Samuel mentioned that the reliability was 1 in 5 or 1 in 10 failures. The same workflow had five `ubuntu-latest` jobs, all started in the same second. Four of them installed Dune in under 45 seconds, while the fifth failed. This meant the server was both working and not working at the same time, depending upon where you connect from.

I forked `setup-dune` and added a workflow that fans out across a large matrix of runners. Each runner records its public egress IP, then probes a handful of targets with a short connect timeout:

{% raw %}
```yaml
probe:
  needs: prep
  strategy:
    fail-fast: false
    max-parallel: 256
    matrix:
      i: ${{ fromJson(needs.prep.outputs.matrix) }}
  runs-on: ubuntu-latest
  steps:
    - name: Probe targets
      run: |
        EGRESS=$(curl -4 -s --max-time 10 https://api.ipify.org)
        probe() {
          tc=$(curl -"$1" -sS -o /dev/null --connect-timeout "$CT" \
                 -w '%{time_connect}' "$3" 2>/dev/null); rc=$?
          if [ "$rc" = 28 ]; then echo "$2:BLOCKED"; else echo "$2:reached"; fi
        }
        probe 4 dune   https://get.dune.build/install
        probe 4 cam    https://128.232.124.158/        # a different Cambridge host
        probe 4 dl2    https://dl2.geotessera.org      # another different subnet
        probe 4 github https://github.com
        probe 4 cf     https://1.1.1.1
```
{% endraw %}

Running 60 runners reproduced it immediately and consistently. Between 15 and 20 of every 60 runners failed, that's around 25-30%. Crucially, every failing runner failed all of its attempts for `get.dune.build`, not just some of them.

Probing multiple hosts shows that it was just the Cambridge network which GHA doesn't like:

```
egress=57.151.129.38 status=FAIL
  dune:BLOCKED   cam:BLOCKED dl2:BLOCKED
  github:reached cf:reached  eu:reached
```

The blocked runners reach GitHub, Cloudflare, and (I added it later) the EU institutions website in single-digit milliseconds, but they cannot reach `get.dune.build` or the unrelated hosts on the same Cambridge subnet. It is not `get.dune.build` specifically, it's anything on the Cambridge subnet.

`traceroute` from the runner was useless as Azure blocked ICMP, so you get a column of `* * *`. But I have access to `get.build.build`, so I ran the trace from the other end: a `tcpdump` on the origin during a fresh 60-runner sweep, then cross-referenced the captured SYNs against the run's results:

```
46/46 successful-probe IPs were seen arriving at the server
 0/14 failing-probe IPs were seen arriving
```

The failing runners' SYNs never reach Cambridge. The drop is somewhere out on the path between GitHub's Azure egress addresses and the JANET/Cambridge border. GitHub-hosted runners have no IPv6 at all, so my idea of just using IPv6 was a non-starter.

I had a bunch of GHA logs, now so I could analyse them a bit. This showed that there were 405 unique IPs spread over 88 distinct /16 subnets. Reviewing the blocked/not blocked, there wasn't a clear pattern. Drilling down to /24 again didn't reveal a pattern either. Looking more closely at individual addresses: `172.183.94.130` fails, while `172.183.94.135` works.

| Heavily blocked | rate | Clean        | rate |
|-----------------|------|--------------|------|
| 20.169.0.0/16   | 67%  | 20.55.0.0/16 | 0/15 |
| 68.154.0.0/16   | 67%  | 20.51.0.0/16 | 0/10 |
| 52.161.0.0/16   | 62%  | 13.83.0.0/16 | 0/6  |
| 20.161.0.0/16   | 60%  |              |      |
| 145.132.0.0/16  | 57%  |              |      |
| 172.208.0.0/16  | 56%  |              |      |
| 74.235.0.0/16   | 56%  |              |      |

I can't fix this, but I could mitigate it by not sending the users to Cambridge in the first place. Anil has recently had some success with CloudFlare, and I wanted to give it a go.

`dune.build` is registered at Gandi. I edited the zone and pointed the nameservers at Cloudflare, which brings the whole thing under Cloudflare's control. It was actually pretty trivial and was up and running in a few minutes with caching.

This still relies on the inbound path into Cambridge, but running the GHA test achieved 100% success on my first attempt. I could foresee an issue with Caddy's automatic certificate renewal in this setup, as the well-known ACME challenge would be sent to Cloudflare rather than Caddy. Cloudflare offers 15-year signed certificates for this purpose, along with a couple of other techniques.

However, I noted that there is the option to use Cloudflare as a reverse proxy with an outbound tunnel. This seems very powerful as it allows services to run inside a firewalled network without needing to open 80/443.

You run a daemon (possibly under Docker) which creates an outbound tunnel to Cloudflare. In the Cloudflare GUI, you define DNS entries like `get.dune.build` to point _through_ the tunnel to a name which is resolved at the endpoint. The TLS certificate is handled by Cloudflare, and you can redirect via HTTP within your stack.

Add `cloudflared` as just another service in the existing Docker Swarm stack:

{% raw %}
```yaml
cloudflared:
  image: cloudflare/cloudflared:latest
  restart: always
  command: tunnel --no-autoupdate run
  environment:
    TUNNEL_TOKEN: "{{ cloudflared_tunnel_token }}"
```
{% endraw %}

That's all that is needed. The token tells `cloudflared` which tunnel to join. On startup it registers four QUIC connections to nearby edges:

```
INF Starting tunnel tunnelID=a959ed9e-...
INF Registered tunnel connection connIndex=0 ip=198.41.192.47 location=lhr18 protocol=quic
INF Registered tunnel connection connIndex=1 ip=198.41.200.73 location=lhr01 protocol=quic
INF Registered tunnel connection connIndex=2 ip=198.41.200.233 location=lhr01 protocol=quic
INF Registered tunnel connection connIndex=3 ip=198.41.192.77 location=lhr15 protocol=quic
```

The routing is configured as public hostnames on the tunnel which automatically creates the corresponding DNS entries. It reads exactly like a reverse proxy pointed into the Docker Swarm's internal network. `cloudflared` shares the stack's overlay network, so it resolves the other services by name:

```
get.dune.build            -> http://caddy:80
preview.dune.build        -> http://caddy:80
staging-preview.dune.build-> http://caddy:80
nightly.dune.build        -> http://www:80
staging-nightly.dune.build-> http://staging:80
```

`get.dune.build` goes to Caddy (which serves the install scripts and tarballs out of `/dune`), while the nightly endpoints go straight to their application containers. The tunnel is doing the same job as an `nginx`/`caddy` reverse proxy would, except the front door is Cloudflare's global edge and the back end is a Docker service name. Pretty cool. I needed to keep Caddy in this case as the two preview sites issue 301 redirects, and get.dune.build is actually a Caddy file server. However, I can see other configurations where it wouldn't be necessary.

In Caddy, I can now define `get.dune.build` as http only:

```
http://get.dune.build {
    root * /dune
    file_server
}
```

The only thing that had changed now was that both HTTP and HTTPS worked, not only because of the change above to the file server, but because Cloudflare redirected both 80 and 443 to their daemon, which passed the connection on to the destinations. Caddy specifically adds a redirect to upgrade all HTTP connections to HTTPS. Under Cloudflare, you can go to SSL/TLS -> Edge Certificates -> Always Use HTTPS, which is a single zone-wide toggle, which makes Cloudflare issue a `301` upgrade for every name:

```
$ curl -sI http://get.dune.build/install | head -1
HTTP/1.1 301 Moved Permanently
Location: https://get.dune.build/install
```

I did a final sweep and with my GHA 60-runner:

```
runners=60  dune-FAIL=0
60 dune:reached
```

