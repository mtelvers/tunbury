---
layout: post
title: "Borg Backup"
date: 2025-06-14 00:00:00 +0000
categories: borg
tags: tunbury.org
image:
  path: /images/borg-logo.png
  thumbnail: /images/thumbs/borg-logo.png
redirect_from:
  - /borg-backup/
---

Our PeerTube installation at [watch.ocaml.org](https://watch.ocaml.org/) holds hundreds of videos we wouldn't want to lose! It's a VM hosted at Scaleway so the chances of a loss are pretty small, but having a second copy would give us extra reassurance. I'm going to use [Borg Backup](https://www.borgbackup.org).

Here's the list of features (taken directly from their website):

- Space-efficient storage of backups.
- Secure, authenticated encryption.
- Compression: lz4, zstd, zlib, lzma or none.
- Mountable backups with FUSE.
- Easy installation on multiple platforms: Linux, macOS, BSD, ...
- Free software (BSD license).
- Backed by a large and active open source community.

We have several OBuilder workers with one or more unused hard disks, which would make ideal backup targets.

In this case, I will format and mount `sdc` as `/home` on one of the workers.

```sh
parted /dev/sdc mklabel gpt
parted /dev/sdc mkpart primary ext4 0% 100%
mkfs.ext4 /dev/sdc1
```

Add this to /etc/fstab and run `mount -a`.

```
/dev/sdc1 /home ext4 defaults 0 2
```

Create a user `borg`.

```sh
adduser --disabled-password --gecos '@borg' --home /home/borg borg
```

On both machines, install the application `borg`.

```sh
apt install borgbackup
```

On the machine we want to backup, generate an SSH key and copy it to the `authorized_keys` file for user `borg` on the target server. Ensure that `chmod` and `chown` are correct.

```sh
ssh-keygen -t ed25519 -f ~/.ssh/borg_backup_key
```

Add lines to the `.ssh/config` for ease of connection. We can now `ssh backup-server` without any prompts.

```
Host backup-server
    HostName your.backup.server.com
    User borg
    IdentityFile ~/.ssh/borg_backup_key
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Borg supports encrypting the backup at rest on the target machine. The data is publicly available in this case, so encryption seems unnecessary.

On the machine to be backed up, run.

```sh
borg init --encryption=none backup-server:repo
```

We can now perform a backup or two and see how the deduplication works.

```sh
# borg create backup-server:repo::test /var/lib/docker/volumes/postgres --compression lz4 --stats --progress
------------------------------------------------------------------------------
Repository: ssh://backup-server/./repo
Archive name: test
Archive fingerprint: 627242cb5b65efa23672db317b4cdc8617a78de4d8e195cdd1e1358ed02dd937
Time (start): Sat, 2025-06-14 13:32:27
Time (end):   Sat, 2025-06-14 13:32:38
Duration: 11.03 seconds
Number of files: 3497
Utilization of max. archive size: 0%
------------------------------------------------------------------------------
                       Original size      Compressed size    Deduplicated size
This archive:              334.14 MB            136.28 MB            132.79 MB
All archives:              334.14 MB            136.28 MB            132.92 MB

                       Unique chunks         Total chunks
Chunk index:                     942                 1568
------------------------------------------------------------------------------
# borg create backup-server:repo::test2 /var/lib/docker/volumes/postgres --compression lz4 --stats --progress
------------------------------------------------------------------------------
Repository: ssh://backup-server/./repo
Archive name: test2
Archive fingerprint: 572bf2225b3ab19afd32d44f058a49dc2b02cb70c8833fa0b2a1fb5b95526bff
Time (start): Sat, 2025-06-14 13:33:05
Time (end):   Sat, 2025-06-14 13:33:06
Duration: 1.43 seconds
Number of files: 3497
Utilization of max. archive size: 0%
------------------------------------------------------------------------------
                       Original size      Compressed size    Deduplicated size
This archive:              334.14 MB            136.28 MB              9.58 MB
All archives:              668.28 MB            272.55 MB            142.61 MB

                       Unique chunks         Total chunks
Chunk index:                     971                 3136
------------------------------------------------------------------------------
# borg list backup-server:repo
test                                 Sat, 2025-06-14 13:32:27 [627242cb5b65efa23672db317b4cdc8617a78de4d8e195cdd1e1358ed02dd937]
test2                                Sat, 2025-06-14 13:33:05 [572bf2225b3ab19afd32d44f058a49dc2b02cb70c8833fa0b2a1fb5b95526bff]
```

Let's run this every day via by placing a script `borgbackup` in `/etc/cron.daily`. The paths given are just examples...

```sh
#!/bin/bash

# Configuration
REPOSITORY="backup-server:repo"

# What to backup
BACKUP_PATHS="
/home
"

# What to exclude
EXCLUDE_ARGS="
--exclude '*.tmp'
--exclude '*.log'
"

# Logging function
log() {
    logger -t "borg-backup" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "========================================"
log "Starting Borg backup"

# Check if borg is installed
if ! command -v borg &> /dev/null; then
    log "ERROR: borg command not found"
    exit 1
fi

# Test repository access
if ! borg info "$REPOSITORY" &> /dev/null; then
    log "ERROR: Cannot access repository $REPOSITORY"
    log "Make sure repository exists and SSH key is set up"
    exit 1
fi

# Create backup
log "Creating backup archive..."
if borg create \
    "$REPOSITORY::backup-{now}" \
    $BACKUP_PATHS \
    $EXCLUDE_ARGS \
    --compression lz4 \
    --stats 2>&1 | logger -t "borg-backup"; then
    log "Backup created successfully"
else
    log "ERROR: Backup creation failed"
    exit 1
fi

# Prune old backups
log "Pruning old backups..."
if borg prune "$REPOSITORY" \
    --keep-daily=7 \
    --keep-weekly=4 \
    --keep-monthly=6 \
    --stats 2>&1 | logger -t "borg-backup"; then
    log "Pruning completed successfully"
else
    log "WARNING: Pruning failed, but backup was successful"
fi

# Monthly repository check (on the 1st of each month)
if [ "$(date +%d)" = "01" ]; then
    log "Running monthly repository check..."
    if borg check "$REPOSITORY" 2>&1 | logger -t "borg-backup"; then
        log "Repository check passed"
    else
        log "WARNING: Repository check failed"
    fi
fi

log "Backup completed successfully"
log "========================================"
```

Check the logs...

```sh
journalctl -t borg-backup
```

