#!/usr/bin/env bash
# apollo-setup.sh - Houston desktop setup / uninstall for macOS and Linux.
# Started by macos/Setup.command, macos/Uninstall.command, linux/setup.sh, linux/uninstall.sh.
#
#   apollo-setup.sh install      guided setup (dialogs on macOS, zenity on Linux, else terminal)
#   apollo-setup.sh uninstall    remove shortcuts and schedule
#
#   APOLLO_UI=terminal           force terminal questions instead of dialogs
#
# What setup does
#   - finds your Apollo (network search) and checks the dashboard password
#   - saves the password: macOS Keychain, or a file only you can read on Linux
#   - copies apollo-miner.sh to a fixed place (so you can delete the download)
#   - checks for Houston on the Apollo (the app + scheduler, see houston/)
#   - creates the shortcuts you pick: the Houston app, Start/Stop/Status, power modes,
#     Bitcoin node. macOS: apps in ~/Applications/Houston (Launchpad). Linux: launchers
#     in your app menu (and on the Desktop if you have one)
#   - schedule: Houston runs it on the Apollo, so any old schedule on this computer is
#     removed. Without Houston, setup can still schedule from this computer
#     (launchd agents on macOS, cron or systemd user timers on Linux)
#
# Works with the bash 3.2 that ships with macOS: no associative arrays, no ${x,,}.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OS="${APOLLO_OS:-$(uname -s)}"                       # Darwin | Linux
TITLE="Houston"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/apollo-miner"
KEYCHAIN_SERVICE="apollo-miner-control"
WEEKDAYS="Monday Tuesday Wednesday Thursday Friday Saturday Sunday"
CRON_BEGIN="# BEGIN apollo-miner-control (managed by setup - edit with setup)"
CRON_END="# END apollo-miner-control"
LAUNCHD_PREFIX="com.apollominercontrol"

if [[ "$OS" == Darwin ]]; then
  INSTALL_DIR="$HOME/Library/Application Support/Apollo Miner Control"
  APPS_DIR="$HOME/Applications/Houston"
  OLD_APPS_DIR="$HOME/Applications/Apollo Miner"     # before Houston
  LOG_FILE="$HOME/Library/Logs/apollo-miner.log"
  ICON_DIR="$ROOT/macos/icons"; ICON_EXT=icns
else
  INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/apollo-miner-control"
  APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  OLD_APPS_DIR=""
  LOG_FILE="$INSTALL_DIR/apollo-miner.log"
  ICON_DIR="$ROOT/linux/icons"; ICON_EXT=png
fi
ENGINE="$INSTALL_DIR/apollo-miner.sh"

# ---------------------------------------------------------------------------
#  UI layer: osascript (macOS) | zenity (Linux desktop) | terminal
# ---------------------------------------------------------------------------
if [[ -n "${APOLLO_UI:-}" ]]; then UI="$APOLLO_UI"
elif [[ "$OS" == Darwin ]] && command -v osascript >/dev/null 2>&1; then UI=mac
elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v zenity >/dev/null 2>&1; then UI=zenity
else UI=terminal; fi

cancelled() { [[ "$UI" == terminal ]] && echo; echo "Setup cancelled. Nothing was changed."; exit 1; }

as_q() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }   # AppleScript string literal
as_list() { local out="" x; for x in "$@"; do out="$out${out:+, }$(as_q "$x")"; done; printf '{%s}' "$out"; }
mac_icon() { if [[ -f "$ICON_DIR/houston.icns" ]]; then printf 'with icon (POSIX file %s)' "$(as_q "$ICON_DIR/houston.icns")"; else printf 'with icon note'; fi; }
osa() { osascript -e "$1" 2>/dev/null; }

ui_info() {   # ui_info "text"
  case "$UI" in
    mac)    osa "activate
display dialog $(as_q "$1") with title $(as_q "$TITLE") buttons {\"OK\"} default button \"OK\" $(mac_icon)" >/dev/null ;;
    zenity) zenity --info --title="$TITLE" --width=440 --text="$1" 2>/dev/null ;;
    *)      printf '\n%s\n' "$1" ;;
  esac
}

ui_error() {
  case "$UI" in
    mac)    osa "activate
display dialog $(as_q "$1") with title $(as_q "$TITLE") buttons {\"OK\"} default button \"OK\" with icon caution" >/dev/null ;;
    zenity) zenity --error --title="$TITLE" --width=440 --text="$1" 2>/dev/null ;;
    *)      printf '\n  ! %s\n' "$1" ;;
  esac
}

ui_confirm() {   # ui_confirm "text" "yes-label" "no-label" [default: yes|no]  -> 0 yes, 1 no
  local yes="${2:-Continue}" no="${3:-Cancel}" def="${4:-yes}" r
  case "$UI" in
    mac)
      local defb="$yes"; [[ "$def" == no ]] && defb="$no"
      r="$(osa "activate
