# run-in-sandbox.ps1 - runs INSIDE Windows Sandbox (started by Start-LabSandbox.ps1).
# 1) parse-checks every .ps1  2) runs lab.ps1 once per task, non-interactive  3) writes summary.md
param(
    [ValidateSet('Dry', 'Real')][string]$Mode = 'Dry',
    [string[]]$Tasks
)
$ErrorActionPreference = 'Continue'
$src = 'C:\lab-src'
$work = 'C:\lab'
$res = 'C:\results'

if (-not $Tasks) {
    $Tasks = @('Cleanup','BrowserClean','RemoveApps','Tune','RevertTune','Install','Winget','Activate','LicenseCheck',
               'Fonts','Certs','WinRARTheme','Wallpaper','BrowserSearch','RevertBrowserSearch','SpssLicense','Check',
               'Unlock','AutoSleep','KeepAlive','CrashWatcher')
}

# the repo is mounted read-only: work on a copy
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
Copy-Item $src $work -Recurse -Force

# test config: never report to production libdesk, no host guard
$cfg = Get-Content (Join-Path $work 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$cfg.telemetryUrl = 'http://127.0.0.1:9/telemetry'
$cfg.allowedHostPattern = '.*'
$cfgTest = Join-Path $work 'config.test.json'
$cfg | ConvertTo-Json -Depth 30 | Set-Content -Path $cfgTest -Encoding UTF8

$rows = New-Object System.Collections.ArrayList

# ---- 1. parse check ----
Write-Host '== Parse check ==' -ForegroundColor Cyan
$parseLines = @()
Get-ChildItem $work -Recurse -Filter *.ps1 | ForEach-Object {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    $bom = (Get-Content $_.FullName -Encoding Byte -TotalCount 3) -join ','
    if ($errors -and $errors.Count -gt 0) {
        $parseLines += "FAIL  $($_.Name): $($errors.Count) error(s): $($errors[0].Message) (line $($errors[0].Extent.StartLineNumber))"
    } else {
        $parseLines += "ok    $($_.Name)  (first bytes: $bom)"
    }
}
$parseLines | ForEach-Object { Write-Host $_ }

# ---- 2. per-task run ----
$env:LAB_DRYRUN = if ($Mode -eq 'Dry') { '1' } else { '0' }
$env:LAB_YES = '1'
$env:LAB_CONFIG = $cfgTest
foreach ($t in $Tasks) {
    Write-Host "== Task: $t ($Mode) ==" -ForegroundColor Cyan
    $env:LAB_TASKS = $t
    $o = Join-Path $res "$t.out.txt"
    $e = Join-Path $res "$t.err.txt"
    $p = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $work 'lab.ps1') `
         -RedirectStandardOutput $o -RedirectStandardError $e -PassThru -WindowStyle Hidden
    $done = $p.WaitForExit(180000)
    if (-not $done) { try { $p.Kill() } catch {} }
    $code = if ($done) { $p.ExitCode } else { 'TIMEOUT' }
    $text = ''
    if (Test-Path $o) { $text += (Get-Content $o -Raw -Encoding UTF8) }
    if (Test-Path $e) { $text += (Get-Content $e -Raw -Encoding UTF8) }
    if (-not $text) { $text = '' }
    $dry = ([regex]::Matches($text, '\[dry\]')).Count
    $errHits = ([regex]::Matches($text, '(?im)^.*(exception|cannot be found|is not recognized|FAIL).*$')).Count
    $verdict = if ($code -eq 0 -and $errHits -eq 0) { 'OK' }
               elseif ($code -eq 2 -or $text -match 'connect share|Outside Campus|FAIL connect') { 'NEEDS-NETWORK' }
               else { 'CHECK' }
    Write-Host "   exit=$code dry-lines=$dry error-lines=$errHits -> $verdict"
    [void]$rows.Add([pscustomobject]@{ Task = $t; Exit = $code; DryLines = $dry; ErrorLines = $errHits; Verdict = $verdict })
}

# ---- 3. summary ----
$md = @()
$md += "# lab-setup sandbox run ($Mode) - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$md += ''
$md += '## Parse check'
$md += ''
$md += ($parseLines | ForEach-Object { "- $_" })
$md += ''
$md += '## Tasks'
$md += ''
$md += '| Task | Exit | [dry] lines | Error lines | Verdict |'
$md += '|---|---|---|---|---|'
foreach ($r in $rows) { $md += "| $($r.Task) | $($r.Exit) | $($r.DryLines) | $($r.ErrorLines) | $($r.Verdict) |" }
$md += ''
$md += 'NEEDS-NETWORK = the task needs the campus share/KMS (sandbox has no network) - test it on a real lab PC with LAB_DRYRUN=1 first.'
$md += 'CHECK = open <Task>.out.txt / <Task>.err.txt in this folder.'
$md | Set-Content -Path (Join-Path $res 'summary.md') -Encoding UTF8
Write-Host ''
Write-Host "Done. Summary: $res\summary.md" -ForegroundColor Green
