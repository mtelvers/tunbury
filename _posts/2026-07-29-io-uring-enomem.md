---
layout: post
title: "io_uring is not available (ENOMEM)"
date: 2026-07-29 06:00:00 +0000
image:
  path: /images/ocaml-logo.png
  thumbnail: /images/thumbs/ocaml-logo.png
categories: [ocluster, obuilder, io_uring]
tags: tunbury.org
---

Thomas reported that [ocaml-multicore/eio](https://github.com/ocaml-multicore/eio) PRs randomly fail on [ocurrent/ocaml-ci](https://github.com/ocurrent/ocaml-ci) with a strange error in the documentation tests.

```
Exception: Failure "io_uring is not available (ENOMEM)".
```

ENOMEM means "cannot allocate memory". The job had run on asteria, one of our 256-core Linux workers, which had 378GB of memory free at the time. The same commit passed on every other machine. How can you run out of memory on an idle machine with hundreds of gigabytes spare?

When a program creates an `io_uring`, the kernel counts the few kilobytes of memory that the ring needs against a quota. The quota is small, it defaults to 8MB, and crucially it is shared by every process on the machine running under the same user id. All of our build jobs run as user id 1000. On a machine with 256 cores running many tests at once, the jobs collectively consumed the quota, and any test that tried to create a ring at the wrong moment failed.

The failing tests were all mdx blocks. mdx is a tool that runs the code samples inside a markdown file and checks the output, and each block in these files starts a fresh eio event loop, which means creating a fresh `io_uring`. The main test suite in the same job passed, including tests that use `io_uring` heavily. Ring creation worked, then failed, then worked again. When the machine was busy, nine blocks failed. On a quieter re-run, one block failed and the very next block succeeded.

The error message comes from `lib_eio_linux/sched.ml` in eio, which translates an ENOMEM from ring creation into the failure we saw in the logs:

```ocaml
| exception Unix.Unix_error(ENOMEM, _, _) ->
    fallback (`Msg "io_uring is not available (ENOMEM)")
```

The first step was to confirm this was a machine problem rather than a code problem, which meant re-running the identical job on asteria and on another worker. OCluster does not let a client choose which worker runs a job, but there is a simple trick: pause every other worker in the pool, submit the job, wait until it has been assigned, then unpause the others. The pool is only restricted for a few seconds.

Every job log starts with the full OBuilder spec, so reproducing a job is a copy and paste exercise:

```sh
sed -n '/^((from /,/^)$/p' job.log > job.spec

for w in $OTHER_WORKERS; do
  ocluster-admin -c admin.cap pause linux-x86_64 $w
done
ocluster-client submit-obuilder -c submission.cap --pool linux-x86_64 \
  --local-file job.spec \
  https://github.com/ocaml-multicore/eio.git <commit> > job-rerun.log &
until grep -q "Building on" job-rerun.log; do sleep 5; done
for w in $OTHER_WORKERS; do
  ocluster-admin -c admin.cap unpause linux-x86_64 $w
done
```

One snag: the PR had been merged by the time I re-ran it, and once a PR is merged GitHub stops advertising its head commit, so a worker with a fresh git cache cannot fetch it by branch. Fetching the commit hash directly into the worker's cached clone fixes that:

```sh
sudo git -C /var/cache/obuilder/ocluster/git/eio.git-<hash> \
  fetch origin <commit-sha>
