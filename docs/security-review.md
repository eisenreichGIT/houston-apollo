# Security review

This page is for anyone deciding whether to run Houston on their Apollo. It explains what Houston can do, what it stores, where data goes, and how it's protected. It also covers what the Apollo itself does, and what Houston can't fix. Everything here can be checked in the code: Houston is one Python file (`houston/houston.py`), one web app (`houston/web/`) and an install script.

> Short version: Houston keeps everything on your Apollo and your own network. It has no account, no cloud service and no tracking. Passwords never leave your devices except to sign in to your own Apollo. The one thing it stores that you should protect is the Apollo sign-in it keeps so your schedule can run.

Last full review: version 2.2.0 (October 2026). [Findings fixed in that review](#findings-fixed-in-the-220-review) are listed at the end. Version 2.2.1 adds the network, market and news cards; their sources and protections are covered below.

## What you're trusting Houston with

Houston uses the Apollo's own API, the one the Apollo dashboard uses, with your dashboard password. Houston can therefore do anything the dashboard can: start and stop the miner and node, change modes and change settings. It never calls the dashboard's *format drive* action.

| Thing | Where it lives | Who can read it |
|---|---|---|
| **Dashboard password** | Never stored by Houston. You type it into the app's sign-in screen, which passes it straight to the Apollo's API and keeps only the sign-in token that comes back | Nobody (Houston never writes it down) |
| **Apollo sign-in token** (browser) | Your browser's local storage on each device where you signed in to Houston | That browser, on that device |
| **Apollo sign-in token** (background) | `/var/lib/houston/auth.json` on the Apollo, mode 600. It lets the schedule, history, alerts and shortcuts work while no browser is open | Houston's own service account and root |
| **Shortcut key** (optional) | `/var/lib/houston/settings.json`, mode 600 | Houston and root. Shown in the app to signed-in users |
| **ntfy topic** (optional) | `settings.json`, mode 600 | Houston and root, plus anyone who knows or guesses the topic on ntfy.sh |
| **Device notification keys** (optional) | `/var/lib/houston/push.json`, mode 600: Houston's signing key, plus each device's push address and encryption keys | Houston and root |
| **History and activity** | `history.json`: one reading per minute for 7 days. `activity.json`: the last 60 events | Houston and root |
| **Desktop setups** | Windows: password encrypted with DPAPI (only your Windows account can decrypt it). macOS: login Keychain. Linux: `~/.config/apollo-miner/password`, mode 600 | Your user account on that computer |

`/var/lib/houston` is mode 700 and belongs to Houston's own throwaway system user. Other accounts on the Apollo can't read it; root can.

## Who could attack what, and what stops them

| Someone who… | Could try to… | What stops them |
|---|---|---|
| **Visits a malicious website in your browser** | Send requests to Houston from that page (CSRF), or point a hostname at your Apollo (DNS rebinding) | Every API call needs an `Authorization` header or a JSON body. Browsers won't send either across sites without asking Houston first, and Houston never says yes (no CORS headers). Requests with an unknown `Host` name get refused (HTTP 421) |
| **Gets HTML or script into the app** (XSS) | Steal the sign-in token from the browser | All text from the Apollo, other Apollos and settings goes in as plain text, never as HTML. The page's security policy only allows Houston's own script files: no inline scripts, no outside scripts, no frames, no plugins, and no connections to other sites |
| **Is on your home Wi-Fi** | Guess your dashboard password through Houston | Houston blocks an address for 15 minutes after 10 wrong passwords, and pauses a second after each one. **The Apollo's own API on port 5000 has no such limit**, so a strong password still matters most |
| **Is on your home Wi-Fi** | Read traffic | At home Houston uses plain HTTP, the same as the Apollo dashboard, so someone who can watch your Wi-Fi traffic could see the token. Away from home, Tailscale encrypts everything end to end. For HTTPS at home too, install with `--https` |
| **Is on your home Wi-Fi** | Read your miner's status without signing in | `/api/glance`, `/api/device` and `/api/price` are public: status, hashrate, watts, temperature, model, version, time zone and the bitcoin price. The Apollo's own API already shares these readings without sign-in. Nothing secret is in them (checked by the tests) |
| **Is on your home Wi-Fi** | Guess the shortcut key | Wrong keys are delayed a second. After 20 wrong tries in 10 minutes, shortcuts are blocked for everyone for a while. The key is 192 random bits |
| **Sends you a link** like `http://<apollo>:8088/#stop` | Make your signed-in browser stop the miner | Houston asks before running a link's action. It runs without asking only when opened from a home-screen shortcut, which is what that feature is for |
| **Is anywhere on the internet** | Reach Houston | Houston isn't reachable from the internet unless you forward a port, which you shouldn't. Remote access goes through your private Tailscale network |
| **Steals your phone** | Use Houston | The phone keeps a sign-in that never expires. See [Lost phone](../SECURITY.md#lost-phone) to revoke all sign-ins |
| **Runs an Apollo you added under Your Apollos** | Attack Houston through its answers | Houston only reads a fixed list of fields from other Apollos, caps each reply at 1 MB, never follows redirects, and shows everything as text |
| **Runs a news feed or market data service** | Inject script or links through headlines or numbers | Houston parses the feed on the Apollo, refuses feeds that declare XML entities, strips all markup, keeps only `https://` links and caps each reply at 1 MB. The app shows everything as plain text, and the links open in a new tab without access to Houston |
| **Runs ntfy.sh or a push service** | Read your alerts | ntfy alerts are plain text to ntfy.sh: status messages such as "Miner stopped" or a temperature, never passwords or keys. Device notifications are encrypted for each device (RFC 8291), so Apple, Google, Mozilla or Microsoft only see that a message was sent |
| **Gets control of Houston itself** | Damage the Apollo | Houston runs as a throwaway system user in a systemd sandbox: read-only system, no root, no capabilities, no devices, private /tmp, a system-call filter, and no writable and executable memory. It can write only to `/var/lib/houston`. With the stored sign-in it could still do what the dashboard can |

## Network: what's open, what's called

**Listening:** Houston listens on TCP port 8088, on every interface (home network and Tailscale). Nothing else is opened. With `--https`, Tailscale also serves Houston on port 443, but only inside your tailnet.

**Inbound endpoints**

| Endpoint | Sign-in needed | What it does |
|---|---|---|
| `/`, app files, icons, fonts, `sw.js` | No | The web app (fixed list of files; nothing else on disk can be requested) |
| `/api/device`, `/api/glance`, `/api/price`, `/api/market` | No | Model, version and time zone; live status readings; cached bitcoin price; cached network, market and news data (all public information) |
| `/api/graphql` | The Apollo's own rules | Passes requests to the Apollo API unchanged, only when sent as JSON. Sign-in attempts are rate limited here |
| `/api/schedule`, `/api/settings`, `/api/activity`, `/api/history`, `/api/fleet`, `/api/auth`, `/api/discover`, `/api/automation`, `/api/push`, `/api/alerts/test` | Yes: a valid Apollo sign-in, checked with the Apollo | Houston's own features |
| `/api/v1/say`, `/api/v1/status`, `/api/v1/action/<action>` | The shortcut key | Status, plus start / stop / modes / node start-stop only |

**Outbound connections** (Houston's, never the browser's: the app's security policy blocks the browser from contacting anything except Houston)

| To | When | What's sent |
|---|---|---|
| `127.0.0.1:5000` (the Apollo API) and `127.0.0.1:3000` (the Apollo's model info) | Always | Your requests and the stored sign-in |
| `api.kraken.com`, `api.exchange.coinbase.com` | Once a minute, if the bitcoin price is on (Settings) | Nothing about you: public price requests |
| `mempool.space`, `api.coingecko.com`, `api.alternative.me`, `bitcoinmagazine.com` | Every 5 to 60 minutes, if *Network, market & news* is on (Settings) | Nothing about you: public data requests (the currency you picked, for market cap and volume) |
| `ntfy.sh` (or your server) | When an alert fires, if you set a topic | The alert title and message |
| Apple / Google / Mozilla / Microsoft push services | When an alert fires, if a device has notifications on | The encrypted alert, a signed header and a time-to-live |
| Your other Apollos (port 8088, or 5000 for status only) | When Home shows Your Apollos | A status request, no sign-in |
| Your home network, ports 5000 and 8088 | Only when you press *Find on my network* | Small "are you an Apollo?" requests |
| `tailscale.com` | Only during installation | The official Tailscale install script and packages |

Houston has no telemetry, update check, analytics or account.

## How the code is built

- **No third-party code at runtime.** The server uses only Python's standard library, plus Ubuntu's `python3-cryptography` package for the device-notification encryption. The app is plain HTML, CSS and JavaScript with no frameworks and no build step. The fonts (Archivo and IBM Plex Mono, open source) are included and served by the Apollo.
- **Input validation.** Settings, schedule windows, times, time zones, modes, topic names, server addresses, Apollo addresses, device names and push subscriptions are all checked against strict patterns and limits before they're saved. Requests are capped at 256 KB, and stalled connections are dropped after 30 seconds.
- **Constant-time comparison** for the shortcut key, a cryptographically random key, and a sign-in check against the Apollo itself, cached for one minute.
- **Atomic, private writes.** State files are written to a temporary file and moved into place. Private files are created with mode 600 and forced back to 600 even if an old temporary file existed.
- **Logs** hold schedule actions, errors and alert results, never passwords, tokens, keys or topics. Read them with `journalctl -u houston`.
- **Tests.** About 400 automated checks run against stand-ins built from FutureBit's own API code (Apollo II and III), including a dedicated security suite: headers, CSRF, DNS rebinding, sign-in checks on every private endpoint, secrets never returned, file permissions, path traversal, request limits, redirects, push address checks and the sign-in rate limit.

## What Houston can't fix (the Apollo's own design)

FutureBit set these up, and they affect every Apollo whether or not you run Houston:

- The **dashboard password is also the SSH password** for the `futurebit` account, and that account has passwordless `sudo` (full root).
- The Apollo API's sign-in has **no rate limit** on port 5000 (Houston limits only its own proxy).
- **Sign-in tokens never expire**, and changing the password doesn't revoke them. Houston stores one, and so does every browser that signs in. To revoke them all, change the API's signing secret: see [Lost phone](../SECURITY.md#lost-phone).
- Everything on the home network is **plain HTTP**, the dashboard included.

So: use a strong, unique dashboard password, don't port-forward the Apollo, and use Tailscale for remote access. [SECURITY.md](../SECURITY.md) has the full checklist.

## Known limits of Houston itself

- **The rate limit is per address.** With `--https`, every visitor reaches Houston through Tailscale from the same local address, so a burst of wrong passwords blocks everyone for 15 minutes. Tailscale already limits who can connect.
- **The shortcut lockout is global.** Someone on your network could keep your shortcuts blocked by sending wrong keys. Siri status and actions stop working until they stop, and nothing else is affected.
- **ntfy topics work like passwords.** Anyone who knows yours can read your alerts and post fake ones. Use the random button, or device notifications instead.
- **Push services see metadata**: that your device received a message, when, and roughly how big it was.
- **Tailscale is installed with its official script** (`curl -fsSL https://tailscale.com/install.sh | sh`), the method Tailscale documents. Use `--no-tailscale` if you'd rather install it yourself.
- **Home-screen action links** (an icon for `#turbo`, say) run without asking. That's the point of them, but treat such icons like a remote control.
- **No independent audit.** This review was done by the authors: the code was written by Claude (Anthropic's AI) and tested on real hardware by @eisenreich. Outside reviews are welcome.

## Check it yourself

On the Apollo (`ssh futurebit@<apollo>`):

```bash
sudo systemd-analyze security houston          # sandbox score for the service
sudo ls -la /var/lib/houston                   # folder 700, private files 600, owned by Houston's user
sudo ss -tlnp | grep 8088                      # the only port Houston opens
journalctl -u houston --since today            # what it logged (no secrets)
grep -n "urlopen\|fetch(" /opt/houston/houston.py   # every place Houston makes a request
```

From a computer on your network:

```bash
curl -sI http://<apollo>:8088/ | grep -i "content-security\|x-frame\|permissions"   # browser protections
curl -s  http://<apollo>:8088/api/glance                                          # all that's public
curl -s  -o /dev/null -w "%{http_code}\n" http://<apollo>:8088/api/settings       # 401: needs a sign-in
```

To remove everything Houston stored: `sudo bash ~/houston/install-houston.sh --uninstall`. That removes the service, `/opt/houston` and `/var/lib/houston`.

## Findings fixed in the 2.2.0 review

| Finding | Risk | Fix |
|---|---|---|
| The page allowed inline scripts in its security policy | An HTML-injection bug, if one existed, could have run script and read the sign-in token | All code moved into `app.js` and `theme.js`. The policy now allows only Houston's own script files (`script-src 'self'`) |
| Sign-in attempts through Houston weren't limited | Faster password guessing from the home network | 10 wrong passwords in 15 minutes block that address, and each wrong one waits a second |
| One-tap action links ran without asking in a normal browser tab | A link sent to you could stop the miner if you were signed in | Houston asks first, except when opened from a home-screen shortcut |
| Requests to other Apollos, push services and ntfy followed redirects and read unlimited replies | A misbehaving device could redirect Houston elsewhere or flood its memory | Redirects are refused, replies are capped at 1 MB, and only known fields are kept from other Apollos |
| A negative `Content-Length` bypassed the request size limit, and stalled connections were never dropped | A device on the network could tie up Houston | Negative sizes are refused, and connections time out after 30 seconds |
| An old temporary file could keep looser permissions when a private file was rewritten | A private file could end up readable by others (only outside the systemd sandbox) | Permissions are forced to 600 on every write, and the state folder to 700 |
| Clicking a notification opened whatever address the message named | A forged notification could open another site | Clicking a notification always opens Houston |
| Missing modern headers | Defense in depth | Added `Permissions-Policy`, `Cross-Origin-Opener-Policy` and `Cross-Origin-Resource-Policy` |

## Reporting

Found something? Open an issue on the project's GitHub page. For anything sensitive, say in the issue that you'd like a private contact, without the details. For problems in Apollo OS itself, contact FutureBit.
