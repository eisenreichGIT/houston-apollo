<#
.SYNOPSIS
  Houston desktop setup for Windows (text version). Easiest: double-click Setup.bat.

.DESCRIPTION
  - Finds your Apollo on the network (or asks for its address)
  - Saves your dashboard password, encrypted with Windows DPAPI, and tests the login
  - Locks the scripts folder so only your account (plus SYSTEM/Administrators) can edit it
  - Detects Apollo II vs Apollo III (the III adds Super Eco and custom hashrate targets)
  - Checks for Houston on the Apollo (the app + scheduler; see the houston folder)
  - Creates the desktop shortcuts you pick: the Houston app; Start, Stop, Status;
    the power modes; Start/Stop Bitcoin Node
  - Schedule: Houston runs it on the Apollo, so old Apollo tasks on this PC are removed.
    Without Houston, it can still create a weekly schedule in Windows Task Scheduler:
      * start/stop windows (the miner only runs during set hours), and/or
      * mode windows (e.g. Eco around the clock, Turbo on weekdays 9:30-16:30)

  Re-run it any time; earlier shortcuts and Apollo tasks are replaced.

.EXAMPLE
  # Guided setup (same as double-clicking Setup.bat)
  powershell -ExecutionPolicy Bypass -File .\Install-ApolloSchedule.ps1

  # Non-interactive: Eco 24/7, Turbo on weekdays 9:30 AM - 4:30 PM
  powershell -ExecutionPolicy Bypass -File .\Install-ApolloSchedule.ps1 -ApolloHost 192.168.1.50 -BoostMode turbo -BoostStart 09:30 -BoostEnd 16:30

  # Apollo III: Super Eco around the clock, 16 TH/s on weekdays 9:30 AM - 4:30 PM
  powershell -ExecutionPolicy Bypass -File .\Install-ApolloSchedule.ps1 -BaseMode super_eco -BoostMode 16 -BoostStart 09:30 -BoostEnd 16:30

  # Non-interactive: only mine Mon/Wed/Fri 10 PM - 6 AM
  powershell -ExecutionPolicy Bypass -File .\Install-ApolloSchedule.ps1 -StartTime 22:00 -StopTime 06:00 -Days Mon,Wed,Fri

  # Only some shortcuts: houston, control (start/stop/status), modes, node - or none
  powershell -ExecutionPolicy Bypass -File .\Install-ApolloSchedule.ps1 -Shortcuts houston,modes

  # Remove scheduled tasks and shortcuts (same as Uninstall.bat)
  powershell -ExecutionPolicy Bypass -File .\Install-ApolloSchedule.ps1 -Uninstall
#>
param(
  [string]$ApolloHost,                # e.g. 192.168.1.50 (found or asked for if omitted)
  [string]$StartTime,                 # start/stop window: start, e.g. 09:30 or 9:30 AM
  [string]$StopTime,                  # start/stop window: stop; "" = never stop automatically
  [string[]]$Days,                    # e.g. Mon-Fri, Mon,Wed,Fri, weekends, "every day" (default Mon-Fri)
  [string]$BoostMode,                 # mode window: faster mode (balanced, turbo; Apollo III also eco or a hashrate 5-20)
  [string]$BoostStart,                # mode window: switch to BoostMode
  [string]$BoostEnd,                  # mode window: switch back to BaseMode
  [string]$BaseMode = 'eco',          # mode outside the mode windows (eco, balanced; Apollo III also super_eco or a hashrate 5-20)
  [switch]$NoSchedule,
  [switch]$Uninstall,
  [string[]]$Shortcuts,               # houston, control, modes, node (comma list) or none; asked if omitted
  # --- used by the setup window (ApolloSetup.ps1) ---
  [string]$ScheduleFile,              # JSON schedule built in the window
  [switch]$PasswordReady,             # password already saved; just test it
  [switch]$DeleteSettings,            # with -Uninstall: also delete saved address/password
  [switch]$Yes                        # never prompt
)

