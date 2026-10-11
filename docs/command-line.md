# Command line and cron (without Houston)

[Houston](houston.md) is the easy way to schedule your Apollo. If you'd rather keep things minimal, `scripts/apollo-miner.sh` does the same jobs from any `bash` shell: on the Apollo itself (with cron), on Linux or on macOS.

```
apollo-miner.sh [--notify] start | stop | restart | status
apollo-miner.sh [--notify] eco | balanced | turbo
apollo-miner.sh [--notify] super_eco | custom 14        # Apollo III (custom: 5-20 TH/s)
apollo-miner.sh [--notify] node_start | node_stop       # the Apollo's Bitcoin node
```

Mode changes restart a running miner (about a minute) and never start a stopped one. `--notify` also shows a desktop notification.

## On the Apollo, with cron

> Don't combine this with Houston's schedule: they'd fight over the mode.

From a computer on your network:

```bash
scp scripts/apollo-miner.sh futurebit@192.168.1.50:~/
ssh futurebit@192.168.1.50          # the SSH password is your dashboard password
```

Then, on the Apollo:

```bash
chmod +x ~/apollo-miner.sh
(umask 077; read -rsp 'Dashboard password: ' P && printf '%s\n' "$P" > ~/.apollo-pass); echo
~/apollo-miner.sh status            # test
timedatectl                         # cron uses the Apollo's time zone; fix with: sudo timedatectl set-timezone America/New_York
crontab -e
```

Example: Eco 24/7, Turbo on weekdays 9:30 AM to 4:30 PM:

```
30 9  * * 1-5  $HOME/apollo-miner.sh turbo >> $HOME/apollo-miner.log 2>&1
30 16 * * 1-5  $HOME/apollo-miner.sh eco   >> $HOME/apollo-miner.log 2>&1
```

Or mine only on weekdays 9:30 AM to 4:30 PM: use `start` and `stop` instead. Cron fields are `minute hour day-of-month month day-of-week` (`1-5` = Monday to Friday).

## From Linux or macOS by hand

```bash
export APOLLO_HOST=192.168.1.50
./scripts/apollo-miner.sh status
```

| Variable | Default | Meaning |
|---|---|---|
| `APOLLO_HOST` | saved by setup, else `127.0.0.1` | Apollo address (`127.0.0.1` = running on the Apollo) |
| `APOLLO_PASS_FILE` | `~/.apollo-pass` | file with the dashboard password (setup uses the macOS Keychain or `~/.config/apollo-miner/password` instead) |

The password and login token go to `curl` through a pipe, so they never appear in the process list.

## Windows

`windows\apollo-miner.ps1 -Action start|stop|restart|status|eco|balanced|turbo|super_eco|node_start|node_stop` (and `custom -Hashrate 14`); see [windows.md](windows.md).
