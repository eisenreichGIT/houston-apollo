#!/usr/bin/env python3
"""
Houston - the remote for your FutureBit Apollo.

Runs on the Apollo (installed by install-houston.sh as the "houston" service):
  - serves the Houston web app (phone and desktop) on port 8088
  - forwards the app's requests to the Apollo's own API (127.0.0.1:5000), so the
    app needs only this one address, at home or through Tailscale
  - stores the weekly schedule and runs it 24/7, so no computer has to stay on
  - keeps a short activity log of what the schedule did

Python 3 standard library only. Unofficial; not affiliated with FutureBit.
"""
import datetime as dt
import base64
import collections
import hashlib
import hmac
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "2.6.0"
HERE = os.path.dirname(os.path.realpath(__file__))
WEB_DIR = os.path.realpath(os.environ.get("HOUSTON_WEB", os.path.join(HERE, "web")))
STATE_DIR = os.environ.get("STATE_DIRECTORY") or os.environ.get("HOUSTON_STATE") or os.path.join(HERE, "state")
API = os.environ.get("HOUSTON_API", "http://127.0.0.1:5000/api/graphql")
UI_CONFIG = os.environ.get("HOUSTON_UI_CONFIG", "http://127.0.0.1:3000/api/config")
PORT = int(os.environ.get("HOUSTON_PORT", "8088"))
TICK = float(os.environ.get("HOUSTON_TICK", "15"))
GRACE_MIN = 3            # a missed event still runs up to 3 minutes late (e.g. after a restart)
MAX_BODY = 256 * 1024

SCHEDULE_FILE = os.path.join(STATE_DIR, "schedule.json")
AUTH_FILE = os.path.join(STATE_DIR, "auth.json")
ACTIVITY_FILE = os.path.join(STATE_DIR, "activity.json")
FIRED_FILE = os.path.join(STATE_DIR, "fired.json")

MODES = ("super_eco", "whisper", "eco", "balanced", "turbo")
# Whisper (Houston's own mode, Apollo I/II): the Apollo's custom mode at its lowest settings, the minimum the
# Apollo dashboard allows (power 30 %, frequency 25). Measured on an Apollo II: about half of Eco's power
# (107 W vs 209 W) at 2.9 TH/s, slightly more efficient. The Apollo III has Super Eco and custom targets instead.
WHISPER = {"voltage": 30.0, "frequency": 25}


def is_whisper(st):
    try:
        return st.get("minerMode") == "custom" and float(st.get("voltage")) == WHISPER["voltage"] \
            and int(st.get("frequency")) == WHISPER["frequency"]
    except (TypeError, ValueError):
        return False


def mode_token(st, iii):
    """The Houston mode token for the Apollo's settings: eco, ..., custom:<TH/s> (III), whisper, custom (II dashboard)."""
    m = st.get("minerMode")
    if m == "custom":
        if iii:
            return "custom:%s" % st.get("minerHashrate")
        return "whisper" if is_whisper(st) else "custom"
    return m
WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
LOCK = threading.RLock()
STATIC = {"/": "index.html", "/index.html": "index.html", "/manifest.json": "manifest.json",
          "/icon-192.png": "icon-192.png", "/icon-512.png": "icon-512.png",
          "/apple-touch-icon.png": "apple-touch-icon.png", "/favicon.png": "favicon.png",
          "/icon-maskable-512.png": "icon-maskable-512.png", "/logo.svg": "logo.svg",
          "/fonts/archivo.woff2": "fonts/archivo.woff2", "/fonts/plex-mono-400.woff2": "fonts/plex-mono-400.woff2",
          "/fonts/plex-mono-500.woff2": "fonts/plex-mono-500.woff2", "/sw.js": "sw.js",
          "/app.js": "app.js", "/theme.js": "theme.js"}
TYPES = {".html": "text/html; charset=utf-8", ".json": "application/json", ".png": "image/png", ".svg": "image/svg+xml",
         ".woff2": "font/woff2", ".js": "text/javascript; charset=utf-8"}


_LOG_RING = collections.deque(maxlen=500)     # recent lines, for Houston's own log in the app


def log(msg):
    line = time.strftime("%Y-%m-%d %H:%M:%S") + " " + str(msg)
    _LOG_RING.append(line)
    print(line, flush=True)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None                     # a redirect is answered as an error, never followed


_OPENER = urllib.request.build_opener(_NoRedirect)
MAX_REPLY = 1024 * 1024


def fetch(req, timeout):
    """Requests Houston makes to addresses that come from settings (other Apollos, push services,
    ntfy): redirects aren't followed and replies are capped at 1 MB."""
    with _OPENER.open(req, timeout=timeout) as r:
        return r.read(MAX_REPLY)


# --------------------------------------------------------------------------- state files
def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, data, private=False, compact=False):
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600 if private else 0o644)
    os.fchmod(fd, 0o600 if private else 0o644)       # even if an old temp file had other permissions
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        if compact:
            json.dump(data, f, separators=(",", ":"))
        else:
            json.dump(data, f, indent=1)
    os.replace(tmp, path)


TZ_RE = re.compile(r"^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}$")
ZONEINFO = "/usr/share/zoneinfo"


def valid_tz(tz):
    return isinstance(tz, str) and bool(TZ_RE.match(tz)) and os.path.isfile(os.path.join(ZONEINFO, tz))


def apply_tz(tz):
    """Run the schedule in the time zone the user picked in the app (the Apollo itself is often on UTC)."""
    if valid_tz(tz) and os.environ.get("TZ") != tz:
        os.environ["TZ"] = tz
        time.tzset()
        log("schedule time zone: %s" % tz)


def default_schedule():
    return {"enabled": False, "base": "eco", "windows": [], "updated": None}


def add_activity(action, ok, message, source="schedule"):
    with LOCK:
        items = read_json(ACTIVITY_FILE, [])
        items.insert(0, {"time": dt.datetime.now().astimezone().isoformat(timespec="seconds"), "action": action,
                         "ok": ok, "message": message, "source": source})
        write_json(ACTIVITY_FILE, items[:60])


# --------------------------------------------------------------------------- Apollo API
def apollo(query, variables=None, token=None, timeout=30):
    body = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request(API, data=body, method="POST", headers={"Content-Type": "application/json"})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.loads(r.read().decode())
    except urllib.error.HTTPError as he:
        # Apollo's API answers a request it can't validate with HTTP 400 and the reason in the body
        try:
            data = json.loads(he.read().decode() or "{}")
        except ValueError:
            data = {}
        if not data.get("errors"):
            raise he
    if data.get("errors"):
        err = data["errors"][0]
        e = RuntimeError(err.get("message", "error"))
        e.code = (err.get("extensions") or {}).get("code")
        raise e
    return data["data"]


def chassis():
    try:
        with urllib.request.urlopen(UI_CONFIG, timeout=4) as r:
            c = json.loads(r.read().decode()).get("chassis")
            if c:
                return c
    except Exception:
        pass
    try:
        with open("/etc/armbian-release", encoding="utf-8") as f:
            if re.search(r'^BOARD_NAME="?Apollo 3', f.read(), re.M):
                return "apollo-iii"
    except OSError:
        pass
    return None


_features = {}