```

With this, the same spec and commit failed on asteria and passed on bremusa. Definitely the machine.

Simple tests on the host could not reproduce the failure. Creating and destroying ten thousand rings in a row worked. Holding 512 rings open at once under an 8MB locked-memory limit worked. Whatever this was, a single test program run by one user could not trip it, so the next step was to watch the real failure as it happened.

First, a small `bpftrace` script. `bpftrace` lets you attach a probe to a kernel function and print something whenever it fires. This one reports every time the `io_uring_setup` system call returns ENOMEM (error code -12):

```
kretprobe:io_uring_setup
/(int64)retval == -12/
{
  printf("%s ENOMEM io_uring_setup pid=%d comm=%s\n",
         strftime("%H:%M:%S", nsecs), pid, comm);
}
```

I left that running with `systemd-run --unit=uring-trace bpftrace trace.bt` and resubmitted the job in a loop. Each submission had a trivially different final command (`&& echo run-N`), because OBuilder caches build steps and would otherwise just return the previous result. The failure showed up within a few iterations, and the trace was revealing: bursts of ENOMEM from five to ten test processes at the same instant, repeating in waves about seven seconds apart. That is the signature of a shared resource that runs out, recovers, and runs out again.

Probes on the individual functions inside `io_uring_setup` all stayed silent, which later turned out to be misleading (the compiler had inlined them, so the probes never fired). The tool that settled it was ftrace, the kernel's built-in call tracer. It can record every function called inside `io_uring_setup` along with each function's return value, and a trigger can freeze the recording the moment the syscall fails so the evidence is not overwritten:

```sh
cd /sys/kernel/tracing
echo function_graph > current_tracer
echo io_uring_setup > set_graph_function
echo 1 > options/funcgraph-retval
echo 'r:uring_fail io_uring_setup ret=$retval' >> kprobe_events
echo 'traceoff:1 if ret==-12' > events/kprobes/uring_fail/trigger
echo 1 > events/kprobes/uring_fail/enable
echo > trace
echo 1 > tracing_on
```

One small trap: the trigger condition must be written as `-12`, not as the equivalent unsigned hex value, because the captured field is declared signed.

The next reproduction froze the trace with the answer at the end:

```
io_uring_setup() {
  io_uring_create() {
    io_ring_ctx_alloc();               /* ret=0xffff8b6bd5193000 */
    ns_capable_noaudit();              /* ret=0x0  (no CAP_IPC_LOCK) */
    io_allocate_scq_urings() {
      io_create_region() {             /* first ring area */
        __io_account_mem();            /* ret=0x0 */
        io_region_allocate_pages();    /* ret=0x0 */
      }
      io_create_region() {             /* second ring area */
        __io_account_mem();            /* ret=-12  <-- here */
      }
    }                                  /* ret=-12 */
  }                                    /* io_uring_create ret=-12 */
}                                      /* io_uring_setup ret=-12 */
```

The failing function is `__io_account_mem`. It is not an allocation at all. It is bookkeeping: it adds the pages the ring needs to a per-user counter of "locked" memory and refuses if the total would exceed the process's locked memory limit, `RLIMIT_MEMLOCK`. The memory was there all along. What ran out was permission to pin more of it.

Three things combine to make this problem:

First, the counter is shared across the whole machine for each user id. Our containers do not use user namespaces (the kernel feature that would map the user inside a container to a different user outside), so user 1000 inside every job container is the same identity as far as the kernel is concerned. Every ring created by any job on the machine draws from one pot.

Second, the limit is inherited. Limits like `RLIMIT_MEMLOCK` pass from parent process to child, so the value set on the `ocluster-worker` service flows through runc into every build process. Nothing configured it, so everything ran with the systemd default of 8MB.

Third, the workload scales with the number of cores. A default eio ring costs 8KB of quota, so 8MB is exactly 1024 rings for the whole machine. dune runs tests with as many parallel jobs as there are cores, 256 on asteria against 72 on bremusa, and the eio test suite creates an event loop per test process, per mdx block, and per spawned domain. Add a few concurrent CI jobs (other projects build eio too), and asteria regularly needed more than 1024 rings at once. Bremusa rarely did. Ring cleanup is also slightly delayed by the kernel, so the quota stays consumed for a moment after a test finishes, which explains the failures arriving in waves.

Every observation now fits: only asteria, intermittent, worse under load, several processes failing at the same instant, recovered seconds later.

I was reluctant to make such a claim without being able to reproduce it. If the quota really is shared between containers under one user id, that should be directly testable. Start two containers as an unused user id, have one hold rings open, and watch the other's allowance shrink. Two small programs, compiled statically, so the containers need nothing else.

`uring_alloc.c` creates rings and holds them open:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/syscall.h>
#include <linux/io_uring.h>
#define FLAGS ((1U<<12)|(1U<<13)|(1U<<9)) /* the flags eio uses */
/* uring_alloc <count> <depth> <hold_sec>: create rings, hold them, exit */
int main(int argc, char **argv) {
    int n = atoi(argv[1]), depth = atoi(argv[2]), hold = atoi(argv[3]);
    int ok = 0;
    for (int i = 0; i < n; i++) {
        struct io_uring_params p; memset(&p, 0, sizeof p); p.flags = FLAGS;
        if (syscall(__NR_io_uring_setup, depth, &p) >= 0) ok++;
    }
    printf("ALLOC uid=%d held %d/%d rings, holding %ds\n", getuid(), ok, n, hold);
    fflush(stdout);
    sleep(hold);
    return 0;
}
```

