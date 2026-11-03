<#
  dhcp-fix.ps1 - lab PC stuck on 169.254.x.x (no address from DHCP).
  Run as Administrator (auto-elevates, window stays open).
    1. DHCP Client service on + adapter back to DHCP + renew (waits up to 30s)
    2. still no address -> temporary static IP from REAL data only: this PC's last DHCP address (net-reset report)
       + the LAN settings (prefix, gateway, DNS) recorded by this tool on a PC in the same room where DHCP works.
       No record yet = it stops and says so (run it once on a working neighbour PC first). Nothing is guessed.
    Every run on a PC where DHCP works records that LAN to lan-profiles.csv on the flash drive.
    .\dhcp-fix.ps1 -Revert   back to automatic (DHCP) once the DHCP server works again
  Report saved next to this script (flash drive).
#>
param([switch]$Revert)
$ErrorActionPreference = 'SilentlyContinue'

$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $a = "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Revert) { $a += ' -Revert' }
    Start-Process powershell.exe -ArgumentList $a -Verb RunAs
    exit
}

$here = Split-Path -Parent $PSCommandPath
$report = Join-Path $here ("dhcp-fix-{0}-{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $report | Out-Null
function Step($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }
$profiles = Join-Path $here 'lan-profiles.csv'
function Net3($ip) { ($ip -split '\.')[0..2] -join '.' }
# true when $ip is inside the subnet $baseIp/$prefix (real prefix recorded from DHCP, e.g. /20 on campus Wi-Fi)
function In-Subnet($ip, $baseIp, [int]$prefix) {
    $toU = { param($x) $b = ([Net.IPAddress]$x).GetAddressBytes(); [Array]::Reverse($b); [BitConverter]::ToUInt32($b, 0) }
    $mask = if ($prefix -eq 0) { [uint32]0 } else { [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefix)) }
    ((& $toU $ip) -band $mask) -eq ((& $toU $baseIp) -band $mask)
}
function Save-LanProfile($nic) {
    $a = Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq 'Dhcp' } | Select-Object -First 1
    if (-not $a) { return }
    $c = Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex
    $row = [pscustomobject]@{ Net = (Net3 $a.IPAddress); Prefix = $a.PrefixLength; Gateway = $c.IPv4DefaultGateway.NextHop
        Dns = (($c.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses -join ' '); FromPC = $env:COMPUTERNAME; FromIP = $a.IPAddress; When = (Get-Date -Format 's') }
    $row | Export-Csv $profiles -NoTypeInformation -Append -Encoding UTF8
    Write-Host ("  recorded LAN {0}.x /{1} gw {2} dns {3} -> {4}" -f $row.Net, $row.Prefix, $row.Gateway, $row.Dns, $profiles) -ForegroundColor Green
}
function Get-IPv4($idx) {
    (Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object -First 1).IPAddress
}
function To-Dhcp($nic) {
    Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 | Where-Object PrefixOrigin -eq 'Manual' | Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' | Where-Object Protocol -eq 'NetMgmt' | Remove-NetRoute -Confirm:$false
    Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ResetServerAddresses
}

# Wired adapter first (the lab LAN), else any connected physical adapter
$nics = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
$nic = ($nics | Where-Object { $_.MediaType -eq '802.3' } | Select-Object -First 1)
if (-not $nic) { $nic = $nics | Select-Object -First 1 }
if (-not $nic) {
    Write-Host 'No connected network adapter: plug in the LAN cable (link light on?) and run again.' -ForegroundColor Red
    Stop-Transcript | Out-Null; return
}
Write-Host ("Adapter: {0} ({1})  MAC {2}" -f $nic.Name, $nic.InterfaceDescription, $nic.MacAddress)

if ($Revert) {
    Step 'Back to automatic (DHCP)'
    To-Dhcp $nic
    ipconfig /renew "$($nic.Name)" | Out-Null
    Write-Host ("  IP now: {0}" -f $(if ($ip = Get-IPv4 $nic.ifIndex) { $ip } else { 'none yet (169.254)' }))
    Stop-Transcript | Out-Null; return
}

Step '1. DHCP Client service + adapter on DHCP'
Set-Service Dhcp -StartupType Automatic
Start-Service Dhcp
Write-Host ("  DHCP Client service: {0}" -f (Get-Service Dhcp).Status)
$wasStatic = (Get-NetIPInterface -InterfaceIndex $nic.ifIndex -AddressFamily IPv4).Dhcp -eq 'Disabled'
if ($wasStatic) { Write-Host '  adapter was on a static IP -> switching to DHCP' -ForegroundColor Yellow; To-Dhcp $nic }

Step '2. Ask DHCP for an address (up to 30s)'
$ip = Get-IPv4 $nic.ifIndex
for ($i = 0; -not $ip -and $i -lt 3; $i++) {
    ipconfig /renew "$($nic.Name)" | Out-Null
    Start-Sleep -Seconds 8
    $ip = Get-IPv4 $nic.ifIndex
}

