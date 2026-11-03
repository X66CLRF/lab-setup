<#
  lab-check.ps1 - one-click health check for a lab / service-room PC. READ-ONLY: changes nothing on the PC.
  PASS = ready to use. FAIL = which flash-drive button fixes it.
    .\lab-check.ps1             check now (window)
    .\lab-check.ps1 -Install    also check at every logon, silently; a popup appears ONLY when something fails
    .\lab-check.ps1 -Uninstall  remove the logon check
    .\lab-check.ps1 -Quiet      (used by the logon check) no window, popup on failure only
#>
param([switch]$Install, [switch]$Uninstall, [switch]$Quiet)
$ErrorActionPreference = 'SilentlyContinue'

$dataDir = Join-Path $env:ProgramData 'LabDeploy'
$localCopy = Join-Path $dataDir 'lab-check.ps1'
$lnk = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\NSRU-Lab-Check.lnk'

if ($Install -or $Uninstall) {
    $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" $(if ($Install) { '-Install' } else { '-Uninstall' })" -Verb RunAs
        exit
    }
    if ($Uninstall) { Remove-Item $lnk, $localCopy -Force; Write-Host 'Logon check removed.' -ForegroundColor Green; exit }
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
    if ($PSCommandPath -ne $localCopy) { Copy-Item $PSCommandPath $localCopy -Force }
    $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $sh.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sh.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localCopy`" -Quiet"
    $sh.WindowStyle = 7
    $sh.Save()
    Write-Host 'Logon check installed: every logon is checked silently, a popup appears only on a problem.' -ForegroundColor Green
    Write-Host 'Running the check once now:' -ForegroundColor Cyan
}

if ($Quiet) { Start-Sleep -Seconds 25 }   # let the network come up after logon

$results = New-Object Collections.Generic.List[object]
function Add-Result($name, $state, $detail, $fix) {
    $results.Add([pscustomobject]@{ Name = $name; State = $state; Detail = $detail; Fix = $fix })
}

# 1. Network adapter / cable
$nics = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
$nic = ($nics | Where-Object MediaType -eq '802.3' | Select-Object -First 1)
if (-not $nic) { $nic = $nics | Select-Object -First 1 }
if ($nic) { Add-Result 'Network cable' 'PASS' "$($nic.Name) $($nic.LinkSpeed)" '' }
else { Add-Result 'Network cable' 'FAIL' 'no connected adapter' 'check the LAN cable / link light, then the room switch' }

# 2. IP address from DHCP
if ($nic) {
    $a = Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 | Select-Object -First 1
    $dhcp = (Get-NetIPInterface -InterfaceIndex $nic.ifIndex -AddressFamily IPv4).Dhcp
    if (-not $a -or $a.IPAddress -like '169.254*') {
        Add-Result 'IP address' 'FAIL' 'no address from DHCP (169.254)' 'several PCs too = room switch; one PC = button 7 (7-FIX-DHCP)'
    } elseif ($dhcp -eq 'Disabled') {
        Add-Result 'IP address' 'WARN' "$($a.IPAddress) is a fixed (temporary?) IP" 'if DHCP works again: 7-FIX-DHCP.cmd revert'
    } else { Add-Result 'IP address' 'PASS' "$($a.IPAddress)/$($a.PrefixLength) (DHCP)" '' }

    # 3. Gateway
    $gw = (Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex).IPv4DefaultGateway.NextHop
    if ($gw -and (Test-Connection $gw -Count 2 -Quiet)) { Add-Result 'Gateway' 'PASS' $gw '' }
    else { Add-Result 'Gateway' 'FAIL' "$(if ($gw) { "$gw no answer" } else { 'none' })" 'room switch / cable / VLAN - network team' }
}

# 4. DNS (campus name only the campus DNS knows)
$ip = ([Net.Dns]::GetHostAddresses('login.nsru.ac.th') | Where-Object AddressFamily -eq 'InterNetwork' | Select-Object -First 1).IPAddressToString
if ($ip) { Add-Result 'DNS' 'PASS' "login.nsru.ac.th = $ip" '' }
else { Add-Result 'DNS' 'FAIL' 'cannot resolve login.nsru.ac.th' 'button 6 (6-NET-RESET)' }

# 5. Internet / portal login
$code = & "$env:SystemRoot\System32\curl.exe" -s -m 6 -o NUL -w '%{http_code}' 'http://clients3.google.com/generate_204'
if ($code -eq '204') { Add-Result 'Internet' 'PASS' 'online' '' }
elseif ($code -and $code -ne '000') { Add-Result 'Internet' 'LOGIN' "portal answers (HTTP $code): log in once in the browser" 'open http://neverssl.com (button 5 opens it at every logon)' }
else { Add-Result 'Internet' 'FAIL' 'no answer' 'button 6 (6-NET-RESET)' }

# 6. Windows activation (campus KMS)
$act = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" | Select-Object -First 1
if ($act.LicenseStatus -eq 1) { Add-Result 'Windows activated' 'PASS' '' '' }
else { Add-Result 'Windows activated' 'WARN' "status $($act.LicenseStatus)" 'button 2 (lab setup) > Activate' }

# 7. Disk space
$c = Get-PSDrive C
$freeGb = [math]::Round($c.Free / 1GB, 1)
if ($freeGb -ge 10) { Add-Result 'Disk C: free' 'PASS' "$freeGb GB" '' }
else { Add-Result 'Disk C: free' 'WARN' "$freeGb GB left" 'button 2 (lab setup) > Cleanup (ask before deleting)' }

# 8. Clock (wrong time breaks https and the portal)
try {
    $hdr = & "$env:SystemRoot\System32\curl.exe" -s -m 6 -I 'http://clients3.google.com/generate_204' | Select-String '^Date:'
    if ($hdr) {
        $srv = [DateTime]::Parse(($hdr.Line -replace '^Date:\s*', '').Trim()).ToUniversalTime()
        $skew = [math]::Abs(((Get-Date).ToUniversalTime() - $srv).TotalMinutes)
        if ($skew -le 5) { Add-Result 'Clock' 'PASS' '' '' } else { Add-Result 'Clock' 'WARN' ("{0:N0} min off" -f $skew) 'Settings > Time > Sync now' }
    }
} catch {}

# Run from the flash drive: add this PC to pc-list.csv (name, MAC, IP) - the list the network team needs to exempt
# the room from the portal login (always-on internet without KeepAlive or shared passwords)
$here = Split-Path -Parent $PSCommandPath
if (-not $Quiet -and $nic -and $here -notlike "$env:ProgramData*") {
    $list = Join-Path $here 'pc-list.csv'
    $row = [pscustomobject]@{ PC = $env:COMPUTERNAME; MAC = $nic.MacAddress; IP = $a.IPAddress; Prefix = $a.PrefixLength; Gateway = $gw; Adapter = $nic.Name; Checked = (Get-Date -Format 's') }
    $old = if (Test-Path $list) { @(Import-Csv $list | Where-Object { $_.PC -ne $env:COMPUTERNAME }) } else { @() }
    @($old) + $row | Export-Csv $list -NoTypeInformation -Encoding UTF8
    Write-Host ("  recorded {0} {1} {2} in {3}" -f $row.PC, $row.MAC, $row.IP, $list) -ForegroundColor DarkGray
}

$bad = @($results | Where-Object State -eq 'FAIL')
$warn = @($results | Where-Object State -in 'WARN', 'LOGIN')

if ($Quiet) {
    if ($bad.Count) {
        $msg = ($bad + $warn | ForEach-Object { "- $($_.Name): $($_.Detail)`n    fix: $($_.Fix)" }) -join "`n"
        (New-Object -ComObject WScript.Shell).Popup("This PC has a problem:`n`n$msg`n`nFlash drive buttons: see README.txt", 0, 'NSRU Lab Check - FAIL', 48) | Out-Null
    }
    exit
}

Write-Host ''
foreach ($r in $results) {
    $color = switch ($r.State) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
    Write-Host ("  [{0,-5}] {1,-18} {2}" -f $r.State, $r.Name, $r.Detail) -ForegroundColor $color
    if ($r.Fix) { Write-Host ("            -> {0}" -f $r.Fix) -ForegroundColor DarkGray }
}
Write-Host ''
if ($bad.Count) { Write-Host '  RESULT: FAIL - fix the red lines (-> shows how)' -ForegroundColor Red }
elseif (@($results | Where-Object State -eq 'LOGIN').Count) { Write-Host '  RESULT: OK - just log in to the internet in the browser' -ForegroundColor Yellow }
else { Write-Host '  RESULT: PASS - this PC is ready' -ForegroundColor Green }