$ErrorActionPreference = 'Stop'
$TaskFolder = '\Apollo Miner\'
$Script     = Join-Path $PSScriptRoot 'apollo-miner.ps1'
$DataDir    = Join-Path $env:LOCALAPPDATA 'ApolloMiner'
$HostFile   = Join-Path $DataDir 'host.txt'
$Desktop    = [Environment]::GetFolderPath('Desktop')
$StartMenu  = [Environment]::GetFolderPath('Programs')
$ShortcutDefs = @(
  # Icon = file in .\icons; Fallback = built-in Windows icon if that file is missing
  @{ Name = 'Start Miner';   Action = 'start';    Group = 'control'; Icon = 'start.ico';    Fallback = 'imageres.dll,101' },
  @{ Name = 'Stop Miner';    Action = 'stop';     Group = 'control'; Icon = 'stop.ico';     Fallback = 'imageres.dll,100' },
  @{ Name = 'Miner Status';  Action = 'status';   Group = 'control'; Icon = 'status.ico';   Fallback = 'imageres.dll,76'  },
  @{ Name = 'Super Eco Mode'; Action = 'super_eco'; Group = 'modes'; Icon = 'super_eco.ico'; Fallback = 'shell32.dll,12'; IIIOnly = $true },
  @{ Name = 'Eco Mode';      Action = 'eco';      Group = 'modes';   Icon = 'eco.ico';      Fallback = 'shell32.dll,12'   },
  @{ Name = 'Balanced Mode'; Action = 'balanced'; Group = 'modes';   Icon = 'balanced.ico'; Fallback = 'shell32.dll,12'   },
  @{ Name = 'Turbo Mode';    Action = 'turbo';    Group = 'modes';   Icon = 'turbo.ico';    Fallback = 'shell32.dll,12'   },
  @{ Name = 'Start Bitcoin Node'; Action = 'node_start'; Group = 'node'; Icon = 'node_start.ico'; Fallback = 'imageres.dll,101' },
  @{ Name = 'Stop Bitcoin Node';  Action = 'node_stop';  Group = 'node'; Icon = 'node_stop.ico';  Fallback = 'imageres.dll,100' }
)
if (-not (Test-Path $Script)) { throw "apollo-miner.ps1 must be in the same folder as this installer." }
. (Join-Path $PSScriptRoot 'ApolloCommon.ps1')

# ============================================================================
#  Helpers
# ============================================================================
function Ask([string]$prompt, [string]$default) {
  $p = if ($default) { "$prompt [$default]" } else { $prompt }
  $a = Read-Host $p
  if ($null -eq $a) { $a = '' }
  $a = $a.Trim()
  if ($a) { return $a } else { return $default }
}

function Ask-YesNo([string]$prompt, [bool]$default) {
  $d = if ($default) { 'Y/n' } else { 'y/N' }
  while ($true) {
    $a = (Read-Host "$prompt [$d]")
    if ($null -eq $a) { $a = '' }
    switch -Regex ($a.Trim().ToLower()) {
      '^$'      { return $default }
      '^y(es)?$' { return $true }
      '^no?$'   { return $false }
    }
    Write-Host '  Please answer y or n.' -ForegroundColor Yellow
  }
}

function Ask-Time([string]$prompt, [string]$default, [switch]$AllowBlank) {
  while ($true) {
    $a = Ask $prompt $default
    if ($AllowBlank -and (-not $a -or $a -match '^(never|none|no)$')) { return $null }
    if ($a) { try { return ConvertTo-Time $a } catch { } }
    Write-Host '  Use a time like 09:30, 16:30 or 4:30 PM.' -ForegroundColor Yellow
  }
}

function Ask-Days([string]$prompt) {
  while ($true) {
    $a = Ask $prompt 'Mon-Fri'
    try { $d = ConvertTo-Days @($a); if ($d.Count) { return $d } } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow; continue }
  }
}

function Ask-Mode([string]$prompt, [string]$default, [string[]]$allowed, [string]$not) {
  while ($true) {
    $a = Ask $prompt $default
    try {
      $tok = ConvertTo-ModeToken $a $isIII
      $kind = if ($tok -like 'custom:*') { 'custom' } else { $tok }
      if ($kind -notin $allowed) { throw "Choose one of: $(($allowed | ForEach-Object { if ($_ -eq 'custom') { 'a number from 5 to 20' } else { $_ -replace '_', ' ' } }) -join ', ')." }
      if ($tok -eq $not) { throw 'That is already the normal mode; pick a different one.' }
      return $tok
    } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow }
  }
}

function Remove-ApolloTasks {
  $old = @(Get-ScheduledTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue)
  $old | Unregister-ScheduledTask -Confirm:$false
  return $old.Count
}

