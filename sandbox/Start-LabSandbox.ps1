# Start-LabSandbox.ps1 - run on the HOST (Windows 11 Pro). Opens a throwaway Windows Sandbox,
# mounts this repo read-only and runs sandbox\run-in-sandbox.ps1 inside it.
#   .\sandbox\Start-LabSandbox.ps1              # Dry: LAB_DRYRUN=1 for every task (changes nothing)
#   .\sandbox\Start-LabSandbox.ps1 -Mode Real   # real run inside the disposable sandbox (still no network)
#   .\sandbox\Start-LabSandbox.ps1 -Tasks Fonts,Tune
# The sandbox has networking disabled: no campus share, no KMS, no telemetry to libdesk.
param(
    [ValidateSet('Dry', 'Real')][string]$Mode = 'Dry',
    [string[]]$Tasks
)
$ErrorActionPreference = 'Stop'

$exe = Join-Path $env:windir 'System32\WindowsSandbox.exe'
if (-not (Test-Path $exe)) {
    Write-Host 'Windows Sandbox is not enabled. As Administrator run:' -ForegroundColor Yellow
    Write-Host '  Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All' -ForegroundColor Yellow
    Write-Host 'then reboot and run this script again.' -ForegroundColor Yellow
    exit 1
}

$repo = Split-Path $PSScriptRoot -Parent
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $HOME "LabSandboxResults\$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Esc([string]$s) { [Security.SecurityElement]::Escape($s) }

$args2 = "-Mode $Mode"
if ($Tasks) { $args2 += " -Tasks $($Tasks -join ',')" }
$cmd = "powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File C:\lab-src\sandbox\run-in-sandbox.ps1 $args2"

$wsb = @"
<Configuration>
  <VGpu>Disable</VGpu>
  <Networking>Disable</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$(Esc $repo)</HostFolder>
      <SandboxFolder>C:\lab-src</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$(Esc $out)</HostFolder>
      <SandboxFolder>C:\results</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>$(Esc $cmd)</Command>
  </LogonCommand>
</Configuration>
"@

$wsbPath = Join-Path $env:TEMP "LabSetup-$stamp.wsb"
[IO.File]::WriteAllText($wsbPath, $wsb, (New-Object Text.UTF8Encoding($false)))
Write-Host "Mode: $Mode   Results: $out" -ForegroundColor Cyan
Start-Process $wsbPath
Write-Host 'Sandbox starting. When the run ends read summary.md in the results folder, then close the sandbox (everything inside is discarded).'
