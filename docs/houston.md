# Houston: the app and scheduler on your Apollo

Houston runs on the Apollo itself. It does three things:

- **Serves the Houston app** on port 8088, for any phone, tablet or computer: status, Start/Stop, power modes, the Bitcoin node, schedule, stats, activity and settings.
- **Runs your schedule** 24/7 on the Apollo, so no computer has to stay on.
- **Watches the Apollo**: saves a reading every minute for the charts and energy costs, and sends alerts to your phone when something goes wrong.

```
Phone / PC browser ──(home Wi-Fi, or Tailscale away from home)──▶ Apollo :8088  Houston
                                                                     │  schedule, history, alerts
                                                                     ▼
                                                                  Apollo :5000  Apollo API (FutureBit's)
```

<img src="images/houston-phone.png" alt="Houston on a phone: Home, Stats and Schedule (demo data)" width="900">

## Install (once, about 5 minutes)

You need the Apollo's address (the one you open the dashboard at, e.g. `192.168.1.50`) and the dashboard password. From a computer on your home network, in the folder you unzipped (Windows 10/11, macOS and Linux all have `ssh` and `scp` built in; on Windows use PowerShell):

```bash
scp -r houston futurebit@192.168.1.50:~/
ssh -t futurebit@192.168.1.50 "sudo bash ~/houston/install-houston.sh"
```

