# Linux — Practical Developer Guide

> Not just commands. Real-world daily usage scenarios.

> **See also:** [Docker](docker-guide.md) · [Helm](helm-guide.md) · [k3s](k3s-dev-guide.md) · [Compose → Helm](compose-to-helm.md) · [Demo walkthrough](examples-guide.md) · [Runnable demo](../examples/README.md)

---

## Table of Contents

1. [What Linux Is in Daily Work](#1-what-linux-is-in-daily-work)
2. [Filesystem and Navigation](#2-filesystem-and-navigation)
3. [Permissions and Ownership](#3-permissions-and-ownership)
4. [Processes and Background Jobs](#4-processes-and-background-jobs)
5. [Networking and Connectivity Checks](#5-networking-and-connectivity-checks)
6. [systemd and Service Management](#6-systemd-and-service-management)
7. [Scheduled Tasks — cron and systemd timers](#7-scheduled-tasks--cron-and-systemd-timers)
8. [Packages and Software Installation](#8-packages-and-software-installation)
9. [Logs and Diagnostics](#9-logs-and-diagnostics)
10. [Disk Usage and Cleanup](#10-disk-usage-and-cleanup)
11. [SSH, curl, tar, and Other Daily Tools](#11-ssh-curl-tar-and-other-daily-tools)
12. [Debugging — Chaotic vs Systematic](#12-debugging--chaotic-vs-systematic)
13. [Useful Aliases and Scripts](#13-useful-aliases-and-scripts)

---

## 1. What Linux Is in Daily Work

Linux for a developer is usually:

- a local workstation environment
- a remote VM via SSH
- a cloud server
- a CI runner
- the host OS for Docker / Kubernetes nodes

The key idea:

```
Application
    ↓
Process
    ↓
Files + ports + environment variables + permissions
    ↓
Linux kernel
```

If you can inspect:

- files
- processes
- ports
- logs
- services
- permissions

then you can usually explain why a system works or fails.

### Quick mental model

| Object | What it means in practice |
|---|---|
| **Process** | A running program with a PID, environment variables, open files, sockets, and a user. |
| **Service** | A process managed by `systemd`, automatically started/restarted. |
| **File descriptor** | An open handle to a file, pipe, or socket. |
| **User / group** | Identity under which a process runs. Controls access. |
| **Permission bits** | Read/write/execute access for owner, group, and others. |
| **Package manager** | Tool for installing software and updates: `apt`, `dnf`, `yum`, `apk`, etc. |
| **Shell** | Interactive command environment: `bash`, `zsh`, `sh`. |
| **Daemon** | Long-running background service. |
| **stdout / stderr** | Standard output and error streams. Often end up in logs. |

---

## 2. Filesystem and Navigation

### Important directories

| Path | What it is |
|---|---|
| `/` | Root of the filesystem. |
| `/home/<user>` | User home directories. |
| `/root` | Home directory of the `root` user. |
| `/etc` | System configuration. |
| `/var/log` | Log files. |
| `/var/lib` | Persistent application state. |
| `/tmp` | Temporary files. Often cleaned automatically. |
| `/usr/bin` | Installed executables. |
| `/opt` | Optional / manually installed software. |
| `/proc` | Virtual filesystem with process and kernel info. |

### Daily navigation

```bash
# Where am I?
pwd

# List files
ls
ls -la

# Move around
cd /etc
cd ~
cd -

# Create directories
mkdir project
mkdir -p app/config/nginx

# Copy / move / delete
cp file.txt backup.txt
cp -r src/ dst/
mv old.txt new.txt
rm file.txt
rm -r old-dir/
```

> `rm -r` is powerful. Verify path carefully before pressing Enter.

### Find files fast

```bash
# Find by name
find . -name "*.log"

# Find large files
find /var -type f -size +100M 2>/dev/null

# Fast text search inside files
rg "DATABASE_URL"
rg "listen 8080" /etc

# List only matching filenames
rg -l "TODO"
```

### Inspect file contents

```bash
cat config.yaml
less /var/log/syslog
head -n 20 file.txt
tail -n 50 app.log
tail -f app.log
```

### Links

```bash
# Symbolic link
ln -s /opt/myapp/current/bin/myapp /usr/local/bin/myapp

# View where a symlink points
ls -l /usr/local/bin/myapp
readlink -f /usr/local/bin/myapp
```

---

## 3. Permissions and Ownership

### View owner and mode

```bash
ls -l deploy.sh
# -rwxr-xr-- 1 admin dev 1234 Mar 29 12:00 deploy.sh
```

Breakdown:

```text
-rwxr-xr--
 ||| ||| ||
 ||| ||| |└─ others
 ||| ||| └── group
 ||| └──── owner
 └──────── file type
```

### chmod

```bash
# Make script executable
chmod +x deploy.sh

# Read/write for owner, read for group/others
chmod 644 config.yaml

# rwx for owner, rx for group/others
chmod 755 deploy.sh
```

### chown

```bash
# Change owner
sudo chown appuser config.yaml

# Change owner and group recursively
sudo chown -R appuser:appgroup /srv/myapp
```

### sudo vs root

```bash
# Run one command as root
sudo systemctl restart nginx

# Open a root shell
sudo -i
```

> Prefer `sudo <command>` over staying in a root shell for a long time.

### Bad vs right

```bash
# Bad: give everyone full permissions
chmod -R 777 /srv/myapp

# Right: fix owner and keep normal modes
sudo chown -R myapp:myapp /srv/myapp
find /srv/myapp -type d -exec chmod 755 {} \;
find /srv/myapp -type f -exec chmod 644 {} \;
chmod +x /srv/myapp/bin/start.sh
```

---

## 4. Processes and Background Jobs

### View running processes

```bash
ps aux
ps aux | grep nginx
pgrep -a python
top
htop
```

### Understand a process

```bash
# Process tree
ps -ef --forest

# What command started PID 1234?
ps -fp 1234

# Which user runs it?
ps -o user,pid,ppid,%cpu,%mem,cmd -p 1234
```

### Stop a process

```bash
kill 1234          # SIGTERM — graceful stop
kill -9 1234       # SIGKILL — force stop
pkill -f "python app.py"
```

> Use `kill -9` only when normal termination does not work.

### Background jobs in the current shell

```bash
sleep 300 &
jobs
fg %1
bg %1
```

### Which process uses a port?

```bash
ss -ltnp
sudo ss -ltnp | grep :8080
sudo lsof -i :8080
```

---

## 5. Networking and Connectivity Checks

### Basic checks

```bash
# Interfaces and IP addresses
ip addr

# Routing
ip route

# DNS resolution
getent hosts example.com
dig example.com
nslookup example.com   # legacy — prefer dig, it shows more detail

# Test connectivity
ping 8.8.8.8
ping example.com
```

### Check if a service listens on a port

```bash
ss -ltn
ss -ltnp | grep :80
ss -lunp | grep :53
```

### Test HTTP quickly

```bash
curl http://localhost:8080/health
curl -I https://example.com
curl -v https://api.example.com
curl -H "Authorization: Bearer $TOKEN" https://api.example.com/me
```

### Check open ports remotely

```bash
nc -vz example.com 443
telnet example.com 443   # legacy — prefer nc -vz, or curl -v (also does the TLS handshake)
```

### Firewall basics

```bash
# Ubuntu / Debian
sudo ufw status
sudo ufw allow 22/tcp
sudo ufw allow 8080/tcp

# RHEL-like systems
sudo firewall-cmd --list-all
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --reload
```

---

## 6. systemd and Service Management

Most modern Linux distributions use `systemd`.

### Main commands

```bash
sudo systemctl status nginx
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl restart nginx
sudo systemctl reload nginx
sudo systemctl enable nginx
sudo systemctl disable nginx
```

### Check why a service failed

```bash
systemctl status myapp
journalctl -u myapp -n 100
journalctl -u myapp -f
```

### Example service file

```ini
[Unit]
Description=My Python App
After=network.target

[Service]
User=myapp
WorkingDirectory=/srv/myapp
Environment=PORT=8080
ExecStart=/usr/bin/python3 /srv/myapp/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Save as:

```text
/etc/systemd/system/myapp.service
```

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myapp
```

### Common failure pattern

```text
systemctl status myapp
  → service exits immediately
journalctl -u myapp
  → "No such file or directory"
ps / ls / sudo -u myapp ...
  → wrong path, wrong permissions, missing env var, missing binary
```

---

## 7. Scheduled Tasks — cron and systemd timers

Typical scenario: a nightly backup and periodic log cleanup that must run without you.

### cron basics

```bash
# Edit the current user's crontab
crontab -e

# List installed cron entries
crontab -l
```

The 5-field syntax:

```text
┌───────── minute        (0-59)
│ ┌─────── hour          (0-23)
│ │ ┌───── day of month  (1-31)
│ │ │ ┌─── month         (1-12)
│ │ │ │ ┌─ day of week   (0-7, 0 and 7 = Sunday)
│ │ │ │ │
* * * * *  command
```

Realistic entries:

```bash
# Nightly backup at 02:30
30 2 * * * /srv/myapp/bin/backup.sh >> /var/log/myapp-backup.log 2>&1

# Delete app logs older than 14 days, every Sunday at 04:00
0 4 * * 0 /usr/bin/find /var/log/myapp -name "*.log" -mtime +14 -delete

# Health check every 5 minutes
*/5 * * * * /usr/bin/curl -fsS http://localhost:8080/health >> /var/log/healthcheck.log 2>&1
```

### Classic cron pitfalls

```bash
# Bad: relies on the interactive shell environment
30 2 * * * backup.sh

# Right: cron has a minimal PATH and almost no env vars
# - use absolute paths for the script and the tools inside it
# - redirect output to a log; 2>&1 also captures errors
30 2 * * * /srv/myapp/bin/backup.sh >> /var/log/myapp-backup.log 2>&1
```

> "Works in my terminal, fails in cron" is almost always PATH, env vars, or a relative path.

### systemd timers — the modern alternative

A timer is a pair of units: `myjob.service` (what to run) + `myjob.timer` (when).

```ini
# /etc/systemd/system/myjob.service
[Unit]
Description=Nightly backup

[Service]
Type=oneshot
ExecStart=/srv/myapp/bin/backup.sh
```

```ini
# /etc/systemd/system/myjob.timer
[Unit]
Description=Run nightly backup at 02:30

[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=10m
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myjob.timer

# See all timers and when they fire next
systemctl list-timers

# Logs go to the journal — no manual redirects needed
journalctl -u myjob.service -n 50
```

Why timers beat cron:

- output lands in the journal automatically (`journalctl -u`)
- dependencies on other units (`After=network-online.target`, mounts)
- `RandomizedDelaySec` spreads load across a fleet
- `Persistent=true` runs a missed job after the machine was off

---

## 8. Packages and Software Installation

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install curl git nginx
apt list --installed | grep nginx
sudo apt remove nginx
sudo apt purge nginx
sudo apt autoremove
```

### RHEL / Rocky / Alma / CentOS Stream / Fedora

```bash
sudo dnf install curl git nginx
sudo dnf remove nginx
sudo dnf update
```

### Alpine

```bash
sudo apk add curl git nginx
sudo apk del nginx
sudo apk update
```

### Verify executable path

```bash
which python3
command -v kubectl
type docker
```

### Package manager vs manual install

```bash
# Prefer package manager when possible
sudo apt install jq

# Manual binary install only when needed
sudo install -m 0755 ./kubectl /usr/local/bin/kubectl
```

---

## 9. Logs and Diagnostics

### Read system logs

```bash
journalctl -xe
journalctl -b              # current boot
journalctl -b -1           # previous boot
journalctl -u nginx -n 100
journalctl -u nginx -f
```

### Traditional log files

```bash
ls /var/log
tail -f /var/log/syslog
tail -f /var/log/messages
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

### Check environment and runtime details

```bash
env | sort
uname -a
hostnamectl
uptime
date
timedatectl
```

### Inspect process runtime state

```bash
# Open files (run with sudo for full visibility of another user's process)
sudo lsof -p 1234

# Environment variables of a process
tr '\0' '\n' < /proc/1234/environ

# Current working directory of a process
readlink /proc/1234/cwd
```

---

## 10. Disk Usage and Cleanup

### See free space

```bash
df -h
df -i
```

### Find what is consuming space

```bash
du -sh .
du -sh /var/log/*
du -sh /var/lib/*
du -xh / | sort -h | tail -n 30
```

> `du -xh /` can be expensive on large systems. Use with care.

### Large deleted files still held by a process

Sometimes disk is full even after deleting files. The reason:

- the file was deleted from the directory tree
- but some process still keeps it open

```bash
sudo lsof +L1
```

Fix:

- restart the process
- or stop it cleanly

### Logs cleanup

```bash
sudo journalctl --disk-usage
sudo journalctl --vacuum-time=7d
sudo journalctl --vacuum-size=500M
```

---

## 11. SSH, curl, tar, and Other Daily Tools

### SSH

```bash
ssh user@server
ssh -i ~/.ssh/prod.pem ubuntu@10.0.0.5
scp file.txt user@server:/tmp/
scp user@server:/etc/nginx/nginx.conf .
rsync -avz ./app/ user@server:/srv/app/
```

### tar

```bash
# Create archive
tar -czf backup.tar.gz /etc/myapp

# Extract archive
tar -xzf backup.tar.gz

# View contents
tar -tzf backup.tar.gz
```

### curl + jq

```bash
curl -s https://api.github.com/repos/torvalds/linux | jq .
curl -s http://localhost:8080/health | jq .
```

### Text processing

```bash
cat access.log | grep 500
sort users.txt | uniq
cut -d: -f1 /etc/passwd
awk '{print $1, $9}' access.log
```

> Prefer `grep pattern file` over `cat file | grep pattern` unless pipelining is necessary.

---

## 12. Debugging — Chaotic vs Systematic

### Bad approach

```text
Service does not work
  → restart it three times
  → edit random configs
  → chmod -R 777
  → kill random processes
  → system still broken
```

### Better approach

```text
1. Define the symptom exactly
   "Port 8080 does not answer"

2. Verify the process
   ps / systemctl / journalctl

3. Verify the port
   ss -ltnp | grep :8080

4. Verify local request
   curl http://127.0.0.1:8080/health

5. Verify network path
   ip route / firewall / reverse proxy / DNS

6. Verify config and permissions
   ls -l /etc/... / env / working directory / user
```

### Common real-world cases

| Symptom | Typical cause | First commands |
|---|---|---|
| `Permission denied` | Wrong owner/mode, missing execute bit | `ls -l`, `id`, `namei -l <path>` |
| `Address already in use` | Another process already listens on the port | `ss -ltnp`, `lsof -i :PORT` |
| Service restarts in loop | Wrong `ExecStart`, missing file, bad env var | `systemctl status`, `journalctl -u` |
| DNS name does not resolve | Broken resolver or wrong DNS config | `getent hosts`, `dig`, `cat /etc/resolv.conf` |
| Disk full | Logs, cache, deleted-but-open files | `df -h`, `du -sh`, `lsof +L1` |
| Process disappeared without a trace | Killed by the OOM killer under memory pressure | `dmesg -T \| grep -i oom`, `journalctl -k` |
| "No space left on device" but `df -h` shows free space | Inodes exhausted by millions of small files | `df -i`, `du --inodes -s /var/* \| sort -n` |
| HTTPS fails with certificate error | Expired or invalid TLS certificate | `curl -vI https://…`, `openssl s_client -connect host:443 \| openssl x509 -noout -dates` |
| `Connection refused` vs timeout | Refused: nothing listens on the port. Timeout: firewall drops packets | `ss -ltn` on the server first, then firewall rules |

> `namei -l` walks every component of a path and prints its permissions — it shows exactly which directory in the chain blocks access.

---

## 13. Useful Aliases and Scripts

### Aliases

```bash
alias ll='ls -lah'              # detailed file listing, including hidden files
alias ..='cd ..'                # go up one directory
alias ...='cd ../..'            # go up two directories
alias psg='ps aux | grep -i'    # search processes by name
alias ports='ss -ltnp'          # show listening TCP ports with process info
alias jfu='journalctl -fu'      # follow logs for a systemd unit
alias dfh='df -h'               # show filesystem free space in human-readable form
alias duh='du -sh'              # show total size of a directory in human-readable form
```

### Function: quick port diagnostics

```bash
portcheck() {
  local port=${1:?"Usage: portcheck <port>"}
  echo "==> Listeners on :$port"
  sudo ss -ltnp | grep ":$port" || true
  echo
  echo "==> lsof"
  sudo lsof -i :"$port" || true
}
```

### Function: quick service diagnostics

```bash
svcdiag() {
  local svc=${1:?"Usage: svcdiag <service>"}
  systemctl status "$svc" --no-pager
  echo
  journalctl -u "$svc" -n 50 --no-pager
}
```

### Final principle

Linux becomes manageable when you reduce every issue to:

- what process is involved
- which user runs it
- what files it needs
- which port it listens on
- what the logs say

That is usually enough to solve 80% of day-to-day infrastructure problems.
