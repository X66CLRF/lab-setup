<#
  update.ps1 - 1-Click Update for NSRU-KeepAlive
  Run as Administrator (or will auto-elevate).
  Copies newest KeepAlive files to C:\ProgramData\LabDeploy\net-auth,
  ensures Node.js is installed or copied offline from USB/Share,
  re-registers the task with Parallel multiple instances and wake trigger,
  and tests login immediately.
#>

$ErrorActionPreference = 'SilentlyContinue'

# Auto-elevate to Administrator
$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$srcDir = Split-Path -Parent $PSCommandPath
$dataDir = Join-Path $env:ProgramData 'LabDeploy'
$netAuthDir = Join-Path $dataDir 'net-auth'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
if (-not (Test-Path $netAuthDir)) { New-Item -ItemType Directory -Force -Path $netAuthDir | Out-Null }

Write-Host "1. Stopping existing KeepAlive processes..." -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'node.exe' OR Name = 'wscript.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like '*KeepAlive*'
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Stop-ScheduledTask -TaskName 'NSRU-KeepAlive' -ErrorAction SilentlyContinue | Out-Null

Write-Host "2. Copying latest files..." -ForegroundColor Cyan
foreach ($f in 'KeepAlive.ps1', 'KeepAlive.js', 'launch.vbs') {
    $src = Join-Path $srcDir $f
    if (-not (Test-Path $src)) {
        $src = "\\192.168.0.72\LabDeploy\net-auth\$f"
    }
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $netAuthDir $f) -Force
        Write-Host "   + $f copied" -ForegroundColor Green
    } else {
        Write-Host "   ! missing $src" -ForegroundColor Red
    }
}

# Sync net-auth.env if available on share or source
$shareEnv = Join-Path $srcDir 'net-auth.env'
if (-not (Test-Path $shareEnv)) { $shareEnv = '\\192.168.0.72\LabDeploy\net-auth.env' }
$localEnv = Join-Path $dataDir 'net-auth.env'
if (Test-Path $shareEnv) {
    Copy-Item $shareEnv $localEnv -Force
    icacls $localEnv /inheritance:r /grant:r 'Administrators:(F)' 'SYSTEM:(F)' | Out-Null
    Write-Host "   + net-auth.env synced (Admins & SYSTEM only)" -ForegroundColor Green
}

# 3. Check / copy Node.js (offline from USB / Share / or winget)
$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node -and (Test-Path "$env:ProgramFiles\nodejs\node.exe")) { $node = "$env:ProgramFiles\nodejs\node.exe" }
if (-not $node -and (Test-Path (Join-Path $dataDir 'node.exe'))) { $node = (Join-Path $dataDir 'node.exe') }
if (-not $node -and (Test-Path (Join-Path $netAuthDir 'node.exe'))) { $node = (Join-Path $netAuthDir 'node.exe') }

if (-not $node) {
    # Check offline sources first (USB / Share)
    $offlineNodeCandidates = @(
        (Join-Path $srcDir 'node.exe'),
        (Join-Path $srcDir '..\tools\node.exe'),
        (Join-Path $srcDir 'tools\node.exe'),
        '\\192.168.0.72\LabDeploy\net-auth\node.exe'
    )
    foreach ($cand in $offlineNodeCandidates) {
        if (Test-Path $cand) {
            try {
                $targetNode = Join-Path $netAuthDir 'node.exe'
                Copy-Item $cand $targetNode -Force
                $node = $targetNode
                Write-Host "   + Copied portable node.exe from $cand" -ForegroundColor Green
                break
            } catch {}
        }
    }
}
if (-not $node) {
    Write-Host "   Installing Node.js LTS via winget..." -ForegroundColor Yellow
    winget install --id OpenJS.NodeJS.LTS -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    $node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
    if (-not $node -and (Test-Path "$env:ProgramFiles\nodejs\node.exe")) { $node = "$env:ProgramFiles\nodejs\node.exe" }
}
Write-Host "   Node.js: $(if ($node) { "OK ($node)" } else { "Not installed (will use curl.exe)" })" -ForegroundColor $(if ($node) { 'Green' } else { 'Yellow' })

Write-Host "4. Registering scheduled task 'NSRU-KeepAlive'..." -ForegroundColor Cyan
$taskName = 'NSRU-KeepAlive'
$vbsPath = Join-Path $netAuthDir 'launch.vbs'
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //Nologo `"$vbsPath`""
$trigStartup = New-ScheduledTaskTrigger -AtStartup
$trigLogon   = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances Parallel

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigStartup, $trigLogon) -Principal $principal -Settings $settings -Force | Out-Null

try {
    [xml]$taskXml = Export-ScheduledTask -TaskName $taskName
    $eventNode = $taskXml.CreateElement('EventTrigger', $taskXml.Task.Triggers.NamespaceURI)
    $enabledNode = $taskXml.CreateElement('Enabled', $taskXml.Task.Triggers.NamespaceURI)
    $enabledNode.InnerText = 'true'
    $eventNode.AppendChild($enabledNode) | Out-Null
    $subNode = $taskXml.CreateElement('Subscription', $taskXml.Task.Triggers.NamespaceURI)
    $subNode.InnerText = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-Power-Troubleshooter''] and (EventID=1)]]</Select></Query></QueryList>'
    $eventNode.AppendChild($subNode) | Out-Null
    $taskXml.Task.Triggers.AppendChild($eventNode) | Out-Null
    Register-ScheduledTask -TaskName $taskName -Xml $taskXml.OuterXml -Force | Out-Null
} catch {}

Write-Host "5. Starting task & testing login..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Test login once
$testPs = Join-Path $netAuthDir 'KeepAlive.ps1'
& powershell.exe -ExecutionPolicy Bypass -File $testPs -Once
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nSUCCESS: KeepAlive updated and internet is ONLINE!" -ForegroundColor Green
} else {
    Write-Host "`nFINISHED: KeepAlive task installed. Check keepalive.log if offline." -ForegroundColor Yellow
}
