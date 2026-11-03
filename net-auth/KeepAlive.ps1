<#
  KeepAlive.ps1 - NSRU Campus LAN Internet KeepAlive Daemon
  Maintains FortiGate captive portal login in background.
  Preferred engine: Node.js (OpenSSL TLS). Fallback engine: built-in curl.exe.
  Includes portable node.exe auto-discovery, auto-sync from Server 72 share,
  instant sleep/wake recovery, and multi-account rotation support.
#>

param(
    [switch]$Once,
    [string]$Portal,
    [int]$IntervalSec = 90,
    [int]$StopHour = -1
)

$ErrorActionPreference = 'SilentlyContinue'

# Kill any duplicate KeepAlive daemons (powershell wrapper AND its node child) to avoid conflicts (not for -Once)
if (-not $Once) { try {
    $myPid = $PID
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $myPid -and ($_.CommandLine -like '*KeepAlive.ps1*' -or $_.CommandLine -like '*net-auth*KeepAlive.js*')
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {} }

$dataDir = Join-Path $env:ProgramData 'LabDeploy'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
$netAuthDir = Join-Path $dataDir 'net-auth'
if (-not (Test-Path $netAuthDir)) { New-Item -ItemType Directory -Force -Path $netAuthDir | Out-Null }
$logFile = Join-Path $dataDir 'keepalive.log'

function Write-Log($msg) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "$ts  $msg"
    try {
        if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 5MB)) {
            $recent = Get-Content $logFile -Tail 2000
            Set-Content -Path $logFile -Value $recent -Encoding UTF8
        }
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    } catch {}
    if (-not [Console]::IsOutputRedirected -and $host.UI.RawUI) {
        Write-Host $line
    }
}

# Auto-sync files from Server 72 share if reachable
function Sync-FromDeployShare {
    $shareAuth = '\\192.168.0.72\LabDeploy\net-auth'
    if (Test-Path $shareAuth) {
        try {
            $updated = $false
            foreach ($fn in @('KeepAlive.ps1', 'KeepAlive.js', 'launch.vbs', 'net-auth.env', 'update.cmd', 'update.ps1')) {
                $src = Join-Path $shareAuth $fn
                $dst = if ($fn -eq 'net-auth.env') { Join-Path $dataDir $fn } else { Join-Path $netAuthDir $fn }
                if (Test-Path $src) {
                    $need = (-not (Test-Path $dst)) -or ((Get-FileHash -LiteralPath $src).Hash -ne (Get-FileHash -LiteralPath $dst).Hash)
                    if ($need) {
                        Copy-Item -LiteralPath $src -Destination $dst -Force
                        $updated = $true
                        Write-Log "Auto-updated $fn from Server 72."
                    }
                }
            }
            return $updated
        } catch {}
    }
    return $false
}

# Wait up to 15s for IPv4 address at boot before making web requests
function Wait-NetworkReady([int]$TimeoutSec = 15) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Ethernet*','Wi-Fi*','LAN*' -ErrorAction SilentlyContinue | Where-Object {
            $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '0.*'
        }
        if ($ips) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

# 1. Wait for interface & check for Server 72 updates
[void](Wait-NetworkReady 10)
$synced = Sync-FromDeployShare
if ($synced -and -not $Once) {
    Write-Log "Initial sync updated scripts. Handing off to new copy..."
}

# 2. Resolve credentials from net-auth.env
$envCandidates = @(
    (Join-Path $dataDir 'net-auth.env'),
    '\\192.168.0.72\LabDeploy\net-auth.env',
    (Join-Path $PSScriptRoot 'net-auth.env'),
    (Join-Path $netAuthDir 'net-auth.env')
)

$cfg = @{}
foreach ($cand in $envCandidates) {
    if (Test-Path $cand) {
        try {
            $found = $false
            Get-Content $cand -Encoding UTF8 | ForEach-Object {
                $trimmed = $_.Trim()
                if ($trimmed -and -not $trimmed.StartsWith('#') -and $trimmed -match '^([^=]+)=(.*)$') {
                    $k = $matches[1].Trim().ToUpper()
                    $v = $matches[2].Trim()
                    $cfg[$k] = $v
                    $found = $true
                }
            }
            if ($found) {
                # Cache locally if read from share
                $localEnv = Join-Path $dataDir 'net-auth.env'
                if ($cand -ne $localEnv -and -not (Test-Path $localEnv)) {
                    try {
                        Copy-Item $cand $localEnv -Force
                        icacls $localEnv /inheritance:r /grant:r 'Administrators:(F)' 'SYSTEM:(F)' | Out-Null
                    } catch {}
                }
                break
            }
        } catch {}
    }
}

