# Windows desktop setup

Connects this PC to your Apollo and adds the desktop shortcuts you pick:

| Shortcut | What it does |
|---|---|
| **Houston** | Opens [Houston](houston.md) in its own window (Microsoft Edge app mode). Also in the Start menu. Needs Houston on the Apollo |
| **Start Miner**, **Stop Miner**, **Miner Status** | One click; a pop-up shows the result |
| **Eco / Balanced / Turbo Mode** (+ **Super Eco** on an [Apollo III](apollo-iii.md)) | Switch the power mode |
| **Start / Stop Bitcoin Node** | Off by default; most people leave the node running |

The schedule lives in Houston on the Apollo. If you can't install Houston, setup can instead create a schedule in Windows Task Scheduler (it only runs while this PC is on).

## Requirements

- Windows 10 or 11. Nothing to install: it uses the built-in PowerShell 5.1.
- Your Apollo's address and dashboard password.
- The PC on the same network as the Apollo (or on your Tailscale network; then use the Apollo's Tailscale address).

## Install (double-click)

1. **Unblock the zip first:** right-click the downloaded zip, choose **Properties**, tick **Unblock** (bottom right), **OK**. This avoids "Windows protected your PC" warnings.
2. Unzip it somewhere permanent, for example `C:\Houston`. The shortcuts point at this folder, so don't move it afterwards (if you do, run setup again).
3. Double-click **`Setup.bat`**. The setup window walks you through four steps:
   1. **Find your Apollo**: **Search my network**, or type the address you open the dashboard at.
   2. **Sign in**: your dashboard password, checked with the Apollo before anything is saved. Setup also detects Apollo II or III.
   3. **Houston**: setup looks for Houston on the Apollo.
      - Found: shows its version with **Open Houston**. The schedule lives there, and any old Apollo tasks on this PC are removed.
      - Not found: shows the two commands that install it with **Copy commands**; run them in PowerShell, then **Check again**. Or carry on without it: the **Schedule on this PC instead** section has the classic schedule builder.

      Then tick the shortcuts you want.
   4. **Review**, then **Install**.

   Prefer plain questions in a console? Run `Setup.bat /text`. Setup also falls back to that automatically if the window can't open.

Run `Setup.bat` again any time to change the shortcuts. **`Uninstall.bat`** removes them (and any Apollo tasks), and optionally the saved address and password. It doesn't touch Houston on the Apollo.

> **Why a `.bat` and not an `.exe`?** A `.bat` file is plain text you can open in Notepad and check: it just starts the PowerShell setup window (`windows\ApolloSetup.ps1`). An unsigned `.exe` downloaded from the internet triggers SmartScreen and antivirus warnings, and you couldn't easily see what it does.

### What setup does

| | |
|---|---|
| Address | `%LOCALAPPDATA%\ApolloMiner\host.txt` |
| Password | encrypted with Windows DPAPI (only your Windows account can read it): `%LOCALAPPDATA%\ApolloMiner\password.xml`. The one-click shortcuts use it; the Houston shortcut doesn't need it |
| Scripts folder | restricted so only your account, SYSTEM and Administrators can change it |
| Shortcuts | on the desktop, each with its own icon (`windows\icons`); Houston also in the Start menu |
| Schedule | with Houston: none on this PC (old Apollo tasks removed). Without: tasks under **Task Scheduler › Apollo Miner** |

## Using the one-click shortcuts

- **Modes** save the mode and restart the miner if it's running (about a minute); a stopped miner stays stopped and uses the new mode when it starts.
- **Start Miner**: the pop-up appears after about 45–60 seconds (the Apollo resets its hashboard first). "Current status: pending" is normal.
- From PowerShell in the `windows` folder: `.\apollo-miner.ps1 -Action start|stop|restart|status|eco|balanced|turbo|node_start|node_stop` (Apollo III: also `super_eco`, and `custom -Hashrate 14`).
- Log: `%LOCALAPPDATA%\ApolloMiner\apollo-miner.log`
- Changed your dashboard password? `.\apollo-miner.ps1 -Action setpassword`

## Advanced: command-line options

From PowerShell in the `windows` folder (prefix with `powershell -ExecutionPolicy Bypass -File` if scripts are blocked):

```powershell
# Pick shortcuts without questions: houston, control, modes, node (or none)
.\Install-ApolloSchedule.ps1 -ApolloHost 192.168.1.50 -Shortcuts houston,modes

# Without Houston: schedule on this PC. Eco 24/7, Turbo on weekdays 9:30 AM - 4:30 PM
.\Install-ApolloSchedule.ps1 -BoostMode turbo -BoostStart 09:30 -BoostEnd 16:30

# Without Houston: mine only weekdays 9:30 AM - 4:30 PM (12-hour times work too)
.\Install-ApolloSchedule.ps1 -StartTime "9:30 AM" -StopTime "4:30 PM"

# Overnight, every day (the stop happens the next morning)
.\Install-ApolloSchedule.ps1 -StartTime 22:00 -StopTime 06:00 -Days "every day"

# Remove the shortcuts and any Apollo tasks
.\Install-ApolloSchedule.ps1 -Uninstall
```

A schedule given on the command line is created even when Houston is installed, so don't run both (they'd fight over the mode). Check the next run times with:

```powershell
Get-ScheduledTask -TaskPath '\Apollo Miner\' | Get-ScheduledTaskInfo | Select TaskName, NextRunTime
```

Scheduled tasks on this PC run **while you're signed in** (a locked screen is fine) and can wake the PC from sleep if **Allow wake timers** is on in Power Options.
