# Changelog

## 2.2.1 (2026-10-11)

- **Bitcoin network & market** on the Stats tab, after the Apollo's own stats: Fear & Greed Index, block height, time since the last block (live), average block time and the next difficulty change, market cap, BTC dominance, 24-hour trading volume, sats per dollar (or your currency), and the latest Bitcoin Magazine headlines.
- Fetched by Houston on the Apollo (never the browser) from public sources with no account or key: mempool.space, CoinGecko, alternative.me and Bitcoin Magazine's feed. Cached and refreshed every 5 to 60 minutes. Settings › Display › *Network, market & news* turns it off.
- Headlines are shown as plain text and only https links are kept; feeds with entity declarations are refused.

## 2.2.0 (2026-10-11)

- **Notifications without ntfy**: Settings › Alerts › *Turn on for this device* sends alerts as regular notifications from the Houston app (Web Push), with no extra app or account. Works on iPhone (iOS 16.4+, from the Home Screen), Android and computers. Needs Houston's https address (`install-houston.sh --https`). ntfy still works, alone or alongside.
- Alerts can be on with only device notifications (no ntfy topic needed). Send a test to one device or everywhere.
- The installer adds `python3-cryptography` (for the notification encryption) if it's missing.
- **Security review and hardening** ([docs/security-review.md](docs/security-review.md)): only Houston's own script files can run in the app (no inline scripts); wrong passwords through Houston are rate limited; one-tap links (`#stop`, …) ask first unless opened from a home-screen shortcut; requests to other Apollos, push services and ntfy don't follow redirects and are size-capped; stricter request handling (size, timeouts); private files always 600; notification clicks always open Houston; extra browser security headers. A dedicated security test suite runs with the others.
- Credits link to [@eisenreich](https://x.com/eisenreich) on X.
- Bitcoin tip jar (address and QR code) in Settings › About and in the README, with a Sponsor button on GitHub.

## 2.1.1 (2026-10-11)

- Browsers now pick up the new logo, icons and fonts right after an update (they could keep showing the old logo for up to a day).

## 2.1.0: New look (2026-10-11)

- **Light and dark**: Settings › Display › *Appearance*: Light, Dark or System (follows the phone or computer). Saved per device; the sun/moon button in the top bar switches quickly. Dark stays the default.
- **Redesign**: warm graphite and paper colors, a large hashrate readout on Home, quieter cards, monospaced readings, and bundled fonts (Archivo, IBM Plex Mono) served by the Apollo itself, so the app still makes no outside connections.
- **Orange means bitcoin**: the bitcoin-orange accent is now used only for the bitcoin price, its charts and the logo. Buttons and selections use the text color.
- **Mode colors and icons**: each power mode has its own color and a dial icon (needle further right = faster): Super Eco purple, Eco teal, Balanced blue, Turbo red (was orange), Custom pink. The current mode shows as a badge on Home and colors the mode buttons, the schedule list and the charts.
- **Logo**: the orbit mark, flattened (no gradients). New app, browser and home-screen icons, and new desktop shortcut icons for Windows, macOS and Linux in the same style. The Windows setup window uses the new colors and logo.

## 2.0.0: Houston (2026-10-10)

The project is now **Houston**, with a new logo, and the Apollo does the work itself.

- **Houston on the Apollo** (`houston/install-houston.sh`): one app for phone and computer, served by the Apollo on port 8088, at home or through Tailscale. Replaces the Apollo Remote phone page (migrated automatically, same address, no new sign-in).
  - **Home**: status, hashrate, power, temperature, efficiency, fan, shares, uptime, pool; Start/Stop; power modes (Apollo III: Super Eco and custom 5-20 TH/s); Bitcoin node card; next scheduled change; your other Apollos.
  - **Schedule** editor, run by the Apollo 24/7: a normal mode plus *change mode* and *mine only* windows, any days, overnight windows, its own time zone, catches up after a short outage, offers to apply right away.
  - **Stats**: 24-hour and 7-day charts (hashrate with the mode timeline, power, temperature), energy per day and cost per month, energy by mode and what faster modes add, solo-mining best share and odds, node details with recent blocks, system meters.
  - **Activity** log (schedule, you, shortcuts, alerts).
  - **Settings**: °F (default) or °C, electricity price, alerts, other Apollos, shortcut key.
- **Bitcoin price ticker**: price, 24-hour change, low/high and sparkline at the top of Home (and in the header on wide screens), a 24-hour / 7-day price chart on Stats, in Siri's status, and electricity cost in sats. USD, EUR, GBP, CAD, AUD, JPY or CHF. Fetched by Houston from Kraken (Coinbase as backup), cached, and can be turned off.
- **Bitcoin node control**: start/stop and status everywhere (Houston, shortcuts, scripts, Siri). Works with Apollo software 2.1.4, which moved node start/stop to GraphQL mutations, and with older versions. Warns when you solo mine through the node.
- **Alerts** through the free ntfy app: stopped unexpectedly, running hot, hashrate drop, node stopped, node drive almost full, solo block found, plus all-clear messages.
- **Siri and shortcuts**: a key-protected automation API (`/api/v1/say`, `/api/v1/action/turbo`...). Guide for iPhone Shortcuts, Android (HTTP Shortcuts) and Google Home through Home Assistant: docs/voice-assistants.md.
- **Several Apollos**: add them in Settings, see all of them on Home, find them on your network.
- **Desktop setups** (Windows window and text, macOS, Linux) now connect to Houston and let you pick shortcuts: the Houston app (own window), Start/Stop/Status, power modes, Bitcoin node. The schedule moves to Houston, and old schedules on the computer are removed. Without Houston, the computer schedule is still available.
- New logo and icons everywhere; node shortcut icons.


## 1.2.0 (2026-10-10)

- **Windows setup window**: a four-step wizard (find Apollo, sign in, schedule, install) with day buttons, time pickers and mode menus, plus an uninstall window. Built on WPF, which ships with Windows, so nothing extra to install. `Setup.bat /text` (or an automatic fallback) keeps the text setup.
- **macOS setup**: `macos/Setup.command` with native dialogs; password in the Keychain; launchd schedule; Launchpad apps with icons; notifications.
- **Linux setup**: `linux/setup.sh` with zenity dialogs or terminal questions; cron schedule (systemd timers if there's no cron); app-menu launchers with icons; notifications.
- `apollo-miner.sh` moved to `scripts/`; it now reads the address and password saved by setup and supports `--notify`.

## 1.1.0 (2026-10-10)

- **Apollo III support**, detected automatically (same check as the dashboard):
  - **Super Eco** mode and **custom hashrate targets** (5-20 TH/s) in the PowerShell script, shell script, schedule builder, phone page and Siri links
  - Super Eco desktop shortcut with its own icon
  - schedule examples: Super Eco 24/7, 16 TH/s while nobody's home
- Apollo II behaviour unchanged; III-only options are hidden or refused with a clear message.
- New guide: docs/apollo-iii.md

## 1.0.0 (2026-10-10)

First public release.

- **Windows:** double-click `Setup.bat` / `Uninstall.bat`
  - finds the Apollo on your network automatically (or type its IP)
  - guided schedule builder: any days and times, multiple windows, start/stop and/or mode switching, overnight windows handled
  - desktop shortcuts with their own icons: Start, Stop, Status, Eco, Balanced, Turbo
  - password stored with Windows DPAPI; scripts folder locked to your account
- **Mode switching** (Eco / Balanced / Turbo) everywhere: shortcuts, schedule, shell script, phone page, Siri links.
  Restarts a running miner to apply; never starts a stopped one; never restarts the Bitcoin node.
- **Shell script** for the Apollo itself (cron), Linux and macOS.
- **Phone page** (Android and iPhone home-screen app) with live hashrate, watts, temperature, start/stop and mode buttons; remote access through Tailscale; one-tap `#start` / `#stop` / `#eco` / `#turbo`... links for Siri Shortcuts.
- Docs: setup guides, troubleshooting (including the "Failed to fetch" / `signal=BUS` fix after an Apollo update), API notes, security notes.
