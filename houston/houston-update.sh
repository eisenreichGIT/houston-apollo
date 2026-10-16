#!/bin/bash
# houston-update.sh - Houston's one-tap updater. Runs as root, started by systemd (houston-update.path)
# when Houston leaves an update request in its own state folder. Houston itself never runs as root.
#
# What it does, and what it won't:
#   - reads only a version number (like 2.7.1) from the request; anything else is refused
#   - downloads that release itself, over HTTPS, from Houston's GitHub repository (never from Houston)
#   - installs only Houston's own files (houston.py, this updater, web/), never runs anything it downloaded
#   - keeps the old version, restarts Houston, and puts the old version back if the new one doesn't start
# The systemd service (Houston's sandbox) and the installer are never changed by an update.

set -uo pipefail
umask 022

REPO_URL="${HOUSTON_UPDATE_URL:-https://github.com/eisenreichGIT/houston-apollo/archive/refs/tags}"
DEST="${HOUSTON_UPDATE_DEST:-/opt/houston}"
RESTART="${HOUSTON_UPDATE_RESTART:-systemctl restart houston}"
HEALTH="${HOUSTON_UPDATE_HEALTH:-http://127.0.0.1:8088/api/device}"
WAIT="${HOUSTON_UPDATE_WAIT:-60}"

# Houston's state folder (systemd's DynamicUser keeps it under /var/lib/private)
STATE="${HOUSTON_UPDATE_STATE:-}"
if [[ -z "$STATE" ]]; then
  for d in /var/lib/private/houston /var/lib/houston; do
    if [[ -f "$d/update-request" ]]; then STATE="$d"; break; fi
  done
fi
[[ -n "$STATE" && -d "$STATE" && ! -L "$STATE/update-request" ]] || exit 0
REQ="$STATE/update-request"
[[ -f "$REQ" ]] || exit 0

status() {   # state, message: a small JSON file Houston reads (owned by Houston, like its other files)
  local f="$STATE/houston-update-status.json"
  printf '{"state": "%s", "version": "%s", "message": "%s", "at": %s}\n' "$1" "${VERSION:-}" "${2//\"/\'}" "$(date +%s)" > "$f.tmp"
  chown --reference="$STATE" "$f.tmp" 2>/dev/null || true
  chmod 600 "$f.tmp"
  mv -f "$f.tmp" "$f"
}

VERSION="$(head -c 32 "$REQ" | tr -d '[:space:]')"
rm -f "$REQ"
if [[ ! "$VERSION" =~ ^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$ ]]; then
  VERSION=""; status failed "The update request wasn't a version number."; exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
status downloading "Downloading Houston $VERSION from GitHub"
PROTO="--proto =https"
[[ "$REPO_URL" == http://127.0.0.1* ]] && PROTO=""        # only the test suite uses a local address
if ! curl -fsSL $PROTO --max-time 120 --max-filesize 60000000 -o "$WORK/release.tar.gz" "$REPO_URL/v$VERSION.tar.gz"; then
  status failed "Couldn't download Houston $VERSION from GitHub."; exit 1
fi

status installing "Checking the download"
mkdir -p "$WORK/x"
if ! tar -xzf "$WORK/release.tar.gz" -C "$WORK/x" --no-same-owner --no-same-permissions 2>/dev/null; then
  status failed "The download isn't a valid release archive."; exit 1
fi
SRC="$(find "$WORK/x" -mindepth 2 -maxdepth 2 -type d -name houston | head -1)"
if [[ -z "$SRC" || ! -f "$SRC/houston.py" ]]; then status failed "The release has no Houston in it."; exit 1; fi
if [[ -n "$(find "$SRC" -type l -o -type b -o -type c -o -type p | head -1)" ]]; then
  status failed "The release contains links or special files; not installing it."; exit 1
fi
if ! grep -q "^VERSION = \"$VERSION\"$" "$SRC/houston.py"; then
  status failed "The release's version doesn't match $VERSION."; exit 1
fi
for f in houston.py web/index.html web/app.js web/theme.js web/sw.js web/manifest.json web/logo.svg; do
  [[ -f "$SRC/$f" ]] || { status failed "The release is missing $f."; exit 1; }
done
if ! python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$SRC/houston.py" 2>/dev/null; then
  status failed "The new houston.py doesn't parse; not installing it."; exit 1
fi

status installing "Installing Houston $VERSION"
rm -rf "$DEST.prev"
cp -a "$DEST" "$DEST.prev"
install_files() {   # only Houston's own files, by name
  install -m 0644 "$1/houston.py" "$DEST/houston.py"
  [[ -f "$1/houston-update.sh" ]] && install -m 0755 "$1/houston-update.sh" "$DEST/houston-update.sh.new" && mv -f "$DEST/houston-update.sh.new" "$DEST/houston-update.sh"
  mkdir -p "$DEST/web/fonts"
  local f
  for f in "$1"/web/*.html "$1"/web/*.js "$1"/web/*.json "$1"/web/*.svg "$1"/web/*.png; do
    [[ -f "$f" ]] && install -m 0644 "$f" "$DEST/web/"
  done
  for f in "$1"/web/fonts/*.woff2 "$1"/web/fonts/*.txt; do
    [[ -f "$f" ]] && install -m 0644 "$f" "$DEST/web/fonts/"
  done
  chown -R root:root "$DEST" 2>/dev/null || true
}
install_files "$SRC"

status restarting "Restarting Houston"
$RESTART
ok=0
for _ in $(seq 1 "$WAIT"); do
  sleep 1
  if curl -fs --max-time 3 "$HEALTH" 2>/dev/null | grep -q "\"version\": \"$VERSION\""; then ok=1; break; fi
done
if [[ $ok == 1 ]]; then
  status done "Houston $VERSION is installed."
  exit 0
fi
# didn't come up: put the old version back
rm -rf "$DEST.failed"; mv "$DEST" "$DEST.failed"; mv "$DEST.prev" "$DEST"
$RESTART
status failed "Houston $VERSION didn't start, so the previous version is back. Check the Houston log."
exit 1
