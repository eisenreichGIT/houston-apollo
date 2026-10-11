#!/usr/bin/env bash
# apollo-miner.sh - start / stop / check / switch the mode of a FutureBit Apollo (II or III).
# Used by the macOS and Linux setup (shortcuts + schedule), and on its own from any
# terminal, including on the Apollo itself (cron) so no other computer has to be on.
#
# Usage:   apollo-miner.sh [--notify] start|stop|restart|status
#          apollo-miner.sh [--notify] eco|balanced|turbo     (switch mining mode)
#          apollo-miner.sh [--notify] super_eco              (Apollo III)
#          apollo-miner.sh [--notify] custom 14              (Apollo III: target 14 TH/s, 5-20)
#          apollo-miner.sh [--notify] node_start|node_stop   (the Apollo's Bitcoin node)
#   --notify  also show the result as a desktop notification (used by the shortcuts)
#
# Where it finds things (first match wins):
#   Apollo address   $APOLLO_HOST, else ~/.config/apollo-miner/host (written by setup),
#                    else 127.0.0.1 (= running on the Apollo itself)
#   Password         $APOLLO_PASS_FILE or ~/.apollo-pass, else the macOS Keychain
#                    (service "apollo-miner-control"), else ~/.config/apollo-miner/password
#
# Manual setup on the Apollo (store the dashboard password, readable only by you):
#   (umask 077; read -rsp 'Dashboard password: ' P && printf '%s\n' "$P" > ~/.apollo-pass); echo
#
# Example crontab on the Apollo (crontab -e): weekdays 9:30 AM start, 4:30 PM stop
#   30 9  * * 1-5  $HOME/apollo-miner.sh start >> $HOME/apollo-miner.log 2>&1
#   30 16 * * 1-5  $HOME/apollo-miner.sh stop  >> $HOME/apollo-miner.log 2>&1
# ...or mine 24/7 in Eco, Turbo on weekdays 9:30 AM - 4:30 PM:
#   30 9  * * 1-5  $HOME/apollo-miner.sh turbo >> $HOME/apollo-miner.log 2>&1
#   30 16 * * 1-5  $HOME/apollo-miner.sh eco   >> $HOME/apollo-miner.log 2>&1
# ...Apollo III: Super Eco 24/7, 16 TH/s on weekdays 9:30 AM - 4:30 PM:
#   30 9  * * 1-5  $HOME/apollo-miner.sh custom 16 >> $HOME/apollo-miner.log 2>&1
#   30 16 * * 1-5  $HOME/apollo-miner.sh super_eco >> $HOME/apollo-miner.log 2>&1

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/apollo-miner"
KEYCHAIN_SERVICE="apollo-miner-control"

NOTIFY=0
if [[ "${1:-}" == --notify ]]; then NOTIFY=1; shift; fi
ACTION="${1:-status}"
HASHRATE="${2:-}"
LAST=""

log() { LAST="$*"; echo "$(date '+%Y-%m-%d %H:%M:%S')  $*"; }
fail() { log "ERROR: $*"; exit 1; }

# Desktop notification with the last message (shortcuts run without a terminal)
notify() {
  local msg="$1" esc
  if [[ "$(uname -s)" == Darwin ]]; then
    esc="${msg//\\/\\\\}"; esc="${esc//\"/\\\"}"
    osascript -e "display notification \"$esc\" with title \"Houston\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Houston" "Houston" "$msg" >/dev/null 2>&1 || true
  elif command -v zenity >/dev/null 2>&1; then
    zenity --notification --text="Houston: $msg" >/dev/null 2>&1 || true
  fi
}
on_exit() { [[ "$NOTIFY" == 1 && -n "$LAST" ]] && notify "${LAST#ERROR: }"; return 0; }
trap on_exit EXIT

usage() { LAST="Unknown action '$ACTION'"; echo "Usage: $0 [--notify] start|stop|restart|status|super_eco|eco|balanced|turbo|custom <5-20>|node_start|node_stop"; exit 2; }

case "$ACTION" in start|stop|restart|status|super_eco|eco|balanced|turbo|custom|node_start|node_stop|check) ;; *) usage;; esac
if [[ "$ACTION" == custom ]] && ! [[ "$HASHRATE" =~ ^[0-9]+$ && "$HASHRATE" -ge 5 && "$HASHRATE" -le 20 ]]; then
  LAST="custom needs a target hashrate between 5 and 20 TH/s"
  echo "custom needs a target hashrate between 5 and 20 TH/s, e.g.: $0 custom 14"; exit 2
fi

