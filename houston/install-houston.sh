#!/bin/bash
# install-houston.sh - run ON the Apollo:  sudo bash ~/houston/install-houston.sh
#
# Installs Houston, the remote for your FutureBit Apollo:
#   - the Houston app (status, start/stop, power modes, schedule) on port 8088,
#     for any phone or computer on your network
#   - the schedule runner, so the Apollo follows your schedule by itself, 24/7
#   - Tailscale (optional), so the app also works away from home without opening
#     any ports on your router
#
# Houston lives in /opt/houston, outside FutureBit's /opt/apolloapi, so Apollo
# software updates don't remove it. It replaces the older "Apollo Remote" phone page.
#
# Options:  --no-tailscale   home network only (skip Tailscale)
#           --https          also serve Houston over HTTPS inside your tailnet
#                            (https://apollo.<your-tailnet>.ts.net)
#           --uninstall      remove Houston (leaves Tailscale and the Apollo alone)

set -euo pipefail
GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/houston
PORT=8088
UNIT=/etc/systemd/system/houston.service

say()  { echo -e "${YELLOW}---> $*${NC}"; }
ok()   { echo -e "${GREEN}---> $*${NC}"; }
fail() { echo -e "${RED}$*${NC}"; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run with sudo: sudo bash $0"

TAILSCALE=1; HTTPS=0; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --no-tailscale) TAILSCALE=0 ;;
    --https) HTTPS=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) fail "Unknown option: $a (try --help)" ;;
  esac
done

remove_old_phone_page() {
  if [[ -f /etc/systemd/system/apollo-remote.service || -d /opt/apollo-remote ]]; then
    say "Removing the old Apollo Remote phone page (Houston replaces it)"
    systemctl disable --now apollo-remote >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/apollo-remote.service
    rm -rf /opt/apollo-remote
  fi
}

if [[ $UNINSTALL == 1 ]]; then
  systemctl disable --now houston >/dev/null 2>&1 || true
  if command -v tailscale >/dev/null 2>&1; then tailscale serve --https=443 off >/dev/null 2>&1 || true; fi
  rm -f "$UNIT"; rm -rf "$DEST" /var/lib/houston /var/lib/private/houston
  remove_old_phone_page
  systemctl daemon-reload; sync
  ok "Houston removed. The Apollo keeps its current mode; nothing is scheduled any more."
  exit 0
fi

# ---------------------------------------------------------------- checks
command -v python3 >/dev/null 2>&1 || fail "python3 not found (Apollo OS includes it; is this the Apollo?)"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' || fail "Houston needs Python 3.7 or newer"
for f in houston.py web/index.html web/manifest.json web/icon-192.png web/icon-512.png web/icon-maskable-512.png web/apple-touch-icon.png web/favicon.png web/logo.svg web/fonts/archivo.woff2 web/fonts/plex-mono-400.woff2 web/fonts/plex-mono-500.woff2 web/sw.js web/app.js web/theme.js; do
  [[ -f "$SRC/$f" ]] || fail "Missing $f. Copy the whole houston folder to the Apollo, then run this again."
done
if ! curl -s --max-time 5 -o /dev/null http://127.0.0.1:5000/api/graphql 2>/dev/null; then
  echo -e "${YELLOW}Note: the Apollo API (port 5000) isn't answering right now. Houston installs anyway"
  echo -e "and starts working as soon as the Apollo software is up.${NC}"
fi

# ---------------------------------------------------------------- optional: notifications without ntfy
# Web push alerts need python3-cryptography (a standard Ubuntu package) for the encryption.
if ! python3 -c 'import cryptography' >/dev/null 2>&1; then
  say "Adding python3-cryptography (for notifications without the ntfy app)"
  if command -v apt-get >/dev/null 2>&1 && { DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-cryptography >/dev/null 2>&1 ||
       { apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-cryptography >/dev/null 2>&1; }; }; then
    ok "python3-cryptography installed"
  else
    echo -e "${YELLOW}Couldn't install python3-cryptography. Houston works; alerts just need the ntfy app.${NC}"
  fi
fi