set r to display dialog $(as_q "$1") with title $(as_q "$TITLE") buttons {$(as_q "$no"), $(as_q "$yes")} default button $(as_q "$defb") $(mac_icon)
return button returned of r")" || return 1
      [[ "$r" == "$yes" ]] ;;
    zenity)
      local extra=(); [[ "$def" == no ]] && extra=(--default-cancel)
      zenity --question --title="$TITLE" --width=460 --ok-label="$yes" --cancel-label="$no" ${extra[@]+"${extra[@]}"} --text="$1" 2>/dev/null ;;
    *)
      printf '\n%s\n' "$1"
      local hint="[Y/n]"; [[ "$def" == no ]] && hint="[y/N]"
      while true; do
        read -r -p "  $yes? $hint " r || cancelled
        case "$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')" in
          '') [[ "$def" == yes ]]; return;; y|yes) return 0;; n|no) return 1;; esac
      done ;;
  esac
}

ui_input() {   # ui_input "prompt" "default"  -> prints the answer; 1 = cancelled
  local r
  case "$UI" in
    mac)
      osa "activate
set r to display dialog $(as_q "$1") default answer $(as_q "$2") with title $(as_q "$TITLE") buttons {\"Cancel\", \"Continue\"} default button \"Continue\" cancel button \"Cancel\" $(mac_icon)
return text returned of r" ;;
    zenity) zenity --entry --title="$TITLE" --width=440 --text="$1" --entry-text="$2" 2>/dev/null ;;
    *)
      read -r -p "  $1${2:+ [$2]}: " r || return 1
      printf '%s\n' "${r:-$2}" ;;
  esac
}

ui_password() {   # ui_password "prompt"
  local r
  case "$UI" in
    mac)
      osa "activate
set r to display dialog $(as_q "$1") default answer \"\" with hidden answer with title $(as_q "$TITLE") buttons {\"Cancel\", \"Continue\"} default button \"Continue\" cancel button \"Cancel\" $(mac_icon)
return text returned of r" ;;
    zenity) zenity --password --title="$TITLE" 2>/dev/null ;;
    *)
      read -r -s -p "  $1: " r || return 1; echo >&2
      printf '%s\n' "$r" ;;
  esac
}

ui_choose() {   # ui_choose "prompt" "default" item...   -> prints the chosen item; 1 = cancelled
  local prompt="$1" def="$2" r i n; shift 2
  case "$UI" in
    mac)
      r="$(osa "activate
set r to choose from list $(as_list "$@") with title $(as_q "$TITLE") with prompt $(as_q "$prompt") default items {$(as_q "$def")} OK button name \"Continue\" cancel button name \"Cancel\"
if r is false then return \"\"
return item 1 of r")" || return 1
      [[ -n "$r" ]] || return 1; printf '%s\n' "$r" ;;
    zenity)
      local args=() x
      for x in "$@"; do if [[ "$x" == "$def" ]]; then args+=(TRUE "$x"); else args+=(FALSE "$x"); fi; done
      zenity --list --radiolist --title="$TITLE" --text="$prompt" --width=520 --height=$((170 + 34 * $#)) \
        --column="" --column="Option" --hide-header "${args[@]}" 2>/dev/null ;;
    *)
      printf '\n  %s\n' "$prompt" >&2
      i=1; n=1; for x in "$@"; do printf '    %d) %s\n' "$i" "$x" >&2; [[ "$x" == "$def" ]] && n=$i; i=$((i + 1)); done
      while true; do
        read -r -p "  Choose 1-$# [$n]: " r || return 1
        r="${r:-$n}"
        if [[ "$r" =~ ^[0-9]+$ ]] && (( r >= 1 && r <= $# )); then eval "printf '%s\n' \"\${$r}\""; return 0; fi
      done ;;
  esac
}

ui_days() {   # ui_days "prompt"  -> prints day numbers 1-7 (Mon-Sun), space separated
  local r out="" d
  case "$UI" in
    mac)
      r="$(osa "activate
set r to choose from list {\"Monday\", \"Tuesday\", \"Wednesday\", \"Thursday\", \"Friday\", \"Saturday\", \"Sunday\"} with title $(as_q "$TITLE") with prompt $(as_q "$1 (hold Command to pick several)") default items {\"Monday\", \"Tuesday\", \"Wednesday\", \"Thursday\", \"Friday\"} OK button name \"Continue\" cancel button name \"Cancel\" with multiple selections allowed
if r is false then return \"\"
set AppleScript's text item delimiters to \",\"
return r as text")" || return 1
      [[ -n "$r" ]] || return 1
      parse_days "$r" ;;
    zenity)
      r="$(zenity --list --checklist --title="$TITLE" --text="$1" --width=380 --height=420 --separator="," \
        --column="" --column="Day" --hide-header TRUE Monday TRUE Tuesday TRUE Wednesday TRUE Thursday TRUE Friday FALSE Saturday FALSE Sunday 2>/dev/null)" || return 1
      [[ -n "$r" ]] || return 1
      parse_days "$r" ;;
    *)
      while true; do
        read -r -p "  $1 (e.g. Mon-Fri, Sat,Sun, every day) [Mon-Fri]: " r || return 1
        if out="$(parse_days "${r:-Mon-Fri}")" && [[ -n "$out" ]]; then printf '%s\n' "$out"; return 0; fi
        echo "  Couldn't read those days." >&2
      done ;;
  esac
}

# ---------------------------------------------------------------------------
#  Parsing and labels
# ---------------------------------------------------------------------------
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

