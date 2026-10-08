<#
  KeepAlive.ps1 - NSRU Campus LAN Internet KeepAlive Daemon
  Maintains FortiGate captive portal login in background.
  Uses built-in curl.exe (Windows 10/11) to eliminate Node.js requirement.
#>

param(
    [switch]$Once,
    [string]$Portal,
    [int]$IntervalSec = 90,
    [int]$StopHour = -1
)

$ErrorActionPreference = 'SilentlyContinue'

$dataDir = Join-Path $env:ProgramData 'LabDeploy'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
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

# 1. Resolve credentials from net-auth.env
$envCandidates = @(
    (Join-Path $dataDir 'net-auth.env'),
    '\\192.168.0.72\LabDeploy\net-auth.env',
    (Join-Path $PSScriptRoot 'net-auth.env')
)

$cfg = @{}
foreach ($cand in $envCandidates) {
    if (Test-Path $cand) {
        try {
            Get-Content $cand -Encoding UTF8 | ForEach-Object {
                $trimmed = $_.Trim()
                if ($trimmed -and -not $trimmed.StartsWith('#') -and $trimmed -match '^([^=]+)=(.*)$') {
                    $k = $matches[1].Trim().ToUpper()
                    $v = $matches[2].Trim()
                    $cfg[$k] = $v
                }
            }
            # Cache locally if read from share
            $localEnv = Join-Path $dataDir 'net-auth.env'
            if ($cand -ne $localEnv -and -not (Test-Path $localEnv)) {
                try {
                    Copy-Item $cand $localEnv -Force
                    icacls $localEnv /inheritance:r /grant:r 'Administrators:(F)' 'SYSTEM:(F)' | Out-Null
                } catch {}
            }
            break
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

$curl = (Get-Command 'curl.exe' -ErrorAction SilentlyContinue).Source
if (-not $curl) { $curl = "$env:SystemRoot\System32\curl.exe" }
if (-not (Test-Path $curl)) {
    Write-Log "FAIL: curl.exe not found at $curl"
    Exit 2
}

function Test-Internet {
    $status = & $curl -s -k -m 6 -w "%{http_code}" -o NUL "http://clients3.google.com/generate_204" 2>$null
    return ($status -eq '204')
}

function Get-RedirectUrl {
    $head = & $curl -s -k -m 6 -i "http://clients3.google.com/generate_204" 2>$null
    if ($head -match 'Location:\s*([^\r\n]+)') { return $matches[1].Trim() }
    if ($head -match 'window\.location\s*=\s*"([^"]+)"') { return $matches[1].Trim() }
    return $null
}

function Invoke-Login($redirTarget) {
    $targetPortal = $portalUrl
    $magicToken = ''
    $loginPage = "$portalUrl/"

    if ($redirTarget) {
        try {
            $loginPage = $redirTarget
            $uri = [Uri]$redirTarget
            $targetPortal = "$($uri.Scheme)://$($uri.Authority)"
            if ($uri.Query -match 'magic=([^&]+)') { $magicToken = $matches[1] }
            elseif ($uri.Query -match '^\?([0-9a-zA-Z]+)') { $magicToken = $matches[1] }
        } catch {}
    }

    $pageHtml = & $curl -s -k -m 8 "$loginPage" 2>$null
    $magic = if ($pageHtml -match 'name="?magic"?\s+value="([^"]+)"') { $matches[1] } else { $magicToken }
    $redir = if ($pageHtml -match 'name="?4Tredir"?\s+value="([^"]+)"') { $matches[1] } else { "$targetPortal/" }

    $postData = "4Tredir=$([Uri]::EscapeDataString($redir))&magic=$([Uri]::EscapeDataString($magic))&username=$([Uri]::EscapeDataString($user))&password=$([Uri]::EscapeDataString($pass))"
    $tmpPost = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($tmpPost, $postData, [Text.Encoding]::ASCII)
        $resp = & $curl -s -k -m 10 -d "@$tmpPost" "$targetPortal/" 2>$null
    } finally {
        Remove-Item $tmpPost -Force -ErrorAction SilentlyContinue
    }

    if ($resp -match 'keepalive\?([0-9a-fA-F]+)') { return $matches[1] }
    if ($resp -match 'logout\?([0-9a-fA-F]+)')    { return $matches[1] }
    return $null
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
    Exit (if (Test-Internet) { 0 } else { 1 })
}

# Daemon loop
while ($true) {
    if ($StopHour -ge 0) {
        $now = Get-Date
        if ($now.Hour -eq $StopHour) {
            Write-Log "Stop hour reached ($StopHour:00). Exiting daemon."
            if ($token) {
                & $curl -s -k -m 5 "$portalUrl/logout?$token" 2>$null | Out-Null
            }
            break
        }
    }

    Start-Sleep -Seconds $IntervalSec

    $isUp = Test-Internet
    if ($isUp) {
        if ($token) {
            $resp = & $curl -s -k -m 6 "$portalUrl/keepalive?$token" 2>$null
            if ($resp -match 'name="magic"' -and $resp -match 'type="password"') {
                Write-Log "Session expired. Re-authenticating..."
                $token = Invoke-Login $null
                Write-Log "Re-login result: $(if ($token) { 'OK' } else { 'FAILED' })"
            }
        }
    } else {
        Write-Log "Connection dropped. Re-authenticating..."
        $redir = Get-RedirectUrl
        $token = Invoke-Login $redir
        if (Test-Internet) {
            Write-Log "Re-connected successfully."
        } else {
            Write-Log "Re-connection attempt failed."
        }
    }
}