# ---------------------------------------------------------------- install files
say "Installing Houston to $DEST"
remove_old_phone_page
mkdir -p "$DEST/web/fonts"
install -m 0644 "$SRC/houston.py" "$DEST/houston.py"
install -m 0644 "$SRC"/web/index.html "$SRC"/web/manifest.json "$SRC"/web/logo.svg "$SRC"/web/sw.js "$SRC"/web/app.js "$SRC"/web/theme.js "$SRC"/web/*.png "$DEST/web/"
install -m 0644 "$SRC"/web/fonts/*.woff2 "$SRC"/web/fonts/LICENSE.txt "$DEST/web/fonts/"
chown -R root:root "$DEST"
chmod 0755 "$DEST" "$DEST/web" "$DEST/web/fonts"

# Which Apollo is this? (Houston checks again itself; this is just for the message.)
CHASSIS="$(curl -s --max-time 5 http://127.0.0.1:3000/api/config 2>/dev/null | sed -n 's/.*"chassis":"\([^"]*\)".*/\1/p' || true)"
CHASSIS="${CHASSIS//[^a-z0-9-]/}"
if [[ -z "$CHASSIS" ]] && grep -qs '^BOARD_NAME="\?Apollo 3' /etc/armbian-release; then CHASSIS=apollo-iii; fi
[[ "$CHASSIS" == apollo-iii ]] && ok "Apollo III detected: Super Eco and custom hashrate available"

# ---------------------------------------------------------------- service
cat > "$UNIT" <<EOF
[Unit]
Description=Houston - remote and scheduler for the FutureBit Apollo
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 $DEST/houston.py
Environment=HOUSTON_WEB=$DEST/web HOUSTON_PORT=$PORT PYTHONDONTWRITEBYTECODE=1
Restart=always
RestartSec=5
# Its own throwaway user; the only writable place is /var/lib/houston (schedule,
# activity log, and the Apollo sign-in the schedule uses), readable only by Houston.
DynamicUser=yes
StateDirectory=houston
StateDirectoryMode=0700
UMask=0077
# Sandbox: read-only system, no privileges, no devices, network only
NoNewPrivileges=yes
CapabilityBoundingSet=
AmbientCapabilities=
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateUsers=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RemoveIPC=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable houston >/dev/null 2>&1
systemctl restart houston

say "Starting Houston"
UP=0
for _ in $(seq 1 15); do
  if curl -s --max-time 2 http://127.0.0.1:$PORT/api/device 2>/dev/null | grep -q '"version"'; then UP=1; break; fi
  sleep 1
done
if [[ $UP == 1 ]]; then
  ok "Houston is running on port $PORT"
else
  echo -e "${RED}---> Houston didn't start. Last log lines:${NC}"
  journalctl -u houston -n 25 --no-pager || true
  exit 1
fi

# ---------------------------------------------------------------- Tailscale
TS_IP=""; TS_NAME=""
if [[ $TAILSCALE == 1 ]]; then
  if ! command -v tailscale >/dev/null 2>&1; then
    say "Installing Tailscale (about a minute)"
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  systemctl enable --now tailscaled >/dev/null 2>&1 || true
  if ! tailscale ip -4 >/dev/null 2>&1; then
    echo
    say "Sign in to Tailscale: open the link below on your computer or phone,"
    echo -e "${YELLOW}     log in (Google works), and approve this device. Then come back here.${NC}"
    echo
    tailscale up --hostname=apollo
  fi
  TS_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  TS_NAME="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
  if [[ $HTTPS == 1 ]]; then
    say "Turning on HTTPS inside your tailnet"
    if tailscale serve --bg --https=443 http://127.0.0.1:$PORT >/dev/null 2>&1; then
      ok "HTTPS on: https://$TS_NAME"
    else
      echo -e "${YELLOW}Couldn't turn on HTTPS. In the Tailscale admin console, open DNS and enable"
      echo -e "MagicDNS and HTTPS Certificates, then run:  sudo tailscale serve --bg --https=443 http://127.0.0.1:$PORT${NC}"
      HTTPS=0
    fi
  fi
fi

sync   # this system delays disk writes; flush them now

LAN_IP="$(hostname -I | awk '{print $1}')"
echo
echo -e "${GREEN}================ Houston is ready ================${NC}"
echo -e "At home:                    http://$LAN_IP:$PORT"
if [[ -n "$TS_IP" ]]; then
  echo -e "Anywhere (Tailscale on):    http://$TS_IP:$PORT"
  [[ -n "$TS_NAME" ]] && echo -e "                            http://${TS_NAME%%.*}:$PORT"
  [[ $HTTPS == 1 && -n "$TS_NAME" ]] && echo -e "                            https://$TS_NAME"
fi
echo
echo "Open it, sign in with your Apollo dashboard password, and set your"
echo "schedule on the Schedule tab. The Apollo runs it from now on, 24/7."
if [[ -n "$TS_IP" ]]; then
  echo
  echo "Tip: in the Tailscale admin console (login.tailscale.com), open the"
  echo "'apollo' machine's ... menu and choose 'Disable key expiry' so it never"
  echo "needs re-authorizing."
fi
echo -e "${GREEN}==================================================${NC}"