if [[ -z "${APOLLO_HOST:-}" && -r "$CONFIG_DIR/host" ]]; then APOLLO_HOST="$(head -n1 "$CONFIG_DIR/host" | tr -d '[:space:]')"; fi
APOLLO_HOST="${APOLLO_HOST:-127.0.0.1}"
[[ "$APOLLO_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || fail "Invalid Apollo address '$APOLLO_HOST'"
URL="http://${APOLLO_HOST}:5000/api/graphql"

get_password() {
  local f="${APOLLO_PASS_FILE:-$HOME/.apollo-pass}"
  if [[ -n "${APOLLO_PASSWORD:-}" ]]; then printf '%s' "$APOLLO_PASSWORD"; return 0; fi   # used by setup's login test
  if [[ -r "$f" ]]; then head -n1 "$f"; return 0; fi
  if [[ "$(uname -s)" == Darwin ]] && security find-generic-password -s "$KEYCHAIN_SERVICE" -a "${USER:-$(id -un)}" -w 2>/dev/null; then return 0; fi
  if [[ -r "$CONFIG_DIR/password" ]]; then head -n1 "$CONFIG_DIR/password"; return 0; fi
  return 1
}

gql() {  # gql <json-body> [token] [timeout-seconds]
  # body and token go via stdin / a pipe so they never appear in the process list
  local t="${3:-30}" hdr=""
  [[ -n "${2:-}" ]] && hdr="Authorization: Bearer $2"
  printf '%s' "$1" | curl -sS --max-time "$t" -X POST "$URL" -H 'Content-Type: application/json' \
    -H @<(printf '%s\n' "$hdr") --data-binary @-
}

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

PASSWORD="$(get_password)" || fail "No saved password. Run the setup again (or create ~/.apollo-pass, see the top of this script)."
PASS="$(json_escape "$PASSWORD")"; PASSWORD=""
LOGIN_Q='query ($p: String!) { Auth { login(input: { password: $p }) { result { accessToken } error { message } } } }'
if ! RESP="$(gql "{\"query\":\"$LOGIN_Q\",\"variables\":{\"p\":\"$PASS\"}}" "" 15 2>/dev/null)"; then
  [[ "$ACTION" == check ]] && { echo "unreachable"; exit 3; }
  fail "Can't reach the Apollo at $APOLLO_HOST. Is it switched on and on this network?"
fi
TOKEN="$(printf '%s' "$RESP" | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')"
if [[ -z "$TOKEN" ]]; then
  [[ "$ACTION" == check ]] && { echo "badpassword"; exit 4; }
  fail "Login failed: wrong password? Run the setup again to update it."
fi

status() {
  gql '{"query":"query { Miner { online { result { online { status } } } } }"}' "$TOKEN" \
    | sed -n 's/.*"status":"\([^"]*\)".*/\1/p'
}
node_status() {
  gql '{"query":"query { Node { online { result { online { status } } } } }"}' "$TOKEN" \
    | sed -n 's/.*"status":"\([^"]*\)".*/\1/p'
}

if [[ "$ACTION" == node_start || "$ACTION" == node_stop ]]; then
  CMD="${ACTION#node_}"
  # Apollo software 2.1.4+ takes node start/stop as a mutation; older software only knows the query form
  RESP="$(gql "{\"query\":\"mutation { Node { $CMD { error { message } } } }\"}" "$TOKEN" 150)" || RESP=""
  if [[ "$RESP" == *'Cannot query field'* || "$RESP" == *'not configured for mutations'* ]]; then
    RESP="$(gql "{\"query\":\"query { Node { $CMD { error { message } } } }\"}" "$TOKEN" 150)"
  fi
  [[ "$RESP" == *'"error":null'* ]] || fail "node $CMD failed: $RESP"
  sleep "${APOLLO_NODE_WAIT:-3}"
  if [[ "$CMD" == start ]]; then log "Bitcoin node start sent. Current status: $(node_status || echo unknown)"
  else log "Bitcoin node stopped. Current status: $(node_status || echo unknown)"; fi
  exit 0
fi

# Apollo III? Same check the dashboard makes: /api/config reports chassis "apollo-iii".
# (On the Apollo itself the dashboard is on port 3000; port 80 is only redirected for other machines.)
is_apollo3() {
  local u
  for u in "http://${APOLLO_HOST}/api/config" "http://${APOLLO_HOST}:3000/api/config"; do
    if curl -s --max-time 5 "$u" 2>/dev/null | grep -q '"chassis":"apollo-iii"'; then return 0; fi
  done
  grep -qs '^BOARD_NAME="\?Apollo 3' /etc/armbian-release && [[ "$APOLLO_HOST" == 127.0.0.1 || "$APOLLO_HOST" == localhost ]]
}

settings() {  # prints the Settings JSON (minerMode, [minerHashrate,] nodeSoftware)
  # minerHashrate only exists on Apollo III software; older software rejects the field
  local f='minerMode nodeSoftware'; [[ "$III" == 1 ]] && f='minerMode minerHashrate nodeSoftware'
  gql "{\"query\":\"query { Settings { read { result { settings { $f } } error { message } } } }\"}" "$TOKEN"
}
field()  { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
number() { sed -n "s/.*\"$1\":\([0-9][0-9]*\).*/\1/p"; }
label()  { case "$1" in super_eco) echo "Super Eco";; custom) echo "custom ${2:-?} TH/s";; *) echo "$1";; esac; }