day_index() {   # "mon"/"monday" -> 1..7
  local d; d="$(lower "$1")"; [[ ${#d} -ge 2 ]] || return 1
  local i=1 w
  for w in $WEEKDAYS; do case "$(lower "$w")" in "$d"*) echo "$i"; return 0;; esac; i=$((i + 1)); done
  return 1
}

parse_days() {   # "Mon-Fri, Sun" / "weekends" / "every day" / "Monday,Tuesday" -> "1 2 3 4 5 7"
  local t part a b i set=" " out=""
  t="$(lower "$1")"
  t="$(printf ' %s ' "$t" | sed -E 's/every ?day|daily|7 days/all/g; s/[[:space:]]+(to|through|thru)[[:space:]]+/-/g; s/[[:space:]]*-[[:space:]]*/-/g; s/[[:space:]]and[[:space:]]/,/g; s/[,;\/&+[:space:]]+/ /g')"
  for part in $t; do
    case "$part" in
      all|everyday) set=" 1 2 3 4 5 6 7 " ;;
      weekday|weekdays|workday|workdays) set="$set1 2 3 4 5 " ;;
      weekend|weekends) set="$set6 7 " ;;
      *-*)
        a="$(day_index "${part%%-*}")" || return 1; b="$(day_index "${part#*-}")" || return 1
        i=$a; while true; do set="$set$i "; [[ $i == "$b" ]] && break; i=$(( i % 7 + 1 )); done ;;
      *) a="$(day_index "$part")" || return 1; set="$set$a " ;;
    esac
  done
  for i in 1 2 3 4 5 6 7; do case "$set" in *" $i "*) out="$out${out:+ }$i";; esac; done
  [[ -n "$out" ]] || return 1
  printf '%s\n' "$out"
}

day_name() { echo "$WEEKDAYS" | cut -d' ' -f"$1"; }

format_days() {   # "1 2 3 4 5" -> "Mon-Fri"
  local days=($1) out="" i=0 j s e n=${#days[@]}
  [[ $n -eq 7 ]] && { echo "Every day"; return; }
  while (( i < n )); do
    j=$i; while (( j + 1 < n )) && (( days[j+1] == days[j] + 1 )); do j=$((j + 1)); done
    s="$(day_name "${days[i]}" | cut -c1-3)"; e="$(day_name "${days[j]}" | cut -c1-3)"
    if (( j - i >= 2 )); then out="$out${out:+,}$s-$e"; elif (( j > i )); then out="$out${out:+,}$s,$e"; else out="$out${out:+,}$s"; fi
    i=$((j + 1))
  done
  echo "$out"
}

next_days() { local d out=""; for d in $1; do out="$out $(( d % 7 + 1 ))"; done; echo $out | tr ' ' '\n' | sort -n | tr '\n' ' ' | sed 's/ $//'; }

parse_time() {   # "9:30", "09:30", "9:30 PM", "9pm", "21:00" -> "H M" (24h)
  local t h m ap re='^([0-9]{1,2})(:([0-9]{2}))?[[:space:]]*([ap])?m?$'
  t="$(lower "$1" | tr -d '.' | sed 's/^ *//; s/ *$//')"
  [[ "$t" =~ $re ]] || return 1
  h=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[3]:-0})); ap="${BASH_REMATCH[4]}"
  (( m <= 59 )) || return 1
  if [[ -n "$ap" ]]; then
    (( h >= 1 && h <= 12 )) || return 1
    [[ "$ap" == a && $h -eq 12 ]] && h=0
    [[ "$ap" == p && $h -lt 12 ]] && h=$((h + 12))
  fi
  (( h <= 23 )) || return 1
  echo "$h $m"
}

fmt_time() {   # "21 30" -> "9:30 PM"
  local h=${1% *} m=${1#* } ap=AM
  (( h >= 12 )) && ap=PM; local h12=$(( h % 12 )); (( h12 == 0 )) && h12=12
  printf '%d:%02d %s\n' "$h12" "$m" "$ap"
}

minutes() { echo $(( ${1% *} * 60 + ${1#* } )); }

mode_label() {
  case "$1" in super_eco) echo "Super Eco";; eco) echo "Eco";; balanced) echo "Balanced";; turbo) echo "Turbo";;
    custom:*) echo "${1#custom:} TH/s";; *) echo "$1";; esac
}
mode_args() { case "$1" in custom:*) echo "custom ${1#custom:}";; *) echo "$1";; esac; }

ask_time() {   # ask_time "prompt" "default" [allow-never]  -> "H M" or "never"
  local r t
  while true; do
    r="$(ui_input "$1" "$2")" || cancelled
    if [[ -n "${3:-}" ]] && [[ "$(lower "$r")" =~ ^(never|none|no|)$ ]]; then echo never; return; fi
    if t="$(parse_time "$r")"; then echo "$t"; return; fi
    ui_error "\"$r\" isn't a time setup understands. Use something like 9:30 AM, 4:30 PM or 21:00."
  done
}

