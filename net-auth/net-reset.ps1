<#
  net-reset.ps1 - fix "no internet / login page never shows" on a lab PC, then open the campus login page.
  Run as Administrator (auto-elevates, window stays open). Steps:
    1. stop KeepAlive  2. show adapters + record the portal answer  3. reset proxy, DNS cache, hosts pin
       (never releases the IP; renews only an adapter stuck on 169.254)
    4. test gateway / DNS / portal port / internet  5. open the portal login page in Edge (exact portal URL, so Edge
       cannot upgrade it to https and skip the firewall)  6. optional deep reset (Winsock + TCP/IP, needs restart)
  A report is saved next to this script (flash drive) or on the Desktop.
#>
param([switch]$Deep)
$ErrorActionPreference = 'SilentlyContinue'

$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $a = "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Deep) { $a += ' -Deep' }
    Start-Process powershell.exe -ArgumentList $a -Verb RunAs
    exit
}

$portal = 'https://login.nsru.ac.th:1000'
$portalIp = '192.168.252.252'   # campus DNS answer for login.nsru.ac.th (2026-11-03)
$campusDns = @('192.168.10.3')  # what DHCP gives campus PCs
$outDir = Split-Path -Parent $PSCommandPath
if (-not (Test-Path $outDir) -or $outDir -like '\\*') { $outDir = [Environment]::GetFolderPath('Desktop') }
$report = Join-Path $outDir ("net-reset-{0}-{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $report | Out-Null
function Step($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }
function Show($ok, $t) { if ($ok) { Write-Host "  [OK]  $t" -ForegroundColor Green } else { Write-Host "  [!!]  $t" -ForegroundColor Red } }

function Show-Adapters {
    Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' } | ForEach-Object {
        $ip = ($_.IPv4Address | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join ', '
        $gw = ($_.IPv4DefaultGateway | ForEach-Object NextHop) -join ', '
        $dns = ($_.DNSServer | Where-Object AddressFamily -eq 2 | ForEach-Object ServerAddresses) -join ', '
        $dhcp = (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4).Dhcp
        Write-Host ("  {0}: IP {1}  GW {2}  DNS {3}  DHCP {4}" -f $_.InterfaceAlias, $ip, $(if ($gw) { $gw } else { '-' }), $(if ($dns) { $dns } else { '-' }), $dhcp)
        if ($ip -like '169.254*') { Write-Host '        169.254.x.x = no address from DHCP: check the LAN cable / switch port' -ForegroundColor Yellow }
    }
    $down = Get-NetAdapter -Physical | Where-Object Status -ne 'Up'
    foreach ($d in $down) { Write-Host ("  {0}: {1} (unplugged or disabled)" -f $d.Name, $d.Status) -ForegroundColor DarkGray }
}

Step '1. Stop KeepAlive (auto login)'
Disable-ScheduledTask -TaskName 'NSRU-KeepAlive' | Out-Null
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'node.exe' OR Name = 'wscript.exe'" | Where-Object {
    $_.CommandLine -like '*KeepAlive*' -or $_.CommandLine -like '*net-auth*launch.vbs*'
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Write-Host '  stopped (1-FIX-KEEPALIVE.cmd turns it back on)'

Step '2. Network adapters (before)'
Show-Adapters

# Record what the portal answers BEFORE any change (redirect target = the auth page Windows/Edge try to open)
Step '2b. Portal answer (before changes)'
$probe = & "$env:SystemRoot\System32\curl.exe" -s -m 6 -i 'http://clients3.google.com/generate_204' 2>&1 | Select-Object -First 12
if ($probe) { $probe | ForEach-Object { Write-Host "  | $_" } } else { Write-Host '  no answer from http://clients3.google.com (curl timeout)' -ForegroundColor Yellow }
if (($probe | Out-String) -match '(?i)https?://([^/:"''\s]+)(?::(\d+))?') {
    $rh = $matches[1]; $rp = if ($matches[2]) { [int]$matches[2] } else { 443 }
    $t = Test-NetConnection $rh -Port $rp -WarningAction SilentlyContinue
    Show $t.TcpTestSucceeded ("auth page host {0} ({1}) port {2} reachable" -f $rh, $t.RemoteAddress, $rp)
}

Step '3. Reset proxy, DNS (no IP release)'
netsh winhttp reset proxy | Out-Null
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0
Write-Host '  proxy: reset (WinHTTP + this user)'
$hostsLines = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }
if ($hostsLines) { Write-Host "  hosts file has entries (check they are wanted):" -ForegroundColor Yellow; $hostsLines | ForEach-Object { Write-Host "    $_" } }
# login.nsru.ac.th exists only on the campus DNS: a PC set to public DNS (8.8.8.8, 1.1.1.1 ...) still sees
# "action needed" from Windows but cannot open the auth page. Static adapters with public DNS -> campus DNS.
$publicDns = '8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1', '9.9.9.9', '208.67.222.222', '208.67.220.220'
foreach ($i in (Get-NetIPInterface -AddressFamily IPv4 -Dhcp Disabled | Where-Object { $_.ConnectionState -eq 'Connected' -and $_.InterfaceAlias -notlike 'Loopback*' })) {
    $cur = (Get-DnsClientServerAddress -InterfaceIndex $i.InterfaceIndex -AddressFamily IPv4).ServerAddresses
    if (-not $cur -or ($cur | Where-Object { $_ -in $publicDns })) {
        Set-DnsClientServerAddress -InterfaceIndex $i.InterfaceIndex -ServerAddresses $campusDns
        Write-Host "  $($i.InterfaceAlias): static DNS '$($cur -join ', ')' -> campus DNS $($campusDns -join ', ')" -ForegroundColor Yellow
    }
}
# Pin the portal name in hosts so the auth page opens whatever DNS the PC (or Edge secure DNS) uses
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$pin = "$portalIp login.nsru.ac.th  # NSRU campus login portal (net-reset.ps1)"
if (-not (Select-String -Path $hostsFile -Pattern '^\s*[0-9.]+\s+login\.nsru\.ac\.th\b' -Quiet)) {
    Add-Content -Path $hostsFile -Value "`r`n$pin" -Encoding ASCII
    Write-Host "  hosts: added $portalIp login.nsru.ac.th" -ForegroundColor Yellow
} else { Write-Host '  hosts: login.nsru.ac.th already pinned' }
ipconfig /flushdns | Out-Null
Write-Host '  DNS cache: flushed'
# Never "ipconfig /release": on the lab LAN a released lease may not come back (seen 2026-11-03: 10.115.12.20 -> 169.254).
# Renew only an adapter that has no usable address.
$noAddr = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '169.254*' -and $_.InterfaceAlias -notlike 'Loopback*' }
foreach ($n in $noAddr) {
    Write-Host "  $($n.InterfaceAlias): no address - asking DHCP (renew)..."
    ipconfig /renew "$($n.InterfaceAlias)" | Out-Null
}
Start-Sleep -Seconds 3

