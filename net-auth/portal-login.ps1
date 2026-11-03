<#
  portal-login.ps1 - open the campus FortiGate login page at Windows logon (manual login instead of KeepAlive).
  Run as Administrator (auto-elevates). Installs a hidden Startup launcher for all users: at logon it checks the
  internet and, when the PC is not logged in to the portal yet, opens Edge on the login page. Online = does nothing.
    .\portal-login.ps1                  stop KeepAlive + install the logon login page
    .\portal-login.ps1 -KeepKeepAlive   install the login page, leave KeepAlive as it is
    .\portal-login.ps1 -Remove          remove the logon login page (1-FIX-KEEPALIVE / update.ps1 turns KeepAlive back on)
#>
param([switch]$Remove, [switch]$KeepKeepAlive)
$ErrorActionPreference = 'SilentlyContinue'

$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $a = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Remove) { $a += ' -Remove' }
    if ($KeepKeepAlive) { $a += ' -KeepKeepAlive' }
    Start-Process powershell.exe -ArgumentList $a -Verb RunAs
    exit
}

$dataDir = Join-Path $env:ProgramData 'LabDeploy'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
$vbs = Join-Path $dataDir 'portal-open.vbs'
$lnk = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\NSRU-Portal-Login.lnk'
# Any plain-http URL is intercepted by the portal; this Microsoft one exists for captive-portal redirects
$loginUrl = 'http://www.msftconnecttest.com/redirect'

if ($Remove) {
    Remove-Item $lnk, $vbs -Force
    Write-Host 'Logon login page removed.' -ForegroundColor Green
    exit
}

if (-not $KeepKeepAlive) {
    Write-Host '1. Stopping KeepAlive (auto login)...' -ForegroundColor Cyan
    Disable-ScheduledTask -TaskName 'NSRU-KeepAlive' | Out-Null
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'node.exe' OR Name = 'wscript.exe'" | Where-Object {
        $_.CommandLine -like '*KeepAlive*' -or $_.CommandLine -like '*net-auth*launch.vbs*'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

Write-Host '2. Installing the logon login page...' -ForegroundColor Cyan
# login.nsru.ac.th resolves only on the campus DNS: pin it so the auth page opens on PCs set to public DNS
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
if (-not (Select-String -Path $hostsFile -Pattern '^\s*[0-9.]+\s+login\.nsru\.ac\.th\b' -Quiet)) {
    Add-Content -Path $hostsFile -Value "`r`n192.168.252.252 login.nsru.ac.th  # NSRU campus login portal (portal-login.ps1)" -Encoding ASCII
    ipconfig /flushdns | Out-Null
    Write-Host '   hosts: pinned login.nsru.ac.th -> 192.168.252.252' -ForegroundColor Green
}
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { $edge = 'msedge' }
# VBScript + MSXML: no console window flashes at logon. 204 = online; a portal answer or no answer = open the page.
$vbsText = @"
' NSRU: open the campus login page at logon when this PC is not logged in to the internet yet (from portal-login.ps1)
Set sh = CreateObject("WScript.Shell")
online = False
For i = 1 To 10
    answered = False
    On Error Resume Next
    Set x = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    x.setTimeouts 3000, 3000, 3000, 3000
    x.Open "GET", "http://clients3.google.com/generate_204", False
    x.Send
    If Err.Number = 0 Then
        answered = True
        If x.Status = 204 Then online = True
    End If
    Err.Clear
    On Error GoTo 0
    If answered Then Exit For
    WScript.Sleep 3000
Next
If Not online Then sh.Run """$edge"" $loginUrl", 1, False
"@
Set-Content -Path $vbs -Value $vbsText -Encoding ASCII
$sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sh.TargetPath = "$env:SystemRoot\System32\wscript.exe"
$sh.Arguments = "//B //Nologo `"$vbs`""
$sh.Save()

if ((Test-Path $lnk) -and (Test-Path $vbs)) {
    Write-Host "   OK: every user gets the login page at logon when the PC is offline" -ForegroundColor Green
    Write-Host '3. Opening it now (only if this PC is not logged in yet)...' -ForegroundColor Cyan
    Start-Process "$env:SystemRoot\System32\wscript.exe" -ArgumentList "//B //Nologo `"$vbs`""
} else {
    Write-Host "   FAIL: could not write $lnk or $vbs" -ForegroundColor Red
}