- Both commands ask for your **dashboard password** (it's also the SSH password). The first connection asks you to trust the Apollo's key: type `yes`.
- The installer:
  1. copies Houston to `/opt/houston` (outside FutureBit's folder, so Apollo software updates leave it alone)
  2. runs it as the sandboxed system service `houston` on **port 8088**, and checks that it answers
  3. removes the older *Apollo Remote* phone page if you had it (Houston replaces it, same port)
  4. installs **Tailscale** for access away from home and prints a `https://login.tailscale.com/a/...` link: **open it, sign in and approve the device, then wait**. The terminal continues by itself and ends with a box showing your addresses:

  ```
  At home:                    http://192.168.1.50:8088
  Anywhere (Tailscale on):    http://100.x.y.z:8088
                              http://apollo:8088
  ```

- Recommended: in the [Tailscale admin console](https://login.tailscale.com/admin/machines), open the **apollo** machine's **⋯** menu and choose **Disable key expiry**, so it doesn't drop off after about 180 days.

Options: `--no-tailscale` (home network only), `--https` (also serve Houston over HTTPS inside your tailnet at `https://apollo.<your-tailnet>.ts.net`; needs MagicDNS and HTTPS certificates turned on in the Tailscale admin console).

## Open it

| Where | How |
|---|---|
| **Computer** | Run the desktop setup (`Setup.bat`, `macos/Setup.command`, `linux/setup.sh`) and pick the **Houston** shortcut: it opens Houston in its own app window. Or just open the address in any browser |
| **Android** | Install **Tailscale** (Play Store), sign in with the same account. In Chrome open `http://100.x.y.z:8088`, then **⋮ › Add to Home screen** (or **Install app**) |
| **iPhone / iPad** | Install **Tailscale** (App Store), sign in with the same account. In Safari open `http://100.x.y.z:8088`, then **Share › Add to Home Screen** |

Sign in with your dashboard password. At home with Tailscale off, use the home address instead.

## The tabs

**Home**: the **bitcoin price** up top, live (it refreshes every 5 seconds while Houston is open). Pick a time frame under the chart (1H, 1D, 7D, 1M, 3M, 6M, YTD, 1Y, 5Y, ALL) for its change, low and high; each device remembers its choice, 1D by default. Tap the price for the Stats chart. Then miner status with hashrate, power and hashboard temperature, plus efficiency (W/TH), fan speed, shares, uptime and pool. Start and Stop, the power modes (Apollo II: also **Whisper**, see below; Apollo III: also Super Eco and a custom 5-20 TH/s target), the Bitcoin node card (sync, block height, peers, disk, Start/Stop), the next scheduled change, **Your Apollos** if you added others, and a card when new Apollo software is available.

**Stats**: 24-hour and 7-day charts of the bitcoin price, hashrate (with a strip showing which mode was active), power and temperature (hover or tap for exact values; each chart also has a table view). Tiles for average hashrate, mining time, energy per day and electricity cost per month. **Energy by mode**, including how much the faster modes add compared with your normal mode. **Solo mining** (when you mine to the Apollo's own solo pool): best share, chance of a block today, expected time to a block. **Bitcoin node**: last block, network hashrate, difficulty, connections, version and the 10 most recent blocks with the pool that found them. **System**: CPU, memory, system and node drives, system temperature. Then **Bitcoin network & market**: the Fear & Greed Index, block height, time since the last block, average block time and the next difficulty change, market cap, BTC dominance, 24-hour volume, sats per dollar (or your currency) and the latest Bitcoin Magazine headlines.

> The charts fill in as Houston runs: it saves one reading per minute and keeps 7 days.

**Schedule**: turn it on, pick a **normal mode** (used around the clock), and add time windows:
- **Change mode**: e.g. *Weekdays 9:30 AM to 4:30 PM: Turbo, then back to Eco.*
- **Mine only**: the miner runs only during the window (optionally in a chosen mode) and is stopped the rest of the time; it can run overnight or have no stop time.

Times use the time zone shown under *Coming up* (your phone's or computer's when you first save; Houston offers to switch if they differ). After saving, Houston offers to apply what the schedule says right now. A mode change restarts a running miner (about a minute) and never starts a stopped one. If the Apollo was off at a scheduled time, Houston still runs it up to 3 minutes late (after a restart, say), but not later.

**Activity**: what happened and who did it: *Schedule*, *You* (from Houston), *Shortcut* (Siri etc.), *Alert* or *Houston* (e.g. an Apollo software update finishing).

**Activity › Logs**: the Apollo's own logs, read through its API: **Miner**, **Node**, **Solo** (when you solo mine), **System** (the Apollo's syslog) and **Houston** (Houston's recent messages). Pick 100, 300 or 1000 lines, type to filter (e.g. `error`), turn on **Live** to refresh every 5 seconds, and copy or download what you see. Errors are tinted red, warnings amber. Bookmark `http://<apollo>:8088/#logs` to open straight to them.

**Settings**:
- **This Apollo**: the Apollo software version, with *Update* when FutureBit has a new one (see [Updating the Apollo software](#updating-the-apollo-software)), and the **Front status light** switch. Changing the light restarts a running miner (about a minute; Houston asks first). A stopped miner stays stopped and uses the setting when it starts.
- **Appearance**: Light, Dark (default) or System, which follows your phone or computer. Saved on each device separately; the sun/moon button in the top bar switches between light and dark.
- **Temperature**: °F or °C (°F by default).
- **Bitcoin price**: on or off, and the currency (USD, EUR, GBP, CAD, AUD, JPY, CHF). Houston fetches it from Kraken's public API every 5 seconds while Houston is open somewhere, and once a minute otherwise (Coinbase as a backup for USD, EUR and GBP), so the app itself never contacts outside sites. When your electricity currency matches, the cost tile also shows the cost in sats.
- **Network, market & news**: on or off. Houston fetches these from mempool.space, CoinGecko, alternative.me and Bitcoin Magazine (public data, no account), every 5 to 60 minutes.
- **Electricity**: your price per kWh, for the cost tiles.
- **Alerts on your phone**: notifications on this device and/or the ntfy app, see below.
- **Your Apollos**: add your other Apollos (or **Find on my network**) to see them all on Home; if they run Houston too, *Open Houston* jumps to theirs.
- **Siri, Google & shortcuts**: a key for phone shortcuts and voice assistants, see [voice-assistants.md](voice-assistants.md).

## Whisper mode

Whisper is Houston's own power mode for the Apollo II (and the original Apollo): about **half of Eco's power**, the quietest and coolest way to mine. On an Apollo II it measured 107 W and 2.9 TH/s, against Eco's 209 W and 5.5 TH/s, and it's slightly more efficient per TH.

It uses the Apollo's built-in custom mode at the lowest settings FutureBit's dashboard allows: power 30% and frequency 25. That's why the Apollo dashboard shows *Custom* while Whisper is on. Running below FutureBit's presets is the low-stress direction (FutureBit's custom-mode warning is about overclocking and overvolting), but it is outside the presets FutureBit tested. Like any mode change, switching to Whisper restarts a running miner.

Use it like any other mode: on Home, as the normal mode or a window in the schedule, in shortcuts (`whisper`) and as a `#whisper` link. The Apollo III doesn't need it: it has Super Eco and custom targets down to 5 TH/s.

## Alerts on your phone

Houston tells you when:

| Alert | When |
|---|---|
| Stopped unexpectedly | The miner has been offline for 3 minutes and wasn't stopped from Houston, a shortcut or the schedule (it can't see the Apollo dashboard, so it says so). Also when Houston can't reach the Apollo's software for 5 minutes |
| Running hot | Hashboard above your limit for 3 readings in a row (default 176 °F / 80 °C) |
| Hashrate drop | The last 10 minutes are more than 40% below the previous 2 hours in the same mode |
| Node stopped | The Bitcoin node has been offline for 5 minutes and wasn't stopped on purpose |
| Node drive almost full | The blockchain drive is 95% full |
| Solo block found | Your solo pool reports a block |
| Apollo software update | FutureBit released a new Apollo software version (once per version; Houston checks every 6 hours). Also when an update you started from Houston finishes, fails or gets stuck |

You also get an *all clear* when a problem goes away. A continuing problem is repeated every 6 hours.

There are two ways to get them. Use either, or both:

| | Notifications on this device | ntfy app |
|---|---|---|
| What you install | Nothing: alerts come from the Houston app itself | The free ntfy app |
| Needs | Houston's **https** address (below); iPhone: iOS 16.4+ and Houston opened from the Home Screen | Nothing extra; works with plain http |
| Who delivers it | Your phone's own push service (Apple or Google), encrypted end to end | ntfy.sh (or your own ntfy server) |

### Notifications on this device (no extra app)

Phones only allow notifications from web apps on secure (https) pages, so this needs Houston's https address inside your Tailscale network. Once:

1. In the [Tailscale admin console](https://login.tailscale.com/admin/dns), turn on **MagicDNS** and **HTTPS Certificates** (DNS page).
2. Run the installer again with `--https`:
   ```bash
   ssh -t futurebit@192.168.1.50 "sudo bash ~/houston/install-houston.sh --https"
   ```
   It prints the new address, like `https://apollo.your-tailnet.ts.net`.
3. On the phone (Tailscale connected), open that address and sign in. **iPhone/iPad:** Share › **Add to Home Screen**, then open Houston from the Home Screen icon (Apple only allows notifications there). **Android:** ⋮ › **Add to Home screen** (optional; Chrome works either way).
4. Houston › Settings › *Alerts on your phone* › **Turn on for this device**, and allow notifications. A test arrives right away.

Repeat step 3 and 4 on each phone or computer that should get alerts (up to 10). The list shows them all; **Remove** stops one. Notifications arrive even when Tailscale isn't connected on the phone (they come through Apple or Google), but opening Houston from one still needs Tailscale.

> The https address is a separate site for your browser: sign in once there, and re-add the Home Screen icon from it.

### ntfy app

Houston uses **[ntfy](https://ntfy.sh)**, a free push-notification app (Android, iPhone) that needs no account.

1. Install the **ntfy** app on your phone.
2. In Houston › Settings › *Alerts on your phone*: tap **Make a random topic**, switch alerts on, pick which ones you want, **Save**.
3. In the ntfy app, tap **+** and subscribe to that exact topic.
4. **Send a test everywhere**.

> The topic works like a password: anyone who knows it can read your alerts. Make it hard to guess (the random button does). Prefer your own server? Enter it under *Your own ntfy server*.

## Several Apollos

Install Houston on each Apollo (same two commands, with that Apollo's address). Then add the others in Settings › *Your Apollos* on any of them: Home shows all of them, with a link to each one's Houston. An Apollo without Houston still shows its status (read from its own API) with a link to its dashboard.

## Updating the Apollo software

When FutureBit releases a new version, Houston says *New version v2.x.x is available!* on Home and in Settings › This Apollo. **Update** runs FutureBit's own updater, the same one as the Update button on the Apollo dashboard; Houston only starts it and follows along:

1. It takes about 10 to 20 minutes. Mining and the Bitcoin node pause while it downloads and rebuilds the Apollo software, then **the Apollo restarts by itself**. Keep it powered on.
2. Houston shows the progress. During the restart Houston is briefly gone too (it runs on the Apollo) and reconnects by itself. You can also close the app; Houston keeps track.
3. When the Apollo is back, Activity says *Apollo software updated to v2.x.x* and, if alerts are on, you get a notification. If the updater reports a failure, or nothing finishes within 90 minutes, Houston says so; look at Activity › Logs › System, and try again.

Houston's alerts for a stopped miner or node, and for an unreachable Apollo, stay quiet during the update. The update doesn't change Houston itself. If the Apollo dashboard shows *Failed to fetch* afterwards, see [troubleshooting](troubleshooting.md).

## Updating Houston

Copy the new `houston` folder over and run the installer again. Your schedule, history and settings are kept:

```bash
scp -r houston futurebit@192.168.1.50:~/
ssh -t futurebit@192.168.1.50 "sudo bash ~/houston/install-houston.sh"
```

## Removing Houston

```bash
ssh -t futurebit@192.168.1.50 "sudo bash ~/houston/install-houston.sh --uninstall"
```

This removes Houston, its schedule, history and settings. The Apollo keeps its current mode, and nothing else is changed. Tailscale stays; to remove it too: `ssh -t futurebit@192.168.1.50 "sudo tailscale logout; sudo apt-get remove -y tailscale"`.

## Coming from Apollo Remote (the old phone page)

Run the installer as above. It replaces the old page on the same port, so your home-screen icon keeps working, and the old page's sign-in carries over. Then:

1. Open Houston › **Schedule** and recreate your schedule there (e.g. *Normal mode Eco; Weekdays 9:30 AM to 4:30 PM, Turbo*).
2. Run the desktop setup again (`Setup.bat` etc.). It sees Houston, removes the old schedule from your computer so the two don't clash, and offers the Houston shortcut.

## What Houston stores on the Apollo

In `/var/lib/houston` (readable only by Houston's own service account):

| File | What |
|---|---|
| `schedule.json` | your schedule and its time zone |
| `auth.json` | an Apollo sign-in (the same kind your browser keeps), so the schedule, history, alerts and shortcuts can work while you're away. Created when you sign in to Houston |
| `settings.json` | units, electricity price, alert topic, other Apollos, the shortcut key |
| `history.json` | one reading per minute for 7 days |
| `push.json` | Houston's notification key and the devices you turned notifications on for (their browser push addresses) |
| `activity.json` | the last 60 events |
| `update.json` | the Apollo software update Houston started (versions and start time, until it finishes) and the last version it told you about |

To revoke everything, see [SECURITY.md](../SECURITY.md#lost-phone).

## Good to know

- **Start** takes about 45 seconds (the Apollo resets its hashboard first) and may show *pending* for a minute after that.
- The browser shows **Not secure** because Houston uses `http://`. Over Tailscale the connection is still encrypted end to end; at home it stays inside your own network, like the Apollo's own dashboard. For a padlock, install with `--https`.
- Houston never touches the dashboard's *format drive* action, and keeps the Bitcoin node software setting unchanged when it switches modes (older Apollo software would otherwise restart the node).
- Android allows one VPN at a time, so Tailscale can't run alongside another VPN app.