Step '4. Network adapters (after)'
Show-Adapters

Step '5. Tests'
$curl = "$env:SystemRoot\System32\curl.exe"
$gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop
Show ([bool]($gw -and (Test-Connection $gw -Count 2 -Quiet))) "gateway $gw answers ping"
$dnsOk = [bool](Resolve-DnsName login.nsru.ac.th -DnsOnly -QuickTimeout)
Show $dnsOk 'DNS server resolves login.nsru.ac.th (hosts pin covers it if not)'
$sysIp = ([Net.Dns]::GetHostAddresses('login.nsru.ac.th') | Where-Object AddressFamily -eq 'InterNetwork' | Select-Object -First 1).IPAddressToString
Show ($sysIp -eq $portalIp) "this PC finds login.nsru.ac.th at $sysIp"
$portOk = (Test-NetConnection login.nsru.ac.th -Port 1000 -WarningAction SilentlyContinue).TcpTestSucceeded
Show $portOk 'portal login.nsru.ac.th:1000 reachable'
$code = & $curl -s -m 6 -o NUL -w '%{http_code}' 'http://clients3.google.com/generate_204'
$online = $code -eq '204'
Show $online "internet (generate_204 -> HTTP $code)"

if ($online) {
    Write-Host "`nInternet works on this PC now." -ForegroundColor Green
} else {
    Step '6. Open the campus login page'
    # Same detection as KeepAlive: the portal answers plain http with its own login URL (redirect or script)
    $target = $null
    $head = & $curl -s -m 6 -i 'http://clients3.google.com/generate_204'
    $txt = ($head | Out-String)
    if ($txt -match '(?im)^Location:\s*(\S+)') { $target = $matches[1] }
    elseif ($txt -match 'window\.location\s*=\s*["'']([^"'']+)') { $target = $matches[1] }
    elseif ($txt -match '(https?://[^"''\s<>]*fgtauth[^"''\s<>]*)') { $target = $matches[1] }
    if ($target -and $target.StartsWith('/')) { $target = "$portal$target" }
    if (-not $target) { $target = "$portal/" }
    Write-Host "  login page: $target"
    if (-not $portOk) { Write-Host '  portal port 1000 is not reachable: the page may not load - check cable/VLAN or ask the network team' -ForegroundColor Yellow }
    Write-Host '  Certificate warning in Edge = click Advanced > Continue, then log in.' -ForegroundColor Yellow
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($edge) { Start-Process $edge -ArgumentList $target } else { Start-Process $target }
}

if (-not $Deep -and -not $online) {
    $ans = Read-Host "`nStill no login page / internet? Deep reset Winsock + TCP/IP (needs restart) [y/N]"
    $Deep = $ans -in 'y', 'Y'
}
if ($Deep) {
    Step 'Deep reset'
    netsh winsock reset | Out-Null
    netsh int ip reset | Out-Null
    Write-Host '  Winsock + TCP/IP reset. RESTART the PC, then run this again if needed.' -ForegroundColor Yellow
}

Stop-Transcript | Out-Null
Write-Host "`nReport saved: $report" -ForegroundColor Cyan
