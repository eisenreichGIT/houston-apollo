# How it works (API notes)

Apollo Web OS v2 has two parts on the Apollo:

| Port | Service | What it is |
|---|---|---|
| 80 / 3000 | `apollo-ui-v2` | The dashboard (Next.js) |
| 5000 | `apollo-api` | GraphQL API the dashboard talks to: `http://<APOLLO-IP>:5000/api/graphql` |

Houston (on the Apollo) and the desktop scripts talk to the API on port 5000. Source for the API and UI: [jstefanop/apolloapi-v2](https://github.com/jstefanop/apolloapi-v2) and [jstefanop/apolloui-v2](https://github.com/jstefanop/apolloui-v2).

Almost all operations, including "actions" like miner start and stop, are GraphQL **queries** sent as `POST` with JSON `{"query": "...", "variables": {...}}`. (Apollo software 2.1.4 started moving actions to mutations, beginning with the node; see below.)

## 1. Log in

```graphql
query ($p: String!) {
  Auth { login(input: { password: $p }) { result { accessToken } error { message } } }
}
```

Returns a JWT. Send it on later requests as `Authorization: Bearer <token>`. The token is signed with a random per-device secret (`APP_SECRET` in `/opt/apolloapi/.env`) and **has no expiry**.

## 2. Start / stop / restart

```graphql
query { Miner { start   { error { message } } } }
query { Miner { stop    { error { message } } } }
query { Miner { restart { error { message } } } }
```

These run `sudo systemctl start|stop|restart apollo-miner` on the Apollo and reply when that finishes. **Start and restart take about 40 seconds or more**, because the miner's start script resets the hashboard and then sleeps 35 seconds. Use a client timeout of at least 2-3 minutes.

## 3. Status

```graphql
query { Miner { online { result { online { status } } } } }        # online | offline | pending
query { Miner { stats { result { stats {
  master { boardsW intervals { int_30 { bySol } } }                  # watts, GH/s (30 s average)
  slots { int_0 { temperature } }                                    # °C
} } } } }
```

`stats` returns one entry per hashboard; sum `bySol` (GH/s) and `boardsW` across boards.

## 4. Mining mode (eco / balanced / turbo)

The mode is a setting. The dashboard saves all settings, then restarts the miner so it picks up the new config:

```graphql
query { Settings { read { result { settings { minerMode nodeSoftware } } } } }

query ($m: MinerMode!, $n: NodeSoftware) {
  Settings { update(input: { minerMode: $m, nodeSoftware: $n }) { result { settings { minerMode } } error { message } } }
}

query { Miner { restart { error { message } } } }    # only if the miner is running
```

> **Gotcha: always send `nodeSoftware` back.** In Apollo Web OS up to v2.1.2, `Settings.update` compares the stored node software with `input.nodeSoftware`. If you leave it out, `undefined` never equals the stored value, so the API decides the Bitcoin node software is changing and **stops and restarts your Bitcoin node** on every update. Read the current value first and send it back unchanged (it may be `null`, which is fine). FutureBit fixed this in 2.1.3; sending it back is harmless there.

`Settings.update` regenerates `/opt/apolloapi/backend/apollo-miner/mode` and `miner_config`. The miner reads them when it starts, so the new mode applies only after a restart. That's why these tools restart a running miner and leave a stopped one alone.

## Apollo III

Apollo OS 2.1.3+ adds `super_eco` to the `MinerMode` enum and three settings: `minerHashrate` (custom mode target, whole TH/s, 5-20), `fanTemp` and `fanPwm`. A hashrate target is:

```graphql
query ($m: MinerMode!, $n: NodeSoftware, $h: Int) {
  Settings { update(input: { minerMode: $m, nodeSoftware: $n, minerHashrate: $h }) { error { message } } }
}
# variables: {"m": "custom", "n": <current nodeSoftware>, "h": 14}
```

Older software rejects `super_eco` and the new fields, and even *querying* `minerHashrate` there is an error, so only ask for it on an Apollo III.

**Which model?** The dashboard (port 80, or 3000 from the Apollo itself) answers `GET /api/config` with `{"chassis": "apollo-iii", ...}` on an Apollo III, from the board name in `/etc/armbian-release` (`BOARD_NAME="Apollo 3"`). Anything else means Apollo I/II. Start/stop is identical on both: the same `apollo-miner` service starts the III's own miner binary, and its stats come back through `Miner.stats` in the same format (with `version: "v3"`).

## Bitcoin node

```graphql
query { Node { online { result { online { status } } } } }          # online | offline | pending
query { Node { stats { result { stats {
  connectionCount blockchainInfo { blocks headers blockTime sizeOnDisk verificationprogress }
  miningInfo { difficulty networkhashps } networkInfo { subversion connections_in connections_out }
} } } } }
query { Node { recentBlocks(count: 10) { result { blocks { height timestamp extras { reward pool { name } } } } } } }

mutation { Node { start { error { message } } } }      # Apollo software 2.1.4+
query    { Node { start { error { message } } } }      # before 2.1.4 (still accepted as a deprecated alias)
```

Start/stop run `sudo systemctl start|stop node`. Software 2.1.4 also reports whether there's a drive for the blockchain (`Node { storage { result { state available } } }`; some Apollo III ship without one). Houston checks once which form the Apollo understands (by asking the API to validate a tiny request) and uses that. It never calls `Node.format`, the dashboard's wipe-the-drive action.

## Other readings Houston uses

- **Miner:** `Miner.stats` also has `master.upTime`, `pool { host intervals { int_0 { sharesAccepted sharesRejected } } }`, `fans { int_0 { rpm } }` and, when you mine to the Apollo's solo pool, `ckpool { pool { hashrate1hr bestshare accepted rejected } users { bestever } blockFound }`. These need no sign-in.
- **System:** `Mcu.stats` (sign-in needed): `temperature` (millidegrees C), `cpu.usedPercent`, `memory` and `disks` (KiB), `uptime` (boot time), `hostname`, `operatingSystem`.
- **Solo odds:** chance of a block per day = hashrate (H/s) × 86,400 / (difficulty × 2³²).

## Houston's own API (port 8088)

| Endpoint | Sign-in | What |
|---|---|---|
| `POST /api/graphql` | the Apollo's | forwarded to the Apollo API unchanged (JSON only), so the app needs a single address |
| `GET /api/device` | none | model, Houston version, the schedule's time zone, API features |
| `GET /api/price?range=24h\|7d` | none | cached bitcoin price, 24 h change, low/high and history (from Kraken's public `Ticker` and 15-minute `OHLC`, or Coinbase Exchange `ticker`/`candles`) |
| `GET /api/glance` | none | short read-only status, for other Houstons (the same readings the Apollo API shares without sign-in) |
| `GET/PUT /api/schedule` | Apollo token | the schedule (validated), upcoming changes, what it expects right now |
| `GET/PUT /api/settings`, `PUT /api/auth` | Apollo token | units, electricity price, alerts, other Apollos; keep a sign-in for background work |
| `GET /api/history?range=24h\|7d`, `GET /api/activity`, `GET /api/fleet`, `POST /api/discover`, `POST /api/alerts/test` | Apollo token | charts and energy, activity, other Apollos, network search, test alert |
| `POST/GET/DELETE /api/automation` | Apollo token | create, show or turn off the shortcut key |
| `GET /api/v1/say`, `GET /api/v1/status`, `POST /api/v1/action/<action>` | shortcut key | for Siri, Android shortcuts, Home Assistant: see [voice-assistants.md](voice-assistants.md) |

Requests with an unknown `Host` header are refused (protection against DNS rebinding): IP addresses, single-word names like `apollo`, and `*.ts.net`, `*.local`, `*.lan`, `*.home.arpa` names are accepted; add others with `HOUSTON_ALLOWED_HOSTS` in the service.

## curl example

```bash
API=http://192.168.1.50:5000/api/graphql
TOKEN=$(curl -s $API -H 'Content-Type: application/json' \
  -d '{"query":"query($p:String!){Auth{login(input:{password:$p}){result{accessToken}}}}","variables":{"p":"YOUR_PASSWORD"}}' \
  | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')

curl -s $API -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"query { Miner { online { result { online { status } } } } }"}'
```

(For real use, prefer `scripts/apollo-miner.sh`. It keeps the password and token out of your shell history and process list.)

## The Houston app

`houston/web/index.html` is a single file with no external dependencies (no CDN, no fonts, no trackers; the content security policy only allows Houston's own address). Charts are drawn as SVG in the page. The browser keeps the Apollo sign-in in `localStorage` (same key as the old Apollo Remote page, so nobody has to sign in again after upgrading).