`uring_probe.c` creates rings until the first failure and reports how far it got:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/syscall.h>
#include <linux/io_uring.h>
#define FLAGS ((1U<<12)|(1U<<13)|(1U<<9))
/* uring_probe <max> <depth>: create rings until first failure */
int main(int argc, char **argv) {
    int max = atoi(argv[1]), depth = atoi(argv[2]);
    int i;
    for (i = 0; i < max; i++) {
        struct io_uring_params p; memset(&p, 0, sizeof p); p.flags = FLAGS;
        if (syscall(__NR_io_uring_setup, depth, &p) < 0) {
            printf("PROBE uid=%d created %d rings, then errno=%d (%s)\n",
                   getuid(), i, errno, strerror(errno));
            return 0;
        }
    }
    printf("PROBE uid=%d created %d rings, no failure\n", getuid(), max);
    return 0;
}
```

Build them:

```sh
gcc -static -O2 -o uring_alloc uring_alloc.c
gcc -static -O2 -o uring_probe uring_probe.c
```

Create three runc containers. Two run as user 2000 (one to consume the quota, one to measure what is left) and a third runs as user 2001 as the control. Each has the old 8MB limit set, and each uses runc's default namespaces, which like OBuilder do not include a user namespace:

```sh
mkdir -p /tmp/urtest/rootfs
cp uring_alloc uring_probe /tmp/urtest/rootfs/
for b in alloc probe probe-other; do
  mkdir -p /tmp/urtest/$b && (cd /tmp/urtest/$b && runc spec)
done
python3 - <<'PYEOF'
import json
def fix(bundle, uid, args):
    p = f"/tmp/urtest/{bundle}/config.json"
    c = json.load(open(p))
    c["root"]["path"] = "/tmp/urtest/rootfs"
    c["process"]["terminal"] = False
    c["process"]["args"] = args
    c["process"]["user"] = {"uid": uid, "gid": uid}
    c["process"]["rlimits"] = [
        {"type": "RLIMIT_MEMLOCK", "hard": 8388608, "soft": 8388608}]
    json.dump(c, open(p, "w"), indent=1)
fix("alloc", 2000, ["/uring_alloc", "400", "64", "120"])
fix("probe", 2000, ["/uring_probe", "5000", "64"])
fix("probe-other", 2001, ["/uring_probe", "5000", "64"])
PYEOF
```

Run the experiment:

```sh
# baseline, nothing else using the quota
sudo runc run -b /tmp/urtest/probe ur-probe-base
# start the consumer in one container...
sudo runc run -b /tmp/urtest/alloc ur-alloc &
sleep 3
# ...and probe from two other containers
sudo runc run -b /tmp/urtest/probe ur-probe-during
sudo runc run -b /tmp/urtest/probe-other ur-probe-other
```

Results on asteria:

```
PROBE uid=2000 created 1021 rings, then errno=24 (Too many open files)
ALLOC uid=2000 held 56/400 rings, holding 120s
PROBE uid=2000 created 968 rings, then errno=12 (Cannot allocate memory)
PROBE uid=2001 created 1021 rings, then errno=24 (Too many open files)
```

The arithmetic is exact: 56 + 968 = 1024 rings, which at 8KB each is precisely the 8MB quota. The second container hit "cannot allocate memory" at exactly the point where its rings, plus the 56 held in a completely different container, filled user 2000's allowance. Meanwhile, user 2001, running the identical probe at the same moment, was untouched (it ran out of file descriptors at 1021, never memory).

There is a bonus lesson in the `56/400` line. The consumer was asked to hold 400 rings but only managed 56, because it started three seconds after the baseline probe exited, and the baseline's 1021 rings were still being counted against the quota. Cleanup really is delayed, which is the same effect behind the seven-second failure waves in CI.

There is a simple one line for this in the `ocluster-worker` systemd service:

```ini
[Service]
LimitMEMLOCK=infinity
```

I rolled it out to the linux-x86_64 pool one worker at a time (pause and wait for the worker to drain, add the setting, reload systemd, restart the worker, unpause) and verified it from inside a job container with a one-step spec:

```
((from ocaml/opam:debian-13-ocaml-5.5)
 (run (shell "grep -i 'locked memory' /proc/self/limits")))
```

It reported 8388608 before and unlimited after. Five consecutive re-runs of the original failing job on asteria all passed, where previously it failed within one to six attempts. The setting is also in the ansible worker role's service template so it survives redeployment.

Was this a new problem? Probably not. We have likely been brushing against this limit for as long as we have had big machines. No one notices because almost nothing creates `io_uring` rings in bulk.
