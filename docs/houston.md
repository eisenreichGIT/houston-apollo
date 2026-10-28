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

**Weather rules** (Schedule › Weather rules): pick the mode by the outdoor temperature, like *Turbo below 40°F* (more heat when it's cold) or *Whisper above 75°F* (cooler and quieter in summer). Up to 4 rules; a "below" temperature must be lower than every "above" one. While a rule applies it wins over your mode windows (a window's mode change is skipped and logged); when no rule applies, your windows and normal mode decide again. Rules only change the mode: they never start or stop the miner, and a *Mine only* window that starts the miner starts it in the rule's mode. Houston uses the hourly forecast from Open-Meteo for the ZIP code or town you enter, keeps a rule on until it's 1°C (about 2°F) past its temperature, and switches at most every 30 minutes, so the miner doesn't keep restarting around the threshold. The autopilot, when it runs, takes over from the schedule and its weather rules.

Times use the time zone shown under *Coming up* (your phone's or computer's when you first save; Houston offers to switch if they differ). After saving, Houston offers to apply what the schedule says right now. A mode change restarts a running miner (about a minute) and never starts a stopped one. If the Apollo was off at a scheduled time, Houston still runs it up to 3 minutes late (after a restart, say), but not later.

**Activity**: what happened and who did it: *Schedule*, *You* (from Houston), *Shortcut* (Siri etc.), *Alert*, *Autopilot* or *Houston* (e.g. an Apollo software update finishing).

**Activity › Health**: a health check of everything Houston depends on: the Apollo API, the background sign-in, the latest readings, the node and its drive, Houston's storage, the schedule, the clock, alerts, Tailscale and each outside source (price, mempool.space, weather, your pool, GitHub). Anything that's off says what to do. *Copy report* copies a plain-text summary (no passwords, keys or addresses) to paste when asking for help. Bookmark `http://<apollo>:8088/#health`.

