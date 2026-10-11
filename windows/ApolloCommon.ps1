# ApolloCommon.ps1 - helpers shared by the setup wizard (GUI) and the text installer.
# Dot-source it:  . (Join-Path $PSScriptRoot 'ApolloCommon.ps1')

$WeekDays = 'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'

function ConvertTo-Time([string]$t) {
  $formats = [string[]]@('H:mm', 'HH:mm', 'h:mm tt', 'h:mmtt', 'htt', 'h tt', 'hmm tt', 'hmmtt', 'Hmm', 'HHmm')
  try {
    return [datetime]::ParseExact($t.Trim().ToUpper(), $formats,
      [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces)
  } catch { throw "Couldn't read the time '$t'. Use 24-hour like 09:30 / 16:30, or 9:30 AM." }
}

# Parse "Mon-Fri", "Mon,Wed,Fri", "Fri-Sun", "weekdays", "weekends", "every day", ...
# Returns full day names in week order (Monday first).
function ConvertTo-Days([string[]]$spec) {
  $text = (($spec | Where-Object { $_ }) -join ',').Trim().ToLower()
  if (-not $text) { $text = 'weekdays' }
  # normalise: "every day" -> all, "Mon - Fri" / "Mon to Fri" / "Mon thru Fri" -> mon-fri
  $text = $text -replace 'every\s*day|daily|7 days', 'all' -replace '\s*(-|\bto\b|\bthrough\b|\bthru\b)\s*', '-' -replace '\band\b', ','
  $set = [System.Collections.Generic.HashSet[int]]::new()
  foreach ($part in ($text -split '[,;/&+\s]+' | Where-Object { $_ })) {
    switch -Regex ($part) {
      '^(all|everyday)$'                    { 0..6 | ForEach-Object { [void]$set.Add($_) }; continue }
      '^(weekdays?|workdays?)$'             { 0..4 | ForEach-Object { [void]$set.Add($_) }; continue }
      '^(weekends?)$'                       { 5..6 | ForEach-Object { [void]$set.Add($_) }; continue }
      '^([a-z]+)-([a-z]+)$' {
        $a = Get-DayIndex $Matches[1]; $b = Get-DayIndex $Matches[2]
        $i = $a; while ($true) { [void]$set.Add($i); if ($i -eq $b) { break }; $i = ($i + 1) % 7 }
        continue
      }
      default { [void]$set.Add((Get-DayIndex $part)) }
    }
  }
  return @(0..6 | Where-Object { $set.Contains($_) } | ForEach-Object { $WeekDays[$_] })
}

function Get-DayIndex([string]$d) {
  $d = $d.Trim().ToLower()
  if ($d.Length -ge 2) {
    for ($i = 0; $i -lt 7; $i++) { if ($WeekDays[$i].ToLower().StartsWith($d)) { return $i } }
  }
  throw "Unknown day '$d'. Use names like Mon, Tue or Monday, or ranges like Mon-Fri."
}

# Short label: Mon-Fri, Sat,Sun, Mon,Wed,Fri, Every day
function Format-Days([string[]]$days) {
  if ($days.Count -eq 7) { return 'Every day' }
  $idx = @($days | ForEach-Object { [array]::IndexOf($WeekDays, $_) } | Sort-Object)
  $parts = @(); $i = 0
  while ($i -lt $idx.Count) {
    $j = $i; while ($j + 1 -lt $idx.Count -and $idx[$j + 1] -eq $idx[$j] + 1) { $j++ }
    $s = $WeekDays[$idx[$i]].Substring(0, 3); $e = $WeekDays[$idx[$j]].Substring(0, 3)
    if ($j - $i -ge 2) { $parts += "$s-$e" } elseif ($j -gt $i) { $parts += $s; $parts += $e } else { $parts += $s }
    $i = $j + 1
  }
  return ($parts -join ',')
}

# The day after each day (for windows that end after midnight)
function Get-NextDays([string[]]$days) {
  return @($days | ForEach-Object { $WeekDays[([array]::IndexOf($WeekDays, $_) + 1) % 7] } |
    Sort-Object { [array]::IndexOf($WeekDays, $_) })
}

# Look for an Apollo on the local network: probe port 5000 on every address in this
# PC's /24 subnet(s), then confirm the Apollo API answers.
function Find-Apollo([string[]]$Candidates) {
  if (-not $Candidates) {
    $Candidates = @()
    $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixLength -ge 16 -and $_.PrefixLength -le 30 }
    foreach ($a in $addrs) {
      $o = $a.IPAddress.Split('.'); $prefix = "$($o[0]).$($o[1]).$($o[2])"
      $Candidates += 1..254 | ForEach-Object { "$prefix.$_" } | Where-Object { $_ -ne $a.IPAddress }
    }
    $Candidates = @($Candidates | Select-Object -Unique)
  }
  if (-not $Candidates) { return @() }
  $probes = foreach ($ip in $Candidates) {
    $c = [System.Net.Sockets.TcpClient]::new()
    [pscustomobject]@{ Ip = $ip; Client = $c; Task = $c.ConnectAsync($ip, 5000) }
  }
  $deadline = (Get-Date).AddMilliseconds(2500)
  while ((Get-Date) -lt $deadline -and ($probes | Where-Object { -not $_.Task.IsCompleted })) { Start-Sleep -Milliseconds 100 }
  $open = @($probes | Where-Object { $_.Task.Status -eq 'RanToCompletion' } | ForEach-Object { $_.Ip })
  $probes | ForEach-Object { try { $_.Client.Close() } catch { } }
  $found = @()
  foreach ($ip in $open) {
    try {
      $body = '{"query":"query { Auth { status { result { status } } } }"}'
      $r = Invoke-RestMethod -Uri "http://${ip}:5000/api/graphql" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 4
      if ($r.data.Auth) { $found += $ip }
    } catch { }
  }
  return $found
}

