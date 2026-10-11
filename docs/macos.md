# macOS desktop setup

Connects this Mac to your Apollo and adds the apps you pick to **Launchpad** (in `~/Applications/Houston`):

| App | What it does |
|---|---|
| **Houston** | Opens [Houston](houston.md) in its own window (Chrome, Edge or Brave app mode if you have one, otherwise your default browser). Needs Houston on the Apollo |
| **Start Miner**, **Stop Miner**, **Miner Status** | One click; a notification shows the result |
| **Eco / Balanced / Turbo Mode** (+ **Super Eco** on an [Apollo III](apollo-iii.md)) | Switch the power mode |
| **Start / Stop Bitcoin Node** | Off by default |

The schedule lives in Houston on the Apollo. Without Houston, setup can schedule from the Mac instead (launchd; runs while you're logged in).

> **Status:** tested against the Apollo API with stand-ins for the macOS tools, not yet on a real Mac. Reports welcome.

## Install

1. Unzip the download (setup copies what it needs, so you can delete the download afterwards).
2. Open the `macos` folder and **right-click `Setup.command` › Open**, then **Open** in the warning. macOS asks once because the file came from the internet.
   - If macOS says it "can't be opened": **System Settings › Privacy & Security › Open Anyway**, or in Terminal: `xattr -dr com.apple.quarantine ~/Downloads/houston-apollo` (your path).
3. Setup's dialogs:
   - **Find your Apollo**: "Search my network", or type the address you open the dashboard at.
   - **Dashboard password**: checked with the Apollo right away.
   - **Houston**: found, or the two Terminal commands to install it (**Copy the commands** puts them on the clipboard), then "check again". Or continue without Houston.
   - **Shortcuts**: yes/no for Houston, Start/Stop/Status, power modes, Bitcoin node.
   - Without Houston only: an optional schedule for this Mac (days like `Mon-Fri`, times like `9:30 AM`).
   - A summary, then **Install**.

## What setup does

| | Where |
|---|---|
| Password | your **Keychain** (item "Houston (Apollo dashboard password)"), for the one-click apps |
| Apollo address | `~/.config/apollo-miner/host` |
| Script | `~/Library/Application Support/Apollo Miner Control/apollo-miner.sh` |
| Apps | `~/Applications/Houston/*.app` (Launchpad, Spotlight; drag to the Dock if you like) |
| Schedule | with Houston: none on the Mac (old ones removed). Without: launchd agents `~/Library/LaunchAgents/com.apollominercontrol.*.plist` |
| Log | `~/Library/Logs/apollo-miner.log` |

## Using it

- The one-click apps run in the background and show a **notification**. The first time, macOS may ask to allow notifications.
- **Start** takes about a minute; mode changes restart a running miner and never start a stopped one.
- Terminal: `"$HOME/Library/Application Support/Apollo Miner Control/apollo-miner.sh" status` (also `start`, `stop`, `eco`, `balanced`, `turbo`, `node_start`, `node_stop`; Apollo III `super_eco`, `custom 14`).

## Change or remove

- **Change the shortcuts or password:** run `Setup.command` again.
- **Remove:** run `Uninstall.command`. It removes the apps (and any schedule on the Mac), and optionally the saved address and Keychain item. Houston on the Apollo isn't touched.