ask_mode() {   # ask_mode "prompt" "default-token" token...  -> token
  local prompt="$1" def="$2" labels=() t r h; shift 2
  for t in "$@"; do if [[ "$t" == custom ]]; then labels+=("Custom hashrate target"); else labels+=("$(mode_label "$t")"); fi; done
  r="$(ui_choose "$prompt" "$(mode_label "$def")" "${labels[@]}")" || cancelled
  case "$r" in
    "Custom hashrate target")
      local hs=() x; for x in 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do hs+=("$x TH/s"); done
      h="$(ui_choose "Target hashrate (the Apollo III tunes itself to hit it):" "16 TH/s" "${hs[@]}")" || cancelled
      echo "custom:${h%% *}" ;;
    "Super Eco") echo super_eco ;;
    *) lower "$r" ;;
  esac
}

# ---------------------------------------------------------------------------
#  Apollo access
# ---------------------------------------------------------------------------
local_prefixes() {   # print "a.b.c" for this computer's IPv4 networks
  local ips=""
  if [[ "$OS" == Darwin ]]; then
    local i; for i in en0 en1 en2 en3 en4 en5; do ips="$ips $(ipconfig getifaddr "$i" 2>/dev/null)"; done
  else
    ips="$(hostname -I 2>/dev/null || true) $(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)"
  fi
  printf '%s\n' $ips | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -vE '^(127|169\.254)\.' | cut -d. -f1-3 | sort -u
}

find_apollos() {   # scan each local /24 for the Apollo API on port 5000
  local p
  for p in $(local_prefixes); do
    seq 1 254 | sed "s/^/$p./" | xargs -P 64 -n 1 sh -c '
      r=$(curl -s --max-time 2 -X POST "http://$1:5000/api/graphql" -H "Content-Type: application/json" \
          --data "{\"query\":\"query { Auth { status { result { status } } } }\"}" 2>/dev/null)
      case "$r" in *\"Auth\"*) echo "$1";; esac' _ 2>/dev/null
  done | sort -t. -k4 -n -u
}

check_login() {   # check_login host password -> "ok model status mode" / exit 3 unreachable, 4 bad password
  APOLLO_HOST="$1" APOLLO_PASSWORD="$2" APOLLO_PASS_FILE=/nonexistent bash "$ROOT/scripts/apollo-miner.sh" check
}

save_password() {   # store the dashboard password where apollo-miner.sh looks for it
  local pw="$1"
  mkdir -p "$CONFIG_DIR"; chmod 700 "$CONFIG_DIR"
  if [[ "$OS" == Darwin ]]; then
    # -T /usr/bin/security lets the scripts read it later without a Keychain prompt
    security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "${USER:-$(id -un)}" -l "Houston (Apollo dashboard password)" \
      -T /usr/bin/security -w "$pw" >/dev/null 2>&1 || return 1
    rm -f "$CONFIG_DIR/password"
  else
    ( umask 077; printf '%s\n' "$pw" > "$CONFIG_DIR/password" )
  fi
}

# ---------------------------------------------------------------------------
#  Shortcuts
# ---------------------------------------------------------------------------
SC_ACTIONS=(start stop status super_eco eco balanced turbo node_start node_stop)
SC_NAMES=("Start Miner" "Stop Miner" "Miner Status" "Super Eco Mode" "Eco Mode" "Balanced Mode" "Turbo Mode" "Start Bitcoin Node" "Stop Bitcoin Node")
SC_GROUPS=(control control control modes modes modes modes node node)

remove_shortcuts() {
  local a
  if [[ "$OS" == Darwin ]]; then rm -rf "$APPS_DIR"; [[ -n "$OLD_APPS_DIR" ]] && rm -rf "$OLD_APPS_DIR"; return; fi
  for a in "${SC_ACTIONS[@]}" houston; do
    rm -f "$APPS_DIR/apollo-miner-$a.desktop" "$(desktop_dir)/apollo-miner-$a.desktop"
  done
}

# Houston on the Apollo? Prints its version, or nothing.
houston_version() {
  curl -s --max-time 4 "http://$1:8088/api/device" 2>/dev/null | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p'
}

# A browser that can open Houston in its own app window (no tabs or address bar)
app_browser() {
  local b
  if [[ "$OS" == Darwin ]]; then
    for b in "/Applications/Google Chrome.app" "/Applications/Microsoft Edge.app" "/Applications/Brave Browser.app" "/Applications/Chromium.app"; do
      [[ -d "$b" ]] && { echo "$b"; return; }
    done
    return
  fi
  for b in chromium chromium-browser google-chrome google-chrome-stable microsoft-edge brave-browser; do
    command -v "$b" >/dev/null 2>&1 && { command -v "$b"; return; }
  done
}

install_desktop_file() {   # install_desktop_file <file>: app menu + Desktop folder
  local f="$1" dd; chmod 755 "$f"
  dd="$(desktop_dir)"
  if [[ -d "$dd" ]]; then
    cp "$f" "$dd/"; chmod 755 "$dd/$(basename "$f")"
    gio set "$dd/$(basename "$f")" metadata::trusted true >/dev/null 2>&1 || true
  fi
}