III=0; is_apollo3 && III=1

if [[ "$ACTION" == check ]]; then   # used by setup: "ok <model> <status> <mode>"
  S="$(settings)"; MODEL=apollo-ii; [[ "$III" == 1 ]] && MODEL=apollo-iii
  M="$(printf '%s' "$S" | field minerMode)"; H="$(printf '%s' "$S" | number minerHashrate)"
  [[ "$M" == custom && -n "$H" ]] && M="custom:$H"
  LAST=""; echo "ok $MODEL $(status) ${M:-unknown}"; exit 0
fi

if [[ "$ACTION" == status ]]; then
  S="$(settings)"; MODEL="Apollo II"; [[ "$III" == 1 ]] && MODEL="Apollo III"
  log "Miner status: $(status) ($(label "$(printf '%s' "$S" | field minerMode)" "$(printf '%s' "$S" | number minerHashrate)") mode, $MODEL), Bitcoin node: $(node_status || echo unknown)"; exit 0
fi

if [[ "$ACTION" =~ ^(super_eco|eco|balanced|turbo|custom)$ ]]; then
  if [[ "$ACTION" =~ ^(super_eco|custom)$ && "$III" != 1 ]]; then
    fail "$(label "$ACTION" "$HASHRATE") is only available on the Apollo III. This Apollo supports eco, balanced and turbo."
  fi
  S="$(settings)"; CUR="$(printf '%s' "$S" | field minerMode)"; CURH="$(printf '%s' "$S" | number minerHashrate)"
  NODE="$(printf '%s' "$S" | field nodeSoftware)"
  [[ -n "$CUR" ]] || fail "couldn't read settings: $S"
  ST="$(status)"; BEFORE="$(label "$CUR" "$CURH")"; AFTER="$(label "$ACTION" "$HASHRATE")"
  if [[ "$CUR" == "$ACTION" && ( "$ACTION" != custom || "$CURH" == "$HASHRATE" ) ]]; then
    log "Already in $AFTER mode (miner $ST)."; exit 0
  fi
  # Send nodeSoftware back unchanged: Apollo software up to 2.1.2 treats a missing value
  # as a node software change and would needlessly stop/restart the Bitcoin node.
  if [[ -n "$NODE" ]]; then NODEJSON="\"$NODE\""; else NODEJSON=null; fi
  if [[ "$ACTION" == custom ]]; then
    UQ='query ($m: MinerMode!, $n: NodeSoftware, $h: Int) { Settings { update(input: { minerMode: $m, nodeSoftware: $n, minerHashrate: $h }) { result { settings { minerMode } } error { message } } } }'
    VARS="{\"m\":\"custom\",\"n\":$NODEJSON,\"h\":$HASHRATE}"
  else
    UQ='query ($m: MinerMode!, $n: NodeSoftware) { Settings { update(input: { minerMode: $m, nodeSoftware: $n }) { result { settings { minerMode } } error { message } } } }'
    VARS="{\"m\":\"$ACTION\",\"n\":$NODEJSON}"
  fi
  RESP="$(gql "{\"query\":\"$UQ\",\"variables\":$VARS}" "$TOKEN" 60)"
  [[ "$RESP" == *'"error":null'* ]] || fail "couldn't change mode: $RESP"
  if [[ "$ST" == offline ]]; then
    log "Mode set to $AFTER ($BEFORE before). Miner is stopped; it will use $AFTER next time it starts."; exit 0
  fi
  RESP="$(gql '{"query":"query { Miner { restart { error { message } } } }"}' "$TOKEN" 180)"
  [[ "$RESP" == *'"error":null'* ]] || fail "mode saved, but miner restart failed: $RESP"
  log "Switched from $BEFORE to $AFTER mode. Miner restarting (about a minute)."; exit 0
fi

# start/restart can take ~40-60s (the Apollo waits ~35s for its hashboards before replying)
RESP="$(gql "{\"query\":\"query { Miner { $ACTION { error { message } } } }\"}" "$TOKEN" 180)"
if [[ "$RESP" == *'"error":null'* ]]; then
  sleep "${APOLLO_WAIT:-10}"
  log "Miner $ACTION sent successfully. Current status: $(status || echo unknown)"
else
  fail "miner $ACTION failed: $RESP"
fi