$user = if ($cfg.ContainsKey('NSRU_USER')) { $cfg['NSRU_USER'] } else { $env:NSRU_USER }
$pass = if ($cfg.ContainsKey('NSRU_PASS')) { $cfg['NSRU_PASS'] } else { $env:NSRU_PASS }
$portalUrl = if ($Portal) { $Portal }
             elseif ($cfg.ContainsKey('PORTAL')) { $cfg['PORTAL'] }
             else { 'https://login.nsru.ac.th:1000' }
if ($cfg.ContainsKey('INTERVAL') -and $IntervalSec -eq 90) {
    $IntervalSec = [int]$cfg['INTERVAL']
}
if ($cfg.ContainsKey('STOP_HOUR') -and $StopHour -eq -1) {
    $StopHour = [int]$cfg['STOP_HOUR']
}

if (-not $user -or -not $pass) {
    Write-Log "FAIL: No credentials found in net-auth.env (NSRU_USER / NSRU_PASS missing)."
    Exit 1
}

# Preferred engine: Node.js (OpenSSL TLS connects fine; Schannel/curl fails on FortiGate TLS)
$nodeExe = (Get-Command 'node.exe' -ErrorAction SilentlyContinue).Source
if (-not $nodeExe -and (Test-Path "$env:ProgramFiles\nodejs\node.exe")) { $nodeExe = "$env:ProgramFiles\nodejs\node.exe" }
if (-not $nodeExe -and (Test-Path (Join-Path $dataDir 'node.exe'))) { $nodeExe = (Join-Path $dataDir 'node.exe') }
if (-not $nodeExe -and (Test-Path (Join-Path $netAuthDir 'node.exe'))) { $nodeExe = (Join-Path $netAuthDir 'node.exe') }

# Offline fallback: copy portable node.exe from share or local script folder if present
if (-not $nodeExe) {
    $nodeCandidates = @(
        '\\192.168.0.72\LabDeploy\net-auth\node.exe',
        (Join-Path $PSScriptRoot 'node.exe'),
        (Join-Path $PSScriptRoot 'tools\node.exe'),
        (Join-Path $PSScriptRoot '..\tools\node.exe'),
        (Join-Path $PSScriptRoot '..\node.exe')
    )
    foreach ($cand in $nodeCandidates) {
        if (Test-Path $cand) {
            try {
                $targetNode = Join-Path $netAuthDir 'node.exe'
                Copy-Item -LiteralPath $cand -Destination $targetNode -Force -ErrorAction Stop
                $nodeExe = $targetNode
                Write-Log "Copied portable node.exe from $cand -> $targetNode"
                break
            } catch {}
        }
    }
}

$jsScript = Join-Path $PSScriptRoot 'KeepAlive.js'
if (-not (Test-Path $jsScript)) { $jsScript = Join-Path $netAuthDir 'KeepAlive.js' }

if ($nodeExe -and (Test-Path $jsScript)) {
    Write-Log "Engine: node ($nodeExe)"
    while ($true) {
        # Export all primary & fallback accounts
        $env:NSRU_USER = $user
        $env:NSRU_PASS = $pass
        foreach ($k in $cfg.Keys) {
            if ($k -like 'NSRU_USER*' -or $k -like 'NSRU_PASS*') {
                Set-Item -Path "Env:\$k" -Value $cfg[$k]
            }
        }
        $nodeArgs = @($jsScript, '--portal', $portalUrl, '--interval', $IntervalSec, '--stop-hour', $StopHour, '--log', $logFile)
        if ($Once) { $nodeArgs += '--once' }
        & $nodeExe @nodeArgs
        $code = $LASTEXITCODE
        Get-ChildItem Env:\NSRU_USER*, Env:\NSRU_PASS* -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
        if ($Once -or $code -eq 1 -or ((Get-Date).Hour -eq $StopHour)) { exit $code }
        # Node exited (likely updated from share or restart requested). Sync and restart in 3s.
        [void](Sync-FromDeployShare)
        Start-Sleep -Seconds 3
    }
}

