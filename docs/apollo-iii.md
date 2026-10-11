# Apollo III

Everything in this project works on the **Apollo III** as well as the Apollo II, and the III gets two extra controls:

| | Apollo II | Apollo III |
|---|---|---|
| Start / stop / status | ✓ | ✓ |
| Eco, Balanced, Turbo | ✓ | ✓ |
| **Super Eco** (lowest power and noise) | | ✓ |
| **Custom hashrate target**, 5-20 TH/s | | ✓ |

You don't have to choose anything: every tool asks the Apollo which model it is, the same way the dashboard does (its `/api/config` page reports `chassis: apollo-iii`). On an Apollo II, the III-only options are hidden or politely refused.

<img src="images/phone-apollo-iii.png" alt="Phone page on an Apollo III (demo data)" width="340">

*Phone page on an Apollo III (demo data).*

> **Status:** written from FutureBit's Apollo III source code (Apollo OS 2.1.3 / 2.1.4) and tested against that API, but **not yet on a real Apollo III**. If you have one, please report how it goes.

## Requirements

- Apollo OS **2.1.3 or newer** (what the Apollo III ships with). Older software has no Super Eco or hashrate target.
- Everything else is the same as the Apollo II: dashboard password, API on port 5000, SSH as `futurebit`.

## How the extra modes behave

- **Super Eco:** the III's lowest-power preset.
- **Custom target:** you pick a hashrate (whole TH/s, 5-20) and the III tunes its own voltage to hit it. Higher targets mean more power, heat and fan noise. Per FutureBit, about 12 TH/s is Eco territory and about 17-18 TH/s is Turbo.
- Like every mode change, these save the setting and **restart a running miner** (about a minute without hashing). A stopped miner stays stopped and uses the new mode when it next starts.

## Windows

`Setup.bat` detects the III and:

- adds a **Super Eco Mode** desktop shortcut (crescent-moon icon) next to Eco, Balanced and Turbo
- lets the schedule use Super Eco and hashrate targets:

```
  Apollo III modes: super eco, eco, balanced, turbo, or a hashrate target from 5 to 20 (TH/s)
  Normal mode, the rest of the time [eco]: super eco
  Faster window 1
    Faster mode (eco, balanced, turbo or 5-20 TH/s) [turbo]: 16
    Days [Mon-Fri]:
    Switch to 16 TH/s at [09:00]: 9:30
    Back to Super Eco at [17:00]: 4:30 PM
```

From PowerShell:

```powershell
.\apollo-miner.ps1 -Action super_eco
.\apollo-miner.ps1 -Action custom -Hashrate 14

# schedule without questions: Super Eco 24/7, 16 TH/s on weekdays 9:30-16:30
.\Install-ApolloSchedule.ps1 -BaseMode super_eco -BoostMode 16 -BoostStart 09:30 -BoostEnd 16:30
```

## Shell script / cron

```bash
~/apollo-miner.sh super_eco
~/apollo-miner.sh custom 14
```

```
# Super Eco 24/7, 16 TH/s on weekdays 9:30 AM - 4:30 PM
30 9  * * 1-5  $HOME/apollo-miner.sh custom 16 >> $HOME/apollo-miner.log 2>&1
30 16 * * 1-5  $HOME/apollo-miner.sh super_eco >> $HOME/apollo-miner.log 2>&1
```

## Houston

Houston detects the model itself. On an Apollo III it shows four mode buttons (Super Eco, Eco, Balanced, Turbo) plus a **Custom target** slider (5-20 TH/s), and the schedule can use Super Eco as the normal mode and any custom target in a window (e.g. *Super Eco 24/7, 16 TH/s on weekdays*). The Bitcoin node card hides itself on an Apollo III without a blockchain drive. Shortcut actions: `super_eco`, `custom-16`.

## Not included (yet)

The III also has fan controls (a target temperature, or a fixed fan speed) and a backup pool. Use the dashboard for those; these tools leave them untouched.
