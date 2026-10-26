# collect-logs.ps1 - READ-ONLY diagnostics bundle for a lab PC (changes nothing, runs no lab task).
# Run in PowerShell (Administrator for scheduled-task details):  .\collect-logs.ps1
# Writes one text file to the Desktop; passwords, tokens and the labdeploy secret are masked. Send that file for review.
param([int]$Tail = 150, [string]$OutDir = [Environment]::GetFolderPath('Desktop'))
$ErrorActionPreference = 'SilentlyContinue'
$data = Join-Path $env:ProgramData 'LabDeploy'
$out  = Join-Path $OutDir ("lab-diag-{0}-{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$buf  = New-Object Collections.Generic.List[string]

function Mask([string]$s) {
    $s = $s -replace '(?i)(NSRU_PASS|PASS(WORD)?)\s*[=:]\s*\S+', '$1=***'
    $s = $s -replace '(?i)(token=)[0-9a-f]{6,}', '$1***'
    $s = $s -replace '(?i)(magic=)[0-9a-zA-Z]{6,}', '$1***'
    $s = $s -replace '(?i)(/pass:)\S+', '$1***'
    $s
}
function Section($t) { $buf.Add(''); $buf.Add("===== $t =====") }
function Add($o) { ($o | Out-String -Width 200).TrimEnd() -split "`r?`n" | ForEach-Object { $buf.Add((Mask $_)) } }
function Tail-File($p) {
    if (Test-Path $p) { $i = Get-Item $p; $buf.Add("[$p  $([int]($i.Length/1KB)) KB  modified $($i.LastWriteTime)]"); Get-Content $p -Tail $Tail -Encoding UTF8 | ForEach-Object { $buf.Add((Mask $_)) } }
    else { $buf.Add("[missing] $p") }
}

Section 'System'
Add ("{0}  {1}  user={2}  {3}" -f $env:COMPUTERNAME, (Get-Date), $env:USERNAME, [Environment]::OSVersion.VersionString)
Add ("PowerShell {0}" -f $PSVersionTable.PSVersion)
Add ("Admin: {0}" -f ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

Section 'Internet / portal'
$c = (Get-Command curl.exe).Source
if ($c) { Add ("generate_204 http code: " + (& $c -s -m 6 -w '%{http_code}' -o NUL 'http://clients3.google.com/generate_204')) }
Add (Test-NetConnection login.nsru.ac.th -Port 1000 -WarningAction SilentlyContinue | Select-Object ComputerName, RemoteAddress, TcpTestSucceeded)
Add (Test-NetConnection 192.168.0.72 -Port 445 -WarningAction SilentlyContinue | Select-Object ComputerName, TcpTestSucceeded)

Section 'KeepAlive engine / task / process'
$node = (Get-Command node.exe).Source
if (-not $node -and (Test-Path "$env:ProgramFiles\nodejs\node.exe")) { $node = "$env:ProgramFiles\nodejs\node.exe" }
Add ("node.exe: " + $(if ($node) { "$node  " + (& $node --version) } else { 'NOT FOUND' }))
foreach ($f in 'KeepAlive.ps1', 'KeepAlive.js', 'launch.vbs') {
    $p = Join-Path $data "net-auth\$f"
    Add ("{0}: {1}" -f $f, $(if (Test-Path $p) { "present  $((Get-Item $p).LastWriteTime)  sha256 $((Get-FileHash -LiteralPath $p).Hash.Substring(0,12))" } else { 'MISSING' }))
}
Add (Get-ScheduledTask -TaskName 'NSRU-KeepAlive' | Select-Object TaskName, State, @{n='Triggers';e={($_.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace 'MSFT_TaskTrigger|Trigger','' }) -join ','}})
Add (Get-ScheduledTaskInfo -TaskName 'NSRU-KeepAlive' | Select-Object LastRunTime, LastTaskResult, NextRunTime)
Add (Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'node.exe' OR Name = 'wscript.exe'" | Where-Object { $_.CommandLine -like '*KeepAlive*' } | Select-Object ProcessId, Name, CreationDate, @{n='Cmd';e={Mask $_.CommandLine}})
Section 'net-auth.env (password masked)'
$envf = Join-Path $data 'net-auth.env'
if (Test-Path $envf) { Get-Content $envf | ForEach-Object { $buf.Add((Mask $_)) } } else { $buf.Add('[missing]') }
Section "keepalive.log (last $Tail lines)"
Tail-File (Join-Path $data 'keepalive.log')

Section 'Other scheduled tasks'
Add (Get-ScheduledTask -TaskName 'Lab_AutoWake', 'Lab_AutoSleep', 'Lab_CrashWatcher' | Select-Object TaskName, State)

Section 'SPSS license path'
Add ("LSHOST (machine): " + [Environment]::GetEnvironmentVariable('LSHOST', 'Machine'))
Add (Test-NetConnection 192.168.0.72 -Port 5093 -WarningAction SilentlyContinue | Select-Object ComputerName, TcpTestSucceeded)
Add (Get-NetTCPConnection -RemotePort 5093 | Select-Object LocalAddress, RemoteAddress, State, OwningProcess)
Add (Get-NetUDPEndpoint | Where-Object LocalPort -eq 5093 | Select-Object LocalAddress, LocalPort, OwningProcess)
Get-ChildItem 'C:\Program Files\IBM', 'C:\Program Files (x86)\IBM' -Recurse -Filter 'spssprod.inf' | ForEach-Object { $buf.Add("[$($_.FullName)]"); Get-Content $_.FullName | ForEach-Object { $buf.Add((Mask $_)) } }
Add (Get-Process -Name '*forti*' | Select-Object Name, Id)

Section "lab.log (last $Tail lines)"
Tail-File (Join-Path $data 'lab.log')

[IO.File]::WriteAllLines($out, $buf, (New-Object Text.UTF8Encoding $true))
Write-Host "Done: $out" -ForegroundColor Green
Write-Host "Passwords/tokens are masked - skim the file once, then send it." -ForegroundColor Cyan