# Same check the Apollo dashboard makes: /api/config reports chassis "apollo-iii"
# on an Apollo III. Anything else (including older software) is an Apollo I/II.
function Get-ApolloModel([string]$apolloHost) {
  foreach ($u in "http://$apolloHost/api/config", "http://${apolloHost}:3000/api/config") {
    try {
      $c = Invoke-RestMethod -Uri $u -TimeoutSec 5
      if ($c.chassis -eq 'apollo-iii') { return 'apollo-iii' }
      return 'apollo-ii'
    } catch { }
  }
  return 'apollo-ii'
}

# Houston: the app and scheduler that run on the Apollo itself (houston\install-houston.sh).
# Returns @{ Version; Url } when it answers, otherwise $null.
function Get-Houston([string]$apolloHost) {
  $url = "http://${apolloHost}:8088/"
  try {
    $d = Invoke-RestMethod -Uri "${url}api/device" -TimeoutSec 4
    if ($d.version) { return @{ Version = "$($d.version)"; Url = $url } }
  } catch { }
  return $null
}

# The two commands that copy Houston to the Apollo and install it (OpenSSH is built into Windows 10/11)
function Get-HoustonInstallCommands([string]$apolloHost) {
  $src = Join-Path (Split-Path $PSScriptRoot -Parent) 'houston'
  return @(
    "scp -r `"$src`" futurebit@${apolloHost}:~/",
    "ssh -t futurebit@$apolloHost `"sudo bash ~/houston/install-houston.sh`""
  )
}