Write-Log "Engine: curl.exe (node.exe not found - install Node.js LTS if login fails with curl 35 / TLS errors)"

$curl = (Get-Command 'curl.exe' -ErrorAction SilentlyContinue).Source
if (-not $curl) { $curl = "$env:SystemRoot\System32\curl.exe" }
if (-not (Test-Path $curl)) {
    Write-Log "FAIL: curl.exe not found at $curl"
    Exit 2
}

$script:activePortal = $portalUrl

function Test-Internet {
    $status = & $curl -s -k -m 6 -w "%{http_code}" -o NUL "http://clients3.google.com/generate_204" 2>$null
    return ($status -eq '204')
}

function Get-RedirectUrl {
    # 1. Follow HTTP redirect and get effective URL directly
    $eff = & $curl -s -k -m 6 -L -o NUL -w "%{url_effective}" "http://clients3.google.com/generate_204" 2>$null
    if ($eff -and $eff -notlike '*generate_204*' -and $eff -like 'http*') {
        return $eff.Trim()
    }
    # 2. Check headers and HTML meta/window.location
    $head = & $curl -s -k -m 6 -i "http://clients3.google.com/generate_204" 2>$null
    if ($head -match 'Location:\s*([^\r\n]+)') { return $matches[1].Trim() }
    if ($head -match 'window\.location\s*=\s*["'']([^"'']+)["'']') { return $matches[1].Trim() }
    if ($head -match '(?i)<meta\s+http-equiv=["'']refresh["'']\s+content=["''][^"'']*url=([^"'']+)["'']') { return $matches[1].Trim() }
    return $null
}

function Invoke-Login($redirTarget) {
    $targetPortal = $portalUrl
    $magicToken = ''
    $loginPage = "$portalUrl/"

    if ($redirTarget) {
        try {
            # Handle relative redirect e.g. "/fgtauth?..."
            if ($redirTarget -notlike 'http*') {
                $base = $portalUrl.TrimEnd('/')
                $rel = $redirTarget.TrimStart('/')
                $redirTarget = "$base/$rel"
            }
            $loginPage = $redirTarget
            $uri = [Uri]$redirTarget
            $targetPortal = "$($uri.Scheme)://$($uri.Authority)"
            if ($uri.Query -match 'magic=([^&]+)') { $magicToken = $matches[1] }
            elseif ($uri.Query -match '^\?([0-9a-zA-Z]+)') { $magicToken = $matches[1] }
        } catch {}
    }

    $pageHtml = & $curl -s -k -m 8 "$loginPage" 2>$null
    $pageExit = $LASTEXITCODE
    $magic = if ($pageHtml -match 'name="?magic"?\s+value="([^"]+)"') { $matches[1] } else { $magicToken }
    $redir = if ($pageHtml -match 'name="?4Tredir"?\s+value="([^"]+)"') { $matches[1] } else { "$targetPortal/" }

    $postData = "4Tredir=$([Uri]::EscapeDataString($redir))&magic=$([Uri]::EscapeDataString($magic))&username=$([Uri]::EscapeDataString($user))&password=$([Uri]::EscapeDataString($pass))"
    $tmpPost = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($tmpPost, $postData, [Text.Encoding]::ASCII)
        $resp = & $curl -s -k -m 10 -d "@$tmpPost" "$targetPortal/" 2>$null
        $postExit = $LASTEXITCODE
    } finally {
        Remove-Item $tmpPost -Force -ErrorAction SilentlyContinue
    }

    $tok = if ($resp -match 'keepalive\?([0-9a-fA-F]+)') { $matches[1] } elseif ($resp -match 'logout\?([0-9a-fA-F]+)') { $matches[1] } else { $null }
    $script:lastRejected = (-not $tok) -and ($resp -match 'type="password"')
    Write-Log ("Login detail: redirect={0} page=curl{1} magic={2} post=curl{3} token={4}" -f
        $(if ($redirTarget) { $targetPortal } else { 'none' }), $pageExit, $(if ($magic) { 'found' } else { 'MISSING' }), $postExit,
        $(if ($tok) { 'found' } elseif ($resp -match 'type="password"') { 'none (login page again: wrong user/password?)' } else { 'none' }))
    $script:activePortal = $targetPortal
    return $tok
}