function Remove-HoustonShortcut {
  foreach ($dir in $Desktop, $StartMenu) {
    if (-not $dir) { continue }
    foreach ($ext in '.lnk', '.url') { Remove-Item (Join-Path $dir "Houston$ext") -ErrorAction SilentlyContinue }
  }
}

# The browser that opens Houston in its own app window (no tabs or address bar): Edge is on every Windows 10/11 PC
function Find-AppBrowser {
  $bases = @([Environment]::GetEnvironmentVariable('ProgramFiles(x86)'), $env:ProgramFiles, $env:LOCALAPPDATA) | Where-Object { $_ }
  foreach ($rel in 'Microsoft\Edge\Application\msedge.exe', 'Google\Chrome\Application\chrome.exe') {
    foreach ($b in $bases) {
      $p = Join-Path $b $rel
      if (Test-Path $p) { return $p }
    }
  }
  return $null
}

# "Houston" on the desktop and in the Start menu
function New-HoustonShortcut([string]$url) {
  Remove-HoustonShortcut
  $ico = Join-Path $PSScriptRoot 'icons\houston.ico'
  $browser = Find-AppBrowser
  foreach ($dir in $Desktop, $StartMenu) {
    if (-not $dir -or -not (Test-Path $dir)) { continue }
    if ($browser) {
      $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $dir 'Houston.lnk'))
      $lnk.TargetPath  = $browser
      $lnk.Arguments   = "--app=$url"
      $lnk.Description = 'Houston - mission control for your Apollo'
      if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
      $lnk.Save()
    } else {
      $lines = @('[InternetShortcut]', "URL=$url")
      if (Test-Path $ico) { $lines += @("IconFile=$ico", 'IconIndex=0') }
      Set-Content -Path (Join-Path $dir 'Houston.url') -Value $lines -Encoding ASCII
    }
  }
}

# ============================================================================
#  Uninstall
# ============================================================================
if ($Uninstall) {
  Write-Host "`n== Uninstall Houston (this PC) =="
  [void](Remove-ApolloTasks)
  foreach ($s in $ShortcutDefs) { Remove-Item (Join-Path $Desktop "$($s.Name).lnk") -ErrorAction SilentlyContinue }
  Remove-HoustonShortcut
  Write-Host '  Scheduled tasks and desktop shortcuts removed. (Houston on the Apollo is not changed.)'
  if ((Test-Path $DataDir) -and ($DeleteSettings -or (-not $Yes -and (Ask-YesNo '  Also delete the saved Apollo address, password and log?' $false)))) {
    Remove-Item $DataDir -Recurse -Force
    Write-Host "  Deleted $DataDir"
  }
  Write-Host '  The miner itself is unchanged. You can delete this folder now.'
  exit 0
}

Write-Host ''
Write-Host '  Houston - setup for this PC' -ForegroundColor Cyan
Write-Host '  Press Enter to accept the [suggested] answer.'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

# ============================================================================
#  1. Apollo address
# ============================================================================
Write-Host "`n== Step 1 of 6: find your Apollo =="
if (-not $ApolloHost) {
  $saved = if (Test-Path $HostFile) { (Get-Content $HostFile -TotalCount 1).Trim() } else { '' }
  while (-not $ApolloHost) {
    $hint = if ($saved) { "Apollo address (Enter = $saved, or type 'search')" } else { 'Apollo address, e.g. 192.168.1.50 (Enter = search your network)' }
    $ans = (Read-Host $hint); if ($null -eq $ans) { $ans = '' }; $ans = $ans.Trim()
    if (-not $ans -and $saved) { $ApolloHost = $saved; break }
    if (-not $ans -or $ans -eq 'search') {
      Write-Host '  Searching your network (a few seconds)...'
      $found = @(Find-Apollo)
      if ($found.Count -eq 1) {
        if (Ask-YesNo "  Found an Apollo at $($found[0]). Use it?" $true) { $ApolloHost = $found[0] }
      } elseif ($found.Count -gt 1) {
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Host "    $($i + 1)) $($found[$i])" }
        $n = Ask '  Which one?' '1'
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $found.Count) { $ApolloHost = $found[[int]$n - 1] }
      } else {
        Write-Host "  No Apollo found. Type its address instead (it's the address you open the dashboard at)." -ForegroundColor Yellow
      }
      continue
    }
    $ApolloHost = $ans
  }
}
$ApolloHost = $ApolloHost.Trim() -replace '^https?://', '' -replace '[:/].*$', ''
if ($ApolloHost -notmatch '^[A-Za-z0-9.\-]+$') { throw "Invalid address '$ApolloHost'." }
Set-Content -Path $HostFile -Value $ApolloHost
Write-Host "  Using $ApolloHost"