create_houston_shortcut() {   # create_houston_shortcut <url>
  local url="$1" b; b="$(app_browser)"
  if [[ "$OS" == Darwin ]]; then
    local app="$APPS_DIR/Houston.app" script
    if [[ -n "$b" ]]; then script="do shell script \"open -na \" & quoted form of \"$b\" & \" --args --app=\" & quoted form of \"$url\""
    else script="open location \"$url\""; fi
    osacompile -o "$app" -e "$script" >/dev/null 2>&1 || { echo "  ! Couldn't create Houston.app" >&2; return; }
    if [[ -f "$ICON_DIR/houston.icns" ]]; then
      cp "$ICON_DIR/houston.icns" "$app/Contents/Resources/applet.icns"
      codesign --force --sign - "$app" >/dev/null 2>&1 || true
      touch "$app"
    fi
    return
  fi
  local f="$APPS_DIR/apollo-miner-houston.desktop" ex
  if [[ -n "$b" ]]; then ex="\"$b\" --app=$url"; else ex="xdg-open $url"; fi
  cat > "$f" <<EOF
[Desktop Entry]
Type=Application
Name=Houston
Comment=Mission control for your FutureBit Apollo
Exec=$ex
Icon=$INSTALL_DIR/icons/houston.png
Terminal=false
Categories=Utility;Network;
EOF
  install_desktop_file "$f"
}

desktop_dir() { local d; d="$(xdg-user-dir DESKTOP 2>/dev/null || true)"; [[ -n "$d" && "$d" != "$HOME" ]] || d="$HOME/Desktop"; echo "$d"; }