# Modes are kept as tokens: super_eco, eco, balanced, turbo, or custom:<TH/s> (Apollo III)
function ConvertTo-ModeToken([string]$text, [bool]$isIII) {
  $t = "$text".Trim().ToLower() -replace '[\s_-]+', ' '
  if ($t -match '^(custom\s*)?(\d{1,2})(\s*th(/s|s)?)?$') {
    if (-not $isIII) { throw 'Custom hashrate targets need an Apollo III.' }
    $h = [int]$Matches[2]
    if ($h -lt 5 -or $h -gt 20) { throw 'Hashrate target must be between 5 and 20 TH/s.' }
    return "custom:$h"
  }
  switch -Regex ($t) {
    '^super ?eco$' { if (-not $isIII) { throw 'Super Eco needs an Apollo III.' }; return 'super_eco' }
    '^(eco|balanced|turbo)$' { return $t }
  }
  throw "Unknown mode '$text'."
}

function Get-ModeLabel([string]$token) {
  if ($token -like 'custom:*') { return "$($token.Split(':')[1]) TH/s" }
  if ($token -eq 'super_eco') { return 'Super Eco' }
  return $token.Substring(0, 1).ToUpper() + $token.Substring(1)
}

# Task Scheduler names can't contain "/"
function Get-ModeTaskLabel([string]$token) {
  if ($token -like 'custom:*') { return "$($token.Split(':')[1]) TH target" }
  return Get-ModeLabel $token
}

function Get-ModeArgs([string]$token) {
  if ($token -like 'custom:*') { return "custom -Hashrate $($token.Split(':')[1])" }
  return $token
}

# Where the scripts keep their settings (per Windows user)
$ApolloDataDir = Join-Path $env:LOCALAPPDATA 'ApolloMiner'

# Log in and report what we find, without saving anything. Used by the setup window.
# Returns @{ Ok; Error; Model; Status; Mode; Houston }
function Test-ApolloLogin([string]$apolloHost, [string]$password) {
  $url = "http://${apolloHost}:5000/api/graphql"
  $post = {
    param($q, $vars, $token)
    $h = @{}; if ($token) { $h['Authorization'] = "Bearer $token" }
    $b = @{ query = $q; variables = $vars } | ConvertTo-Json -Depth 5 -Compress
    $r = Invoke-RestMethod -Uri $url -Method Post -Headers $h -ContentType 'application/json' -Body $b -TimeoutSec 15
    if ($r.errors) { throw (($r.errors | ForEach-Object { $_.message }) -join '; ') }
    $r.data
  }
  try {
    $d = & $post 'query ($p: String!) { Auth { login(input: { password: $p }) { result { accessToken } error { message } } } }' @{ p = $password } $null
  } catch {
    return @{ Ok = $false; Error = "Can't reach the Apollo at $apolloHost. Check the address and that it's switched on." }
  }
  if ($d.Auth.login.error -or -not $d.Auth.login.result) {
    return @{ Ok = $false; Error = 'Wrong password. Use the password you log in to the Apollo dashboard with.' }
  }
  $token = $d.Auth.login.result.accessToken
  $model = Get-ApolloModel $apolloHost
  $fields = if ($model -eq 'apollo-iii') { 'minerMode minerHashrate' } else { 'minerMode' }
  $status = 'unknown'; $mode = ''
  try {
    $s = & $post "query { Miner { online { result { online { status } } } } Settings { read { result { settings { $fields } } } } }" @{} $token
    $status = $s.Miner.online.result.online.status
    $st = $s.Settings.read.result.settings
    $mode = if ($st.minerMode -eq 'custom' -and $st.minerHashrate) { "custom:$($st.minerHashrate)" } else { $st.minerMode }
  } catch { }
  return @{ Ok = $true; Error = ''; Model = $model; Status = $status; Mode = $mode; Houston = (Get-Houston $apolloHost) }
}

# Save the dashboard password the same way apollo-miner.ps1 does (DPAPI, this Windows user only)
function Save-ApolloPassword([Security.SecureString]$secure) {
  New-Item -ItemType Directory -Force -Path $ApolloDataDir | Out-Null
  $secure | ConvertFrom-SecureString | Set-Content -Path (Join-Path $ApolloDataDir 'password.xml')
}