**Activity › Logs**: the Apollo's own logs, read through its API: **Miner**, **Node**, **Solo** (when you solo mine), **System** (the Apollo's syslog) and **Houston** (Houston's recent messages). Pick 100, 300 or 1000 lines, type to filter (e.g. `error`), turn on **Live** to refresh every 5 seconds, and copy or download what you see. Errors are tinted red, warnings amber. Bookmark `http://<apollo>:8088/#logs` to open straight to them.

**Settings**: the everyday settings are on top; the rest folds into **Advanced features** (each device remembers whether it's open).
- **Display**: **Appearance** (Light, Dark (default) or System, which follows your phone or computer; saved on each device separately, and the sun/moon button in the top bar switches between light and dark), **Temperature** in °F or °C, the **Bitcoin price** on or off and its currency (USD, EUR, GBP, CAD, AUD, JPY, CHF; Houston fetches it from Kraken's public API every 5 seconds while Houston is open somewhere, once a minute otherwise, with Coinbase as a backup, so the app itself never contacts outside sites), and **Network, market & news** on or off (from mempool.space, CoinGecko, alternative.me and Bitcoin Magazine, every 5 to 60 minutes).
- **Electricity**: your price per kWh, for the cost tiles, or *Look up my utility's rates* (US, see [Mining economics](#mining-economics)).
- **Alerts on your phone**: notifications on this device and/or the ntfy app, and the **daily digest**, see below.
- **Houston (this app)**: Houston's version, *Update* when a new one is out (see [Updating Houston](#updating-houston)), and *Run a health check*.
- **This Apollo**: the Apollo software version, with *Update* when FutureBit has a new one (see [Updating the Apollo software](#updating-the-apollo-software)), and the **Front status light** switch. Changing the light restarts a running miner (about a minute; Houston asks first). A stopped miner stays stopped and uses the setting when it starts.
- **Advanced features**:
  - **Mining economics**: time-of-use prices, heat, the autopilot and your pool, see [Mining economics](#mining-economics).
  - **Connect a wallet**: use your Apollo's node with a wallet, see [Connect a wallet](#connect-a-wallet).
  - **Your Apollos**: add your other Apollos (or **Find on my network**) to see them all on Home; if they run Houston too, *Open Houston* jumps to theirs.
  - **Siri, Google & shortcuts**: a key for phone shortcuts and voice assistants, see [voice-assistants.md](voice-assistants.md).

## Connect a wallet

Settings › Advanced features › *Connect a wallet* shows what a desktop wallet like **Sparrow** needs to use your Apollo's own Bitcoin node instead of someone else's server: the address, port 8332, the user `futurebit` and the node's password (hidden until you tap *Show*). In Sparrow: Settings (Preferences on a Mac) › Server › **Bitcoin Core**, enter the address and port, choose User / Pass, and press Test Connection.

The node only accepts wallets when the Apollo's **Allow LAN connections** is on; the switch on the card turns it on or off (the Apollo restarts its node to apply, as on the dashboard). Away from home, use the Apollo's Tailscale address. Wallets that need an Electrum server (Electrum, BlueWallet, the Blockstream app) can't connect directly, because the Apollo runs Bitcoin Core only. Keep the password private (it controls your node, not your coins) and never forward port 8332 on your router.

## Whisper mode

Whisper is Houston's own power mode for the Apollo II (and the original Apollo): about **half of Eco's power**, the quietest and coolest way to mine. On an Apollo II it measured 107 W and 2.9 TH/s, against Eco's 209 W and 5.5 TH/s, and it's slightly more efficient per TH.

It uses the Apollo's built-in custom mode at the lowest settings FutureBit's dashboard allows: power 30% and frequency 25. That's why the Apollo dashboard shows *Custom* while Whisper is on. Running below FutureBit's presets is the low-stress direction (FutureBit's custom-mode warning is about overclocking and overvolting), but it is outside the presets FutureBit tested. Like any mode change, switching to Whisper restarts a running miner.

Use it like any other mode: on Home, as the normal mode or a window in the schedule, in shortcuts (`whisper`) and as a `#whisper` link. The Apollo III doesn't need it: it has Super Eco and custom targets down to 5 TH/s.

## Mining economics

Stats › *Mining economics* works out what your Apollo really earns and costs, from its own readings rather than the spec sheet. Add your electricity price (Settings › Electricity) to turn it on.

- **Right now**: net per day, earned vs electricity vs heat, every mode side by side and the break-even electricity price.
- **Next 24 hours**: the best mode for each hour, from your prices and the forecast.
- **The last 12 months**: what each mode and the autopilot would have earned, priced day by day with that day's real difficulty and bitcoin price.
- **Outlook**: the difficulty trend and what the next 12 months look like next to a calculator that assumes difficulty stays flat.

Settings › Advanced features › *Mining economics*:

- **Time-of-use prices**: add a price for certain hours (weekdays, weekends or every day; 23:00 to 07:00 works). Other hours use your normal price.
- **Heat**: if the Apollo sits in a room you heat, pick your heating (electric, heat pump, gas, propane or oil), its price and efficiency, the outdoor temperature below which you heat, and your ZIP code or town. Houston then counts the heat it makes at what your heating would have paid for it, whenever it's that cold outside.
- **Autopilot**: *Suggest* alerts you when another mode would be better; *Run* switches by itself (at most once an hour, only when it saves at least your minimum, never within 2 hours of your own change, and it pauses the schedule). Choose the modes it may use and whether it may stop the miner.

The earnings are an expected value: a pool pays about that (minus its fee); solo mining pays nothing until you find a block. Not financial advice.

**Look up your rates (US)**: Settings › Electricity › *Look up my utility's rates* searches OpenEI's U.S. Utility Rate Database for the residential plans in your ZIP code. *Use this* sets your price per kWh (the price most hours have) and adds the plan's time-of-use prices, by season when the plan has seasons. It uses each plan's first tier, ignores fixed monthly charges (they don't change with mining), and may not include a separate supplier's price in states where you choose your supplier (like Pennsylvania): check against your bill. The search uses OpenEI's shared demo key; if it's busy, get a free key and add it under the search.

### Monthly report

Stats › *Monthly report* adds up each month as it goes: earned (in your currency and sats, at each moment's difficulty and bitcoin price, minus your pool fee), electricity (with your time-of-use prices), heat saved, and net, plus a bar per day, mining time, average hashrate, the hottest hashboard, the mode used most, mode changes and alerts, best share (solo) and blocks found. Use ‹ › for earlier months and *Download CSV* for the days. Houston keeps one small record per day for about 3 years. When you first install 2.7.0, the past week comes from Houston's history (marked as estimates). On the 1st of each month (from 9 AM) Houston sends last month's numbers as a notification (Settings › Alerts › Monthly report). Bookmark `http://<apollo>:8088/#report`.

### Pool payouts

Settings › Advanced features › Mining economics › *Pool* connects your pool, and Stats shows what it actually paid over the last 30 days next to what Houston expected from your hashrate, your unpaid balance, the last payout and the hashrate the pool sees:

- **OCEAN**: enter the bitcoin address you mine to. OCEAN's stats are public, so no account or key is needed. OCEAN pays per block the pool finds, so single days swing; 30 days evens it out.
- **Braiins Pool**: make a **read-only** API token in your Braiins Pool account settings and paste it in. Houston keeps it on the Apollo and never shows it again. Braiins credits rewards per day in UTC, so its days can be a few hours off from yours.

Houston checks the pool once an hour. Below 100% can be luck, stale or rejected shares, or a fee Houston doesn't know about (set your pool fee under Mining economics › More).

## Alerts on your phone

> **Daily digest**: turn it on under Settings › Alerts and pick a time (8:00 AM by default). Each morning Houston sends yesterday's earnings (and sats), electricity, heat saved and net, the mining time and average hashrate, the bitcoin price, anything that needs a look, and the next scheduled change, over the same channels as your alerts.

> **A block!** If your solo pool finds a block, every device with Houston open shows a full-screen celebration (once per device), on top of the alert. Settings › Alerts › *Preview the block-found celebration* shows what it looks like.

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

## Android and iPhone apps

Optional apps add a home-screen widget, an Android quick-settings tile and notifications, and Siri on iPhone. They show this same Houston from your Apollo. See [apps.md](apps.md).

## Several Apollos

Install Houston on each Apollo (same two commands, with that Apollo's address). Then add the others in Settings › *Your Apollos* on any of them: Home shows all of them, with a link to each one's Houston. An Apollo without Houston still shows its status (read from its own API) with a link to its dashboard.

## Updating the Apollo software

When FutureBit releases a new version, Houston says *New version v2.x.x is available!* on Home and in Settings › This Apollo. **Update** runs FutureBit's own updater, the same one as the Update button on the Apollo dashboard; Houston only starts it and follows along:

1. It takes about 10 to 20 minutes. Mining and the Bitcoin node pause while it downloads and rebuilds the Apollo software, then **the Apollo restarts by itself**. Keep it powered on.
2. Houston shows the progress. During the restart Houston is briefly gone too (it runs on the Apollo) and reconnects by itself. You can also close the app; Houston keeps track.
3. When the Apollo is back, Activity says *Apollo software updated to v2.x.x* and, if alerts are on, you get a notification. If the updater reports a failure, or nothing finishes within 90 minutes, Houston says so; look at Activity › Logs › System, and try again.

Houston's alerts for a stopped miner or node, and for an unreachable Apollo, stay quiet during the update. The update doesn't change Houston itself. If the Apollo dashboard shows *Failed to fetch* afterwards, see [troubleshooting](troubleshooting.md).

## Updating Houston

**From Houston 2.7.0 on, one tap**: Settings › Houston (this app) shows when a new version is out (Houston checks GitHub twice a day, and you can *Check for updates*), with what's new. *Update* installs it in about a minute. Mining and the schedule aren't affected; only Houston restarts. If the new version doesn't start, the previous one comes back by itself.

How it stays safe: Houston runs without any privileges, so it can't update itself. It only leaves the version number in its own folder. A small root helper that the installer adds (`/opt/houston/houston-update.sh`, started by systemd's `houston-update.path`) then downloads that release from Houston's GitHub repository itself, over HTTPS, checks it (version number, no links or special files, the code parses), installs only Houston's own files, restarts Houston, and rolls back if it doesn't answer. It never runs anything from the download, and it never changes Houston's sandbox or the installer.

**The first time** (from 2.6 or older), or to change installer options, copy the new `houston` folder over and run the installer again. Your schedule, history and settings are kept:

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
| `settings.json` | units, electricity price, alert topic, other Apollos, the shortcut key, your pool's address or token, an OpenEI key if you added one |
| `history.json` | one reading per minute for 7 days |
| `push.json` | Houston's notification key and the devices you turned notifications on for (their browser push addresses) |
| `activity.json` | the last 60 events |
| `econ.json` | the network numbers, weather and geocoded place for Mining economics (your ZIP code or town lives in `settings.json`) |
| `daily.json` | one small record per day (about 3 years) for the monthly report |
| `pool.json` | your pool's daily earnings, payouts and balance (mode 600) |
| `blocks.json` | solo blocks your Apollo found, for the celebration |
| `update-request`, `houston-update-status.json` | only while a Houston update runs: the version you asked for, and the updater's progress |
| `update.json` | the Apollo software update Houston started (versions and start time, until it finishes) and the last version it told you about |

To revoke everything, see [SECURITY.md](../SECURITY.md#lost-phone).

## Good to know

- **Start** takes about 45 seconds (the Apollo resets its hashboard first) and may show *pending* for a minute after that.
- The browser shows **Not secure** because Houston uses `http://`. Over Tailscale the connection is still encrypted end to end; at home it stays inside your own network, like the Apollo's own dashboard. For a padlock, install with `--https`.
- Houston never touches the dashboard's *format drive* action, and keeps the Bitcoin node software setting unchanged when it switches modes (older Apollo software would otherwise restart the node).
- Android allows one VPN at a time, so Tailscale can't run alongside another VPN app.