# ============================================================================
#  2. Lock down this folder
# ============================================================================
# Folders created at the root of C:\ are writable by every local account by default.
# Scheduled tasks run these scripts as you, so restrict who can edit them.
Write-Host "`n== Step 2 of 6: secure the scripts folder =="
Unblock-File -Path (Join-Path $PSScriptRoot '*.ps1') -ErrorAction SilentlyContinue
$acl = & icacls "$PSScriptRoot" /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "  Only $env:USERNAME, SYSTEM and Administrators can modify $PSScriptRoot" }
else { Write-Warning "Couldn't tighten folder permissions (continuing): $acl" }

# ============================================================================
#  3. Password + connection test
# ============================================================================
Write-Host "`n== Step 3 of 6: dashboard password =="
Write-Host '  (the password you use to log in to the Apollo dashboard; typing is hidden)'
for ($try = 1; $try -le 3; $try++) {
  if ($PasswordReady) {
    & $Script -Action status -ApolloHost $ApolloHost
    if ($LASTEXITCODE -ne 0) { throw 'Could not log in to the Apollo with the saved password.' }
    break
  }
  & $Script -Action setpassword -ApolloHost $ApolloHost
  Write-Host '  Testing...'
  & $Script -Action status -ApolloHost $ApolloHost
  if ($LASTEXITCODE -eq 0) { break }
  if ($try -eq 3) { throw 'Could not log in to the Apollo. Check the address and password, then run setup again.' }
  Write-Host '  That did not work; try again.' -ForegroundColor Yellow
}
$isIII = (Get-ApolloModel $ApolloHost) -eq 'apollo-iii'
if ($isIII) { Write-Host '  Detected an Apollo III: Super Eco and custom hashrate targets are available.' -ForegroundColor Cyan }
else        { Write-Host '  Detected an Apollo II (modes: Eco, Balanced, Turbo).' }

# ============================================================================
#  4. Houston on the Apollo
# ============================================================================
Write-Host "`n== Step 4 of 6: Houston =="
$houston = Get-Houston $ApolloHost
$cliSchedule = $PSBoundParameters.ContainsKey('StartTime') -or $PSBoundParameters.ContainsKey('StopTime') -or
               $PSBoundParameters.ContainsKey('BoostMode') -or $PSBoundParameters.ContainsKey('BoostStart') -or
               $PSBoundParameters.ContainsKey('BoostEnd') -or $ScheduleFile
$interactiveSetup = -not ($Yes -or $cliSchedule -or $NoSchedule -or $PSBoundParameters.ContainsKey('Shortcuts'))
while (-not $houston -and $interactiveSetup) {
  Write-Host '  Houston is not installed on this Apollo yet. Houston is the app (phone and PC) and runs'
  Write-Host '  your schedule on the Apollo itself, so this PC can be off. To install it, run these two'
  Write-Host '  commands in PowerShell (the password is your dashboard password):'
  Write-Host ''
  foreach ($c in (Get-HoustonInstallCommands $ApolloHost)) { Write-Host "    $c" -ForegroundColor Yellow }
  Write-Host ''
  if (-not (Ask-YesNo '  Installed it? Check again (n = continue without Houston)' $false)) { break }
  $houston = Get-Houston $ApolloHost
}
if ($houston) { Write-Host "  Houston $($houston.Version) is running: $($houston.Url)" -ForegroundColor Green }
else { Write-Host '  Continuing without Houston.' }