create_shortcuts() {   # create_shortcuts is_iii "groups" [houston-url]   groups: houston control modes node
  local iii="$1" groups=" $2 " url="${3:-}" i action name
  remove_shortcuts
  mkdir -p "$APPS_DIR"
  [[ "$groups" == *" houston "* && -n "$url" ]] && create_houston_shortcut "$url"
  for (( i = 0; i < ${#SC_ACTIONS[@]}; i++ )); do
    action="${SC_ACTIONS[i]}"; name="${SC_NAMES[i]}"
    [[ "$groups" == *" ${SC_GROUPS[i]} "* ]] || continue
    [[ "$action" == super_eco && "$iii" != 1 ]] && continue
    if [[ "$OS" == Darwin ]]; then
      local app="$APPS_DIR/$name.app"
      osacompile -o "$app" -e "do shell script \"/bin/bash \" & quoted form of \"$ENGINE\" & \" --notify $action >> \" & quoted form of \"$LOG_FILE\" & \" 2>&1 || true\"" >/dev/null 2>&1 \
        || { echo "  ! Couldn't create $name.app" >&2; continue; }
      if [[ -f "$ICON_DIR/$action.icns" ]]; then
        cp "$ICON_DIR/$action.icns" "$app/Contents/Resources/applet.icns"
        codesign --force --sign - "$app" >/dev/null 2>&1 || true   # re-seal after changing the icon
        touch "$app"
      fi
    else
      local f="$APPS_DIR/apollo-miner-$action.desktop"
      cat > "$f" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=Houston: $name
Exec=/bin/bash "$ENGINE" --notify $action
Icon=$INSTALL_DIR/icons/$action.png
Terminal=false
Categories=Utility;
EOF
      install_desktop_file "$f"
    fi
  done
}

# ---------------------------------------------------------------------------
#  Schedule: launchd (macOS) / cron or systemd user timers (Linux)
# ---------------------------------------------------------------------------
# Tasks are lines: "<H> <M> <days 1-7 comma-separated> <action args...>"
TASKS=()

add_task() { TASKS+=("$1 $2 $3 $4"); }   # add_task H M "1,2,3" "turbo"

remove_schedule() {
  if [[ "$OS" == Darwin ]]; then
    local f
    for f in "$HOME/Library/LaunchAgents/$LAUNCHD_PREFIX".*.plist; do
      [[ -e "$f" ]] || continue
      launchctl bootout "gui/$(id -u)" "$f" >/dev/null 2>&1 || launchctl unload "$f" >/dev/null 2>&1 || true
      rm -f "$f"
    done
    return
  fi
  if command -v crontab >/dev/null 2>&1; then
    local cur; cur="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$cur" | grep -qF "$CRON_BEGIN"; then
      printf '%s\n' "$cur" | sed "/^# BEGIN apollo-miner-control/,/^# END apollo-miner-control/d" | crontab -
    fi
  fi
  local u
  for u in "${XDG_CONFIG_HOME:-$HOME/.config}"/systemd/user/apollo-miner-*.timer; do
    [[ -e "$u" ]] || continue
    systemctl --user disable --now "$(basename "$u")" >/dev/null 2>&1 || true
    rm -f "$u" "${u%.timer}.service"
  done
  systemctl --user daemon-reload >/dev/null 2>&1 || true
}

install_schedule() {
  remove_schedule
  [[ ${#TASKS[@]} -gt 0 ]] || return 0
  local t h m days args n=0
  if [[ "$OS" == Darwin ]]; then
    mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$LOG_FILE")"
    for t in "${TASKS[@]}"; do
      n=$((n + 1)); h=${t%% *}; t=${t#* }; m=${t%% *}; t=${t#* }; days=${t%% *}; args=${t#* }
      local plist="$HOME/Library/LaunchAgents/$LAUNCHD_PREFIX.$n.plist" a d intervals=""
      for d in $(echo "$days" | tr ',' ' '); do
        intervals="$intervals
      <dict><key>Weekday</key><integer>$(( d % 7 ))</integer><key>Hour</key><integer>$h</integer><key>Minute</key><integer>$m</integer></dict>"
      done
      local argxml="      <string>/bin/bash</string>
      <string>$(xml_esc "$ENGINE")</string>"
      for a in $args; do argxml="$argxml
      <string>$a</string>"; done
      cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LAUNCHD_PREFIX.$n</string>
  <key>ProgramArguments</key>
  <array>
$argxml
  </array>
  <key>StartCalendarInterval</key>
  <array>$intervals
  </array>
  <key>StandardOutPath</key><string>$(xml_esc "$LOG_FILE")</string>
  <key>StandardErrorPath</key><string>$(xml_esc "$LOG_FILE")</string>
</dict>
</plist>
EOF
      launchctl bootstrap "gui/$(id -u)" "$plist" >/dev/null 2>&1 || launchctl load -w "$plist" >/dev/null 2>&1 || true
    done
    SCHEDULER="launchd (runs while you're logged in; missed runs happen when the Mac wakes)"
    return 0
  fi
  if command -v crontab >/dev/null 2>&1; then
    local block="$CRON_BEGIN" cdays d
    for t in "${TASKS[@]}"; do
      h=${t%% *}; t=${t#* }; m=${t%% *}; t=${t#* }; days=${t%% *}; args=${t#* }
      cdays=""; for d in $(echo "$days" | tr ',' ' '); do cdays="$cdays${cdays:+,}$(( d % 7 ))"; done
      block="$block
$m $h * * $cdays /bin/bash \"$ENGINE\" $args >> \"$LOG_FILE\" 2>&1"
    done
    block="$block
$CRON_END"
    local cur; cur="$(crontab -l 2>/dev/null || true)"   # read first, then write
    if [[ -n "$cur" ]]; then printf '%s\n%s\n' "$cur" "$block"; else printf '%s\n' "$block"; fi | crontab -
    SCHEDULER="cron (runs even when you're logged out, as long as the computer is on)"
    return 0
  fi
  # No cron: systemd user timers
  local udir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" names=""
  mkdir -p "$udir"
  for t in "${TASKS[@]}"; do
    n=$((n + 1)); h=${t%% *}; t=${t#* }; m=${t%% *}; t=${t#* }; days=${t%% *}; args=${t#* }
    local sd="" d; for d in $(echo "$days" | tr ',' ' '); do sd="$sd${sd:+,}$(day_name "$d" | cut -c1-3)"; done
    printf '[Unit]\nDescription=Houston: %s\n\n[Service]\nType=oneshot\nExecStart=/bin/bash "%s" %s\n' "$args" "$ENGINE" "$args" > "$udir/apollo-miner-$n.service"
    printf '[Unit]\nDescription=Houston: %s\n\n[Timer]\nOnCalendar=%s *-*-* %02d:%02d:00\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' "$args" "$sd" "$h" "$m" > "$udir/apollo-miner-$n.timer"
    names="$names apollo-miner-$n.timer"
  done
  systemctl --user daemon-reload && systemctl --user enable --now $names >/dev/null 2>&1 \
    || { ui_error "Couldn't enable the systemd timers. Install cron (e.g. 'sudo apt install cron') and run setup again."; return 1; }
  SCHEDULER="systemd user timers (run while you're logged in)"
}

xml_esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# ---------------------------------------------------------------------------
#  Uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
  ui_confirm "Remove Houston's shortcuts from this computer?

This removes the shortcuts, and any schedule this computer ran with older versions. Houston on your Apollo, its schedule, mining and settings are not changed (see docs/houston.md to remove Houston from the Apollo)." "Uninstall" "Cancel" || cancelled
  remove_schedule
  remove_shortcuts
  local msg="Done. The shortcuts and schedule are gone."
  if ui_confirm "Also delete the saved Apollo address and password from this computer?" "Delete them" "Keep them" no; then
    rm -rf "$CONFIG_DIR" "$INSTALL_DIR"
    [[ "$OS" == Darwin ]] && security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "${USER:-$(id -un)}" >/dev/null 2>&1
    msg="$msg The saved address and password were deleted too."
  fi
  ui_info "$msg You can delete the download now."
}

# ---------------------------------------------------------------------------
#  Install
# ---------------------------------------------------------------------------
do_install() {
  local host="" saved="" choice found pw result iii=0 status mode
  [[ -r "$CONFIG_DIR/host" ]] && saved="$(head -n1 "$CONFIG_DIR/host")"

  ui_info "Welcome to Houston.

Setup finds your Apollo, checks your dashboard password, connects to Houston on the Apollo, and adds the shortcuts you choose.

Nothing changes until the last step." || cancelled

  # ---- 1. find the Apollo
  while [[ -z "$host" ]]; do
    local opts=("Search my network" "Type its address")
    [[ -n "$saved" ]] && opts=("Use $saved (from last time)" "${opts[@]}")
    choice="$(ui_choose "How should setup find your Apollo?" "${opts[0]}" "${opts[@]}")" || cancelled
    case "$choice" in
      Use*) host="$saved" ;;
      Search*)
        [[ "$UI" == terminal ]] && echo "  Searching your network (a few seconds)..."
        found="$(find_apollos)"
        if [[ -z "$found" ]]; then
          ui_error "No Apollo found on this network. Choose \"Type its address\" and enter the address you open the dashboard at."
        elif [[ "$(echo "$found" | wc -l | tr -d ' ')" == 1 ]]; then
          ui_confirm "Found an Apollo at $found. Use it?" "Use it" "Back" && host="$found"
        else
          host="$(ui_choose "Found more than one Apollo. Which one?" "$(echo "$found" | head -n1)" $found)" || host=""
        fi ;;
      Type*)
        host="$(ui_input "Apollo address (the one you open the dashboard at, e.g. 192.168.1.50):" "$saved")" || cancelled
        host="$(printf '%s' "$host" | sed -E 's#^https?://##; s#[:/].*$##; s/[[:space:]]//g')"
        if ! [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]]; then ui_error "\"$host\" doesn't look like an address. Example: 192.168.1.50"; host=""; fi ;;
    esac
  done

  # ---- 2. password
  local tries=0
  while true; do
    pw="$(ui_password "Dashboard password for the Apollo at $host:")" || cancelled
    [[ "$UI" == terminal ]] && echo "  Checking..."
    result="$(check_login "$host" "$pw")"
    case $? in
      0) break ;;
      3) ui_error "Can't reach the Apollo at $host. Check that it's switched on and the address is right."; exit 1 ;;
      *) tries=$((tries + 1)); [[ $tries -ge 3 ]] && { ui_error "That password didn't work three times. Run setup again when you have it."; exit 1; }
         ui_error "Wrong password. Use the password you log in to the Apollo dashboard with." ;;
    esac
  done
  set -- $result; [[ "$2" == apollo-iii ]] && iii=1; status="$3"; mode="${4:-unknown}"
  local model="Apollo II"; [[ $iii == 1 ]] && model="Apollo III"

  # ---- 3. Houston on the Apollo
  local hv url="" groups=""
  hv="$(houston_version "$host")"
  while [[ -z "$hv" ]]; do
    choice="$(ui_choose "Connected to your $model ($status, $(mode_label "$mode") mode).

Houston isn't installed on this Apollo yet. Houston is the app (phone and desktop) and runs your schedule on the Apollo itself, so no computer has to stay on. To install it, open a Terminal and run these two commands (the password is your dashboard password):

scp -r \"$ROOT/houston\" futurebit@$host:~/
ssh -t futurebit@$host \"sudo bash ~/houston/install-houston.sh\"

Then come back here." "I installed it, check again" "I installed it, check again" "Copy the commands" "Continue without Houston")" || cancelled
    [[ "$choice" == Continue* ]] && break
    if [[ "$choice" == Copy* ]]; then
      local cmds="scp -r \"$ROOT/houston\" futurebit@$host:~/
ssh -t futurebit@$host \"sudo bash ~/houston/install-houston.sh\""
      if printf '%s\n' "$cmds" | { pbcopy 2>/dev/null || wl-copy 2>/dev/null || xclip -selection clipboard 2>/dev/null; }; then
        ui_info "Copied. Paste them into a Terminal window, one at a time."
      else
        ui_info "Copy these into a Terminal window:

$cmds"
      fi
      continue
    fi
    hv="$(houston_version "$host")"
    [[ -z "$hv" ]] && ui_error "Houston still isn't answering at http://$host:8088. Check the installer finished without errors."
  done
  [[ -n "$hv" ]] && url="http://$host:8088/"

  # ---- 4. shortcuts
  local where="apps in ~/Applications/Houston (Launchpad)"; [[ "$OS" != Darwin ]] && where="launchers in your app menu"
  if [[ -n "$hv" ]] && ui_confirm "Houston $hv is running on your Apollo.

Add a Houston shortcut? It opens the app in its own window: status, power modes, schedule, stats and settings." "Add it" "No thanks"; then groups="houston"; fi
  local extra=""; [[ $iii == 1 ]] && extra=", Super Eco"
  ui_confirm "Add one-click shortcuts for Start, Stop and Status?" "Add them" "No thanks" && groups="$groups control"
  ui_confirm "Add one-click shortcuts for the power modes (Eco, Balanced, Turbo$extra)?" "Add them" "No thanks" && groups="$groups modes"
  ui_confirm "Add shortcuts to start and stop the Apollo's Bitcoin node? (Most people leave the node running.)" "Add them" "No thanks" no && groups="$groups node"

  # ---- 5. schedule
  local base="eco" kind
  local summary="" on off days offdays tok w=0 more next
  TASKS=()
  if [[ -n "$hv" ]]; then
    kind="houston"
    summary="
In Houston: open it and use the Schedule tab. (Any schedule this computer ran before is removed.)"
  else
    kind="$(ui_choose "Without Houston, this computer can run a schedule instead. It only works while this computer is on (and, on a Mac, while you're logged in).

What should happen automatically?" "No schedule (shortcuts only)" \
      "No schedule (shortcuts only)" "Mine 24/7, faster at set times" "Mine only during set hours" "Both")" || cancelled
  fi

  if [[ "$kind" == "Mine only during set hours" || "$kind" == Both ]]; then
    while true; do
      w=$((w + 1))
      days="$(ui_days "Mining window $w: which days?")" || cancelled
      on="$(ask_time "Mining window $w: start mining at" "9:00 AM")"
      off="$(ask_time "Mining window $w: stop mining at (or type never)" "5:00 PM" allow-never)"
      add_task ${on% *} ${on#* } "$(echo $days | tr ' ' ',')" start
      if [[ "$off" == never ]]; then
        summary="$summary
$(format_days "$days"): start mining at $(fmt_time "$on") (no automatic stop)"
      else
        offdays="$days"; next=""
        if (( $(minutes "$off") <= $(minutes "$on") )); then offdays="$(next_days "$days")"; next=" (next day)"; fi
        add_task ${off% *} ${off#* } "$(echo $offdays | tr ' ' ',')" stop
        summary="$summary
$(format_days "$days"): mine $(fmt_time "$on") to $(fmt_time "$off")$next"
      fi
      ui_confirm "Add another mining window (different days or times)?" "Add another" "No, continue" no || break
    done
  fi

  if [[ "$kind" == "Mine 24/7, faster at set times" || "$kind" == Both ]]; then
    if [[ $iii == 1 ]]; then base="$(ask_mode "Normal mode, the rest of the time:" eco super_eco eco balanced custom)"
    else base="$(ask_mode "Normal mode, the rest of the time:" eco eco balanced)"; fi
    w=0
    while true; do
      w=$((w + 1))
      while true; do
        if [[ $iii == 1 ]]; then tok="$(ask_mode "Time window $w: which faster mode?" turbo eco balanced turbo custom)"
        else tok="$(ask_mode "Time window $w: which faster mode?" turbo balanced turbo)"; fi
        [[ "$tok" != "$base" ]] && break
        ui_error "$(mode_label "$tok") is already the normal mode. Pick a different one."
      done
      days="$(ui_days "Time window $w ($(mode_label "$tok")): which days?")" || cancelled
      on="$(ask_time "Switch to $(mode_label "$tok") at" "9:00 AM")"
      off="$(ask_time "Back to $(mode_label "$base") at" "5:00 PM")"
      offdays="$days"; next=""
      if (( $(minutes "$off") <= $(minutes "$on") )); then offdays="$(next_days "$days")"; next=" (next day)"; fi
      add_task ${on% *} ${on#* } "$(echo $days | tr ' ' ',')" "$(mode_args "$tok")"
      add_task ${off% *} ${off#* } "$(echo $offdays | tr ' ' ',')" "$(mode_args "$base")"
      summary="$summary
$(format_days "$days"): $(mode_label "$tok") $(fmt_time "$on") to $(fmt_time "$off")$next, $(mode_label "$base") otherwise"
      ui_confirm "Add another time window (different days or times)?" "Add another" "No, continue" no || break
    done
  fi
  [[ -z "$summary" ]] && summary="
No schedule (any previous Apollo schedule on this computer is removed)."

  local picked=""
  [[ "$groups" == *houston* ]] && picked="Houston"
  [[ "$groups" == *control* ]] && picked="$picked${picked:+, }Start, Stop, Status"
  [[ "$groups" == *modes* ]] && picked="$picked${picked:+, }Eco, Balanced, Turbo$extra"
  [[ "$groups" == *node* ]] && picked="$picked${picked:+, }Start/Stop Bitcoin Node"
  local sc_line="No shortcuts."; [[ -n "$picked" ]] && sc_line="Shortcuts ($where): $picked."
  ui_confirm "Ready to set up your $model at $host.

$sc_line

Schedule:$summary

Setup saves the dashboard password ($( [[ "$OS" == Darwin ]] && echo "in your Keychain" || echo "in a file only you can read")) for the shortcuts." "Install" "Cancel" || cancelled

  # ---- 4. install
  [[ "$UI" == terminal ]] && echo "  Installing..."
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"; chmod 700 "$CONFIG_DIR"
  cp "$ROOT/scripts/apollo-miner.sh" "$ENGINE"; chmod 700 "$ENGINE"
  if [[ "$OS" != Darwin ]]; then mkdir -p "$INSTALL_DIR/icons"; cp "$ICON_DIR"/*.png "$INSTALL_DIR/icons/" 2>/dev/null || true; fi
  printf '%s\n' "$host" > "$CONFIG_DIR/host"
  save_password "$pw" || { ui_error "Couldn't save the password$( [[ "$OS" == Darwin ]] && echo " in the Keychain")."; exit 1; }
  pw=""
  create_shortcuts "$iii" "$groups" "$url"
  SCHEDULER=""
  install_schedule || exit 1

  local done_msg="All set!"
  [[ -n "$url" ]] && done_msg="$done_msg

Houston: $url (works on your phone too; away from home through Tailscale)."
  [[ -n "$groups" ]] && done_msg="$done_msg

Your shortcuts are in $( [[ "$OS" == Darwin ]] && echo "Launchpad and ~/Applications/Houston" || echo "your app menu (search \"Houston\" or \"Miner\")" ). The one-click shortcuts show a notification with the result."
  [[ ${#TASKS[@]} -gt 0 ]] && done_msg="$done_msg

The schedule uses $SCHEDULER."
  [[ "$OS" == Darwin ]] && done_msg="$done_msg

The first time a shortcut runs, macOS may ask to allow notifications."
  done_msg="$done_msg

Run setup again any time to change the shortcuts. Log: $LOG_FILE"
  ui_info "$done_msg"
}

case "${1:-install}" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  *) echo "Usage: $0 install|uninstall"; exit 2 ;;
esac
