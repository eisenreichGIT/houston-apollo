# Linux desktop setup

Connects this computer to your Apollo and adds the app-menu launchers you pick (copied to your Desktop folder too, if you have one):

| Launcher | What it does |
|---|---|
| **Houston** | Opens [Houston](houston.md) in its own window (Chromium, Chrome, Edge or Brave app mode if installed, otherwise your default browser). Needs Houston on the Apollo |
| **Start Miner**, **Stop Miner**, **Miner Status** | One click; a notification shows the result |
| **Eco / Balanced / Turbo Mode** (+ **Super Eco** on an [Apollo III](apollo-iii.md)) | Switch the power mode |
| **Start / Stop Bitcoin Node** | Off by default |

The schedule lives in Houston on the Apollo. Without Houston, setup can schedule from this computer instead (cron, or systemd user timers).

Setup shows desktop dialogs when [zenity](https://help.gnome.org/users/zenity/) is installed, otherwise it asks in the terminal (also over SSH).

> **Status:** tested end to end in terminal and zenity mode against the Apollo API. Reports from different distros welcome.

## Requirements

`bash` and `curl`. Optional: `zenity` (dialogs), `notify-send` (notifications), `cron` (only for a schedule on this computer).

## Install

```bash
cd ~/Downloads/houston-apollo      # wherever you unzipped it
bash linux/setup.sh
```

Questions in the terminal instead of dialogs: `APOLLO_UI=terminal bash linux/setup.sh`

Setup asks the same things as on Windows and macOS: find the Apollo, the dashboard password (checked right away), Houston (found, or the two commands to install it), which shortcuts, and, only without Houston, an optional schedule (days like `Mon-Fri`, times like `9:30 AM`).

## What setup does

| | Where |
|---|---|
| Password | `~/.config/apollo-miner/password`, readable only by you (mode 600), for the one-click launchers |
| Apollo address | `~/.config/apollo-miner/host` |
| Script | `~/.local/share/apollo-miner-control/apollo-miner.sh` |
| Launchers | `~/.local/share/applications/apollo-miner-*.desktop` (+ Desktop folder) |
| Schedule | with Houston: none on this computer (an old setup's block is removed from your crontab; your other cron jobs are left alone). Without: a marked block in your crontab, or systemd user timers |
| Log | `~/.local/share/apollo-miner-control/apollo-miner.log` |

## Using it

- Launchers run in the background and show a notification (if `notify-send` is available).
- Terminal: `~/.local/share/apollo-miner-control/apollo-miner.sh status` (also `start`, `stop`, `eco`, `balanced`, `turbo`, `node_start`, `node_stop`; Apollo III `super_eco`, `custom 14`).

## Change or remove

- **Change the shortcuts or password:** run `bash linux/setup.sh` again.
- **Remove:** `bash linux/uninstall.sh` removes the launchers (and any schedule on this computer), and optionally the saved address and password. Houston on the Apollo isn't touched.
