# Troubleshooting

## Dashboard says "Failed to fetch" everywhere (often right after an Apollo update)

The page loads but every panel shows **Error / Failed to fetch**. The logo may be broken and some menu items may be missing. The dashboard runs, but the Apollo's API service behind it (port 5000) does not. Quick check: open `http://<APOLLO-IP>:5000/health` in a browser. `"status":"OK"` means the API is up; no response means it's down.

To find out why, SSH in (`ssh futurebit@<APOLLO-IP>`, dashboard password) and run:

```bash
sudo systemctl status apollo-api --no-pager
sudo journalctl -u apollo-api -n 60 --no-pager
```

### `code=killed, signal=BUS` (crashes about one second after starting)

A file the API loads got corrupted, usually a compiled add-on module written during the update. The Apollo holds disk writes in memory for up to 10 minutes, so a power cut or forced reboot soon after an update can leave files half-written.

1. Confirm the module is the problem and that the storage is healthy:

   ```bash
   dmesg | grep -iE "i/o error|ext4-fs error" | tail     # should print nothing
   cd /opt/apolloapi && sudo -u futurebit /usr/local/nvm/versions/node/v21.6.2/bin/node \
     -e "require('sqlite3'); require('diskusage'); console.log('modules OK')"
   ```

   `Bus error` confirms a damaged module. If `dmesg` shows I/O errors, the SD/eMMC storage itself may be failing. Stop there and contact FutureBit support.

2. Reinstall the API's modules (backs up your database first, takes 3-5 minutes):

   ```bash
   sudo systemctl stop apollo-api
   cd /opt/apolloapi
   sudo cp futurebit.sqlite ~/futurebit.sqlite.bak
   sudo rm -rf node_modules
   sudo bash -c '. /usr/local/nvm/nvm.sh && nvm use 21 && yarn cache clean && yarn'
   sudo chown -R futurebit /opt/apolloapi
   sync
   sudo systemctl reset-failed apollo-api
   sudo systemctl start apollo-api
   sleep 10; sudo systemctl status apollo-api --no-pager   # want: active (running)
   ```

3. Once everything works, delete the backup. It contains your password hash and the node's RPC password:

   ```bash
   rm -f ~/futurebit.sqlite.bak
   ```

The Node.js path above (`v21.6.2`) matches Apollo Web OS v2.1.x. If yours differs, check `ExecStart` in `systemctl cat apollo-api`.

### Other failures

Re-run the official update over SSH and watch it. It ends with a reboot; don't interrupt it, as the UI build alone can take 15-30 minutes:

```bash
sudo bash /opt/apolloapi/backend/update
```

**Prevention:** after an update, restart or shut down from the dashboard rather than pulling the plug. If you must cut power, run `sync` over SSH first.

## Windows

| Symptom | Fix |
|---|---|
| The setup window doesn't appear | Run `Setup.bat /text` for the same setup as questions in a console. Setup also falls back to it automatically when the window can't load |
| "Windows protected your PC" when opening `Setup.bat` | The zip was downloaded from the internet. Click **More info › Run anyway**, or next time unblock the zip before unzipping (right-click › Properties › **Unblock**) |
| Setup can't find the Apollo | Type its IP instead (the address you open the dashboard at). The search only covers your PC's own subnet |
| `Login failed: Invalid password` | `.\apollo-miner.ps1 -Action setpassword` | (or run `Setup.bat` again)
| `Could not reach the Apollo API` | Apollo off, wrong IP, or the API is down (see above). Check `host.txt` in `%LOCALAPPDATA%\ApolloMiner` |
| `No Apollo address set` | Run `Install-ApolloSchedule.ps1`, or pass `-ApolloHost <ip>` |
| Start pop-up says "pending" | Normal. Mining begins within a minute or two |
| "only available on the Apollo III" on an Apollo III | The Apollo's software is older than 2.1.3, or its dashboard isn't answering. Check `http://<APOLLO-IP>/api/config` shows `"chassis":"apollo-iii"`; update the Apollo, then reload Houston |
| Mode changed but dashboard shows the old mode | The miner restarts to apply it; give it a minute and refresh. If the miner was stopped, the new mode applies when it starts |
| Scheduled task didn't run | You must be signed in to Windows. For sleep, enable **Allow wake timers** in Power Options. See **Task Scheduler › Apollo Miner › History** |
| "running scripts is disabled" | Prefix commands with `powershell -ExecutionPolicy Bypass -File` |

## macOS

| Symptom | Fix |
|---|---|
| "Setup.command can't be opened" / "unidentified developer" | Right-click › **Open** › **Open**. Or **System Settings › Privacy & Security › Open Anyway**. Or in Terminal: `xattr -dr com.apple.quarantine <unzipped folder>` |
| Double-click opens a text editor | Run it from Terminal: `bash macos/Setup.command` (the download lost its "executable" flag) |
| No notification after a shortcut | Allow notifications for the shortcut in **System Settings › Notifications**. The result is also in `~/Library/Logs/apollo-miner.log` |
| A dialog appears behind other windows | Click the dialog's icon in the Dock, or press ⌘-Tab |

## Linux

| Symptom | Fix |
|---|---|
| Questions appear in the terminal, not as dialogs | Install zenity (`sudo apt install zenity`), or keep using the terminal. It does the same thing |
| No notifications | Install libnotify (`sudo apt install libnotify-bin`). Results are also in `~/.local/share/apollo-miner-control/apollo-miner.log` |
| "Couldn't enable the systemd timers" | Install cron (`sudo apt install cron`, or `cronie` on Fedora/Arch) and run setup again |
| Desktop launchers show as untrusted | Right-click › **Allow Launching** (GNOME), or use the app menu entries instead |

## Houston

| Problem | Fix |
|---|---|
| Houston doesn't load at all | On the Apollo: `systemctl status houston` (should be `active (running)`) and `journalctl -u houston -n 30`. Re-run `install-houston.sh` |
| Loads at home, not away | Tailscale must be on (on the phone and the Apollo: `tailscale status`). Use the `100.x.y.z` address or `apollo` |
| "Unknown host name" | You used a DNS name Houston doesn't know. Use the IP address, or add the name: `sudo systemctl edit houston`, add `Environment=HOUSTON_ALLOWED_HOSTS=miner.example.lan`, restart |
| Schedule ran at the wrong time | Check the time zone under *Coming up* on the Schedule tab; use *Use (your time zone)* and save |
| "Sign-in expired" in Activity | The Apollo's signing secret changed (you revoked tokens, or reinstalled the API). Open Houston, sign in, and save the schedule once |
| Charts are empty | Houston saves one reading a minute; give it a few minutes. "Unknown" mode in energy = readings before you first signed in |
| No alerts arrive | Settings › Alerts: alerts switched on, the topic in the ntfy app is identical, **Send a test**. The Apollo needs internet access to reach ntfy.sh |
| Siri says the key is wrong | Settings › Siri: check the header is `Authorization` with value `Bearer hk_...` (with "Bearer " in front). After 20 wrong tries Houston blocks shortcuts for 10 minutes |
| Still have the old phone page | Re-run `install-houston.sh`; it removes `apollo-remote` automatically |

## SSH

- `Are you sure you want to continue connecting (yes/no)?`: type the full word `yes`. Pressing Enter cancels.
- `REMOTE HOST IDENTIFICATION HAS CHANGED` after re-flashing the Apollo: `ssh-keygen -R <APOLLO-IP>` then connect again.