if ($ip) {
    Write-Host "  [OK] DHCP gave $ip" -ForegroundColor Green
    Save-LanProfile $nic
} else {
    Write-Host '  [!!] no answer from DHCP (still 169.254)' -ForegroundColor Red
    Write-Host '  DHCP client log (evidence for the network team):'
    Get-WinEvent -LogName 'Microsoft-Windows-Dhcp-Client/Admin' -MaxEvents 6 | ForEach-Object {
        Write-Host ("    {0:HH:mm:ss} [{1}] {2}" -f $_.TimeCreated, $_.Id, (($_.Message -split "`r?`n")[0])) }
    Step '3. Temporary static IP (real data only)'
    # Last good address of THIS PC from a net-reset report ("before" section), so it does not take another PC's address
    $last = $null
    Get-ChildItem $here -Filter "net-reset-$env:COMPUTERNAME-*.txt" | Sort-Object LastWriteTime -Descending | ForEach-Object {
        if (-not $last) {
            $m = Select-String -Path $_.FullName -Pattern 'IP (10\.\d+\.\d+\.\d+|172\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+)(?:/\d+)?\s+GW (\d+\.\d+\.\d+\.\d+)' | Select-Object -First 1
            if ($m) { $last = @{ IP = $m.Matches[0].Groups[1].Value; GW = $m.Matches[0].Groups[2].Value } }
        }
    }
    if (-not $last) {
        Write-Host "  No earlier address of $env:COMPUTERNAME on this flash drive (net-reset-$env:COMPUTERNAME-*.txt) - not guessing one." -ForegroundColor Yellow
        Write-Host '  Ask the network team for a free IP of this room, or fix DHCP (MAC above).'; Stop-Transcript | Out-Null; return
    }
    $lan = if (Test-Path $profiles) { Import-Csv $profiles | Where-Object { In-Subnet $last.IP $_.FromIP $_.Prefix } | Select-Object -Last 1 }
    if (-not $lan) {
        Write-Host ("  No recorded LAN settings that contain {0} yet - not guessing the mask." -f $last.IP) -ForegroundColor Yellow
        Write-Host '  Do this: plug this flash drive into a PC in the SAME room whose internet works, run 7-FIX-DHCP.cmd once'
        Write-Host '  (it only records the real LAN settings there), then come back and run 7-FIX-DHCP.cmd on this PC.'
        Stop-Transcript | Out-Null; return
    }
    $useIp = $last.IP; $useGw = $lan.Gateway; $usePrefix = [int]$lan.Prefix; $useDns = $lan.Dns -split ' '
    Write-Host ("  IP {0} = this PC's own DHCP address before the problem (report)" -f $useIp)
    Write-Host ("  /{0}, gateway {1}, DNS {2} = recorded on {3} ({4}) at {5}" -f $usePrefix, $useGw, $lan.Dns, $lan.FromPC, $lan.FromIP, $lan.When)
    $ok = Read-Host '  Use these? [Y/n]'
    if ($ok -in 'n', 'N') { Write-Host '  skipped.'; Stop-Transcript | Out-Null; return }
    # Someone else using it? (ARP/ping answer before we take it)
    $taken = Test-Connection $useIp -Count 1 -Quiet
    if (-not $taken) { $taken = [bool](Get-NetNeighbor -IPAddress $useIp | Where-Object { $_.State -in 'Reachable', 'Stale' -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' }) }
    if ($taken) { Write-Host "  [!!] $useIp is in use by another PC now - not taking it. Ask the network team for a free IP." -ForegroundColor Red; Stop-Transcript | Out-Null; return }
    Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
    New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $useIp -PrefixLength $usePrefix -DefaultGateway $useGw | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $useDns
    Start-Sleep -Seconds 3
    # Windows duplicate-address detection is the real conflict check (from 169.254 the ping above cannot reach the LAN)
    if ((Get-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $useIp).AddressState -eq 'Duplicate') {
        To-Dhcp $nic
        Write-Host "  [!!] Windows reports $useIp is already used by another PC - removed it, back to DHCP. Ask the network team for a free IP." -ForegroundColor Red
        Stop-Transcript | Out-Null; return
    }
    $ip = Get-IPv4 $nic.ifIndex
    Write-Host ("  static {0}/{1}  gateway {2}  DNS {3}" -f $ip, $usePrefix, $useGw, ($useDns -join ', ')) -ForegroundColor Yellow
    Write-Host '  TEMPORARY: when DHCP works again run 7-FIX-DHCP.cmd revert (else this IP may clash with another PC).' -ForegroundColor Yellow
}

Step '4. Tests'
$gw = (Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex).IPv4DefaultGateway.NextHop
$gwOk = $gw -and (Test-Connection $gw -Count 2 -Quiet)
Write-Host ("  gateway {0}: {1}" -f $gw, $(if ($gwOk) { 'OK' } else { 'no answer' })) -ForegroundColor $(if ($gwOk) { 'Green' } else { 'Red' })
$code = & "$env:SystemRoot\System32\curl.exe" -s -m 6 -o NUL -w '%{http_code}' 'http://clients3.google.com/generate_204'
if ($code -eq '204') {
    Write-Host '  internet: ONLINE' -ForegroundColor Green
} else {
    Write-Host "  internet: not logged in yet (HTTP $code) - opening the login page" -ForegroundColor Yellow
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($edge) { Start-Process $edge -ArgumentList 'http://neverssl.com' } else { Start-Process 'http://neverssl.com' }
}
if (-not $gwOk) { Write-Host '  Gateway does not answer: cable / switch port / VLAN problem - ask the network team (give them the MAC above).' -ForegroundColor Red }

Stop-Transcript | Out-Null
Write-Host "`nReport saved: $report" -ForegroundColor Cyan