# ============================================================================
#  5. Desktop shortcuts
# ============================================================================
Write-Host "`n== Step 5 of 6: desktop shortcuts =="
if ($PSBoundParameters.ContainsKey('Shortcuts')) {
  $groups = @($Shortcuts | ForEach-Object { "$_" -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLower() })
  foreach ($g in $groups) { if ($g -notin 'houston', 'control', 'modes', 'node', 'none') { throw "Unknown shortcut group '$g'. Use houston, control, modes, node or none." } }
} elseif ($interactiveSetup) {
  $groups = @()
  if ($houston -and (Ask-YesNo '  Houston app shortcut (opens Houston in its own window)?' $true)) { $groups += 'houston' }
  if (Ask-YesNo '  Start, Stop and Status shortcuts?' $true) { $groups += 'control' }
  $modeNames = if ($isIII) { 'Super Eco, Eco, Balanced, Turbo' } else { 'Eco, Balanced, Turbo' }
  if (Ask-YesNo "  Power mode shortcuts ($modeNames)?" $true) { $groups += 'modes' }
  if (Ask-YesNo '  Start/Stop Bitcoin Node shortcuts (most people leave the node on)?' $false) { $groups += 'node' }
} else {
  $groups = @('houston', 'control', 'modes')
}
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function New-Args([string]$actionArgs, [switch]$notify) {
  $a = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`" -Action $actionArgs"
  if ($notify) { $a += ' -Notify' }
  return $a
}
$shell = New-Object -ComObject WScript.Shell
$made = @()
if ($houston -and ($groups -contains 'houston')) { New-HoustonShortcut $houston.Url; $made += 'Houston' }
else { Remove-HoustonShortcut }
foreach ($s in $ShortcutDefs) {
  $path = Join-Path $Desktop "$($s.Name).lnk"
  if (($s.IIIOnly -and -not $isIII) -or ($groups -notcontains $s.Group)) { Remove-Item $path -ErrorAction SilentlyContinue; continue }
  $made += $s.Name
  $lnk = $shell.CreateShortcut($path)
  $lnk.TargetPath       = $psExe
  $lnk.Arguments        = New-Args $s.Action -notify
  $lnk.WorkingDirectory = $PSScriptRoot
  $ico = Join-Path $PSScriptRoot "icons\$($s.Icon)"
  $lnk.IconLocation     = if (Test-Path $ico) { "$ico,0" } else { "$env:SystemRoot\System32\$($s.Fallback)" }
  $lnk.WindowStyle      = 7   # minimized
  $lnk.Save()
}
if ($made.Count) { Write-Host "  Created: $($made -join ', ')" } else { Write-Host '  No shortcuts.' }

if ($NoSchedule) { Write-Host "`nDone (no schedule changes)."; exit 0 }

# ============================================================================
#  6. Schedule
# ============================================================================
Write-Host "`n== Step 6 of 6: schedule =="
if ($houston -and -not $cliSchedule) {
  $n = Remove-ApolloTasks
  Write-Host "  Your schedule lives in Houston: open $($houston.Url) and use the Schedule tab." -ForegroundColor Green
  Write-Host '  The Apollo runs it by itself, so this PC can be off.'
  if ($n) { Write-Host "  Removed $n old Apollo task(s) from Task Scheduler so they don't clash with Houston." }
  Write-Host "`nDone."
  exit 0
}
if (-not $houston -and $interactiveSetup) {
  $existing = @(Get-ScheduledTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue).Count
  Write-Host '  Without Houston, this PC can run the schedule instead (only while it is on and you are signed in).'
  if ($existing -and (Ask-YesNo "  Keep the $existing Apollo task(s) already in Task Scheduler?" $true)) { Write-Host "`nDone."; exit 0 }
}
# Each window: @{ Type = 'run'|'mode'; Days; On; Off; Mode }
$windows = [System.Collections.ArrayList]::new()
$cliRun  = $PSBoundParameters.ContainsKey('StartTime') -or $PSBoundParameters.ContainsKey('StopTime')
$cliMode = $PSBoundParameters.ContainsKey('BoostMode') -or $PSBoundParameters.ContainsKey('BoostStart') -or $PSBoundParameters.ContainsKey('BoostEnd')
$interactive = -not ($cliRun -or $cliMode -or $ScheduleFile)

if ($ScheduleFile) {
  # Built by the setup window (or {"windows": []} to remove any PC schedule): {"base":"eco","windows":[{"type":"run"|"mode","days":[...],"on":"09:30","off":"16:30"|null,"mode":"turbo"|"custom:16"}]}
  $spec = Get-Content $ScheduleFile -Raw | ConvertFrom-Json
  $tokOf = { param($m) if ("$m" -like 'custom:*') { ConvertTo-ModeToken ("$m".Split(':')[1]) $isIII } else { ConvertTo-ModeToken "$m" $isIII } }
  $baseTok = & $tokOf $(if ($spec.base) { $spec.base } else { 'eco' })
  foreach ($w in @($spec.windows)) {
    $d = @(ConvertTo-Days @($w.days))
    $on = ConvertTo-Time $w.on
    $off = if ($w.off) { ConvertTo-Time $w.off } else { $null }
    if ($w.type -eq 'mode') {
      $m = & $tokOf $w.mode
      if ($m -eq $baseTok) { throw "A faster window uses the same mode as the normal mode ($(Get-ModeLabel $m))." }
      if (-not $off) { throw 'Every mode window needs an end time.' }
      [void]$windows.Add(@{ Type = 'mode'; Days = $d; On = $on; Off = $off; Mode = $m })
    } else {
      [void]$windows.Add(@{ Type = 'run'; Days = $d; On = $on; Off = $off })
    }
  }
  if (-not $windows.Count) {
    [void](Remove-ApolloTasks)
    Write-Host "`nDone. No schedule on this PC (any previous Apollo tasks were removed)."; exit 0
  }
} elseif (-not $interactive) {
  $d = ConvertTo-Days $Days
  if ($cliRun) {
    if (-not $StartTime) { throw '-StartTime is required with -StopTime.' }
    $off = if ($StopTime) { ConvertTo-Time $StopTime } else { $null }
    [void]$windows.Add(@{ Type = 'run'; Days = $d; On = (ConvertTo-Time $StartTime); Off = $off })
  }
  if ($cliMode) {
    if (-not ($BoostMode -and $BoostStart -and $BoostEnd)) { throw '-BoostMode, -BoostStart and -BoostEnd go together.' }
    $baseTok = ConvertTo-ModeToken $BaseMode $isIII
    $boostTok = ConvertTo-ModeToken $BoostMode $isIII
    if ($baseTok -eq $boostTok) { throw '-BoostMode and -BaseMode are the same.' }
    [void]$windows.Add(@{ Type = 'mode'; Days = $d; On = (ConvertTo-Time $BoostStart); Off = (ConvertTo-Time $BoostEnd); Mode = $boostTok })
  }
} else {
  Write-Host '  What should happen automatically?'
  Write-Host '    1) Mine only during certain hours (start and stop the miner)'
  Write-Host '    2) Mine around the clock, switching modes by time (e.g. quiet Eco when home, Turbo when out)'
  Write-Host '    3) Both'
  Write-Host '    4) Nothing - shortcuts only (recommended: install Houston for the schedule)'
  $choice = ''
  while ($choice -notin '1', '2', '3', '4') { $choice = Ask '  Choose 1-4' '2' }
  if ($choice -eq '4') {
    [void](Remove-ApolloTasks)
    Write-Host "`nDone. No schedule (any previous Apollo schedule was removed)."; exit 0
  }
  Write-Host "`n  Days: Mon-Fri, Sat,Sun, Mon,Wed,Fri, weekends, every day...   Times: 09:30, 16:30 or 4:30 PM"

  if ($choice -in '1', '3') {
    Write-Host "`n  -- Mining hours (the miner is stopped outside these) --" -ForegroundColor Cyan
    $n = 1
    do {
      Write-Host "  Window $n"
      $d   = Ask-Days '    Days'
      $on  = Ask-Time '    Start mining at' '09:00'
      $off = Ask-Time "    Stop mining at (or 'never')" '17:00' -AllowBlank
      [void]$windows.Add(@{ Type = 'run'; Days = $d; On = $on; Off = $off })
      $n++
    } while (Ask-YesNo '  Add another mining window (different days or times)?' $false)
  }

  if ($choice -in '2', '3') {
    Write-Host "`n  -- Mode schedule --" -ForegroundColor Cyan
    if ($isIII) {
      Write-Host '  Apollo III modes: super eco, eco, balanced, turbo, or a hashrate target from 5 to 20 (TH/s)'
      $baseTok = Ask-Mode '  Normal mode, the rest of the time' 'eco' @('super_eco', 'eco', 'balanced', 'custom') ''
    } else {
      $baseTok = Ask-Mode '  Normal mode, the rest of the time (eco or balanced)' 'eco' @('eco', 'balanced') ''
    }
    $n = 1
    do {
      Write-Host "  Faster window $n"
      if ($isIII) { $m = Ask-Mode '    Faster mode (eco, balanced, turbo or 5-20 TH/s)' 'turbo' @('eco', 'balanced', 'turbo', 'custom') $baseTok }
      else        { $m = Ask-Mode '    Faster mode (balanced or turbo)' 'turbo' @('balanced', 'turbo') $baseTok }
      $d   = Ask-Days '    Days'
      $on  = Ask-Time "    Switch to $(Get-ModeLabel $m) at" '09:00'
      $off = Ask-Time "    Back to $(Get-ModeLabel $baseTok) at" '17:00'
      [void]$windows.Add(@{ Type = 'mode'; Days = $d; On = $on; Off = $off; Mode = $m })
      $n++
    } while (Ask-YesNo '  Add another faster window (different days or times)?' $false)
  }
}

# Build the task list. A window ending at or before its start time ends the next day.
$tasks = [System.Collections.ArrayList]::new()
$runCount  = @($windows | Where-Object { $_.Type -eq 'run' }).Count
$modeCount = @($windows | Where-Object { $_.Type -eq 'mode' }).Count
$k = 0
foreach ($w in $windows) {
  $k++
  $label  = Format-Days $w.Days
  $offDays = $w.Days
  $overnight = $w.Off -and ($w.Off.TimeOfDay -le $w.On.TimeOfDay)
  if ($overnight) { $offDays = Get-NextDays $w.Days }
  $multi = if ($w.Type -eq 'run') { $runCount -gt 1 } else { $modeCount -gt 1 }
  $sfx = if ($multi) { " #$k ($label)" } else { '' }
  if ($w.Type -eq 'run') {
    [void]$tasks.Add(@{ Name = "Start Miner$sfx"; Action = 'start'; Days = $w.Days; At = $w.On })
    if ($w.Off) { [void]$tasks.Add(@{ Name = "Stop Miner$sfx"; Action = 'stop'; Days = $offDays; At = $w.Off }) }
  } else {
    [void]$tasks.Add(@{ Name = "Switch to $(Get-ModeTaskLabel $w.Mode)$sfx"; Action = (Get-ModeArgs $w.Mode); Days = $w.Days; At = $w.On })
    [void]$tasks.Add(@{ Name = "Switch to $(Get-ModeTaskLabel $baseTok)$sfx"; Action = (Get-ModeArgs $baseTok); Days = $offDays; At = $w.Off })
  }
}

Write-Host "`n  Your schedule:" -ForegroundColor Cyan
foreach ($w in $windows) {
  $label = Format-Days $w.Days
  $on = $w.On.ToString('h:mm tt')
  if ($w.Type -eq 'run') {
    if ($w.Off) {
      $note = if ($w.Off.TimeOfDay -le $w.On.TimeOfDay) { ' (next day)' } else { '' }
      Write-Host ("    {0,-12} mine {1} - {2}{3}" -f $label, $on, $w.Off.ToString('h:mm tt'), $note)
    } else { Write-Host ("    {0,-12} start mining at {1} (no automatic stop)" -f $label, $on) }
  } else {
    $note = if ($w.Off.TimeOfDay -le $w.On.TimeOfDay) { ' (next day)' } else { '' }
    Write-Host ("    {0,-12} {1} {2} - {3}{4}, {5} otherwise" -f $label, (Get-ModeLabel $w.Mode), $on, $w.Off.ToString('h:mm tt'), $note, (Get-ModeLabel $baseTok))
  }
}
if ($interactive -and -not (Ask-YesNo "`n  Save this schedule?" $true)) {
  Write-Host '  Nothing changed. Run setup again to start over.'; exit 0
}

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
              -DontStopIfGoingOnBatteries -WakeToRun -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
[void](Remove-ApolloTasks)
foreach ($t in $tasks) {
  $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $t.Days -At $t.At
  $act     = New-ScheduledTaskAction -Execute $psExe -Argument (New-Args $t.Action)
  Register-ScheduledTask -TaskPath $TaskFolder -TaskName $t.Name -Trigger $trigger `
    -Action $act -Settings $settings -Description "Apollo miner: $($t.Action)" -Force | Out-Null
}

Write-Host "`n  Saved $($tasks.Count) scheduled tasks (Task Scheduler > Apollo Miner)." -ForegroundColor Green
Write-Host "  They run while you're signed in to Windows (a locked screen is fine)."
if ($modeCount) { Write-Host '  Mode switches restart a running miner (about a minute) and never start a stopped one.' }
if ($modeCount -and -not $runCount) { Write-Host '  The mode schedule never starts the miner, so make sure it is running (Start Miner shortcut).' }
Write-Host "  Change it any time by running setup again. Log: $DataDir\apollo-miner.log"
