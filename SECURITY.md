# Security

Short version: **keep everything on your home network or your own Tailscale account, use a strong dashboard password, and never port-forward the Apollo to the internet.**

For the full picture (what Houston stores, every endpoint and outbound connection, the threat model, known limits and how to check it yourself), read the **[security review](docs/security-review.md)**.

## How the Apollo itself is set up (by FutureBit, not by this project)

Know these before deciding what to expose:

- The **dashboard password is also the SSH password** for the `futurebit` account, and that account has **passwordless sudo** (full root).
- The API's login has **no rate limiting**. Anyone who can reach port 5000 can keep guessing; only password strength slows them down.
- **Login tokens never expire.** Changing the dashboard password does **not** invalidate tokens already issued.
- Everything is **plain HTTP**. On your home network the password and token travel unencrypted, the same as when you use the dashboard.
- Miner and node *readings* (status, hashrate, temperature) are available from the API without signing in.

## What Houston adds (on the Apollo)

| | |
|---|---|
| **Service** | `houston` on port 8088, Python standard library only. Runs as a throwaway `DynamicUser` in a systemd sandbox: read-only system, no privileges or capabilities, no devices, private /tmp, syscall filter, memory W^X. Its only writable place is `/var/lib/houston` (mode 700) |
| **Stored sign-in** | When you sign in to Houston, it keeps one Apollo login token in `/var/lib/houston/auth.json` (mode 600) so the schedule, history, alerts and shortcuts work while you're away. Same power as the token your browser keeps |
| **Shortcut key** | Optional, created in Settings. Can only read status and run start / stop / modes / node start-stop through `/api/v1/...`, not change the schedule, settings or password. Compared in constant time; wrong keys are slowed down and, after 20 tries in 10 minutes, shortcuts are blocked for a while. Turn off or replace any time |
| **Alert topic** | Stored in `settings.json` (mode 600). Alerts go out over HTTPS to ntfy.sh (or your server) and contain only status messages. Anyone who knows the topic can read them, so use a hard-to-guess one |
| **Device notifications** | Web Push: Houston keeps its own signing key and each device's push address in `push.json` (mode 600). Messages are encrypted for that one device (RFC 8291) and signed (VAPID) before they go to the phone's push service (Apple, Google, Mozilla or Microsoft), which can't read them. Houston only sends to those push services, never to other addresses. Remove a device in Settings to stop it |
| **No sign-in needed for** | the app files, `/api/price` (the cached bitcoin price), `/api/market` (cached network, market and news data), `/api/device` (model, version, time zone) and `/api/glance` (status, hashrate, watts, temperature: the same readings the Apollo API already shares without sign-in) |
| **Everything else** | needs a valid Apollo sign-in (checked with the Apollo) or, for `/api/v1`, the shortcut key |
| **Browser protections** | Requests from other websites are blocked: the API needs an `Authorization` header or JSON body (which browsers won't send cross-site without permission, and Houston grants none), unknown `Host` names are refused (DNS rebinding), and the app has a strict content security policy: only Houston's own script files (no inline or outside scripts), no frames, no plugins, no connections to other sites. All text is inserted as text, never as HTML |
| **Sign-in attempts** | Through Houston: 10 wrong passwords in 15 minutes block that address for a while, and each wrong one waits a second. (The Apollo API on port 5000 itself has no limit.) |
| **Requests** | Capped at 256 KB; stalled connections are dropped after 30 seconds. Requests Houston makes to other Apollos, push services and ntfy never follow redirects and read at most 1 MB |
| **Outbound** | Houston connects only to the Apollo's own API, to Kraken / Coinbase for the bitcoin price (public market data, no account; turn it off in Settings), to mempool.space, CoinGecko, alternative.me and Bitcoin Magazine for the network, market and news cards on Stats (public data; turn off in Settings), to ntfy (if you set a topic), to Apple / Google / Mozilla / Microsoft push services (if you turn on notifications on a device), and to the other Apollos you add |

Houston never calls the API's *format drive* action, and keeps the Bitcoin node software setting unchanged when it switches modes.

## The desktop setups

| | |
|---|---|
| Windows | Password stored with Windows DPAPI (only your Windows account can decrypt it). The scripts folder is restricted to your account, SYSTEM and Administrators, because the one-click shortcuts (and a PC schedule, if you use one) run those scripts as you |
| macOS | Password in your login **Keychain**; the scripts read it via `/usr/bin/security` without prompts. While setup saves it, the password is briefly visible to other processes of your own user (it's passed to `security` as an argument) |
| Linux | Password in `~/.config/apollo-miner/password` (mode 600, folder 700), like an SSH key: a file rather than the desktop keyring, so cron can use it when you're logged out. Only setup's marked block of your crontab is ever changed |
| `apollo-miner.sh` | Password and token are piped to `curl`, never on the command line |

The Houston shortcut itself stores nothing: it just opens the address.

## Tailscale

Outbound connections only, no router ports opened. Any device signed in to your Tailscale account can reach all of the Apollo's ports, including 22 (SSH) and 5000 (API). Use [Tailscale ACLs](https://tailscale.com/kb/1018/acls) if you share your tailnet with others.

## Recommendations

1. **Strong, unique dashboard password** (14+ characters, not reused). It's the master key to the box.
2. **Never port-forward** 22, 80, 3000, 5000 or 8088 to the Apollo. Use Tailscale for remote access. Port 8333 (Bitcoin P2P) is the only one that's reasonable to forward.
3. **2-step verification** on the account you sign in to Tailscale with: whoever controls it can add devices to your tailnet.
4. Give the Apollo a **DHCP reservation** so a different device never ends up at the address your shortcuts send the password to.
5. **Disable key expiry** for the Apollo in Tailscale, but remove devices you no longer use.
6. Use a phone with a screen lock. Houston on the phone keeps a never-expiring sign-in.

## Lost phone

Revoke every Apollo sign-in by giving the API a new signing secret. Desktop shortcuts log in fresh each time, so they keep working; phones and Houston must sign in again (open Houston, sign in, and save the schedule once, so its background sign-in is renewed):

```bash
ssh -t futurebit@192.168.1.50 'sudo sed -i "s/^APP_SECRET=.*/APP_SECRET=$(openssl rand -hex 64)/" /opt/apolloapi/.env && sudo systemctl restart apollo-api'
```

Also: in Houston › Settings, make a **New key** if the phone had Siri shortcuts; remove the phone from your Tailscale admin console; and change the dashboard password if you think it was exposed (then run setup again on your computers, or `apollo-miner.ps1 -Action setpassword` on Windows).

## Action links

Houston still accepts one-tap links like `…:8088/#turbo`, `#stop` or `#node-stop` (from the older phone page), only in a browser that's already signed in to Houston on that device. Opened in a normal browser tab, Houston asks before doing anything, so a link someone sends you can't act on its own. Opened from a home-screen shortcut (as an app), it runs right away. The shortcut key API (`/api/v1`) is the better choice for Siri and other automation.

## Reporting

This is an unofficial community project. For vulnerabilities in Apollo Web OS itself, contact FutureBit.