function Sleep-Smarter([int]$Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    $lastTick = Get-Date
    while ((Get-Date) -lt $end) {
        Start-Sleep -Seconds 3
        $now = Get-Date
        # Clock jump > 8s means machine was suspended (Sleep/Hibernate)
        if (($now - $lastTick).TotalSeconds -gt 8) {
            Write-Log "System resume from sleep detected (clock jumped $([int]($now - $lastTick).TotalSeconds)s)."
            return $true
        }
        $lastTick = $now
    }
    return $false
}

Write-Log "KeepAlive started (Target: $portalUrl, Interval: ${IntervalSec}s)"

# Initial check & login
$online = Test-Internet
$token = $null
if ($online) {
    Write-Log "Internet is online."
} else {
    Write-Log "Internet is offline or captive portal detected. Attempting login for '$user'..."
    $redir = Get-RedirectUrl
    $token = Invoke-Login $redir
    Start-Sleep -Seconds 2
    if (Test-Internet) {
        Write-Log "Login SUCCESS (token: $(if ($token) { $token } else { 'ok' }))"
    } else {
        Write-Log "Login attempted, internet still offline."
    }
}

if ($Once) {
    if (Test-Internet) { exit 0 } else { exit 1 }
}

$lastShareSync = Get-Date
$failCount = 0
$script:lastRejected = $false

# Daemon loop
while ($true) {
    if ($StopHour -ge 0) {
        $now = Get-Date
        if ($now.Hour -eq $StopHour) {
            Write-Log "Stop hour reached (${StopHour}:00). Exiting daemon."
            if ($token) {
                & $curl -s -k -m 5 "$script:activePortal/logout?$token" 2>$null | Out-Null
            }
            break
        }
    }

    # Periodic check for Server 72 updates every 30 minutes
    if (((Get-Date) - $lastShareSync).TotalMinutes -gt 30) {
        $lastShareSync = Get-Date
        if (Sync-FromDeployShare) {
            Write-Log "Update detected from Server 72. Restarting daemon..."
            exit 0
        }
    }

    $isUp = Test-Internet
    if ($isUp) {
        if ($token) {
            $resp = & $curl -s -k -m 6 "$script:activePortal/keepalive?$token" 2>$null
            if ($resp -match 'name="magic"' -and $resp -match 'type="password"') {
                Write-Log "Session expired. Re-authenticating..."
                $token = Invoke-Login $null
                Write-Log "Re-login result: $(if ($token) { 'OK' } else { 'FAILED' })"
            }
        }
        $woke = Sleep-Smarter $IntervalSec
        if ($woke) {
            if (-not (Test-Internet)) {
                Write-Log "Internet dropped after wake. Re-authenticating immediately..."
                $redir = Get-RedirectUrl
                $token = Invoke-Login $redir
            }
        }
    } else {
        Write-Log "Connection dropped. Re-authenticating..."
        $redir = Get-RedirectUrl
        $token = Invoke-Login $redir
        if (Test-Internet) {
            $failCount = 0
            Write-Log "Re-connected successfully."
            $woke = Sleep-Smarter $IntervalSec
            if ($woke) {
                if (-not (Test-Internet)) {
                    Write-Log "Internet dropped after wake. Re-authenticating immediately..."
                    $redir = Get-RedirectUrl
                    $token = Invoke-Login $redir
                }
            }
        } else {
            # Shared account on every lab PC: fast retries get it locked out at the portal, so back off
            $failCount++
            $wait = if ($script:lastRejected) { 900 } else { [Math]::Min(30 * [Math]::Pow(2, $failCount - 1), 900) }
            if ($script:lastRejected) { Write-Log "Portal rejected the user/password (wrong or locked, ${failCount}x). Pausing ${wait}s so the account is not locked out - fix net-auth.env on Server 72." }
            else { Write-Log "Re-connection attempt failed (${failCount}x). Retrying in ${wait}s..." }
            if (Sync-FromDeployShare) {
                Write-Log "Update detected from Server 72 while offline. Restarting..."
                exit 0
            }
            [void](Sleep-Smarter ([int]$wait))
        }
    }
}