def api_features():
    """What this Apollo software supports, found once by asking the API to validate two tiny requests:
    nodeMutation - node start/stop is a GraphQL mutation (2.1.4+; older software only has the query form)
    nodeStorage  - the API reports whether there is a drive for the blockchain (2.1.4+)
    mcuMutation  - the software update is started with a mutation (2.1.4+; a query before that)"""
    if _features:
        return _features
    probes = {"nodeMutation": "mutation { Node { __typename } }", "nodeStorage": "query { Node { storage { __typename } } }",
              "mcuMutation": "mutation { Mcu { __typename } }"}
    found = {}
    for name, q in probes.items():
        req = urllib.request.Request(API, data=json.dumps({"query": q}).encode(), method="POST",
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                body = r.read()
        except urllib.error.HTTPError as e:
            body = e.read()
        except Exception:
            return {}                     # API not reachable: don't cache, try again next time
        try:
            errs = json.loads(body.decode() or "{}").get("errors") or []
        except ValueError:
            return {}
        found[name] = not any(re.search(r"Cannot query field|not configured for mutations", x.get("message") or "") for x in errs)
    _features.update(found)
    return _features


_verified = {}


def token_ok(token):
    """True if the Apollo accepts this login token (cached for a minute)."""
    if not token or len(token) > 4096:
        return False
    key = hashlib.sha256(token.encode()).hexdigest()
    if _verified.get(key, 0) > time.time():
        return True
    try:
        apollo("query { Settings { read { error { message } } } }", token=token, timeout=10)
    except Exception as e:
        if getattr(e, "code", None) == "UNAUTHENTICATED":
            return False
        raise
    _verified[key] = time.time() + 60
    return True


def label(token):
    if token.startswith("custom:"):
        return token.split(":")[1] + " TH/s"
    return {"super_eco": "Super Eco", "custom": "Custom (dashboard)"}.get(token, token.capitalize())


def miner_status(token):
    st = apollo("query { Miner { online { result { online { status } } } } }", token=token)
    return st["Miner"]["online"]["result"]["online"]["status"]


def describe(action):
    if action in ("node_start", "node_stop"):
        return "Start Bitcoin node" if action == "node_start" else "Stop Bitcoin node"
    if action == "start":
        return "Start mining"
    if action == "stop":
        return "Stop mining"
    if action.startswith("start@"):
        return "Start mining in %s" % label(action[6:])
    return "Switch to " + label(action)


def run_action(action, token):
    """start | stop | start@<mode> | <mode token>. Returns a message; raises on failure. Same rules
    as the scripts: mode changes restart a running miner and never start a stopped one."""
    note_intent(action)
    if action in ("node_start", "node_stop"):
        return node_action(action[5:], token)
    if action.startswith("start@"):
        first = run_action(action[6:], token)
        return first + "; " + run_action("start", token)
    if action in ("start", "stop"):
        status = miner_status(token)
        if action == "start" and status == "online":
            return "Already mining"
        if action == "stop" and status == "offline":
            return "Already stopped"
        d = apollo("query { Miner { %s { error { message } } } }" % action, token=token, timeout=200)
        err = d["Miner"][action]["error"]
        if err:
            raise RuntimeError(err.get("message", "failed"))
        return "Miner started" if action == "start" else "Miner stopped"
    iii = chassis() == "apollo-iii"
    mode, hr = (action.split(":") + [None])[:2] if action.startswith("custom:") else (action, None)
    if mode in ("super_eco", "custom") and not iii:
        raise RuntimeError("%s needs an Apollo III" % label(action))
    if mode == "whisper" and iii:
        raise RuntimeError("Whisper is for the Apollo II; on the Apollo III use Super Eco or a custom target")
    fields = "minerMode minerHashrate nodeSoftware" if iii else "minerMode voltage frequency nodeSoftware"
    s = apollo("query { Settings { read { result { settings { %s } } } } }" % fields, token=token)
    s = s["Settings"]["read"]["result"]["settings"]
    status = miner_status(token)
    if mode_token(s, iii) == (action if mode != "custom" else "custom:%s" % hr):
        return "Already in %s mode" % label(action)
    # Send nodeSoftware back unchanged (Apollo software up to 2.1.2 would otherwise restart the node)
    if mode == "custom":
        q = ("query ($m: MinerMode!, $n: NodeSoftware, $h: Int) { Settings { update(input: "
             "{ minerMode: $m, nodeSoftware: $n, minerHashrate: $h }) { error { message } } } }")
        v = {"m": "custom", "n": s.get("nodeSoftware"), "h": int(hr)}
    elif mode == "whisper":
        q = ("query ($m: MinerMode!, $n: NodeSoftware, $v: Float, $f: Int) { Settings { update(input: "
             "{ minerMode: $m, nodeSoftware: $n, voltage: $v, frequency: $f }) { error { message } } } }")
        v = {"m": "custom", "n": s.get("nodeSoftware"), "v": WHISPER["voltage"], "f": WHISPER["frequency"]}
    else:
        q = ("query ($m: MinerMode!, $n: NodeSoftware) { Settings { update(input: "
             "{ minerMode: $m, nodeSoftware: $n }) { error { message } } } }")
        v = {"m": mode, "n": s.get("nodeSoftware")}
    d = apollo(q, v, token=token, timeout=60)
    if d["Settings"]["update"]["error"]:
        raise RuntimeError(d["Settings"]["update"]["error"]["message"])
    if status == "offline":
        return "Mode set to %s (miner is stopped; used when it starts)" % label(action)
    d = apollo("query { Miner { restart { error { message } } } }", token=token, timeout=200)
    if d["Miner"]["restart"]["error"]:
        raise RuntimeError("mode saved, restart failed: " + d["Miner"]["restart"]["error"]["message"])
    return "Switched to %s" % label(action)


def node_action(cmd, token):
    """Start or stop the Bitcoin node (a mutation on Apollo software 2.1.4+, a query before that)."""
    q = "{ Node { %s { error { message } } } }" % cmd
    use_mutation = api_features().get("nodeMutation", True)
    try:
        d = apollo(("mutation " if use_mutation else "query ") + q, token=token, timeout=150)
    except urllib.error.HTTPError:
        d = apollo("query " + q, token=token, timeout=150)
    except RuntimeError as e:
        if "Cannot query field" not in str(e):
            raise
        d = apollo("query " + q, token=token, timeout=150)
    err = d["Node"][cmd]["error"]
    if err:
        raise RuntimeError(err.get("message", "failed"))
    return "Bitcoin node started" if cmd == "start" else "Bitcoin node stopped"


# --------------------------------------------------------------------------- schedule
TIME_RE = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


def valid_mode(m, iii):
    if not isinstance(m, str):
        return False
    if m.startswith("custom:"):
        h = m[7:]
        return iii and h.isdigit() and 5 <= int(h) <= 20
    if m == "super_eco":
        return iii
    if m == "whisper":
        return not iii
    return m in ("eco", "balanced", "turbo")


def validate(s):
    """Return a clean schedule or raise ValueError with a readable message."""
    if not isinstance(s, dict):
        raise ValueError("schedule must be an object")
    iii = chassis() == "apollo-iii"
    base = s.get("base", "eco")
    if not valid_mode(base, iii):
        raise ValueError("Normal mode '%s' isn't available on this Apollo" % base)
    wins = s.get("windows", [])
    if not isinstance(wins, list) or len(wins) > 20:
        raise ValueError("up to 20 time windows")
    out = []
    for i, w in enumerate(wins, 1):
        if not isinstance(w, dict) or w.get("type") not in ("run", "mode"):
            raise ValueError("window %d: type must be run or mode" % i)
        days = w.get("days")
        if not isinstance(days, list) or not days or any(type(d) is not int or d < 1 or d > 7 for d in days):
            raise ValueError("window %d: pick at least one day" % i)
        on, off = w.get("on"), w.get("off")
        if not isinstance(on, str) or not TIME_RE.match(on):
            raise ValueError("window %d: start time must be HH:MM" % i)
        if off is not None and (not isinstance(off, str) or not TIME_RE.match(off)):
            raise ValueError("window %d: end time must be HH:MM" % i)
        if off == on:
            raise ValueError("window %d: start and end time are the same" % i)
        clean = {"type": w["type"], "days": sorted(set(days)), "on": on, "off": off}
        if w["type"] == "run" and w.get("mode"):
            if not valid_mode(w["mode"], iii):
                raise ValueError("window %d: mode '%s' isn't available on this Apollo" % (i, w["mode"]))
            clean["mode"] = w["mode"]
        if w["type"] == "mode":
            if off is None:
                raise ValueError("window %d: a mode window needs an end time" % i)
            if not valid_mode(w.get("mode"), iii) or w.get("mode") == base:
                raise ValueError("window %d: pick a mode different from the normal mode" % i)
            clean["mode"] = w["mode"]
        out.append(clean)
    tz = s.get("tz")
    if tz is not None and not valid_tz(tz):
        raise ValueError("Unknown time zone '%s'" % tz)
    return {"enabled": bool(s.get("enabled", True)), "base": base, "windows": out, "tz": tz,
            "updated": dt.datetime.now().isoformat(timespec="seconds")}


def events(schedule):
    """All weekly events: (weekday 1-7, 'HH:MM', action, description)."""
    ev = []
    base = schedule.get("base", "eco")
    for w in schedule.get("windows", []):
        on_h, on_m = map(int, w["on"].split(":"))
        if w["type"] == "run":
            start_action = "start@" + w["mode"] if w.get("mode") else "start"
        else:
            start_action = w["mode"]
        for d in w["days"]:
            ev.append((d, w["on"], start_action))
        if w.get("off"):
            off_h, off_m = map(int, w["off"].split(":"))
            overnight = (off_h, off_m) <= (on_h, on_m)
            stop_action = "stop" if w["type"] == "run" else base
            for d in w["days"]:
                ev.append(((d % 7) + 1 if overnight else d, w["off"], stop_action))
    return ev


def upcoming(schedule, now=None, count=6):
    if not schedule.get("enabled") or not schedule.get("windows"):
        return []
    now = now or dt.datetime.now()
    out = []
    for d, hhmm, action in events(schedule):
        h, m = map(int, hhmm.split(":"))
        days_ahead = (d - now.isoweekday()) % 7
        when = (now + dt.timedelta(days=days_ahead)).replace(hour=h, minute=m, second=0, microsecond=0)
        if when <= now:
            when += dt.timedelta(days=7)
        out.append((when, action))
    out.sort()
    return [{"time": w.isoformat(timespec="minutes"), "action": a, "label": describe(a)} for w, a in out[:count]]


def expected_now(schedule, now=None):
    """What the schedule says should be true right now: {"mode": token|None, "running": bool|None}.
    None for either means the schedule doesn't control it. Used to offer "apply now" after saving."""
    if not schedule.get("enabled") or not schedule.get("windows"):
        return None
    now = now or dt.datetime.now()
    last_mode = last_run = None
    for d, hhmm, action in events(schedule):
        h, m = map(int, hhmm.split(":"))
        when = (now - dt.timedelta(days=(now.isoweekday() - d) % 7)).replace(hour=h, minute=m, second=0, microsecond=0)
        if when > now:
            when -= dt.timedelta(days=7)
        if action in ("start", "stop") or action.startswith("start@"):
            if last_run is None or when > last_run[0]:
                last_run = (when, action != "stop")
            if action.startswith("start@") and (last_mode is None or when > last_mode[0]):
                last_mode = (when, action[6:])
        elif last_mode is None or when > last_mode[0]:
            last_mode = (when, action)
    return {"mode": last_mode[1] if last_mode else None, "running": last_run[1] if last_run else None}


def scheduler_loop():
    log("scheduler running (Apollo local time; tick %ss)" % TICK)
    while True:
        try:
            tick(dt.datetime.now())
        except Exception as e:  # never let the loop die
            log("scheduler error: %s" % e)
        time.sleep(TICK)


def tick(now):
    with LOCK:
        sched = read_json(SCHEDULE_FILE, default_schedule())
        fired = read_json(FIRED_FILE, {})
    if not sched.get("enabled"):
        return
    if get_settings()["econ"]["autopilot"].get("mode") == "run":
        return                                   # the economics autopilot is running the Apollo
    due = []
    for d, hhmm, action in events(sched):
        h, m = map(int, hhmm.split(":"))
        for back in range(GRACE_MIN + 1):          # this minute, or up to 3 minutes ago
            t = now - dt.timedelta(minutes=back)
            if t.isoweekday() == d and t.hour == h and t.minute == m:
                key = "%s %s %s" % (t.strftime("%Y-%m-%d"), hhmm, action)
                if key not in fired:
                    due.append((key, action))
    if not due:
        return
    token = read_json(AUTH_FILE, {}).get("token")
    for key, action in due:
        fired[key] = now.isoformat(timespec="seconds")
        with LOCK:  # mark first, so a slow action is never started twice
            cutoff = (now - dt.timedelta(days=2)).strftime("%Y-%m-%d")
            write_json(FIRED_FILE, {k: v for k, v in fired.items() if k[:10] >= cutoff})
        if not token:
            add_activity(action, False, "Not signed in: open Houston and save the schedule once")
            continue
        try:
            msg = run_action(action, token)
            add_activity(action, True, msg)
            log("schedule: %s -> %s" % (action, msg))
        except Exception as e:
            code = getattr(e, "code", None)
            msg = "Sign-in expired: open Houston and save the schedule again" if code == "UNAUTHENTICATED" else str(e)
            add_activity(action, False, msg)
            log("schedule: %s FAILED: %s" % (action, msg))


# --------------------------------------------------------------------------- settings
SETTINGS_FILE = os.path.join(STATE_DIR, "settings.json")
HISTORY_FILE = os.path.join(STATE_DIR, "history.json")
ALERTS_FILE = os.path.join(STATE_DIR, "alerts.json")
SAMPLE_EVERY = float(os.environ.get("HOUSTON_SAMPLE", "60"))
HISTORY_DAYS = 7
TOPIC_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
URL_RE = re.compile(r"^https?://[A-Za-z0-9.-]+(:\d{1,5})?(/[A-Za-z0-9._~/-]*)?$")
PEER_RE = re.compile(r"^[A-Za-z0-9.-]{1,253}$")


def default_settings():
    return {
        "units": "F",                 # temperature unit shown in the app and in alerts (F or C)
        "rate": None,                 # electricity price per kWh, e.g. 0.16
        "currency": "$",
        "alerts": {"enabled": False, "server": "https://ntfy.sh", "topic": "",
                   "offline": True, "hot": True, "hotC": 80, "hashrate": True, "node": True, "disk": True, "block": True,
                   "update": True, "econ": True},
        "apollos": [],                # other Apollos: [{"name": "Garage", "host": "192.168.1.51"}]
        "automation": {"key": None},  # key for Siri Shortcuts / HTTP Shortcuts (see /api/v1/...)
        "price": {"enabled": True, "fiat": "USD"},   # bitcoin price ticker
        "market": {"enabled": True},                 # network, market and news cards on Stats
        "econ": econ_defaults(),                     # mining economics, time-of-use prices, heat, autopilot
    }


def get_settings():
    s = default_settings()
    saved = read_json(SETTINGS_FILE, {})
    for k, v in saved.items():
        if k == "econ" and isinstance(v, dict):
            for kk, vv in v.items():
                if kk in ("heat", "autopilot") and isinstance(vv, dict):
                    s["econ"][kk].update(vv)
                elif kk in s["econ"]:
                    s["econ"][kk] = vv
        elif k in ("alerts", "automation", "price", "market") and isinstance(v, dict):
            s[k].update(v)
        elif k in s:
            s[k] = v
    return s


def validate_settings(new, current):
    """Merge a partial settings update into the current settings; raise ValueError if anything is off."""
    if not isinstance(new, dict):
        raise ValueError("settings must be an object")
    s = json.loads(json.dumps(current))
    if "units" in new:
        if new["units"] not in ("F", "C"):
            raise ValueError("units must be F or C")
        s["units"] = new["units"]
    if "rate" in new:
        r = new["rate"]
        if r in (None, ""):
            s["rate"] = None
        else:
            try:
                r = float(r)
            except (TypeError, ValueError):
                raise ValueError("electricity price must be a number, like 0.16")
            if not 0 <= r <= 10:
                raise ValueError("electricity price looks wrong (0 to 10 per kWh)")
            s["rate"] = round(r, 4)
    if "currency" in new:
        c = str(new["currency"] or "$").strip()[:4]
        s["currency"] = c or "$"
    if "alerts" in new:
        a = new["alerts"]
        if not isinstance(a, dict):
            raise ValueError("alerts must be an object")
        for k in ("enabled", "offline", "hot", "hashrate", "node", "disk", "block", "update", "econ"):
            if k in a:
                s["alerts"][k] = bool(a[k])
        if "server" in a:
            srv = str(a["server"] or "https://ntfy.sh").strip().rstrip("/")
            if not URL_RE.match(srv):
                raise ValueError("notification server must look like https://ntfy.sh")
            s["alerts"]["server"] = srv
        if "topic" in a:
            t = str(a["topic"] or "").strip()
            if t and not TOPIC_RE.match(t):
                raise ValueError("topic: letters, numbers, - and _ only (up to 64)")
            s["alerts"]["topic"] = t
        if "hotC" in a:
            try:
                h = float(a["hotC"])
            except (TypeError, ValueError):
                raise ValueError("temperature limit must be a number")
            if not 40 <= h <= 110:
                raise ValueError("temperature limit must be between 40 and 110 °C (104 and 230 °F)")
            s["alerts"]["hotC"] = round(h, 1)
        if s["alerts"]["enabled"] and not s["alerts"]["topic"] and not (PUSH_OK and push_devices()):
            raise ValueError("turn on notifications on this device, or pick an ntfy topic, to turn alerts on")
    if "price" in new:
        pr = new["price"]
        if not isinstance(pr, dict):
            raise ValueError("price must be an object")
        if "enabled" in pr:
            s["price"]["enabled"] = bool(pr["enabled"])
        if "fiat" in pr:
            if pr["fiat"] not in FIATS:
                raise ValueError("price currency must be one of " + ", ".join(FIATS))
            s["price"]["fiat"] = pr["fiat"]
    if "market" in new:
        mk = new["market"]
        if not isinstance(mk, dict):
            raise ValueError("market must be an object")
        if "enabled" in mk:
            s["market"]["enabled"] = bool(mk["enabled"])
    if "econ" in new:
        validate_econ(new["econ"], s["econ"])
    if "apollos" in new:
        lst = new["apollos"]
        if not isinstance(lst, list) or len(lst) > 20:
            raise ValueError("up to 20 other Apollos")
        out = []
        for p in lst:
            if not isinstance(p, dict):
                raise ValueError("each Apollo needs an address")
            host = str(p.get("host") or "").strip()
            host = re.sub(r"^https?://", "", host).split("/")[0].split(":")[0]
            if not PEER_RE.match(host):
                raise ValueError("'%s' isn't an address like 192.168.1.51" % host)
            name = str(p.get("name") or host).strip()[:40] or host
            out.append({"name": name, "host": host})
        s["apollos"] = out
    return s


def _num(v, name, lo, hi, allow_none=False):
    if v in (None, "") and allow_none:
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        raise ValueError("%s must be a number" % name)
    if not lo <= f <= hi:
        raise ValueError("%s must be between %s and %s" % (name, lo, hi))
    return f


def validate_econ(e, cur):
    """Mining economics settings: time-of-use periods, extra watts, pool fee, heating, autopilot."""
    if not isinstance(e, dict):
        raise ValueError("economics settings must be an object")
    if "enabled" in e:
        cur["enabled"] = bool(e["enabled"])
    if "tou" in e:
        lst = e["tou"]
        if not isinstance(lst, list) or len(lst) > 12:
            raise ValueError("up to 12 time-of-use periods")
        out = []
        for p in lst:
            if not isinstance(p, dict):
                raise ValueError("each time-of-use period needs days, times and a price")
            days = sorted({int(d) for d in (p.get("days") or []) if str(d).isdigit() and 1 <= int(d) <= 7})
            if not days:
                raise ValueError("pick at least one day for each time-of-use period")
            fr, to = str(p.get("from", "")), str(p.get("to", ""))
            if not (TIME_RE.match(fr) and TIME_RE.match(to)) or fr == to:
                raise ValueError("time-of-use times must be like 07:00 and 21:00 (and different)")
            out.append({"days": days, "from": fr, "to": to, "rate": round(_num(p.get("rate"), "time-of-use price", 0, 10), 4)})
        cur["tou"] = out
    if "extraW" in e:
        cur["extraW"] = round(_num(e["extraW"], "extra watts", 0, 200))
    if "poolFee" in e:
        cur["poolFee"] = round(_num(e["poolFee"], "pool fee", 0, 10), 2)
    if "heat" in e:
        h = e["heat"]
        if not isinstance(h, dict):
            raise ValueError("heat settings must be an object")
        if "type" in h:
            if h["type"] not in HEAT_TYPES:
                raise ValueError("heating must be one of " + ", ".join(HEAT_TYPES))
            cur["heat"]["type"] = h["type"]
        if "cop" in h:
            cur["heat"]["cop"] = round(_num(h["cop"], "heat pump efficiency (COP)", 1, 6), 2)
        if "price" in h:
            p = _num(h["price"], "fuel price", 0, 50, allow_none=True)
            cur["heat"]["price"] = None if p is None else round(p, 3)
        if "eff" in h:
            cur["heat"]["eff"] = round(_num(h["eff"], "furnace efficiency", 0.3, 1.0), 2)
        if "balanceC" in h:
            cur["heat"]["balanceC"] = round(_num(h["balanceC"], "heating temperature", -10, 30), 1)
        if "location" in h:
            loc = str(h["location"] or "").strip()[:80]
            if loc and not re.match(r"^[\w .,'-]+$", loc, re.U):
                raise ValueError("location: a ZIP code, town, or latitude,longitude")
            cur["heat"]["location"] = loc
    if "autopilot" in e:
        a = e["autopilot"]
        if not isinstance(a, dict):
            raise ValueError("autopilot settings must be an object")
        if "mode" in a:
            if a["mode"] not in AUTOPILOT_MODES:
                raise ValueError("autopilot must be off, suggest or run")
            cur["autopilot"]["mode"] = a["mode"]
        if "modes" in a:
            ms = [m for m in (a["modes"] or []) if m in MODES]
            cur["autopilot"]["modes"] = ms
        if "allowStop" in a:
            cur["autopilot"]["allowStop"] = bool(a["allowStop"])
        if "minGain" in a:
            cur["autopilot"]["minGain"] = round(_num(a["minGain"], "smallest gain worth switching for", 0, 10), 3)


def public_settings(s):
    """Settings as the app sees them (the automation key is only shown when asked for)."""
    out = json.loads(json.dumps(s))
    out["automation"] = {"enabled": bool(s["automation"].get("key"))}
    return out


def stored_token():
    return read_json(AUTH_FILE, {}).get("token")


def save_token(token):
    write_json(AUTH_FILE, {"token": token, "saved": dt.datetime.now().isoformat(timespec="seconds")}, private=True)


# --------------------------------------------------------------------------- intent
# Alerts report only unexpected stops. When you, the schedule or a shortcut stops the miner or the
# node, Houston remembers that until it's running again; a mode change (which restarts the miner)
# or a start gets a few quiet minutes while the miner comes back up.
_quiet = {"miner": 0.0, "node": 0.0}
_stopped_on_purpose = {"miner": False, "node": False}


def quiet(what, minutes):
    _quiet[what] = max(_quiet[what], time.time() + minutes * 60)


def note_intent(action):
    if action in ("stop",):
        _stopped_on_purpose["miner"] = True
    elif action in ("start", "restart") or action.startswith("start@"):
        _stopped_on_purpose["miner"] = False
        quiet("miner", 5)
    elif action == "node_stop":
        _stopped_on_purpose["node"] = True
    elif action == "node_start":
        _stopped_on_purpose["node"] = False
        quiet("node", 10)
    else:                       # mode change: the miner restarts
        quiet("miner", 5)


def is_quiet(what):
    return _stopped_on_purpose[what] or time.time() < _quiet[what]


# --------------------------------------------------------------------------- history
_history = []          # samples, oldest first
_hist_dirty = [0]      # samples since the last save
_last = {}             # most recent sample + extras (for alerts and /api/v1/status)


def load_history():
    data = read_json(HISTORY_FILE, [])
    cutoff = time.time() - HISTORY_DAYS * 86400
    with LOCK:
        _history[:] = [x for x in data if isinstance(x, dict) and x.get("t", 0) >= cutoff]


def save_history():
    with LOCK:
        data = list(_history)
        _hist_dirty[0] = 0
    write_json(HISTORY_FILE, data, compact=True)


def hashrate_ghs(stats):
    return sum(((b.get("master") or {}).get("intervals") or {}).get("int_30", {}).get("bySol") or 0 for b in stats)


def take_sample():
    """One reading of the Apollo: status, hashrate, power, temperatures, mode, node. Missing parts stay None."""
    token = stored_token()
    s = {"t": int(time.time())}
    extra = {}
    q = ("query { Miner { online { result { online { status } } } stats { result { stats { master { boardsW upTime "
         "intervals { int_30 { bySol } } } fans { int_0 { rpm } } slots { int_0 { temperature } } } "
         "ckpool { pool { hashrate1hr bestshare } blockFound } } } } "
         "Node { online { result { online { status } } } stats { result { stats { blockchainInfo { blocks headers } } } } } }")
    try:
        d = apollo(q, token=token, timeout=20)
    except Exception as e:
        s["s"] = "unreachable"
        extra["error"] = str(e)
        return s, extra
    m = d.get("Miner") or {}
    s["s"] = (((m.get("online") or {}).get("result") or {}).get("online") or {}).get("status") or "unknown"
    res = (m.get("stats") or {}).get("result") or {}
    boards = [b for b in (res.get("stats") or []) if b]
    if boards and s["s"] == "online":
        s["h"] = round(hashrate_ghs(boards), 1)
        s["w"] = round(sum((b.get("master") or {}).get("boardsW") or 0 for b in boards), 1)
        temps = [((b.get("slots") or {}).get("int_0") or {}).get("temperature") for b in boards]
        temps = [x for x in temps if x is not None]
        if temps:
            s["tb"] = round(max(temps), 1)
        rpm = [r for b in boards for r in (((b.get("fans") or {}).get("int_0") or {}).get("rpm") or []) if r]
        if rpm:
            s["f"] = int(sum(rpm) / len(rpm))
    ck = res.get("ckpool") or {}
    extra["blockFound"] = bool(ck.get("blockFound"))
    n = d.get("Node") or {}
    s["n"] = (((n.get("online") or {}).get("result") or {}).get("online") or {}).get("status") or "unknown"
    bi = ((((n.get("stats") or {}).get("result") or {}).get("stats") or {}).get("blockchainInfo") or {})
    extra["blocks"], extra["headers"] = bi.get("blocks"), bi.get("headers")
    if token:   # mode, system temperature and disks need a sign-in
        iii = chassis() == "apollo-iii"
        try:
            st = apollo("query { Settings { read { result { settings { minerMode%s } } } } }"
                        % (" minerHashrate" if iii else " voltage frequency"), token=token, timeout=15)
            st = st["Settings"]["read"]["result"]["settings"]
            s["m"] = mode_token(st, iii)
        except Exception:
            pass
        try:
            mc = apollo("query { Mcu { stats { result { stats { temperature cpu { usedPercent } memory { total available } "
                        "disks { total used mountPoint } } } } } }", token=token, timeout=20)
            ms = mc["Mcu"]["stats"]["result"]["stats"]
            if ms.get("temperature"):
                t = float(ms["temperature"])
                s["ts"] = round(t / 1000 if t > 1000 else t, 1)     # the Apollo reports millidegrees
            extra["cpu"] = (ms.get("cpu") or {}).get("usedPercent")
            mem = ms.get("memory") or {}
            if mem.get("total"):
                extra["mem"] = round(100 * (1 - (mem.get("available") or 0) / mem["total"]), 1)
            disks = [x for x in (ms.get("disks") or []) if x.get("total")]
            root = next((x for x in disks if x.get("mountPoint") == "/"), None)
            others = sorted((x for x in disks if x.get("mountPoint") not in ("/", "/boot", "/boot/efi")),
                            key=lambda x: -x["total"])
            node_disk = next((x for x in others if "nvme" in (x.get("mountPoint") or "") or "node" in (x.get("mountPoint") or "")),
                             others[0] if others else None)
            if root:
                extra["disk"] = {"used": root["used"], "total": root["total"]}
            if node_disk:
                extra["nodeDisk"] = {"used": node_disk["used"], "total": node_disk["total"], "mount": node_disk.get("mountPoint")}
        except Exception:
            pass
    return s, extra


def sampler_loop():
    load_history()
    log("history: %d samples loaded, sampling every %ss" % (len(_history), SAMPLE_EVERY))
    while True:
        try:
            record_sample(*take_sample())
        except Exception as e:
            log("sampler error: %s" % e)
        time.sleep(SAMPLE_EVERY)


def record_sample(s, extra):
    if s.get("s") == "online":
        _stopped_on_purpose["miner"] = False
    if s.get("n") == "online":
        _stopped_on_purpose["node"] = False
    with LOCK:
        _history.append(s)
        cutoff = time.time() - HISTORY_DAYS * 86400
        while _history and _history[0]["t"] < cutoff:
            _history.pop(0)
        _hist_dirty[0] += 1
        _last.clear()
        _last.update(s)
        _last.update(extra)
    if _hist_dirty[0] * SAMPLE_EVERY >= 1800:    # every 30 minutes (and on shutdown): easy on the Apollo's storage
        save_history()
    check_alerts(s, extra)


def bucketize(samples, step):
    """Average samples into buckets of `step` seconds (status and mode: the last one in the bucket)."""
    out, cur, key = [], [], None
    for x in samples:
        k = x["t"] // step
        if key is not None and k != key:
            out.append(merge(cur, key * step))
            cur = []
        key = k
        cur.append(x)
    if cur:
        out.append(merge(cur, key * step))
    return out


def merge(items, t):
    p = {"t": t}
    for f in ("h", "w", "tb", "ts", "f"):
        vals = [x[f] for x in items if x.get(f) is not None]
        if vals:
            p[f] = round(sum(vals) / len(vals), 1)
    p["s"] = items[-1].get("s")
    p["m"] = items[-1].get("m")
    p["on"] = round(sum(1 for x in items if x.get("s") == "online") / len(items), 2)
    return p


def energy(samples, rate):
    """kWh used, from the power readings: last 24 h, last 7 days, per mode, and what non-normal modes added."""
    now = time.time()
    by_mode, kwh24, kwh7, hours_by_mode, watts_by_mode = {}, 0.0, 0.0, {}, {}
    first = samples[0]["t"] if samples else now
    for i, x in enumerate(samples):
        nxt = samples[i + 1]["t"] if i + 1 < len(samples) else min(now, x["t"] + SAMPLE_EVERY)
        dt_s = max(0, min(nxt - x["t"], SAMPLE_EVERY * 3))     # don't stretch across gaps (Houston was off)
        w = x.get("w") or 0
        kwh = w * dt_s / 3600000
        kwh7 += kwh
        if x["t"] >= now - 86400:
            kwh24 += kwh
        m = x.get("m") or "unknown"
        by_mode[m] = by_mode.get(m, 0) + kwh
        if w:
            hours_by_mode[m] = hours_by_mode.get(m, 0) + dt_s / 3600
            watts_by_mode.setdefault(m, []).append(w)
    days = max((now - first) / 86400, 1 / 24) if samples else 0
    avg_w = {m: sum(v) / len(v) for m, v in watts_by_mode.items()}
    out = {"kwh24": round(kwh24, 3), "kwh7d": round(kwh7, 3), "days": round(min(days, HISTORY_DAYS), 2),
           "perDay": round(kwh7 / days, 3) if days else None,
           "byMode": {m: {"kwh": round(v, 3), "hours": round(hours_by_mode.get(m, 0), 2),
                          "avgW": round(avg_w[m], 1) if m in avg_w else None} for m, v in by_mode.items() if v > 0},
           "rate": rate}
    if rate is not None:
        out["cost24"] = round(kwh24 * rate, 2)
        out["costPerDay"] = round(out["perDay"] * rate, 2) if out["perDay"] is not None else None
        out["costPerMonth"] = round(out["perDay"] * rate * 30.4, 2) if out["perDay"] is not None else None
    # What the faster windows add: their energy minus what the normal mode would have used in those hours
    base = read_json(SCHEDULE_FILE, {}).get("base")
    if base and base in avg_w:
        extra_kwh = sum(max(0, (avg_w[m] - avg_w[base])) * hours_by_mode[m] / 1000
                        for m in hours_by_mode if m != base and m in avg_w)
        out["extraVsNormal"] = {"base": base, "kwh": round(extra_kwh, 3),
                                "cost": round(extra_kwh * rate, 2) if rate is not None else None}
    return out


def history_view(rng):
    with LOCK:
        samples = list(_history)
    now = time.time()
    if rng == "7d":
        pts = bucketize([x for x in samples if x["t"] >= now - 7 * 86400], 3600)
    else:
        pts = bucketize([x for x in samples if x["t"] >= now - 86400], 300)
    return {"range": rng, "points": pts, "energy": energy(samples, get_settings()["rate"]),
            "last": dict(_last), "sampleEvery": SAMPLE_EVERY}


# --------------------------------------------------------------------------- alerts (ntfy)
PRIORITY = {"min": 1, "low": 2, "default": 3, "high": 4, "urgent": 5}


def ntfy(title, message, tags="", priority="default", settings=None):
    """Send a push notification through ntfy (https://ntfy.sh, or your own ntfy server)."""
    a = (settings or get_settings())["alerts"]
    if not a.get("topic"):
        raise RuntimeError("no topic set")
    body = {"topic": a["topic"], "title": title, "message": message, "priority": PRIORITY.get(priority, 3),
            "tags": [t for t in tags.split(",") if t]}
    req = urllib.request.Request(a["server"].rstrip("/") + "/", data=json.dumps(body).encode("utf-8"), method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": "Houston/" + VERSION})
    fetch(req, 15)


# --------------------------------------------------------------------------- alerts (web push, no extra app)
# Houston can also send alerts straight to the Houston app on a phone or computer, as ordinary
# notifications (the Web Push standard). The phone's own push service (Apple's or Google's) delivers
# them; there's no account and no extra app. Needs Houston's https address and, for the encryption,
# the python3-cryptography package (the installer adds it).
PUSH_FILE = os.path.join(STATE_DIR, "push.json")
PUSH_HOSTS = ("fcm.googleapis.com", "android.googleapis.com", "push.services.mozilla.com", "push.apple.com",
              "notify.windows.com")
PUSH_TEST_HOSTS = {h.strip().lower() for h in os.environ.get("HOUSTON_PUSH_TEST_HOSTS", "").split(",") if h.strip()}
PUSH_CONTACT = "https://github.com/eisenreichGIT/houston-apollo"
MAX_PUSH_DEVICES = 10
B64_RE = re.compile(r"^[A-Za-z0-9_-]+={0,2}$")

try:
    from cryptography.hazmat.primitives.asymmetric import ec as _ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature as _dss
    from cryptography.hazmat.primitives import hashes as _hashes, serialization as _ser
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM as _AESGCM
    PUSH_OK = True
except Exception:          # not installed: web push is simply unavailable, ntfy still works
    PUSH_OK = False


def _b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _unb64u(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def _hmac(key, data):
    return hmac.new(key, data, hashlib.sha256).digest()


def _pub_bytes(key):
    return key.public_key().public_bytes(_ser.Encoding.X962, _ser.PublicFormat.UncompressedPoint)


def push_data():
    d = read_json(PUSH_FILE, {})
    d.setdefault("devices", [])
    return d


def push_keys():
    """Houston's own VAPID key pair (created once, kept in the private state folder)."""
    with LOCK:
        d = push_data()
        if not d.get("vapid"):
            k = _ec.generate_private_key(_ec.SECP256R1())
            d["vapid"] = {"d": _b64u(k.private_numbers().private_value.to_bytes(32, "big")), "pub": _b64u(_pub_bytes(k))}
            write_json(PUSH_FILE, d, private=True)
    priv = _ec.derive_private_key(int.from_bytes(_unb64u(d["vapid"]["d"]), "big"), _ec.SECP256R1())
    return priv, d["vapid"]["pub"]


def push_devices():
    return push_data()["devices"]


def push_device_id(endpoint):
    return hashlib.sha256(endpoint.encode()).hexdigest()[:16]


def push_endpoint_ok(endpoint):
    """Only the browsers' real push services (or test hosts), so Houston can't be used to call anything else."""
    from urllib.parse import urlsplit
    try:
        u = urlsplit(endpoint)
    except ValueError:
        return False
    host = (u.hostname or "").lower()
    if not host or len(endpoint) > 1024:
        return False
    if host in PUSH_TEST_HOSTS:
        return u.scheme in ("http", "https")
    return u.scheme == "https" and u.port in (None, 443) and any(host == h or host.endswith("." + h) for h in PUSH_HOSTS)


def push_subscribe(sub, name):
    if not PUSH_OK:
        raise ValueError("this Apollo can't send notifications yet: run the Houston installer again")
    if not isinstance(sub, dict) or not isinstance(sub.get("keys"), dict):
        raise ValueError("subscription missing")
    ep, k = str(sub.get("endpoint") or ""), sub["keys"]
    p256dh, auth = str(k.get("p256dh") or ""), str(k.get("auth") or "")
    if not push_endpoint_ok(ep):
        raise ValueError("that isn't a browser push address Houston knows")
    if not (B64_RE.match(p256dh) and B64_RE.match(auth)) or len(_unb64u(p256dh)) != 65 or len(_unb64u(auth)) != 16:
        raise ValueError("subscription keys look wrong")
    name = re.sub(r"[^\w .,()+/·-]", "", str(name or "This device"))[:40].strip() or "This device"
    with LOCK:
        d = push_data()
        devs = [x for x in d["devices"] if x["endpoint"] != ep]
        if len(devs) >= MAX_PUSH_DEVICES:
            raise ValueError("up to %d devices; remove one first" % MAX_PUSH_DEVICES)
        devs.append({"id": push_device_id(ep), "endpoint": ep, "p256dh": p256dh, "auth": auth, "name": name,
                     "added": dt.datetime.now().isoformat(timespec="seconds")})
        d["devices"] = devs
        write_json(PUSH_FILE, d, private=True)
    return push_device_id(ep)


def push_remove(dev_id):
    with LOCK:
        d = push_data()
        before = len(d["devices"])
        d["devices"] = [x for x in d["devices"] if x["id"] != dev_id]
        write_json(PUSH_FILE, d, private=True)
    return before != len(d["devices"])


def push_encrypt(payload, p256dh, auth):
    """RFC 8291 (aes128gcm) message encryption for one subscription."""
    ua_pub = _unb64u(p256dh)
    secret = _unb64u(auth)
    eph = _ec.generate_private_key(_ec.SECP256R1())
    eph_pub = _pub_bytes(eph)
    shared = eph.exchange(_ec.ECDH(), _ec.EllipticCurvePublicKey.from_encoded_point(_ec.SECP256R1(), ua_pub))
    ikm = _hmac(_hmac(secret, shared), b"WebPush: info\x00" + ua_pub + eph_pub + b"\x01")
    salt = os.urandom(16)
    prk = _hmac(salt, ikm)
    cek = _hmac(prk, b"Content-Encoding: aes128gcm\x00\x01")[:16]
    nonce = _hmac(prk, b"Content-Encoding: nonce\x00\x01")[:12]
    body = _AESGCM(cek).encrypt(nonce, payload + b"\x02", None)
    return salt + (4096).to_bytes(4, "big") + bytes([len(eph_pub)]) + eph_pub + body


def vapid_header(endpoint):
    """RFC 8292: a short-lived token signed with Houston's key, so push services know who's sending."""
    from urllib.parse import urlsplit
    priv, pub = push_keys()
    u = urlsplit(endpoint)
    head = _b64u(json.dumps({"typ": "JWT", "alg": "ES256"}, separators=(",", ":")).encode())
    claims = _b64u(json.dumps({"aud": "%s://%s" % (u.scheme, u.netloc), "exp": int(time.time()) + 12 * 3600,
                               "sub": PUSH_CONTACT}, separators=(",", ":")).encode())
    r, s_ = _dss(priv.sign((head + "." + claims).encode(), _ec.ECDSA(_hashes.SHA256())))
    jwt = head + "." + claims + "." + _b64u(r.to_bytes(32, "big") + s_.to_bytes(32, "big"))
    return "vapid t=%s, k=%s" % (jwt, pub)


def push_send(title, message, tag="houston", priority="default", only=None):
    """Send to every registered device (or just `only`). Returns (sent, failed). Gone devices are removed."""
    if not PUSH_OK:
        return 0, 0
    payload = json.dumps({"title": title, "body": message, "tag": tag, "url": "./"}).encode()
    sent = failed = 0
    gone = []
    for dev in push_devices():
        if only and dev["id"] != only:
            continue
        try:
            req = urllib.request.Request(dev["endpoint"], data=push_encrypt(payload, dev["p256dh"], dev["auth"]), method="POST",
                                         headers={"Authorization": vapid_header(dev["endpoint"]), "Content-Encoding": "aes128gcm",
                                                  "Content-Type": "application/octet-stream", "TTL": "86400",
                                                  "Urgency": "high" if priority in ("high", "urgent") else "normal"})
            fetch(req, 15)
            sent += 1
        except urllib.error.HTTPError as e:
            failed += 1
            if e.code in (404, 410):          # the browser dropped this subscription
                gone.append(dev["id"])
            log("push to %s failed: HTTP %s" % (dev["name"], e.code))
        except Exception as e:
            failed += 1
            log("push to %s failed: %s" % (dev["name"], e))
    for g in gone:
        push_remove(g)
    return sent, failed


def notify(title, message, tags="", priority="default", settings=None, tag="houston"):
    """Send an alert on every channel that's set up: ntfy (if a topic is set) and web push devices."""
    s = settings or get_settings()
    errors, ok = [], 0
    if s["alerts"].get("topic"):
        try:
            ntfy(title, message, tags, priority, s)
            ok += 1
        except Exception as e:
            errors.append("ntfy: %s" % e)
    sent, failed = push_send(title, message, tag, priority)
    ok += sent
    if failed:
        errors.append("%d device%s didn't take it" % (failed, "" if failed == 1 else "s"))
    if not ok:
        raise RuntimeError("; ".join(errors) or "no alert channel set up")
    return ok, errors


def push_view():
    return {"available": PUSH_OK, "key": push_keys()[1] if PUSH_OK else None,
            "devices": [{"id": x["id"], "name": x["name"], "added": x["added"]} for x in push_devices()]}


def alert_channels(s):
    return bool(s["alerts"].get("topic")) or (PUSH_OK and bool(push_devices()))


def fmt_temp(c, units):
    return ("%.0f°F" % (c * 9 / 5 + 32)) if units == "F" else ("%.0f°C" % c)


_alert_state = {}      # name -> {"active": bool, "since": t, "count": n}


def alert(name, active, title, message, tags, priority="default", repeat_hours=6):
    """Send `title` when a condition starts (and again after repeat_hours if it continues);
    send a short all-clear when it ends."""
    st = _alert_state.setdefault(name, {"active": False, "sent": 0})
    s = get_settings()
    if not (s["alerts"]["enabled"] and alert_channels(s)):
        st["active"] = active
        return
    now = time.time()
    try:
        if active and (not st["active"] or now - st["sent"] > repeat_hours * 3600):
            notify(title, message, tags, priority, s, tag=name)
            st["sent"] = now
            add_activity("alert", True, title, source="alert")
        elif not active and st["active"] and st["sent"]:
            ok_msgs = {"offline": "Miner is mining again", "unreachable": "Houston can reach the Apollo again",
                       "hot": "Temperature is back to normal", "hashrate": "Hashrate is back to normal",
                       "node": "Bitcoin node is running again"}
            if name in ok_msgs:
                notify(ok_msgs[name], ok_msgs[name] + ".", "white_check_mark", "low", s, tag=name)
    except Exception as e:
        log("alert '%s' not sent: %s" % (name, e))
    st["active"] = active


def recent(n, field=None):
    with LOCK:
        items = _history[-n:]
    return items if field is None else [x.get(field) for x in items]


def check_alerts(s, extra):
    st = get_settings()
    a, units = st["alerts"], st["units"]
    last5 = recent(5)
    # Can't reach the Apollo's software at all (5 minutes)
    upd = updating()            # an Apollo software update stops the miner and node and reboots: no alarms
    unreachable = len(last5) >= 5 and all(x.get("s") == "unreachable" for x in last5) and not upd
    alert("unreachable", unreachable and a["offline"], "Houston can't reach your Apollo",
          "The Apollo's software hasn't answered for 5 minutes. It may be updating, restarting, or stuck.", "warning", "high")
    # Miner stopped without anyone stopping it (3 minutes)
    last3 = recent(3)
    stopped = (len(last3) >= 3 and all(x.get("s") in ("offline", "error") for x in last3) and not is_quiet("miner") and not upd
               and any(x.get("s") == "online" for x in recent(60)))
    alert("offline", stopped and a["offline"], "Your Apollo stopped mining",
          "The miner has been offline for 3 minutes, and it wasn't stopped from Houston or the schedule. (If you stopped it on the Apollo dashboard, ignore this.)", "warning", "high")
    # Hot hashboard (3 readings in a row)
    temps = recent(3, "tb")
    hot = len(temps) >= 3 and all(t is not None and t >= a["hotC"] for t in temps)
    alert("hot", hot and a["hot"], "Your Apollo is running hot",
          "Hashboard at %s (your limit: %s). Check airflow and the fan." % (fmt_temp(temps[-1] or 0, units), fmt_temp(a["hotC"], units)),
          "thermometer", "high")
    # Hashrate drop: last 10 minutes well below the previous 2 hours in the same mode
    drop = False
    win = recent(130)
    if len(win) >= 60 and not is_quiet("miner") and not upd:
        cur, prev = win[-10:], win[:-15]
        mode = s.get("m")
        cur_h = [x["h"] for x in cur if x.get("h") and x.get("m") == mode]
        prev_h = sorted(x["h"] for x in prev if x.get("h") and x.get("m") == mode)
        if len(cur_h) >= 8 and len(prev_h) >= 30 and all(x.get("s") == "online" for x in cur):
            median = prev_h[len(prev_h) // 2]
            drop = sum(cur_h) / len(cur_h) < 0.6 * median
    alert("hashrate", drop and a["hashrate"], "Your Apollo's hashrate dropped",
          "Hashrate is down more than 40%% from its usual level in this mode (now %.2f TH/s)." % ((s.get("h") or 0) / 1000),
          "chart_with_downwards_trend")
    # Node stopped without anyone stopping it (5 minutes)
    nodes = recent(5, "n")
    node_down = len(nodes) >= 5 and all(x == "offline" for x in nodes) and not is_quiet("node") and not upd \
        and any(x.get("n") == "online" for x in recent(120))
    alert("node", node_down and a["node"], "Your Bitcoin node stopped",
          "The Apollo's Bitcoin node has been offline for 5 minutes.", "warning")
    # Node drive nearly full
    nd = extra.get("nodeDisk")
    full = bool(nd and nd["total"] and nd["used"] / nd["total"] >= 0.95)
    alert("disk", full and a["disk"], "Your node drive is almost full",
          "The blockchain drive is %d%% full. When it fills up, the node stops." % (100 * nd["used"] / nd["total"]) if nd else "",
          "floppy_disk", "high", repeat_hours=24)
    # Solo block found!
    alert("block", bool(extra.get("blockFound")) and a["block"], "Your Apollo found a block!",
          "Your solo pool reports a block found. Check the dashboard and your wallet.", "tada,moneybag", "urgent",
          repeat_hours=24 * 365)


# --------------------------------------------------------------------------- other Apollos
def glance_local():
    """Short status for other Houstons and for /api/v1/status: no sign-in needed (the Apollo's
    own API already shares these readings without one)."""
    with LOCK:
        x = dict(_last)
    return {"name": os.uname().nodename, "chassis": chassis(), "status": x.get("s"), "ghs": x.get("h"), "watts": x.get("w"),
            "tempC": x.get("tb"), "node": x.get("n"), "time": x.get("t"), "houston": VERSION, "mode": x.get("m")}


def glance_remote(host):
    """Status of another Apollo: its Houston if it has one, otherwise its own API (read-only parts)."""
    try:
        g = json.loads(fetch("http://%s:8088/api/glance" % host, 3).decode())
        g = {k: g.get(k) for k in ("name", "chassis", "status", "ghs", "watts", "tempC", "node", "time", "houston")}
        g["url"] = "http://%s:8088/" % host
        return g
    except Exception:
        pass
    try:
        q = ("query { Miner { online { result { online { status } } } stats { result { stats { master { boardsW "
             "intervals { int_30 { bySol } } } slots { int_0 { temperature } } } } } } }")
        req = urllib.request.Request("http://%s:5000/api/graphql" % host, data=json.dumps({"query": q}).encode(),
                                     method="POST", headers={"Content-Type": "application/json"})
        d = json.loads(fetch(req, 3).decode())["data"]["Miner"]
        boards = [b for b in (((d.get("stats") or {}).get("result") or {}).get("stats") or []) if b]
        temps = [((b.get("slots") or {}).get("int_0") or {}).get("temperature") for b in boards]
        temps = [t for t in temps if t is not None]
        return {"status": d["online"]["result"]["online"]["status"], "ghs": round(hashrate_ghs(boards), 1) if boards else None,
                "watts": round(sum((b.get("master") or {}).get("boardsW") or 0 for b in boards), 1) if boards else None,
                "tempC": max(temps) if temps else None, "houston": None, "url": "http://%s/" % host}
    except Exception:
        return {"status": "unreachable", "url": "http://%s/" % host}


def fleet():
    peers = get_settings()["apollos"]
    results = [{"name": p["name"], "host": p["host"], "status": "unreachable", "url": "http://%s/" % p["host"]} for p in peers]

    def work(i, p):
        g = glance_remote(p["host"])
        g.update({"name": p["name"], "host": p["host"]})
        results[i] = g
    threads = [threading.Thread(target=work, args=(i, p)) for i, p in enumerate(peers)]
    for t in threads:
        t.start()
    deadline = time.time() + 8
    for t in threads:
        t.join(max(0, deadline - time.time()))
    return list(results)


def local_network_hosts():
    """Addresses on this Apollo's local networks (/24), for "Find Apollos"."""
    import socket
    nets = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
        s.close()
        if not ip.startswith("127."):
            nets.add(ip.rsplit(".", 1)[0])
            return nets, ip
    except Exception:
        pass
    return nets, None


def discover():
    import socket
    nets, me = local_network_hosts()
    found, lock = [], threading.Lock()

    def probe(ip):
        try:
            with socket.create_connection((ip, 5000), timeout=0.6):
                pass
        except Exception:
            return
        try:
            req = urllib.request.Request("http://%s:5000/api/graphql" % ip,
                                         data=b'{"query":"query { Auth { status { result { status } } } }"}',
                                         method="POST", headers={"Content-Type": "application/json"})
            if b'"Auth"' not in fetch(req, 3):
                return
        except Exception:
            return
        houston = None
        try:
            houston = str(json.loads(fetch("http://%s:8088/api/device" % ip, 2).decode()).get("version"))[:20]
        except Exception:
            pass
        with lock:
            found.append({"host": ip, "houston": houston, "self": ip == me})
    threads = []
    for net in nets:
        for i in range(1, 255):
            t = threading.Thread(target=probe, args=("%s.%d" % (net, i),), daemon=True)
            t.start()
            threads.append(t)
    for t in threads:
        t.join(6)
    return sorted(found, key=lambda x: tuple(int(p) for p in x["host"].split(".")))


# --------------------------------------------------------------------------- bitcoin price
# Fetched by Houston (not the browser), so the app keeps its "no outside connections" rule and every
# phone shares one cached price. Kraken first (no key, many currencies), Coinbase as a fallback.
KRAKEN = os.environ.get("HOUSTON_KRAKEN", "https://api.kraken.com").rstrip("/")
COINBASE = os.environ.get("HOUSTON_COINBASE", "https://api.exchange.coinbase.com").rstrip("/")
FIATS = ("USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CHF")
PRICE_EVERY = float(os.environ.get("HOUSTON_PRICE_EVERY", "60"))
_price = {}


def http_json(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": "Houston/" + VERSION, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


PRICE_FAST = float(os.environ.get("HOUSTON_PRICE_FAST", "5"))   # while someone has Houston open
PRICE_WATCH = 45                                                  # "open" = asked for the price in the last 45 s
_price_seen = [0.0]
# Time frames for the price chart: span in seconds (None = since Jan 1 / everything), Kraken OHLC interval in
# minutes (Kraken returns the latest 720 candles), how long a fetched history is reused, and the Coinbase
# candle size used as a backup (Coinbase returns up to 300 candles; None = no backup for this range).
RANGES = {
    "1H": (3600, 1, 60, 60),
    "1D": (86400, 5, 300, 300),
    "7D": (7 * 86400, 30, 900, 3600),
    "1M": (30 * 86400, 240, 3600, 21600),
    "3M": (91 * 86400, 1440, 6 * 3600, 86400),
    "6M": (182 * 86400, 1440, 6 * 3600, 86400),
    "YTD": (None, 1440, 6 * 3600, 86400),
    "1Y": (365 * 86400, 1440, 6 * 3600, None),
    "5Y": (5 * 365 * 86400, 10080, 24 * 3600, None),
    "ALL": (None, 21600, 24 * 3600, None),
}
_hist = {}                 # (fiat, interval) -> {"at": time, "rows": [[t, close], ...], "source": name}
_hist_lock = threading.Lock()


def kraken_ticker(fiat):
    d = http_json("%s/0/public/Ticker?pair=XBT%s" % (KRAKEN, fiat))
    if d.get("error"):
        raise RuntimeError("; ".join(d["error"]))
    t = next(iter(d["result"].values()))
    return {"price": float(t["c"][0]), "high24": float(t["h"][1]), "low24": float(t["l"][1])}


def coinbase_ticker(fiat):
    if fiat not in ("USD", "EUR", "GBP"):
        raise RuntimeError("Coinbase backup only covers USD, EUR and GBP")
    t = http_json("%s/products/BTC-%s/ticker" % (COINBASE, fiat))
    return {"price": float(t["price"])}


def fetch_history(fiat, rng):
    """[[time, close], ...] for a time frame, cached; Kraken first, Coinbase as a backup where it reaches."""
    span, interval, keep, cb = RANGES[rng]
    key = (fiat, interval)
    with _hist_lock:
        h = _hist.get(key)
        if h and time.time() - h["at"] < keep:
            return h["rows"], h["source"]
        errors = []
        try:
            o = http_json("%s/0/public/OHLC?pair=XBT%s&interval=%d" % (KRAKEN, fiat, interval), timeout=15)
            if o.get("error"):
                raise RuntimeError("; ".join(o["error"]))
            rows = next(v for k, v in o["result"].items() if k != "last")
            got = ([[int(r[0]), float(r[4])] for r in rows], "Kraken")
        except Exception as e:
            errors.append("Kraken: %s" % e)
            got = None
        if got is None and cb and fiat in ("USD", "EUR", "GBP"):
            try:
                rows = http_json("%s/products/BTC-%s/candles?granularity=%d" % (COINBASE, fiat, cb), timeout=15)
                got = (sorted([int(r[0]), float(r[4])] for r in rows), "Coinbase")   # [time, low, high, open, close, vol]
            except Exception as e:
                errors.append("Coinbase: %s" % e)
        if got is None:
            if h:
                return h["rows"], h["source"]       # an older copy beats nothing
            raise RuntimeError("; ".join(errors) or "no price history for this time frame")
        _hist[key] = {"at": time.time(), "rows": got[0], "source": got[1]}
        if len(_hist) > 24:
            _hist.pop(min(_hist, key=lambda k: _hist[k]["at"]))
        return got


def range_start(rng, now):
    span = RANGES[rng][0]
    if rng == "YTD":
        t = time.localtime(now)
        return time.mktime((t.tm_year, 1, 1, 0, 0, 0, 0, 0, -1))
    return 0 if span is None else now - span


def refresh_price(force_history=False):
    st = get_settings()["price"]
    if not st.get("enabled"):
        return
    fiat = st.get("fiat", "USD")
    now = time.time()
    errors = []
    for name, fn in (("Kraken", kraken_ticker), ("Coinbase", coinbase_ticker)):
        try:
            got = fn(fiat)
        except Exception as e:
            errors.append("%s: %s" % (name, e))
            continue
        with LOCK:
            if _price.get("fiat") != fiat:
                _price.clear()
            _price.update({"fiat": fiat, "price": got["price"], "source": name, "updated": int(now), "error": None,
                           "high24": got.get("high24"), "low24": got.get("low24")})
        try:   # 24 h change (for the header chip, Siri and the 1D view) from the 1D history
            rows, _ = fetch_history(fiat, "1D")
            then = min(rows, key=lambda r: abs(r[0] - (now - 86400))) if rows else None
            with LOCK:
                if then and abs(then[0] - (now - 86400)) < 3 * 3600 and then[1]:
                    _price["change24"] = round((got["price"] - then[1]) / then[1] * 100, 2)
                day = [r[1] for r in rows if r[0] >= now - 86400] + [got["price"]]
                if _price.get("high24") is None:
                    _price["high24"], _price["low24"] = max(day), min(day)
                else:          # the range always includes the price right now
                    _price["high24"], _price["low24"] = max(_price["high24"], got["price"]), min(_price["low24"], got["price"])
        except Exception as e:
            log("price history not updated: %s" % e)
        return
    with LOCK:
        _price["error"] = "; ".join(errors)
    log("bitcoin price not updated: %s" % _price["error"])


def price_loop():
    last = 0.0
    while True:
        now = time.time()
        every = PRICE_FAST if now - _price_seen[0] < PRICE_WATCH else PRICE_EVERY
        if now - last >= every:
            last = now
            try:
                refresh_price()
            except Exception as e:
                log("price error: %s" % e)
        time.sleep(1)


def price_view(rng="1D", points=True):
    """The price, with the change, low and high over the time frame `rng` (1H … ALL) and its chart points."""
    st = get_settings()["price"]
    if not st.get("enabled"):
        return {"enabled": False}
    rng = {"24h": "1D", "7d": "7D"}.get(rng, rng)
    if rng not in RANGES:
        rng = "1D"
    with LOCK:
        p = dict(_price)
    now = time.time()
    fiat = p.get("fiat") or st.get("fiat", "USD")
    p.update({"enabled": True, "fiat": fiat, "range": rng, "ranges": list(RANGES)})
    try:
        rows, src = fetch_history(fiat, rng)
        start = range_start(rng, now)
        pts = [r for r in rows if r[0] >= start]
        if p.get("price"):
            pts = pts + [[int(p.get("updated") or now), p["price"]]]
        if len(pts) >= 2 and pts[0][1]:
            ys = [r[1] for r in pts]
            p.update({"change": round((pts[-1][1] - pts[0][1]) / pts[0][1] * 100, 2), "low": min(ys), "high": max(ys),
                      "from": pts[0][0]})
        if points:
            p["points"] = pts
    except Exception as e:
        p["rangeError"] = str(e)[:200]
        if points:
            p["points"] = []
    return p


# --------------------------------------------------------------------------- bitcoin network, market and news
# Also fetched by Houston (never the browser), cached and shared by every device. All public data, no
# account or key: mempool.space (blocks, difficulty), CoinGecko (market cap, dominance, volume),
# alternative.me (Fear & Greed Index) and Bitcoin Magazine's RSS feed (headlines). Can be turned off.
MEMPOOL = os.environ.get("HOUSTON_MEMPOOL", "https://mempool.space").rstrip("/")
COINGECKO = os.environ.get("HOUSTON_COINGECKO", "https://api.coingecko.com").rstrip("/")
FNG = os.environ.get("HOUSTON_FNG", "https://api.alternative.me").rstrip("/")
NEWS_FEED = os.environ.get("HOUSTON_NEWS", "https://bitcoinmagazine.com/feed")
NEWS_SOURCE = "Bitcoin Magazine"
MARKET_EVERY = float(os.environ.get("HOUSTON_MARKET_EVERY", "300"))
# how often each part is refreshed, in multiples of MARKET_EVERY (5 minutes)
MARKET_PARTS = {"network": 1, "market": 2, "news": 6, "fng": 12}
_market = {}
NEWS_LINK_RE = re.compile(r"^https://[A-Za-z0-9.-]+(:\d+)?(/[^\s<>\"']*)?$")


def http_text(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": "Houston/" + VERSION, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(MAX_REPLY)


def btc_supply(height):
    """Bitcoin in existence after block `height` (50 BTC per block, halving every 210,000 blocks)."""
    sats, sub, left = 0, 50 * 10 ** 8, height + 1
    while left > 0 and sub > 0:
        n = min(left, 210000)
        sats += n * sub
        left -= n
        sub //= 2
    return sats / 1e8


def fetch_network():
    height = int(http_text(MEMPOOL + "/api/blocks/tip/height").decode().strip())
    blocks = json.loads(http_text(MEMPOOL + "/api/v1/blocks").decode())
    last = max((b for b in blocks if isinstance(b, dict) and b.get("timestamp")), key=lambda b: b.get("height", 0))
    d = json.loads(http_text(MEMPOOL + "/api/v1/difficulty-adjustment").decode())
    return {"height": height, "lastBlockTime": int(last["timestamp"]),
            "blockMinutes": round(float(d["timeAvg"]) / 60000, 2) if d.get("timeAvg") else None,
            "retargetBlocks": d.get("remainingBlocks"), "retargetChange": d.get("difficultyChange"),
            "retargetTime": int(d["estimatedRetargetDate"] / 1000) if d.get("estimatedRetargetDate") else None,
            "supply": round(btc_supply(height), 2)}


def fetch_market(fiat):
    f = fiat.lower()
    p = json.loads(http_text("%s/api/v3/simple/price?ids=bitcoin&vs_currencies=%s&include_market_cap=true&include_24hr_vol=true"
                             % (COINGECKO, f)).decode())["bitcoin"]
    g = json.loads(http_text(COINGECKO + "/api/v3/global").decode())["data"]
    return {"fiat": fiat, "marketCap": p.get(f + "_market_cap"), "volume24": p.get(f + "_24h_vol"),
            "dominance": g.get("market_cap_percentage", {}).get("btc")}


def fetch_fng():
    d = json.loads(http_text(FNG + "/fng/?limit=1").decode())["data"][0]
    v = int(d["value"])
    if not 0 <= v <= 100:
        raise ValueError("index out of range")
    return {"value": v, "label": str(d.get("value_classification") or "")[:30], "time": int(d.get("timestamp") or 0)}


def parse_feed(raw, limit=6):
    """Headlines from an RSS or Atom feed. Only plain text and https links are kept."""
    import email.utils
    import xml.etree.ElementTree as ET
    if re.search(rb"<!ENTITY", raw, re.I):            # no custom entities (entity-expansion attacks)
        raise ValueError("feed declares entities")
    root = ET.fromstring(raw)
    out = []
    for it in root.iter():
        if it.tag.split("}")[-1] not in ("item", "entry"):
            continue
        title = link = when = None
        for ch in it:
            t = ch.tag.split("}")[-1]
            if t == "title" and title is None:
                title = "".join(ch.itertext())
            elif t == "link" and link is None:
                link = (ch.text or ch.get("href") or "").strip()
            elif t in ("pubDate", "published", "updated") and when is None:
                when = (ch.text or "").strip()
        title = re.sub(r"\s+", " ", re.sub(r"<[^>]*>", "", title or "")).strip()[:160]
        if not title or not link or len(link) > 500 or not NEWS_LINK_RE.match(link):
            continue
        ts = None
        if when:
            try:
                ts = int(email.utils.parsedate_to_datetime(when).timestamp())
            except (TypeError, ValueError, IndexError):
                try:
                    ts = int(dt.datetime.fromisoformat(when.replace("Z", "+00:00")).timestamp())
                except ValueError:
                    ts = None
        out.append({"title": title, "link": link, "time": ts})
        if len(out) >= limit:
            break
    return out


def fetch_news():
    items = parse_feed(http_text(NEWS_FEED, 15))
    if not items:
        raise ValueError("no headlines in the feed")
    return {"items": items, "source": NEWS_SOURCE}


def refresh_market(force=False):
    if not get_settings()["market"].get("enabled"):
        return
    fiat = get_settings()["price"].get("fiat", "USD")
    now = time.time()
    jobs = {"network": fetch_network, "market": lambda: fetch_market(fiat), "fng": fetch_fng, "news": fetch_news}
    for part, every in MARKET_PARTS.items():
        with LOCK:
            cur = _market.get(part) or {}
        stale = now - cur.get("at", 0) >= every * MARKET_EVERY - 1
        if part == "market" and cur.get("fiat") != fiat:
            stale = True
        if not (force or stale):
            continue
        try:
            got = jobs[part]()
            got["at"] = int(now)
            with LOCK:
                _market[part] = got
                _market.setdefault("errors", {}).pop(part, None)
        except Exception as e:
            with LOCK:
                _market.setdefault("errors", {})[part] = str(e)[:200]
                if part == "market" and cur.get("fiat") != fiat:
                    _market.pop("market", None)          # don't show another currency's numbers
            log("%s data not updated: %s" % (part, e))


def market_loop():
    while True:
        try:
            refresh_market()
        except Exception as e:
            log("market error: %s" % e)
        time.sleep(max(5, min(60, MARKET_EVERY)))


def market_view():
    st = get_settings()
    if not st["market"].get("enabled"):
        return {"enabled": False}
    with LOCK:
        m = json.loads(json.dumps(_market))
        price, pfiat = _price.get("price"), _price.get("fiat")
    fiat = st["price"].get("fiat", "USD")
    net = m.get("network")
    mk = dict(m.get("market") or {})
    if price and pfiat == fiat:
        mk["satsPer"] = round(1e8 / price)
        if not mk.get("marketCap") and net and net.get("supply"):
            mk["marketCap"] = round(price * net["supply"])            # price × coins in existence
            mk["capEstimated"] = True
    return {"enabled": True, "fiat": fiat, "network": net, "market": mk or None, "fng": m.get("fng"),
            "news": m.get("news"), "errors": m.get("errors") or {}, "now": int(time.time())}


# --------------------------------------------------------------------------- automation API (Siri Shortcuts etc.)
_auto_fail = []

# --------------------------------------------------------------------------- mining economics
# What running the Apollo actually earns and costs, from Houston's own measurements (hashrate and watts per
# mode), your electricity price (flat or time-of-use), the network's real difficulty and fees, the bitcoin
# price, and (optionally) the value of the heat it puts into your home. Public data only, fetched by Houston:
# mempool.space (difficulty, fees) and Open-Meteo (outdoor temperature, if you give a location).
METEO = os.environ.get("HOUSTON_METEO", "https://api.open-meteo.com").rstrip("/")
METEO_GEO = os.environ.get("HOUSTON_METEO_GEO", "https://geocoding-api.open-meteo.com").rstrip("/")
METEO_ARCHIVE = os.environ.get("HOUSTON_METEO_ARCHIVE", "https://archive-api.open-meteo.com").rstrip("/")
ECON_EVERY = float(os.environ.get("HOUSTON_ECON_EVERY", "1800"))      # network data refresh (seconds)
ECON_FILE = os.path.join(STATE_DIR, "econ.json")
HEAT_TYPES = ("none", "electric", "heatpump", "gas", "propane", "oil")
HEAT_KWH = {"gas": 29.3071, "propane": 26.8, "oil": 40.6}           # kWh of heat in a therm / gallon
HEAT_UNIT = {"gas": "therm", "propane": "gallon", "oil": "gallon"}
AUTOPILOT_MODES = ("off", "suggest", "run")
AUTOPILOT_EVERY = float(os.environ.get("HOUSTON_AUTOPILOT_EVERY", "300"))   # how often the autopilot looks (seconds)
# Starting estimates until Houston has measured a mode itself (TH/s, watts). Apollo II figures are measured
# on a real unit; Apollo III figures are rough and get replaced by your own readings.
MODE_DEFAULTS = {
    "ii": {"whisper": (2.93, 107), "eco": (5.6, 209), "balanced": (6.6, 260), "turbo": (7.6, 330)},
    "iii": {"super_eco": (4.2, 140), "eco": (5.75, 209), "balanced": (6.6, 260), "turbo": (7.6, 330)},
}
_econ = {"errors": {}}
_econ_lock = threading.Lock()


def econ_defaults():
    return {"enabled": True, "tou": [], "extraW": 0, "poolFee": 0.0,
            "heat": {"type": "none", "cop": 3.0, "price": None, "eff": 0.95, "balanceC": 15.5, "location": ""},
            "autopilot": {"mode": "off", "modes": [], "allowStop": False, "minGain": 0.05}}


def subsidy_btc(height):
    return 50.0 / (2 ** (int(height) // 210000))


def btc_per_th_day(difficulty, height, fee_btc):
    """Expected BTC a day for 1 TH/s: (hashes a day / hashes per block) x (block subsidy + average fees)."""
    return 1e12 * 86400 / (float(difficulty) * 2 ** 32) * (subsidy_btc(height) + float(fee_btc))


def _in_window(minute, start, end):
    return start <= minute < end if start < end else (minute >= start or minute < end)


def rate_at(ts, s):
    """Electricity price at time `ts` (local time): the first matching time-of-use period, else the flat rate."""
    lt = time.localtime(ts)
    minute = lt.tm_hour * 60 + lt.tm_min
    for p in s["econ"].get("tou") or []:
        start, end = (int(p["from"][:2]) * 60 + int(p["from"][3:]), int(p["to"][:2]) * 60 + int(p["to"][3:]))
        day = lt.tm_wday + 1
        if start >= end and minute < end:          # overnight period: the early hours belong to the previous day
            day = 7 if day == 1 else day - 1
        if day in p["days"] and _in_window(minute, start, end):
            return float(p["rate"])
    return s.get("rate")


def heat_value(ts, temp_c, s, rate=None):
    """What a kWh of the Apollo's heat is worth at `ts`: what your heating would have paid for that heat, when
    it's cold enough to need heating (outdoor temperature below your balance point). 0 otherwise."""
    h = s["econ"]["heat"]
    kind = h.get("type", "none")
    if kind == "none" or temp_c is None or temp_c >= float(h.get("balanceC", 15.5)):
        return 0.0
    if rate is None:
        rate = rate_at(ts, s)
    if kind == "electric":
        return float(rate or 0)                                   # resistive heat: 1 kWh in, 1 kWh of heat
    if kind == "heatpump":
        return float(rate or 0) / max(1.0, float(h.get("cop") or 3))
    price = h.get("price")
    if price is None:
        return 0.0
    return float(price) / HEAT_KWH[kind] / max(0.3, float(h.get("eff") or 0.9))


def mode_stats(iii=None):
    """Average TH/s and watts per mode from Houston's readings (last 7 days, while mining). Modes Houston hasn't
    measured for at least 30 minutes use the starting estimates, marked measured=False."""
    if iii is None:
        iii = chassis() == "apollo-iii"
    defaults = MODE_DEFAULTS["iii" if iii else "ii"]
    with LOCK:
        hist = list(_history)
    acc = {}
    for x in hist:
        m, h, w = x.get("m"), x.get("h"), x.get("w")
        if x.get("s") == "online" and m and h and w and h > 100:
            a = acc.setdefault(m, [0, 0.0, 0.0])
            a[0] += 1; a[1] += h / 1000; a[2] += w
    out = {}
    for m, (ths, w) in defaults.items():
        a = acc.get(m)
        if a and a[0] >= 30:
            out[m] = {"ths": round(a[1] / a[0], 3), "watts": round(a[2] / a[0], 1), "measured": True, "hours": round(a[0] * SAMPLE_EVERY / 3600, 1)}
        else:
            out[m] = {"ths": ths, "watts": w, "measured": False, "hours": round((a[0] if a else 0) * SAMPLE_EVERY / 3600, 1)}
    up = [1 if x.get("s") == "online" else 0 for x in hist if x.get("s")]
    return out, (sum(up) / len(up) if up else None)


def mode_hour(ms, btcday, price, rate, hv, s):
    """Money per hour for one mode: revenue, electricity, heat credit, net."""
    kw = (ms["watts"] + float(s["econ"].get("extraW") or 0)) / 1000
    rev = ms["ths"] * btcday / 24 * price * (1 - float(s["econ"].get("poolFee") or 0) / 100)
    cost = kw * float(rate or 0)
    heat = kw * hv
    return {"revenue": rev, "cost": cost, "heat": heat, "net": rev - cost + heat, "kw": kw}


def breakeven_rate(ms, btcday, price, hv_kind, s, hv_fixed):
    """The electricity price at which this mode exactly pays for itself (with the heat credit, if it's heating)."""
    kw = (ms["watts"] + float(s["econ"].get("extraW") or 0)) / 1000
    rev = ms["ths"] * btcday / 24 * price * (1 - float(s["econ"].get("poolFee") or 0) / 100)
    if hv_kind == "electric":
        return None                                             # heat offsets every cent: pays at any price
    if hv_kind == "heatpump":
        cop = max(1.0, float(s["econ"]["heat"].get("cop") or 3))
        return rev / (kw * (1 - 1 / cop)) if cop > 1 else None
    return (rev + kw * hv_fixed) / kw


def difficulty_growth(points, days=180):
    """Monthly difficulty growth from a least-squares fit of log(difficulty) over the last `days` days."""
    import math
    now = time.time()
    pts = [(t, d) for t, d in points if t >= now - days * 86400 and d > 0]
    if len(pts) < 3:
        return None
    xs = [t / 86400 for t, _ in pts]
    ys = [math.log(d) for _, d in pts]
    n = len(xs); mx = sum(xs) / n; my = sum(ys) / n
    den = sum((x - mx) ** 2 for x in xs)
    if den == 0:
        return None
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den
    return math.exp(slope * 30.44) - 1


# ---- data
def fetch_econ_network():
    hr = http_json(MEMPOOL + "/api/v1/mining/hashrate/1y", timeout=20)
    rs = http_json(MEMPOOL + "/api/v1/mining/reward-stats/144")
    da = http_json(MEMPOOL + "/api/v1/difficulty-adjustment")
    diffs = []
    for p in hr.get("difficulty") or []:
        t, d = p.get("time") or p.get("timestamp"), p.get("difficulty")
        if t and d:
            diffs.append([int(t), float(d)])
    diffs.sort()
    blocks = max(1, int(rs.get("endBlock", 0)) - int(rs.get("startBlock", 0)) + 1)
    return {"difficulty": float(hr.get("currentDifficulty") or diffs[-1][1]), "hashrate": float(hr.get("currentHashrate") or 0),
            "height": int(rs.get("endBlock") or 0), "feeBtc": float(rs.get("totalFee") or 0) / blocks / 1e8,
            "rewardBtc": float(rs.get("totalReward") or 0) / blocks / 1e8, "history": diffs,
            "nextChange": da.get("difficultyChange"), "retargetTime": int(da["estimatedRetargetDate"] / 1000) if da.get("estimatedRetargetDate") else None,
            "at": int(time.time())}


def geocode(location):
    from urllib.parse import quote
    loc = (location or "").strip()
    m = re.match(r"^\s*(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)\s*$", loc)
    if m:
        return {"lat": float(m.group(1)), "lon": float(m.group(3)), "name": loc}
    j = http_json("%s/v1/search?name=%s&count=1&language=en&format=json" % (METEO_GEO, quote(loc)))
    r = (j.get("results") or [None])[0]
    if not r:
        raise RuntimeError("couldn't find '%s'" % loc)
    name = ", ".join(x for x in (r.get("name"), r.get("admin1"), r.get("country_code")) if x)
    return {"lat": float(r["latitude"]), "lon": float(r["longitude"]), "name": name}


def fetch_forecast(geo):
    j = http_json("%s/v1/forecast?latitude=%.2f&longitude=%.2f&hourly=temperature_2m&past_days=1&forecast_days=2"
                  "&timezone=UTC&timeformat=unixtime" % (METEO, geo["lat"], geo["lon"]))
    h = j.get("hourly") or {}
    return [[int(t), v] for t, v in zip(h.get("time") or [], h.get("temperature_2m") or []) if v is not None]


def fetch_archive(geo):
    end = dt.date.today() - dt.timedelta(days=6)
    start = end - dt.timedelta(days=372)
    j = http_json("%s/v1/archive?latitude=%.2f&longitude=%.2f&start_date=%s&end_date=%s&daily=temperature_2m_mean"
                  "&timezone=UTC&timeformat=unixtime" % (METEO_ARCHIVE, geo["lat"], geo["lon"], start, end), timeout=25)
    d = j.get("daily") or {}
    return [[int(t), v] for t, v in zip(d.get("time") or [], d.get("temperature_2m_mean") or []) if v is not None]


def refresh_econ(force=False):
    s = get_settings()
    if not s["econ"].get("enabled"):
        return
    now = time.time()
    with _econ_lock:
        state = _econ
        net = state.get("network")
        if force or not net or now - net.get("at", 0) >= ECON_EVERY:
            try:
                state["network"] = fetch_econ_network()
                state["errors"].pop("network", None)
            except Exception as e:
                state["errors"]["network"] = str(e)[:200]
                log("economics: network data not updated: %s" % e)
        loc = (s["econ"]["heat"].get("location") or "").strip()
        if loc and s["econ"]["heat"].get("type") != "none":
            saved = read_json(ECON_FILE, {})
            geo = saved.get("geo")
            try:
                if not geo or geo.get("query") != loc:
                    geo = geocode(loc)
                    geo["query"] = loc
                    saved = {"geo": geo}                         # new place: old weather doesn't apply
                    write_json(ECON_FILE, saved, private=True)
                    state.pop("forecast", None); state.pop("archive", None); state.pop("backtest", None)
                state["geo"] = geo
                fc = state.get("forecast")
                if force or not fc or now - fc["at"] >= 3600:
                    state["forecast"] = {"at": int(now), "hours": fetch_forecast(geo)}
                ar = state.get("archive") or saved.get("archive")
                if not ar or now - ar.get("at", 0) >= 86400 * 3:
                    ar = {"at": int(now), "days": fetch_archive(geo)}
                    saved["archive"] = ar
                    write_json(ECON_FILE, saved, private=True)
                    state.pop("backtest", None)
                state["archive"] = ar
                state["errors"].pop("weather", None)
            except Exception as e:
                state["errors"]["weather"] = str(e)[:200]
                log("economics: weather not updated: %s" % e)
        else:
            for k in ("geo", "forecast", "archive"):
                state.pop(k, None)


def temp_at(ts):
    fc = (_econ.get("forecast") or {}).get("hours") or []
    if not fc:
        return None
    t, v = min(fc, key=lambda r: abs(r[0] - ts))
    return v if abs(t - ts) <= 3 * 3600 else None


def econ_inputs():
    """Everything the model needs right now, or (None, reason)."""
    s = get_settings()
    if not s["econ"].get("enabled"):
        return None, "off"
    if s.get("rate") is None and not s["econ"].get("tou"):
        return None, "rate"
    net = _econ.get("network")
    with LOCK:
        p = dict(_price)
    if not net or not p.get("price"):
        return None, "waiting"
    if p.get("fiat") and s["price"].get("fiat") and p["fiat"] != s["price"]["fiat"]:
        return None, "waiting"
    btcday = btc_per_th_day(net["difficulty"], net["height"], net["feeBtc"])
    return {"s": s, "net": net, "price": float(p["price"]), "fiat": p.get("fiat", "USD"), "btcday": btcday}, None


def allowed_modes(s, stats):
    ap = s["econ"]["autopilot"].get("modes") or []
    ms = [m for m in stats if (not ap or m in ap)]
    return ms or list(stats)


def best_choice(stats, inp, ts, temp_c, current=None):
    """The mode that earns the most (or loses the least) at time `ts`; 'stop' when stopping is allowed and every mode loses."""
    s = inp["s"]
    rate = rate_at(ts, s)
    hv = heat_value(ts, temp_c, s, rate)
    nets = {m: mode_hour(stats[m], inp["btcday"], inp["price"], rate, hv, s)["net"] for m in allowed_modes(s, stats)}
    if s["econ"]["autopilot"].get("allowStop"):
        nets["stop"] = 0.0
    best = max(nets, key=lambda k: nets[k])
    return best, nets, rate, hv


def backtest(stats, inp, temps_by_day, days=365):
    """What each way of running would have earned over the last year: the real difficulty and daily bitcoin
    price for every day, your electricity prices hour by hour, heat credit from that day's outdoor temperature,
    and today's measured hashrate and watts per mode. Fees: the recent average (they aren't in the daily data)."""
    s = inp["s"]
    net = inp["net"]
    diffs = net.get("history") or []
    try:
        rows, _ = fetch_history(inp["fiat"], "1Y")
    except Exception:
        rows = []
    prices = sorted(rows)
    if len(diffs) < 2 or len(prices) < 30:
        return None
    modes = list(stats)                       # every mode is shown; the autopilot only picks from the allowed ones
    pick = set(allowed_modes(s, stats))
    allow_stop = bool(s["econ"]["autopilot"].get("allowStop"))
    strategies = {m: {"net": 0.0, "revenue": 0.0, "cost": 0.0, "heat": 0.0, "btc": 0.0} for m in modes}
    strategies["auto"] = {"net": 0.0, "revenue": 0.0, "cost": 0.0, "heat": 0.0, "btc": 0.0, "hours": {}}
    series = {k: [] for k in strategies}
    today = dt.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    di = pi = 0
    for k in range(days, 0, -1):
        day = today - dt.timedelta(days=k)
        t0 = day.timestamp()
        while di + 1 < len(diffs) and diffs[di + 1][0] <= t0:
            di += 1
        while pi + 1 < len(prices) and prices[pi + 1][0] <= t0 + 43200:
            pi += 1
        diff, price = diffs[di][1], prices[pi][1]
        if diffs[0][0] > t0 + 86400 or abs(prices[pi][0] - t0) > 4 * 86400:
            continue
        btcday = btc_per_th_day(diff, net["height"], net["feeBtc"])
        temp = temps_by_day.get(day.strftime("%Y-%m-%d"))
        for h in range(24):
            ts = t0 + h * 3600
            rate = rate_at(ts, s)
            hv = heat_value(ts, temp, s, rate)
            best, best_net, best_r = None, None, None
            for m in modes:
                r = mode_hour(stats[m], btcday, price, rate, hv, s)
                st = strategies[m]
                st["net"] += r["net"]; st["revenue"] += r["revenue"]; st["cost"] += r["cost"]; st["heat"] += r["heat"]
                st["btc"] += stats[m]["ths"] * btcday / 24 * (1 - float(s["econ"].get("poolFee") or 0) / 100)
                if m in pick and (best_net is None or r["net"] > best_net):
                    best, best_net, best_r = m, r["net"], r
            a = strategies["auto"]
            if allow_stop and best_net < 0:
                a["hours"]["stop"] = a["hours"].get("stop", 0) + 1
            else:
                a["net"] += best_r["net"]; a["revenue"] += best_r["revenue"]; a["cost"] += best_r["cost"]; a["heat"] += best_r["heat"]
                a["btc"] += stats[best]["ths"] * btcday / 24 * (1 - float(s["econ"].get("poolFee") or 0) / 100)
                a["hours"][best] = a["hours"].get(best, 0) + 1
        if k % 7 == 0 or k == 1:
            for name, st in strategies.items():
                series[name].append([int(t0 + 86400), round(st["net"], 2)])
    out = {name: {kk: (round(v, 2) if isinstance(v, float) and kk != "btc" else (round(v, 8) if kk == "btc" else v)) for kk, v in st.items()}
           for name, st in strategies.items()}
    return {"strategies": out, "series": series, "days": days, "at": int(time.time()), "heat": bool(temps_by_day)}


def econ_view():
    inp, why = econ_inputs()
    s = get_settings()
    base = {"enabled": s["econ"].get("enabled", True), "settings": s["econ"], "errors": dict(_econ.get("errors") or {}),
            "rate": s.get("rate"), "currency": s.get("currency", "$")}
    if why:
        base["missing"] = why
        return base
    net, price, btcday = inp["net"], inp["price"], inp["btcday"]
    iii = chassis() == "apollo-iii"
    stats, uptime = mode_stats(iii)
    now = time.time()
    temp_now = temp_at(now)
    rate_now = rate_at(now, s)
    hv_now = heat_value(now, temp_now, s, rate_now)
    kind = s["econ"]["heat"].get("type", "none")
    current = _last.get("m") if _last.get("m") in stats else None
    modes = {}
    for m, ms in stats.items():
        r = mode_hour(ms, btcday, price, rate_now, hv_now, s)
        hv_fixed = heat_value(now, -100, s, rate_now) if kind in HEAT_KWH else 0.0
        be = breakeven_rate(ms, btcday, price, kind if hv_now > 0 else "none", s, hv_fixed if hv_now > 0 else 0.0)
        need = (r["cost"] - r["heat"]) / (r["revenue"] / price) if r["revenue"] > 0 and r["cost"] > r["heat"] else 0.0
        modes[m] = {"ths": ms["ths"], "watts": ms["watts"], "measured": ms["measured"], "hours": ms["hours"],
                    "revenue": round(r["revenue"] * 24, 4), "cost": round(r["cost"] * 24, 4), "heat": round(r["heat"] * 24, 4),
                    "net": round(r["net"] * 24, 4), "breakevenRate": round(be, 4) if be is not None else None,
                    "breakevenPrice": round(need, 0), "sats": round(ms["ths"] * btcday * 1e8 * (1 - float(s["econ"].get("poolFee") or 0) / 100))}
    # next 24 hours, hour by hour (time-of-use prices and the temperature forecast)
    start = int(now // 3600 * 3600)
    hours = []
    for i in range(24):
        ts = start + i * 3600
        t = temp_at(ts)
        best, nets, rate, hv = best_choice(stats, inp, ts, t)
        hours.append({"t": ts, "rate": rate, "tempC": t, "best": best, "net": round(nets[best], 4),
                      "nets": {k: round(v, 4) for k, v in nets.items()}})
    # outlook: difficulty trend, and the next 12 months at today's price for the mode in use (or Eco)
    g = difficulty_growth(net.get("history") or [])
    ref = current or ("eco" if "eco" in stats else next(iter(stats)))
    rev_day = modes[ref]["revenue"]
    if g is not None:
        factor = sum(1 / (1 + g) ** (k + 0.5) for k in range(12)) / 12
    else:
        factor = 1.0
    outlook = {"growthMonth": round(g, 4) if g is not None else None, "nextChange": net.get("nextChange"),
               "retargetTime": net.get("retargetTime"), "mode": ref,
               "year": {"calculator": round(rev_day * 365, 2), "houston": round(rev_day * 365 * factor, 2)}}
    # last 12 months
    with _econ_lock:
        bt = _econ.get("backtest")
        if not bt or now - bt.get("at", 0) > 6 * 3600 or bt.get("key") != json.dumps(s["econ"], sort_keys=True) + str(s.get("rate")):
            temps = {}
            for t, v in ((_econ.get("archive") or {}).get("days") or []):
                temps[dt.datetime.fromtimestamp(t, dt.timezone.utc).strftime("%Y-%m-%d")] = v
            try:
                bt = backtest(stats, inp, temps)
                if bt:
                    bt["key"] = json.dumps(s["econ"], sort_keys=True) + str(s.get("rate"))
                    _econ["backtest"] = bt
            except Exception as e:
                log("economics: backtest failed: %s" % e)
                bt = None
    ap = s["econ"]["autopilot"]
    best_now, nets_now, _, _ = best_choice(stats, inp, now, temp_now)
    state = dict(_econ.get("ap") or {})
    reward = net.get("rewardBtc") or (subsidy_btc(net["height"]) + net["feeBtc"])
    base.update({
        "price": price, "fiat": inp["fiat"], "btcPerThDay": btcday, "hashprice": round(btcday * price * 1000, 2),
        "network": {"difficulty": net["difficulty"], "hashrate": net["hashrate"], "height": net["height"],
                    "feeBtc": round(net["feeBtc"], 5), "subsidy": subsidy_btc(net["height"]),
                    "feeShare": round(net["feeBtc"] / reward, 4) if reward else None, "at": net["at"]},
        "now": {"rate": rate_now, "tempC": temp_now, "heatValue": round(hv_now, 4), "heating": hv_now > 0, "mode": current,
                "status": _last.get("s")},
        "modes": modes, "uptime": round(uptime, 4) if uptime is not None else None, "hours": hours, "outlook": outlook,
        "backtest": {k: v for k, v in (bt or {}).items() if k != "key"} if bt else None,
        "place": (_econ.get("geo") or {}).get("name"),
        "autopilot": {"mode": ap.get("mode", "off"), "best": best_now, "nets": {k: round(v * 24, 4) for k, v in nets_now.items()},
                      "state": state},
    })
    return base


# ---- autopilot and economics alerts
def _recent_manual(minutes=120):
    cutoff = dt.datetime.now().astimezone() - dt.timedelta(minutes=minutes)
    for it in read_json(ACTIVITY_FILE, [])[:20]:
        try:
            t = dt.datetime.fromisoformat(it.get("time"))
        except (TypeError, ValueError):
            continue
        if t < cutoff:
            break
        a = it.get("action", "")
        if it.get("source") in ("app", "shortcut", "schedule") and (a in ("start", "stop") or a in MODES or a.startswith(("custom", "start@"))):
            return True
    return False


def autopilot_step():
    inp, why = econ_inputs()
    if why:
        return
    s = inp["s"]
    ap = s["econ"]["autopilot"]
    mode = ap.get("mode", "off")
    state = _econ.setdefault("ap", {})
    if mode == "off":
        state.clear()
        return
    stats, _ = mode_stats()
    now = time.time()
    best, nets, rate, hv = best_choice(stats, inp, now, temp_at(now))
    status, current = _last.get("s"), _last.get("m")
    running = status in ("online", "pending")
    if not running:
        cur_key, cur_net = "stop", 0.0
    elif current in stats:
        cur_key = current
        cur_net = mode_hour(stats[current], inp["btcday"], inp["price"], rate, hv, s)["net"]
    else:
        cur_key, cur_net = None, None          # a mode Houston can't price (e.g. a dashboard custom setting): leave it alone
    if state.get("best") != best:
        state.update({"best": best, "since": now})
    gain_day = (nets[best] - cur_net) * 24 if cur_key else 0
    state.update({"gainDay": round(gain_day, 4), "checked": int(now)})
    min_gain = float(ap.get("minGain") or 0.05)
    if mode == "suggest":
        lasting = now - state.get("since", now) >= 3600
        should = cur_key is not None and best != cur_key and gain_day >= min_gain and lasting
        label_best = "stopping" if best == "stop" else label(best)
        alert("econ_suggest", should and get_settings()["alerts"].get("econ", True),
              "Autopilot suggests %s" % label_best,
              "Right now %s would earn %s more a day than %s (electricity %s/kWh%s)." % (
                  label_best, money_txt(gain_day, s), "stopped" if cur_key == "stop" else label(cur_key or ""),
                  money_txt(rate or 0, s, 3), ", heat counted" if hv > 0 else ""), "bulb", "low", repeat_hours=12)
        return
    # mode == "run": act, but never fight a change you just made, and don't flip back and forth
    token = stored_token()
    if not token or cur_key is None or best == cur_key or status in ("unreachable", None) or updating():
        return
    if _recent_manual():
        state["paused"] = "your change"
        return
    state.pop("paused", None)
    if gain_day < min_gain or now - state.get("appliedAt", 0) < 3600:
        return
    action = "stop" if best == "stop" else (("start@" + best) if not running else best)
    state.update({"applied": best, "appliedAt": now})
    why_txt = "%s/day better than %s" % (money_txt(gain_day, s), "stopped" if cur_key == "stop" else label(cur_key))
    try:
        msg = run_action(action, token)
        if action.startswith("start@"):
            msg = "Started mining in %s" % label(best)
        add_activity(action, True, "%s (%s)" % (msg, why_txt), source="autopilot")
        log("autopilot: %s -> %s" % (action, msg))
    except Exception as e:
        add_activity(action, False, str(e), source="autopilot")


def money_txt(v, s, digits=2):
    cur = s.get("currency") or "$"
    sign = "-" if v < 0 else ""
    return "%s%s%.*f" % (sign, cur, digits, abs(v))


def econ_alerts():
    inp, why = econ_inputs()
    if why:
        return
    s = inp["s"]
    if not s["alerts"].get("econ", True):
        return
    net = inp["net"]
    saved = read_json(ECON_FILE, {})
    last = saved.get("lastDifficulty")
    if last and abs(net["difficulty"] - last) / last > 0.001:
        change = (net["difficulty"] - last) / last * 100
        stats, _ = mode_stats()
        m = _last.get("m") if _last.get("m") in stats else ("eco" if "eco" in stats else next(iter(stats)))
        r = mode_hour(stats[m], inp["btcday"], inp["price"], rate_at(time.time(), s), 0.0, s)
        title = "Difficulty %s %.1f%%" % ("up" if change > 0 else "down", abs(change))
        msg = "Your Apollo now earns about %.1f%% %s per day: %s a day in %s." % (abs(change) / (1 + change / 100), "less" if change > 0 else "more",
                                                                           money_txt(r["revenue"] * 24, s), label(m))
        if s["alerts"]["enabled"] and alert_channels(s):
            try:
                notify(title, msg, "chart_with_upwards_trend" if change > 0 else "chart_with_downwards_trend", "low", s, tag="econ")
                add_activity("alert", True, title + ": " + msg, source="alert")
            except Exception as e:
                log("economics alert not sent: %s" % e)
    if not last or abs(net["difficulty"] - last) / last > 0.001:
        saved["lastDifficulty"] = net["difficulty"]
        write_json(ECON_FILE, saved, private=True)
    # pays / doesn't pay for itself, for the mode in use
    stats, _ = mode_stats()
    m = _last.get("m")
    if m in stats and _last.get("s") == "online":
        now = time.time()
        rate = rate_at(now, s)
        r = mode_hour(stats[m], inp["btcday"], inp["price"], rate, heat_value(now, temp_at(now), s, rate), s)
        alert("econ_pays", r["net"] > 0.001, "Your Apollo pays for itself right now",
              "%s earns %s a day more than its electricity%s costs." % (label(m), money_txt(r["net"] * 24, s), " (minus the heat it saves)" if r["heat"] else ""),
              "moneybag", "low", repeat_hours=24 * 7)


def econ_loop():
    time.sleep(10)
    last_ap = 0
    while True:
        try:
            refresh_econ()
            econ_alerts()
            if time.time() - last_ap >= AUTOPILOT_EVERY:
                last_ap = time.time()
                autopilot_step()
        except Exception as e:
            log("economics error: %s" % e)
        time.sleep(min(60, max(5, AUTOPILOT_EVERY)))


# --------------------------------------------------------------------------- Apollo software updates
# FutureBit's own update: Houston only asks the Apollo's API to run it (Mcu.update) and follows its
# progress (Mcu.updateProgress), exactly like the Apollo dashboard does. It downloads the new
# dashboard and API, rebuilds them and reboots the Apollo. Houston itself isn't touched by it.
APOLLO_DIR = os.environ.get("HOUSTON_APOLLO_DIR", "/opt/apolloapi")
UPDATE_FILE = os.path.join(STATE_DIR, "update.json")
UPDATE_EVERY = float(os.environ.get("HOUSTON_UPDATE_EVERY", str(6 * 3600)))   # how often to look for a new version
UPDATE_WINDOW = float(os.environ.get("HOUSTON_UPDATE_WINDOW", str(90 * 60)))  # after this, an update counts as stuck
VER_RE = re.compile(r"^v?(\d{1,4})\.(\d{1,4})\.(\d{1,4})")
_upd = {"latest": None, "checked": 0.0}


def vtuple(v):
    m = VER_RE.match(str(v or "").strip())
    return tuple(int(x) for x in m.groups()) if m else None


def installed_version():
    """The Apollo software version on this Apollo (the dashboard's own package.json, like the dashboard uses)."""
    for rel in ("apolloui-v2/package.json", "package.json"):
        pk = read_json(os.path.join(APOLLO_DIR, rel), {})
        v = pk.get("version") if isinstance(pk, dict) else None
        if vtuple(v):
            return str(v).lstrip("v")
    return None


def latest_version(token, force=False):
    """The newest Apollo software, as the Apollo's API reports it (it asks FutureBit's GitHub)."""
    if not force and _upd["latest"] and time.time() - _upd["checked"] < 3600:
        return _upd["latest"]
    d = apollo("query { Mcu { version { result error { message } } } }", token=token, timeout=20)
    v = d["Mcu"]["version"]
    if v.get("error"):
        raise RuntimeError(v["error"].get("message") or "version check failed")
    if not vtuple(v.get("result")):
        raise RuntimeError("the Apollo didn't report a version")
    _upd.update(latest=str(v["result"]).lstrip("v"), checked=time.time())
    return _upd["latest"]


def update_progress(token):
    """0 = no update running, 10..100 while it runs, below 0 = it failed."""
    d = apollo("query { Mcu { updateProgress { result { value } error { message } } } }", token=token, timeout=10)
    r = d["Mcu"]["updateProgress"]
    if r.get("error"):
        raise RuntimeError(r["error"].get("message") or "progress unavailable")
    try:
        return int((r.get("result") or {}).get("value") or 0)
    except (TypeError, ValueError):
        return 0


def newer(a, b):
    ta, tb = vtuple(a), vtuple(b)
    return bool(ta and tb and ta > tb)


def update_run():
    return read_json(UPDATE_FILE, {}).get("run")


def updating():
    r = update_run()
    return bool(r and time.time() - r.get("t", 0) < UPDATE_WINDOW)


def start_update(token):
    with LOCK:
        if updating():
            raise ValueError("An update is already running.")
        inst = installed_version()
        latest = latest_version(token, force=True)
        if inst and not newer(latest, inst):
            raise ValueError("Already up to date (v%s)." % inst)
        try:
            if update_progress(token) > 0:
                raise ValueError("An update is already running (started from the Apollo dashboard?).")
        except RuntimeError:
            pass
        q = "{ Mcu { update { error { message } } } }"
        use_mutation = api_features().get("mcuMutation", True)
        try:
            d = apollo(("mutation " if use_mutation else "query ") + q, token=token, timeout=60)
        except RuntimeError as e:
            # only a request the API refused to read (so nothing ran) is retried in the older form
            if not (use_mutation and re.search(r'Cannot query field|not configured for mutations', str(e))):
                raise
            d = apollo("query " + q, token=token, timeout=60)
        err = d["Mcu"]["update"]["error"]
        if err:
            raise RuntimeError(err.get("message") or "the Apollo didn't start the update")
        data = read_json(UPDATE_FILE, {})
        data["run"] = {"t": time.time(), "from": inst, "to": latest}
        write_json(UPDATE_FILE, data, private=True)
    quiet("miner", UPDATE_WINDOW / 60)
    quiet("node", UPDATE_WINDOW / 60)
    msg = "Apollo software update started" + (" (v%s to v%s)" % (inst, latest) if inst else " (to v%s)" % latest)
    add_activity("update", True, msg, source="app")
    log(msg)
    return msg


def finish_update(ok, message):
    with LOCK:
        data = read_json(UPDATE_FILE, {})
        if not data.pop("run", None):
            return                          # already reported

        write_json(UPDATE_FILE, data, private=True)
    _upd["checked"] = 0
    add_activity("update", ok, message, source="houston")
    log(message)
    s = get_settings()
    if s["alerts"]["enabled"] and s["alerts"].get("update", True) and alert_channels(s):
        try:
            notify("Apollo software updated" if ok else "Apollo software update didn't finish", message,
                   "white_check_mark" if ok else "warning", "default" if ok else "high", s, tag="update")
        except Exception as e:
            log("update note not sent: %s" % e)


_UPD_LOCK = threading.Lock()


def update_watch(token=None):
    """Follows an update Houston started (through the reboot), and now and then looks for a new version."""
    with _UPD_LOCK:
        _update_watch(token or stored_token())


def _update_watch(token):
    data = read_json(UPDATE_FILE, {})
    run = data.get("run")
    if run:
        try:
            p = update_progress(token)
        except Exception:
            p = None                        # the API is down: rebuilding or rebooting
        inst = installed_version()
        if p is None or p > 0:
            if not run.get("seen"):
                run["seen"] = True
                with LOCK:
                    d2 = read_json(UPDATE_FILE, {})
                    if d2.get("run"):
                        d2["run"]["seen"] = True
                        write_json(UPDATE_FILE, d2, private=True)
        if p is not None and p < 0:
            finish_update(False, "The Apollo software update failed. The System log (Houston › Activity › Logs) may say why; you can try again.")
        elif p == 0 and (run.get("seen") or newer(inst, run.get("from"))) and time.time() - run.get("t", 0) > 20:
            finish_update(True, "Apollo software updated to v%s" % inst if newer(inst, run.get("from"))
                          else "Apollo software update finished" + (" (v%s)" % inst if inst else ""))
        elif time.time() - run.get("t", 0) > UPDATE_WINDOW:
            finish_update(False, "The Apollo software update hasn't finished after %d minutes. Check the Apollo dashboard."
                          % (UPDATE_WINDOW // 60))
        return
    if not token or time.time() - data.get("checked", 0) < UPDATE_EVERY:
        return
    latest = latest_version(token, force=True)
    data["checked"] = time.time()
    inst = installed_version()
    s = get_settings()
    if newer(latest, inst) and data.get("notified") != latest:
        data["notified"] = latest
        if s["alerts"]["enabled"] and s["alerts"].get("update", True) and alert_channels(s):
            title = "Apollo software v%s is available" % latest
            try:
                notify(title, "You have v%s. Update from Houston: Settings › Your Apollo." % inst, "arrow_up", "low", s, tag="update")
                add_activity("alert", True, title, source="alert")
            except Exception as e:
                log("update note not sent: %s" % e)
    with LOCK:
        cur = read_json(UPDATE_FILE, {})
        cur.update({"checked": data["checked"], "notified": data.get("notified")})
        write_json(UPDATE_FILE, cur, private=True)


def update_loop():
    time.sleep(20)
    while True:
        try:
            update_watch()
        except Exception as e:
            log("update check: %s" % e)
        time.sleep(15 if update_run() else 60)


def update_view(token, check=False):
    if update_run():
        try:
            update_watch(token)             # notice a finished update right away
        except Exception as e:
            log("update check: %s" % e)
    out = {"installed": installed_version(), "latest": None, "available": False, "running": updating(),
           "progress": None, "run": update_run(), "error": None}
    try:
        out["latest"] = latest_version(token, force=check)
    except Exception as e:
        out["error"] = "Couldn't check for updates: %s" % str(e)[:150]
    out["available"] = newer(out["latest"], out["installed"])
    try:
        out["progress"] = update_progress(token)
    except Exception:
        out["progress"] = None              # the API isn't answering (expected while it rebuilds and reboots)
    if out["progress"] and out["progress"] > 0:
        out["running"] = True
    return out



def automation_ok(key):
    """True if `key` matches the automation key. Slows down and locks out repeated wrong keys."""
    import hmac
    real = get_settings()["automation"].get("key")
    now = time.time()
    _auto_fail[:] = [t for t in _auto_fail if now - t < 600]
    if len(_auto_fail) >= 20:
        return False
    if real and key and hmac.compare_digest(real.encode(), key.encode()):
        return True
    _auto_fail.append(now)
    time.sleep(1)
    return False


_login_fail = {}       # client address -> [times of failed sign-ins]
LOGIN_RE = re.compile(r"Auth\s*\{\s*login\b")


def login_blocked(ip):
    now = time.time()
    lst = [t for t in _login_fail.get(ip, []) if now - t < 900]
    _login_fail[ip] = lst
    return len(lst) >= 10                     # 10 wrong passwords in 15 minutes: wait


def login_failed(ip):
    _login_fail.setdefault(ip, []).append(time.time())
    if len(_login_fail) > 1000:              # don't grow without bound
        _login_fail.pop(next(iter(_login_fail)))


AUTO_ACTIONS = {"start", "stop", "whisper", "eco", "balanced", "turbo", "super_eco", "node_start", "node_stop"}


def automation_action(action):
    """Check the action, start it in the background (start/stop take about a minute) and return what to say."""
    a = action.lower().replace("-", "_")
    m = re.match(r"^custom_?(\d{1,2})$", a)
    if m:
        a = "custom:%s" % m.group(1)
    elif a not in AUTO_ACTIONS:
        raise ValueError("Unknown action '%s'" % action)
    token = stored_token()
    if not token:
        raise RuntimeError("Houston isn't signed in yet. Open Houston once and sign in.")
    if a.startswith("custom:") and not 5 <= int(a[7:]) <= 20:
        raise ValueError("Custom target must be 5 to 20 TH/s")
    iii = chassis() == "apollo-iii"
    if a == "whisper" and iii:
        raise ValueError("Whisper is for the Apollo II. On the Apollo III use super_eco or custom-5.")
    if (a == "super_eco" or a.startswith("custom:")) and not iii:
        raise ValueError("%s needs an Apollo III. Try whisper for the quietest mode." % label(a))

    def work():
        try:
            msg = run_action(a, token)
            add_activity(a, True, msg, source="shortcut")
        except Exception as e:
            add_activity(a, False, str(e), source="shortcut")
    threading.Thread(target=work, daemon=True).start()
    say = {"start": "Starting the miner. It takes about a minute.", "stop": "Stopping the miner.",
           "node_start": "Starting the Bitcoin node.", "node_stop": "Stopping the Bitcoin node."}
    return say.get(a, "Switching to %s." % label(a))


def alerts_since(since, limit=20):
    """Alerts Houston sent (and update results) after `since` (epoch seconds), oldest first."""
    out = []
    for it in read_json(ACTIVITY_FILE, []):
        if it.get("source") not in ("alert", "houston"):
            continue
        try:
            t = dt.datetime.fromisoformat(it.get("time")).timestamp()
        except (TypeError, ValueError):
            continue
        if t <= since:
            continue
        title = it.get("message") or ""
        if it.get("action") == "update":
            title, body = ("Apollo software updated" if it.get("ok") else "Apollo software update didn't finish"), title
        else:
            body = ""
        out.append({"t": int(t), "title": title[:200], "message": body[:400], "ok": bool(it.get("ok")), "kind": it.get("action")})
    return sorted(out, key=lambda a: a["t"])[-limit:]


def status_sentence():
    st = get_settings()
    x = glance_local()
    if not x.get("status"):
        return "Houston is still starting up. Try again in a minute."
    if x["status"] == "unreachable":
        return "Houston can't reach the Apollo's software right now."
    parts = []
    mode = _last.get("m")
    if x["status"] == "online":
        parts.append("Your Apollo is mining at %.2f terahash%s." % ((x.get("ghs") or 0) / 1000,
                                                                   " in %s mode" % label(mode) if mode else ""))
        if x.get("tempC"):
            parts.append("Hashboard temperature %s." % fmt_temp(x["tempC"], st["units"]).replace("°F", " degrees Fahrenheit").replace("°C", " degrees Celsius"))
        if x.get("watts"):
            parts.append("Using %d watts." % round(x["watts"]))
    else:
        parts.append("Your Apollo's miner is %s." % ("stopped" if x["status"] == "offline" else x["status"]))
    if x.get("node") and x["node"] != "unknown":
        parts.append("The Bitcoin node is %s." % ("running" if x["node"] == "online" else "stopped" if x["node"] == "offline" else x["node"]))
    p = price_view()
    if p.get("price"):
        ch = p.get("change24")
        parts.append("Bitcoin is at %s %s%s." % (format(round(p["price"]), ","), p["fiat"],
                                                 "" if ch is None else ", %s %.1f percent today" % ("up" if ch >= 0 else "down", abs(ch))))
    return " ".join(parts)


# --------------------------------------------------------------------------- HTTP
HOST_RE = re.compile(r"^(\[[0-9a-fA-F:.]+\]|[0-9.]+|[A-Za-z0-9-]+|[A-Za-z0-9.-]+\.(ts\.net|local|lan|home|home\.arpa|internal|localdomain))(:\d+)?$")
EXTRA_HOSTS = {h.strip().lower() for h in os.environ.get("HOUSTON_ALLOWED_HOSTS", "").split(",") if h.strip()}


def host_allowed(host):
    """Blocks DNS-rebinding: only IP addresses, plain device names (apollo), Tailscale and home-network
    names are accepted. Add others with HOUSTON_ALLOWED_HOSTS=name1,name2."""
    host = (host or "").strip()
    if HOST_RE.match(host):
        return True
    return host.lower().rsplit(":", 1)[0] in EXTRA_HOSTS


ACTION_RE = re.compile(r"Miner\s*\{\s*(start|stop|restart)\b")
NODE_RE = re.compile(r"Node\s*\{\s*(start|stop)\b")
MODE_RE = re.compile(r"Settings\s*\{\s*update\b")


def has_error(node):
    if isinstance(node, dict):
        return any((k == "error" and v) or has_error(v) for k, v in node.items())
    if isinstance(node, list):
        return any(has_error(v) for v in node)
    return False


def note_app_action(body, response):
    """Add miner actions made from the app to the activity log (not reads)."""
    try:
        req = json.loads(body.decode() or "{}")
        q = req.get("query") or ""
        res = json.loads(response.decode() or "{}")
    except (ValueError, AttributeError):
        return
    if res.get("errors") or has_error(res.get("data")):
        return
    n = NODE_RE.search(q)
    if n:
        a = "node_" + n.group(1)
        note_intent(a)
        add_activity(a, True, "Bitcoin node started" if a == "node_start" else "Bitcoin node stopped", source="app")
        return
    m = ACTION_RE.search(q)
    if m:
        a = m.group(1)
        if a == "restart":  # the restart that applies a mode change made a moment ago is part of that change
            last = (read_json(ACTIVITY_FILE, []) or [{}])[0]
            try:
                age = (dt.datetime.now().astimezone() - dt.datetime.fromisoformat(last.get("time"))).total_seconds()
            except (TypeError, ValueError):
                age = 1e9
            if last.get("source") == "app" and last.get("action") not in ("start", "stop", "restart", "schedule") and age < 300:
                note_intent("restart")
                return
        note_intent(a)
        add_activity(a, True, {"start": "Miner started", "stop": "Miner stopped", "restart": "Miner restarted"}[a],
                     source="app")
        return
    if MODE_RE.search(q):
        v = req.get("variables") or {}
        if isinstance(v.get("led"), bool):            # the front status light (powerLedOff)
            add_activity("light", True, "Front status light turned " + ("off" if v["led"] else "on"), source="app")
            return
        mode = v.get("m") or v.get("mode") or v.get("minerMode")
        if mode == "custom" and v.get("h"):
            mode = "custom:%s" % v["h"]
        elif mode == "custom" and is_whisper({"minerMode": "custom", "voltage": v.get("v"), "frequency": v.get("f")}):
            mode = "whisper"
        if isinstance(mode, str):
            note_intent(mode)
            add_activity(mode, True, "Mode set to %s" % label(mode), source="app")


class Handler(BaseHTTPRequestHandler):
    server_version = "Houston/" + VERSION
    sys_version = ""
    timeout = 30                      # drop connections that stall

    def log_message(self, fmt, *args):  # quieter log: only errors and API writes
        pass

    def _send(self, code, body, ctype="application/json", extra=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()")
        if ctype.startswith("text/html"):
            self.send_header("Content-Security-Policy",
                             "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
                             "img-src 'self' data:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; "
                             "base-uri 'none'; form-action 'self'")
        self.send_header("Cache-Control", "max-age=86400" if ctype.startswith(("image/", "font/")) else "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n < 0 or n > MAX_BODY:
            raise ValueError("request too large")
        return self.rfile.read(n) if n else b""

    def _token(self):
        a = self.headers.get("Authorization", "")
        return a[7:].strip() if a.startswith("Bearer ") else ""

    def _require_auth(self):
        try:
            if token_ok(self._token()):
                return True
            self._send(401, {"error": "Please sign in again.", "code": "UNAUTHENTICATED"})
        except Exception:
            self._send(502, {"error": "Can't reach the Apollo API right now."})
        return False

    def _host_ok(self):
        if host_allowed(self.headers.get("Host")):
            return True
        self._send(421, {"error": "Unknown host name. Use the Apollo's address, or add the name to "
                                  "HOUSTON_ALLOWED_HOSTS."})
        return False

    def do_HEAD(self):
        self.do_GET()

    def _json_body(self):
        return json.loads(self._body().decode() or "{}")

    def _query(self):
        from urllib.parse import parse_qs, urlsplit
        return {k: v[-1] for k, v in parse_qs(urlsplit(self.path).query).items()}

    def _automation_key(self):
        return self.headers.get("X-Houston-Key") or self._token()

    def do_GET(self):
        if not self._host_ok():
            return
        path = self.path.split("?")[0]
        if path in STATIC:
            f = os.path.realpath(os.path.join(WEB_DIR, STATIC[path]))
            if not f.startswith(WEB_DIR + os.sep) or not os.path.isfile(f):
                return self._send(404, {"error": "not found"})
            with open(f, "rb") as fh:
                body = fh.read()
            if f.endswith((".html", ".json", ".js")):
                # versioned asset links, so browsers fetch new icons and fonts after an update
                body = body.replace(b"__HOUSTON_V__", VERSION.encode())
            return self._send(200, body, TYPES.get(os.path.splitext(f)[1], "application/octet-stream"))
        if path == "/api/device":
            now = dt.datetime.now().astimezone()
            return self._send(200, {"chassis": chassis(), "version": VERSION, "time": now.isoformat(timespec="seconds"),
                                    "tz": os.environ.get("TZ") or now.tzname(), "abbr": now.tzname(),
                                    "offset": now.strftime("%z"), "features": api_features()})
        if path == "/api/glance":            # for other Houstons on your network (no sign-in, read-only)
            return self._send(200, glance_local())
        if path == "/api/market":            # cached network / market / news data (public, no sign-in)
            return self._send(200, market_view())
        if path == "/api/price":             # cached bitcoin price (public market data, no sign-in)
            q = self._query()
            _price_seen[0] = time.time()     # someone is looking: refresh every few seconds
            return self._send(200, price_view(q.get("range", "1D"), q.get("points") != "0"))
        if path == "/api/v1/alerts":         # for the Android app's notifications (shortcut key)
            if not automation_ok(self._automation_key()):
                return self._send(401, {"error": "Wrong or missing Houston key."})
            try:
                since = float(self._query().get("since") or 0)
            except ValueError:
                since = 0
            return self._send(200, {"now": int(time.time()), "alerts": alerts_since(since)})
        if path in ("/api/v1/status", "/api/v1/say"):
            if not automation_ok(self._automation_key()):
                return self._send(401, "Wrong or missing Houston key.", "text/plain; charset=utf-8")
            if path == "/api/v1/say":
                return self._send(200, status_sentence(), "text/plain; charset=utf-8")
            g = glance_local()
            g["mode"] = _last.get("m")
            pv = price_view()
            g["btc"] = {k: pv.get(k) for k in ("price", "fiat", "change24")} if pv.get("price") else None
            g["text"] = status_sentence()
            return self._send(200, g)
        if path not in ("/api/schedule", "/api/activity", "/api/settings", "/api/history", "/api/fleet", "/api/automation",
                        "/api/push", "/api/apollo-update", "/api/houston-log", "/api/economics"):
            return self._send(404, {"error": "not found"})
        if not self._require_auth():
            return
        if path == "/api/schedule":
            with LOCK:
                sch = read_json(SCHEDULE_FILE, default_schedule())
            return self._send(200, {"schedule": sch, "upcoming": upcoming(sch), "now": expected_now(sch),
                                    "authorized": bool(stored_token())})
        if path == "/api/activity":
            return self._send(200, read_json(ACTIVITY_FILE, []))
        if path == "/api/settings":
            return self._send(200, {"settings": public_settings(get_settings()), "authorized": bool(stored_token())})
        if path == "/api/history":
            rng = self._query().get("range", "24h")
            return self._send(200, history_view("7d" if rng == "7d" else "24h"))
        if path == "/api/fleet":
            return self._send(200, {"self": glance_local(), "apollos": fleet()})
        if path == "/api/automation":
            return self._send(200, {"key": get_settings()["automation"].get("key")})
        if path == "/api/push":
            return self._send(200, push_view())
        if path == "/api/apollo-update":
            return self._send(200, update_view(self._token(), self._query().get("check") == "1"))
        if path == "/api/economics":
            if self._query().get("refresh") == "1":
                refresh_econ(True)
            return self._send(200, econ_view())
        if path == "/api/houston-log":
            return self._send(200, {"content": "\n".join(_LOG_RING), "timestamp": dt.datetime.now().astimezone().isoformat(timespec="seconds")})
        return self._send(404, {"error": "not found"})

    def do_PUT(self):
        if not self._host_ok():
            return
        path = self.path.split("?")[0]
        if path not in ("/api/schedule", "/api/settings", "/api/auth"):
            return self._send(404, {"error": "not found"})
        if not self._require_auth():
            return
        if path == "/api/auth":
            # keep this (non-expiring) Apollo sign-in for the schedule, history, alerts and shortcuts
            with LOCK:
                save_token(self._token())
            return self._send(200, {"authorized": True})
        if path == "/api/settings":
            try:
                with LOCK:
                    old_price, old_market = get_settings()["price"], get_settings()["market"]
                    old_econ_loc = get_settings()["econ"]["heat"].get("location")
                    new = validate_settings(self._json_body(), get_settings())
                    write_json(SETTINGS_FILE, new, private=True)
                    save_token(self._token())
                if new["price"] != old_price:
                    threading.Thread(target=refresh_price, args=(True,), daemon=True).start()
                if new["econ"]["heat"].get("location") != old_econ_loc:
                    threading.Thread(target=refresh_econ, args=(True,), daemon=True).start()
                if new["market"] != old_market or new["price"].get("fiat") != old_price.get("fiat"):
                    threading.Thread(target=refresh_market, args=(True,), daemon=True).start()
            except (ValueError, UnicodeDecodeError) as e:
                return self._send(400, {"error": str(e)})
            return self._send(200, {"settings": public_settings(new), "authorized": True})
        try:
            clean = validate(self._json_body())
        except (ValueError, UnicodeDecodeError) as e:
            return self._send(400, {"error": str(e)})
        except Exception:
            return self._send(502, {"error": "Can't check the schedule right now."})
        with LOCK:
            apply_tz(clean.get("tz"))
            clean["updated"] = dt.datetime.now().isoformat(timespec="seconds")
            write_json(SCHEDULE_FILE, clean)
            save_token(self._token())
        n = len(clean["windows"])
        add_activity("schedule", True, ("Schedule saved: %d window%s" % (n, "" if n == 1 else "s")) if clean["enabled"] and n
                     else "Schedule turned off", source="app")
        log("schedule saved (%d windows, enabled=%s)" % (n, clean["enabled"]))
        return self._send(200, {"schedule": clean, "upcoming": upcoming(clean), "now": expected_now(clean),
                                "authorized": True})

    def do_DELETE(self):
        if not self._host_ok():
            return
        path = self.path.split("?")[0]
        if path not in ("/api/automation", "/api/push"):
            return self._send(404, {"error": "not found"})
        if not self._require_auth():
            return
        if path == "/api/push":
            dev = self._query().get("id", "")
            name = next((x["name"] for x in push_devices() if x["id"] == dev), None)
            if push_remove(dev):
                add_activity("alert", True, "Notifications turned off on %s" % name, source="app")
            return self._send(200, push_view())
        with LOCK:
            st = get_settings()
            st["automation"]["key"] = None
            write_json(SETTINGS_FILE, st, private=True)
        add_activity("automation", True, "Shortcut key turned off", source="app")
        return self._send(200, {"key": None})

    def do_POST(self):
        if not self._host_ok():
            return
        path = self.path.split("?")[0]
        if path.startswith("/api/v1/action/"):
            if not automation_ok(self._automation_key()):
                return self._send(401, "Wrong or missing Houston key.", "text/plain; charset=utf-8")
            try:
                return self._send(200, automation_action(path[len("/api/v1/action/"):]), "text/plain; charset=utf-8")
            except (ValueError, RuntimeError) as e:
                return self._send(400, str(e), "text/plain; charset=utf-8")
        if path in ("/api/alerts/test", "/api/discover", "/api/automation", "/api/push", "/api/apollo-update"):
            if not self._require_auth():
                return
            if path == "/api/apollo-update":
                try:
                    with LOCK:
                        save_token(self._token())
                    msg = start_update(self._token())
                except ValueError as e:
                    return self._send(409, {"error": str(e)})
                except Exception as e:
                    return self._send(502, {"error": "The Apollo didn't start the update: %s" % str(e)[:200]})
                return self._send(200, {"ok": True, "message": msg, "update": update_view(self._token())})
            if path == "/api/push":
                try:
                    b = self._json_body()
                    dev = push_subscribe(b.get("subscription"), b.get("name"))
                    with LOCK:
                        st = get_settings()
                        if not st["alerts"]["enabled"]:          # turning on a device means "send me alerts"
                            st["alerts"]["enabled"] = True
                            write_json(SETTINGS_FILE, st, private=True)
                        save_token(self._token())
                except (ValueError, UnicodeDecodeError, AttributeError) as e:
                    return self._send(400, {"error": str(e)})
                name = next((x["name"] for x in push_devices() if x["id"] == dev), "a device")
                add_activity("alert", True, "Notifications turned on for %s" % name, source="app")
                out = push_view()
                out["id"] = dev
                return self._send(200, out)
            if path == "/api/alerts/test":
                try:
                    b = self._json_body() if self.headers.get("Content-Length") not in (None, "0") else {}
                    title, msg = "Houston test", "Alerts from your Apollo will look like this."
                    if b.get("device"):
                        sent, failed = push_send(title, msg, "test", only=str(b["device"]))
                        if not sent:
                            raise RuntimeError("this device didn't accept it; turn notifications off and on again")
                        return self._send(200, {"ok": True, "sent": sent})
                    sent, warnings = notify(title, msg, "rocket", "default", get_settings(), tag="test")
                    return self._send(200, {"ok": True, "sent": sent, "warnings": warnings})
                except Exception as e:
                    return self._send(400, {"error": "Couldn't send: %s" % e})
            if path == "/api/discover":
                return self._send(200, {"found": discover()})
            import secrets
            with LOCK:
                st = get_settings()
                st["automation"]["key"] = "hk_" + secrets.token_urlsafe(24)
                write_json(SETTINGS_FILE, st, private=True)
                save_token(self._token())
            add_activity("automation", True, "New shortcut key created", source="app")
            return self._send(200, {"key": st["automation"]["key"]})
        if path != "/api/graphql":
            return self._send(404, {"error": "not found"})
        # JSON only: a web page on another site can't send that without the browser asking first
        if not (self.headers.get("Content-Type") or "").lower().startswith("application/json"):
            return self._send(415, {"errors": [{"message": "Content-Type must be application/json"}]})
        # Forward to the Apollo's own API (same request, same sign-in)
        try:
            body = self._body()
            is_login = bool(LOGIN_RE.search(body.decode("utf-8", "replace")))
            ip = self.client_address[0]
            if is_login and login_blocked(ip):
                return self._send(429, {"errors": [{"message": "Too many wrong passwords. Wait 15 minutes and try again."}]})
            req = urllib.request.Request(API, data=body, method="POST", headers={"Content-Type": "application/json"})
            if self.headers.get("Authorization"):
                req.add_header("Authorization", self.headers["Authorization"])
            with urllib.request.urlopen(req, timeout=200) as r:
                out = r.read()
                status = r.status
            if status == 200:
                note_app_action(body, out)
            if is_login and (b'"accessToken"' not in out or b'"accessToken":null' in out.replace(b" ", b"")):
                login_failed(ip)
                time.sleep(1)
            return self._send(status, out)
        except urllib.error.HTTPError as e:
            return self._send(e.code, e.read() or b"{}")
        except ValueError as e:
            return self._send(413, {"error": str(e)})
        except Exception:
            return self._send(502, {"errors": [{"message": "Can't reach the Apollo API. Is the Apollo software running?"}]})


def main():
    import signal
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    try:
        os.chmod(STATE_DIR, 0o700)
    except OSError:
        pass
    apply_tz(read_json(SCHEDULE_FILE, {}).get("tz"))
    threading.Thread(target=scheduler_loop, daemon=True).start()
    if SAMPLE_EVERY > 0:
        threading.Thread(target=sampler_loop, daemon=True).start()
    if PRICE_EVERY > 0:
        threading.Thread(target=price_loop, daemon=True).start()
    if MARKET_EVERY > 0:
        threading.Thread(target=market_loop, daemon=True).start()
    if UPDATE_EVERY > 0:
        threading.Thread(target=update_loop, daemon=True).start()
    if ECON_EVERY > 0:
        threading.Thread(target=econ_loop, daemon=True).start()

    def stop(*_):
        save_history()          # keep the charts across restarts
        os._exit(0)
    signal.signal(signal.SIGTERM, stop)
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    log("Houston %s on port %d (web: %s, state: %s)" % (VERSION, PORT, WEB_DIR, STATE_DIR))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        save_history()


if __name__ == "__main__":
    sys.exit(main())
