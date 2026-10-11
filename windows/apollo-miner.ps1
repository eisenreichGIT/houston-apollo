<#
.SYNOPSIS
  Start, stop, check or change the mode of a FutureBit Apollo (II or III) without
  opening the web dashboard.

.DESCRIPTION
  Calls the Apollo's own API (the same one the dashboard uses): logs in with your
  dashboard password, then starts/stops the miner, reports its status, or switches
  the mining mode.

  Modes:  eco | balanced | turbo                 (every Apollo)
          super_eco | custom -Hashrate 5..20     (Apollo III only)
  Node:   node_start | node_stop                 (the Apollo's Bitcoin node)

  The password is stored once, encrypted with Windows DPAPI, so only your Windows
  account on this PC can decrypt it. The Apollo's address is stored by the
  installer in %LOCALAPPDATA%\ApolloMiner\host.txt (or pass -ApolloHost).

.EXAMPLE
  .\apollo-miner.ps1 -Action status
  .\apollo-miner.ps1 -Action start -Notify
  .\apollo-miner.ps1 -Action turbo                    # restarts the miner if it's running
  .\apollo-miner.ps1 -Action super_eco                # Apollo III
  .\apollo-miner.ps1 -Action custom -Hashrate 14      # Apollo III: target 14 TH/s
  .\apollo-miner.ps1 -Action node_stop                # stop the Bitcoin node (mining via a pool continues)
  .\apollo-miner.ps1 -Action setpassword
#>
param(
  [ValidateSet('start', 'stop', 'restart', 'status', 'super_eco', 'eco', 'balanced', 'turbo', 'custom', 'node_start', 'node_stop', 'setpassword')]
  [string]$Action = 'status',

  # Apollo III custom mode: target hashrate in TH/s (5-20)
  [int]$Hashrate,

  # IP address or hostname of the Apollo. Defaults to the one saved by the installer.
  [string]$ApolloHost,

  # Show a pop-up with the result (used by the desktop shortcuts)
  [switch]$Notify
)

$ErrorActionPreference = 'Stop'
$DataDir  = Join-Path $env:LOCALAPPDATA 'ApolloMiner'
$CredFile = Join-Path $DataDir 'password.xml'
$HostFile = Join-Path $DataDir 'host.txt'
$LogFile  = Join-Path $DataDir 'apollo-miner.log'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

function Write-Log([string]$msg) {
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path $LogFile -Value $line
  Write-Host $line
}

function Show-Result([string]$msg, [bool]$ok) {
  if ($Notify) {
    $icon = if ($ok) { 64 } else { 16 }   # 64 = info, 16 = error
    (New-Object -ComObject WScript.Shell).Popup($msg, 8, 'Houston', $icon) | Out-Null
  }
}

function Save-Password {
  $secure = Read-Host 'Apollo dashboard password' -AsSecureString
  $secure | ConvertFrom-SecureString | Set-Content -Path $CredFile
  Write-Host "Password saved (encrypted for your Windows account) to $CredFile"
}

function Get-Password {
  if (-not (Test-Path $CredFile)) { Save-Password }
  $secure = Get-Content $CredFile | ConvertTo-SecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Resolve-ApolloHost {
  $h = $ApolloHost
  if (-not $h -and (Test-Path $HostFile)) { $h = (Get-Content $HostFile -TotalCount 1).Trim() }
  if (-not $h) { throw "No Apollo address set. Run Setup.bat, or pass -ApolloHost <ip>." }
  if ($h -notmatch '^[A-Za-z0-9.\-]+$') { throw "Invalid Apollo address '$h'. Use an IP like 192.168.1.50 or a hostname." }
  return $h
}

function Invoke-Gql([string]$url, [string]$query, [hashtable]$vars, [string]$token, [int]$timeout = 30) {
  $headers = @{}
  if ($token) { $headers['Authorization'] = "Bearer $token" }
  $body = @{ query = $query; variables = $vars } | ConvertTo-Json -Depth 6 -Compress
  $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers `
            -ContentType 'application/json' -Body $body -TimeoutSec $timeout
  if ($resp.errors) { throw (($resp.errors | ForEach-Object { $_.message }) -join '; ') }
  return $resp.data
}

function Test-Endpoint([string]$url) {
  try {
    $d = Invoke-Gql $url 'query { Auth { status { result { status } } } }' @{} $null
    if ($d.Auth) { return }
  } catch { }
  throw "Could not reach the Apollo API at $url. Is the Apollo powered on and on the network?"
}

function Get-Token([string]$url) {
  $q = 'query ($p: String!) { Auth { login(input: { password: $p }) { result { accessToken } error { message } } } }'
  $d = Invoke-Gql $url $q @{ p = (Get-Password) } $null
  if ($d.Auth.login.error) {
    throw "Login failed: $($d.Auth.login.error.message). Run with -Action setpassword to update the saved password."
  }
  return $d.Auth.login.result.accessToken
}

# Which hardware is this? Same check the Apollo dashboard makes: its /api/config
# page reports chassis "apollo-iii" on an Apollo III. Anything else (including
# older software) is treated as Apollo I/II.
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

function Format-Mode([string]$mode, $hashrate) {
  switch ($mode) {
    'super_eco' { return 'Super Eco' }
    'custom'    { if ($hashrate) { return "custom $hashrate TH/s" } else { return 'custom' } }
    default     { return $mode }
  }
}

function Get-MinerStatus([string]$url, [string]$token) {
  $d = Invoke-Gql $url 'query { Miner { online { result { online { status } } error { message } } } }' @{} $token
  return $d.Miner.online.result.online.status
}

function Get-Settings([string]$url, [string]$token, [bool]$isIII) {
  # minerHashrate only exists on Apollo III software; asking older software for it is an error
  $fields = if ($isIII) { 'minerMode minerHashrate nodeSoftware' } else { 'minerMode nodeSoftware' }
  $d = Invoke-Gql $url "query { Settings { read { result { settings { $fields } } error { message } } } }" @{} $token
  if ($d.Settings.read.error) { throw "Couldn't read settings: $($d.Settings.read.error.message)" }
  return $d.Settings.read.result.settings
}

function Set-MinerMode([string]$url, [string]$token, [string]$mode, [int]$hashrate, [bool]$isIII) {
  if ($mode -in 'super_eco', 'custom' -and -not $isIII) {
    $what = if ($mode -eq 'custom') { 'Custom hashrate targets are' } else { 'Super Eco is' }
    throw "$what only available on the Apollo III. This Apollo supports eco, balanced and turbo."
  }
  if ($mode -eq 'custom' -and ($hashrate -lt 5 -or $hashrate -gt 20)) {
    throw 'Custom mode needs a target hashrate between 5 and 20 TH/s, e.g. -Hashrate 14.'
  }
  $current = Get-Settings $url $token $isIII
  $status  = Get-MinerStatus $url $token
  $before  = Format-Mode $current.minerMode $current.minerHashrate
  $after   = Format-Mode $mode $hashrate
  if ($current.minerMode -eq $mode -and ($mode -ne 'custom' -or $current.minerHashrate -eq $hashrate)) {
    return "Already in $after mode (miner $status)."
  }

  # Send the current nodeSoftware back unchanged. Apollo software up to 2.1.2 treats a
  # missing value as "node software changed" and would needlessly restart the Bitcoin node.
  if ($mode -eq 'custom') {
    $q = 'query ($m: MinerMode!, $n: NodeSoftware, $h: Int) { Settings { update(input: { minerMode: $m, nodeSoftware: $n, minerHashrate: $h }) { result { settings { minerMode } } error { message } } } }'
    $vars = @{ m = $mode; n = $current.nodeSoftware; h = $hashrate }
  } else {
    $q = 'query ($m: MinerMode!, $n: NodeSoftware) { Settings { update(input: { minerMode: $m, nodeSoftware: $n }) { result { settings { minerMode } } error { message } } } }'
    $vars = @{ m = $mode; n = $current.nodeSoftware }
  }
  $d = Invoke-Gql $url $q $vars $token 60
  if ($d.Settings.update.error) { throw "Couldn't change mode: $($d.Settings.update.error.message)" }

  # A new mode takes effect when the miner restarts. Don't start a miner that was stopped.
  if ($status -eq 'offline') { return "Mode set to $after ($before before). Miner is stopped; it will use $after next time it starts." }
  $r = Invoke-Gql $url 'query { Miner { restart { error { message } } } }' @{} $token 180
  if ($r.Miner.restart.error) { throw "Mode saved, but restarting the miner failed: $($r.Miner.restart.error.message)" }
  return "Switched from $before to $after mode. Miner restarting (about a minute)."
}

function Get-NodeStatus([string]$url, [string]$token) {
  $d = Invoke-Gql $url 'query { Node { online { result { online { status } } error { message } } } }' @{} $token
  return $d.Node.online.result.online.status
}

# Apollo software 2.1.4+ takes node start/stop as a mutation; older software only as a query
# (it rejects the mutation with HTTP 400, so fall back to the query form then).
function Send-NodeCommand([string]$url, [string]$token, [string]$cmd) {
  try {
    $d = Invoke-Gql $url "mutation { Node { $cmd { error { message } } } }" @{} $token 150
  } catch {
    if ($_.Exception.Message -notmatch '400|Bad Request|Mutation') { throw }
    $d = Invoke-Gql $url "query { Node { $cmd { error { message } } } }" @{} $token 150
  }
  $err = $d.Node.$cmd.error
  if ($err) { throw "Node $cmd failed: $($err.message)" }
}

try {
  if ($Action -eq 'setpassword') { Save-Password; exit 0 }

  # The Apollo API listens on port 5000
  $apolloHost = Resolve-ApolloHost
  $url = "http://${apolloHost}:5000/api/graphql"
  Test-Endpoint $url
  $token = Get-Token $url

  if ($Action -eq 'status') {
    $isIII = (Get-ApolloModel $apolloHost) -eq 'apollo-iii'
    $model = if ($isIII) { 'Apollo III' } else { 'Apollo II' }
    $s = Get-MinerStatus $url $token
    $m = 'unknown'
    try { $st = Get-Settings $url $token $isIII; $m = Format-Mode $st.minerMode $st.minerHashrate } catch { }
    $n = 'unknown'
    try { $n = Get-NodeStatus $url $token } catch { }
    Write-Log "Miner status: $s ($m mode, $model), Bitcoin node: $n"
    Show-Result "Miner status: $s`nMode: $m`nBitcoin node: $n`nModel: $model" $true
    exit 0
  }

  if ($Action -in 'node_start', 'node_stop') {
    $cmd = $Action.Substring(5)
    Send-NodeCommand $url $token $cmd
    Start-Sleep -Seconds 3
    $n = 'unknown'
    try { $n = Get-NodeStatus $url $token } catch { }
    $msg = if ($cmd -eq 'start') { "Bitcoin node start sent. Current status: $n" } else { "Bitcoin node stopped. Current status: $n" }
    Write-Log $msg
    Show-Result $msg $true
    exit 0
  }

  if ($Action -in 'super_eco', 'eco', 'balanced', 'turbo', 'custom') {
    $isIII = (Get-ApolloModel $apolloHost) -eq 'apollo-iii'
    $msg = Set-MinerMode $url $token $Action $Hashrate $isIII
    Write-Log $msg
    Show-Result $msg $true
    exit 0
  }

  # Start/restart can take ~40-60s: the Apollo waits ~35s for its hashboards before replying
  $d = Invoke-Gql $url "query { Miner { $Action { error { message } } } }" @{} $token 180
  $err = $d.Miner.$Action.error
  if ($err) { throw "Miner $Action failed: $($err.message)" }

  # Give the miner a moment, then report what the Apollo says
  Start-Sleep -Seconds 10
  $s = 'unknown'
  try { $s = Get-MinerStatus $url $token } catch { }
  $msg = "Miner $Action sent successfully. Current status: $s"
  Write-Log $msg
  Show-Result $msg $true
  exit 0
}
catch {
  $msg = "ERROR ($Action): $($_.Exception.Message)"
  Write-Log $msg
  Show-Result $msg $false
  exit 1
}
