# lab.ps1 - Lab PC setup (Windows 11 Pro)
# Run in PowerShell as Administrator (short bootstrap, verifies this file's SHA256):
#   irm x66clrf.github.io/lab-setup/go.txt | iex
# Direct:
#   irm https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.7/lab.ps1 | iex
# Dry run (list actions, change nothing):   $env:LAB_DRYRUN='1'; irm ... | iex
# Skip menu (comma list):                   $env:LAB_TASKS='Install,Fonts'; irm ... | iex
#   Tasks: Cleanup BrowserClean RemoveApps Tune RevertTune Install Winget Activate LicenseCheck Fonts Certs WinRARTheme Wallpaper BrowserSearch RevertBrowserSearch SpssLicense Check Unlock AutoSleep KeepAlive CrashWatcher
# Skip "type YES" before wiping data drives:  $env:LAB_YES='1'
# CrashWatcher auto-installs on launch when missing; opt out:  $env:LAB_NO_AUTO_CW='1'

# Folder of this script when run as a file (run.cmd on the share); empty for irm|iex
$LabScriptDir = if ($PSCommandPath) { Split-Path $PSCommandPath -Parent }

# Pin to main
$LabConfigUrl = 'https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.7/config.json'

function Invoke-LabSetup {
    $ErrorActionPreference = 'Stop'
    try {
        if ([Environment]::OSVersion.Platform -eq 'Win32NT') { chcp 65001 | Out-Null }
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        Set-ItemProperty -Path 'HKCU:\Console' -Name 'QuickEdit' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    } catch {}
    $dryRun = $env:LAB_DRYRUN -eq '1'
    # Menu groups: 5 clean organized categories
    $groups = [ordered]@{
        'Install Software (Office, SPSS, Share packages, Winget)'                       = @('Install', 'Winget')
        'Optimize & Clean (Cleanup, BrowserClean, RemoveApps, RemoveAI, Tune)'          = @('Optimize')
        'Diagnostics & Licenses (Network status, Windows/Office/SPSS KMS check & fix)'   = @('Diagnostics')
        'Lab Settings & Policies (Fonts, Certs, WinRAR theme, Wallpaper, Search, Stop Sign-In)' = @('Settings')
        'Background Automation (Auto Wake/Sleep, KeepAlive, LibDesk Crash Watcher)'     = @('Automation')
    }
    $subMenus = @{
        'Optimize' = @(
            @{ Task = 'Cleanup';             Label = 'Cleanup (ล้าง Downloads, ไดรฟ์ D: และ Temp)' },
            @{ Task = 'BrowserClean';        Label = 'BrowserClean (ล้างประวัติ/เซสชัน Chrome และ Edge)' },
            @{ Task = 'RemoveApps';          Label = 'RemoveApps (ถอนบล็อกแวร์/แอนตี้ไวรัสเถื่อนตาม config)' },
            @{ Task = 'RemoveAI';            Label = 'RemoveAI (ปิดและถอน Windows Copilot, Recall, AI Search, Click to Do)' },
            @{ Task = 'RevertRemoveAI';      Label = 'RevertRemoveAI (คืนสิทธิ์ให้ใช้งาน Copilot และ Windows AI ได้)' },
            @{ Task = 'Tune';                Label = 'Tune (เปิด High Performance + ปิด Visual Effects เร่งความเร็ว)' },
            @{ Task = 'RevertTune';          Label = 'RevertTune (คืนค่า Balanced Power + คืนค่า Visual Effects ปกติ)' }
        )
        'Diagnostics' = @(
            @{ Task = 'Check';               Label = 'Check Network (ตรวจสถานะเน็ต, VPN, KMS, พอร์ตแชร์ 445, SPSS)' },
            @{ Task = 'LicenseCheck';        Label = 'LicenseCheck (ตรวจและต่ออายุไลเซนส์ Windows, Office, SPSS ผ่าน KMS)' },
            @{ Task = 'SpssLicense';         Label = 'SpssLicense (ตั้งค่า IP ของ SPSS License Server)' }
        )
        'Settings' = @(
            @{ Task = 'Fonts';               Label = 'Fonts (ติดตั้งฟอนต์ไทย มรนว. ทุกผู้ใช้)' },
            @{ Task = 'Certs';               Label = 'Certs (ติดตั้งใบรับรองความปลอดภัย)' },
            @{ Task = 'WinRARTheme';         Label = 'WinRAR Theme (ติดตั้งธีม WinRAR)' },
            @{ Task = 'Wallpaper';           Label = 'Wallpaper (ตั้งค่า & ล็อกหน้าจอ / ปลดล็อก Wallpaper)' },
            @{ Task = 'BrowserSearch';       Label = 'BrowserSearch (ตั้งค่าค้นหาเริ่มต้น Google ในเบราว์เซอร์)' },
            @{ Task = 'RevertBrowserSearch'; Label = 'RevertBrowserSearch (ลบนโยบายค้นหา คืนสิทธิ์ให้เบราว์เซอร์เลือกเอง)' },
            @{ Task = 'StopSignIn';          Label = 'Stop Sign-In (บล็อก Microsoft Account + ปิดป๊อปอัป Office + ปิด Browser Sync)' },
            @{ Task = 'RevertStopSignIn';    Label = 'RevertStopSignIn (คืนสิทธิ์ให้ Sign-in บัญชีได้ตามปกติ)' }
        )
        'Automation' = @(
            @{ Task = 'AutoSleep';           Label = 'Auto Wake/Sleep (ตั้งเวลาเปิด-ปิดเครื่องอัตโนมัติ 08:20 / 16:40)' },
            @{ Task = 'KeepAlive';           Label = 'Campus Internet KeepAlive (ล็อกอินอินเทอร์เน็ตอัตโนมัติ)' },
            @{ Task = 'CrashWatcher';        Label = 'LibDesk Crash Watcher (เฝ้าระวังจอฟ้า/แอปแครช ส่ง LibDesk KPI)' }
        )
    }
    # --- admin check ---
    $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'ERROR: run PowerShell as Administrator.' -ForegroundColor Red; $global:LabExitCode = 1; return
    }

    $root = Join-Path $env:ProgramData 'LabDeploy'
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $logFile = Join-Path $root 'lab.log'
    function Log($msg, $color = 'Gray') {
        $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $msg
        Write-Host $line -ForegroundColor $color
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    }

    # config source: local file path > URL > default LabConfigUrl
    $cfgPath = if ($env:LAB_CONFIG -and (Test-Path $env:LAB_CONFIG)) { $env:LAB_CONFIG }
               elseif ($LabScriptDir -and (Test-Path (Join-Path $LabScriptDir 'config.json'))) { Join-Path $LabScriptDir 'config.json' }
    try {
        $cfg = if ($cfgPath) {
                   Log "config: $cfgPath"
                   Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
               } else {
                   $url = if ($env:LAB_CONFIG -and ($env:LAB_CONFIG -match '^https?://')) { $env:LAB_CONFIG } else { $LabConfigUrl }
                   Log "config: $url"
                   Invoke-RestMethod -Uri $url -UseBasicParsing
               }
    }
    catch { Log "FAIL load config: $($_.Exception.Message)" 'Red'; $global:LabExitCode = 1; return }

    # Telemetry to LibDesk (/computer-lab tab "จัดเครื่องเข้าห้อง") — non-blocking, guarded
    # Same helper text runs here AND is embedded into crash-watch.ps1 (single source).
    # Machine identity = hardwareId (BIOS serial > physical MAC > UUID), not COMPUTERNAME (names collide across campuses).
    # Auth = shared token in %ProgramData%\LabDeploy\telemetry.token (ACL SYSTEM + Administrators) or $env:LAB_TELEMETRY_TOKEN.
    # Never put the token in config.json (public on GitHub) or commit it. No token = nothing is sent.
    $LabTelemetryHelpers = @'
function Get-LabHardwareId {
    $junk = '^(0+|none|default string|to be filled by o\.e\.m\.|system serial number|chassis serial number|not specified|not applicable|invalid|123456789|o\.e\.m\.)$'
    try { $sn = [string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber } catch { $sn = '' }
    $sn = $sn.Trim()
    if ($sn -and $sn -notmatch $junk) {
        $clean = $sn -replace '[^A-Za-z0-9._-]', ''
        if ($clean.Length -ge 3) { return 'sn:' + $clean.Substring(0, [Math]::Min(96, $clean.Length)) }
    }
    try {
        $nic = Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=True' -ErrorAction Stop |
            Where-Object { $_.MACAddress } | Sort-Object @{ Expression = { -not $_.NetEnabled } }, Index | Select-Object -First 1
        if ($nic) { return 'mac:' + ($nic.MACAddress -replace '[^0-9A-Fa-f]', '').ToUpper() }
    } catch {}
    try { $uuid = [string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch { $uuid = '' }
    if ($uuid -and $uuid -notmatch '^[0F-]+$') { return 'uuid:' + $uuid }
    return $null
}
function Get-LabDomain {
    try { return [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Domain } catch { return $null }
}
function Get-LabTelemetryToken {
    $f = Join-Path $env:ProgramData 'LabDeploy\telemetry.token'
    if (Test-Path $f) { $t = [string](Get-Content $f -Raw -ErrorAction SilentlyContinue); if ($t.Trim()) { return $t.Trim() } }
    if ($env:LAB_TELEMETRY_TOKEN) { return $env:LAB_TELEMETRY_TOKEN.Trim() }
    return $null
}
# Failure reason of the last Send-LabEvent ($null = sent) so callers can show why a PC never shows up in LibDesk
$global:LabSendError = $null
function Send-LabEvent($url, $campus, $eventType, $title, $detail, $performedBy) {
    $token = Get-LabTelemetryToken
    $hw = Get-LabHardwareId
    if (-not $token) { $global:LabSendError = "no telemetry token ($env:ProgramData\LabDeploy\telemetry.token missing - share not connected at install)"; return $false }
    if (-not $hw) { $global:LabSendError = 'no hardware ID (BIOS serial / MAC / UUID unreadable)'; return $false }
    if ($detail) { $detail = [string]$detail; if ($detail.Length -gt 3500) { $detail = $detail.Substring(0, 3500) } }
    $body = [PSCustomObject]@{
        campus      = $campus
        machineCode = $env:COMPUTERNAME
        hardwareId  = $hw
        domain      = Get-LabDomain
        eventType   = $eventType
        title       = $title
        detail      = $detail
        performedBy = $performedBy
    } | ConvertTo-Json -Compress
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072  # TLS 1.2
        # bytes, not string: PS 5.1 sends string bodies as ISO-8859-1 and Thai titles arrive garbled
        Invoke-RestMethod -Uri $url -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8' -Headers @{ 'X-Lab-Token' = $token } -TimeoutSec 5 -UseBasicParsing | Out-Null
        $global:LabSendError = $null
        return $true
    } catch {
        $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        $msg = $_.Exception.Message  # inside switch $_ is the switch value
        $global:LabSendError = switch ($code) {
            401 { 'HTTP 401 - token rejected (telemetry.token differs from LAB_TELEMETRY_TOKEN on the server)' }
            403 { 'HTTP 403 - this network is not in LAB_TELEMETRY_ALLOW_CIDRS' }
            429 { 'HTTP 429 - too many reports, try again in 10 minutes' }
            0   { "network: $msg ($url)" }
            default { "HTTP $code from $url" }
        }
        return $false
    }
}
'@
    . ([ScriptBlock]::Create($LabTelemetryHelpers))

    # Store the token where the SYSTEM task can read it (admins only)
    function Save-LabTelemetryToken([string]$token) {
        $f = Join-Path $root 'telemetry.token'
        Set-Content -Path $f -Value $token.Trim() -Encoding ASCII -NoNewline
        & icacls $f /inheritance:r /grant:r '*S-1-5-18:R' '*S-1-5-32-544:F' | Out-Null
    }

    # Share is the source of truth for net-auth.env / telemetry.token: copy when missing OR changed on the share,
    # so a password/token changed once on Server 72 reaches every lab PC on its next KeepAlive/CrashWatcher run.
    # Returns $true when the local file exists afterwards (share unreachable = keep the local copy).
    function Sync-ShareFile([string]$src, [string]$dst, [string]$label) {
        if ($src -and (Test-Path $src)) {
            try {
                $same = (Test-Path $dst) -and ((Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash)
                if (-not $same) {
                    if ($dryRun) { Log "  [dry] update $label from Server 72" }
                    else {
                        Copy-Item $src $dst -Force -ErrorAction Stop
                        & icacls $dst /inheritance:r /grant:r 'Administrators:(F)' 'SYSTEM:(F)' | Out-Null
                        Log "$label updated from Server 72 -> $dst (Admins & SYSTEM only)" 'Green'
                    }
                }
            } catch { Log "FAIL copy $label from share: $($_.Exception.Message)" 'Yellow' }
        } elseif (Test-Path $dst) {
            Log "[i] $label not reachable on Server 72 - keeping local copy" 'DarkGray'
        } else {
            Log "[i] $label not found on Server 72 ($src). Check: cmdkey /list (labdeploy for $shareHost), port 445, or 'net use * /delete' if connected as another user." 'Yellow'
        }
        return (Test-Path $dst)
    }

    function Send-LabTelemetry($eventType, $title, $detail = $null) {
        try {
            $telemetryUrl = if ($cfg -and $cfg.telemetryUrl) { $cfg.telemetryUrl }
                            elseif ($env:LAB_TELEMETRY_URL) { $env:LAB_TELEMETRY_URL }
                            else { "https://libdesk.nsru.ac.th/api/computer-lab/telemetry" }
            $camp = if ($cfg -and $cfg.campus) { $cfg.campus } else { "city" }
            $sent = Send-LabEvent $telemetryUrl $camp $eventType $title $detail $env:USERNAME
            if ($sent) { Log "LibDesk: report sent ($env:COMPUTERNAME)" 'DarkGray' }
            else { Log "LibDesk: report NOT sent - $global:LabSendError" 'Yellow' }
            $sent
        } catch { $false }
    }

    # --- safety guard: only lab machines (skip if wildcard or not set) ---
    if ($cfg.allowedHostPattern -and $cfg.allowedHostPattern -ne '.*' -and ($env:COMPUTERNAME -notmatch $cfg.allowedHostPattern)) {
        Log "STOP: $env:COMPUTERNAME not match allowedHostPattern '$($cfg.allowedHostPattern)'" 'Red'; $global:LabExitCode = 1; return
    }

    function Parse-IndexList($inputStr, $maxCount) {
        if (-not $inputStr -or $inputStr.Trim() -eq '' -or $inputStr.Trim() -eq '0') { return 1..$maxCount }
        $indices = [System.Collections.Generic.List[int]]::new()
        $parts = $inputStr -split '[,\s]+' | Where-Object { $_ }
        foreach ($part in $parts) {
            if ($part -match '^(\d+)-(\d+)$') {
                $start = [int]$matches[1]; $end = [int]$matches[2]
                if ($start -le $end) {
                    foreach ($idx in $start..$end) {
                        if ($idx -ge 1 -and $idx -le $maxCount -and -not $indices.Contains($idx)) { $indices.Add($idx) }
                    }
                }
            } elseif ($part -match '^\d+$') {
                $idx = [int]$part
                if ($idx -ge 1 -and $idx -le $maxCount -and -not $indices.Contains($idx)) { $indices.Add($idx) }
            }
        }
        return $indices
    }

    function Read-Pick($items, $title) {
        # returns selected task strings; Enter/0 = default all (revert tasks excluded unless chosen); B = back
        Write-Host "`n--- $title ---" -ForegroundColor Cyan
        for ($i = 0; $i -lt $items.Count; $i++) {
            $lbl = if ($items[$i] -is [hashtable] -and $items[$i].Label) { $items[$i].Label }
                   elseif ($items[$i].PSObject.Properties['Label']) { $items[$i].Label }
                   else { $items[$i] }
            Write-Host ("  [{0}] {1}" -f ($i + 1), $lbl)
        }
        Write-Host '  [B] Back to main menu' -ForegroundColor DarkGray
        $s = Read-Host 'Choose (e.g. 1,3,5 or 1-3 / Enter = default all / B = back)'
        if ($s -eq 'b' -or $s -eq 'B') { return $null }
        $selectedItems = if ($s -notmatch '\d') {
            # Enter = select standard tasks, exclude Revert tasks so hitting Enter does not accidentally undo
            $items | Where-Object {
                $t = if ($_ -is [hashtable] -and $_.Task) { $_.Task } elseif ($_.PSObject.Properties['Task']) { $_.Task } else { $_ }
                $t -notmatch '^Revert'
            }
        } else {
            $indices = Parse-IndexList $s $items.Count
            if ($indices.Count -eq 0) { return $null }
            $indices | ForEach-Object { $items[$_ - 1] }
        }
        return @($selectedItems | ForEach-Object {
            if ($_ -is [hashtable] -and $_.Task) { $_.Task }
            elseif ($_.PSObject.Properties['Task']) { $_.Task }
            else { $_ }
        })
    }

    # --- helpers ---
    function Get-UserHives {
        # Returns @{ Name; Key (HKU path); Unload (temp key or $null) } for every real profile + Default
        $list = @()
        $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
            Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-' }   # local/AD + Entra ID accounts
        $i = 0
        foreach ($p in $profiles) {
            $sid  = $p.PSChildName
            $path = (Get-ItemProperty $p.PSPath).ProfileImagePath
            $name = Split-Path $path -Leaf
            if ($cfg.excludeProfiles -contains $name) { continue }
            if (Test-Path "Registry::HKEY_USERS\$sid") {
                $list += @{ Name = $name; Key = "Registry::HKEY_USERS\$sid"; Unload = $null }
            } elseif (Test-Path "$path\NTUSER.DAT") {
                $tmp = "LabTmp$i"; $i++
                reg.exe load "HKU\$tmp" "$path\NTUSER.DAT" | Out-Null
                if ($LASTEXITCODE -eq 0) { $list += @{ Name = $name; Key = "Registry::HKEY_USERS\$tmp"; Unload = $tmp } }
            }
        }
        reg.exe load 'HKU\LabDefault' "$env:SystemDrive\Users\Default\NTUSER.DAT" | Out-Null
        if ($LASTEXITCODE -eq 0) { $list += @{ Name = '(Default)'; Key = 'Registry::HKEY_USERS\LabDefault'; Unload = 'LabDefault' } }
        return $list
    }
    function Close-UserHives($hives) {
        [gc]::Collect(); Start-Sleep -Milliseconds 500
        foreach ($h in $hives) { if ($h.Unload) { reg.exe unload "HKU\$($h.Unload)" | Out-Null } }
    }
    function Set-Reg($key, $name, $value, $type) {
        if ($dryRun) { Log "  [dry] $key\$name = $value"; return }
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name $name -Value $value -PropertyType $type -Force | Out-Null
    }
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    function Remove-Path($p) {
        if ($dryRun) { Log "  [dry] recycle $p"; return }
        try {
            if (Test-Path -LiteralPath $p -PathType Container) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
            Log "  moved to recycle bin: $p"
        } catch {
            try {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                Log "  deleted $p"
            } catch {
                Log "  FAIL $p : $($_.Exception.Message)" 'Yellow'
            }
        }
    }
    function Clear-Tree($dir, $exclusions) {
        # Delete contents of $dir, keep excluded paths (and their parents)
        foreach ($item in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue) {
            $full = $item.FullName.TrimEnd('\')
            if ($exclusions | Where-Object { $_ -ieq $full }) { Log "  keep $full"; continue }
            $fullPrefix = $full + '\'
            if ($exclusions | Where-Object { $_.StartsWith($fullPrefix, [System.StringComparison]::OrdinalIgnoreCase) }) { Clear-Tree $full $exclusions; continue }
            Remove-Path $full
        }
    }
    function Get-Installed($pattern) {
        $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pattern }
    }
    function Get-SpssDirs {
        $dirs = [System.Collections.Generic.List[string]]::new()
        $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object {
            ($_.DisplayName -like '*SPSS*' -or $_.DisplayName -like '*Amos*') -and $_.InstallLocation
        } | ForEach-Object {
            $p = $_.InstallLocation.Trim().TrimEnd('\')
            if ((Test-Path $p) -and -not $dirs.Contains($p)) { $dirs.Add($p) }
        }
        $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path "$_\IBM") } | ForEach-Object { "$_\IBM" }
        foreach ($r in $roots) {
            Get-ChildItem $r -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
                (Test-Path (Join-Path $_.FullName 'stats.exe')) -or
                (Test-Path (Join-Path $_.FullName 'spss.exe')) -or
                (Test-Path (Join-Path $_.FullName 'law.exe')) -or
                (Test-Path (Join-Path $_.FullName 'Amos.exe')) -or
                (Test-Path (Join-Path $_.FullName 'spssprod.inf')) -or
                (Test-Path (Join-Path $_.FullName 'lservrc')) -or
                (Test-Path (Join-Path $_.FullName 'lopts'))
            } | ForEach-Object {
                if (-not $dirs.Contains($_.FullName)) { $dirs.Add($_.FullName) }
            }
        }
        return @($dirs)
    }
    function Set-SpssLicense($targetDirs, $licenseServer) {
        if (-not $licenseServer) { return }
        if (-not $dryRun) {
            [Environment]::SetEnvironmentVariable('LSHOST', $licenseServer, 'Machine')
            $env:LSHOST = $licenseServer
        }
        Log "  LSHOST System Environment = $licenseServer" 'Green'
        foreach ($d in $targetDirs) {
            if (-not (Test-Path $d)) { continue }
            $lshostFile = Join-Path $d 'lshost'
            if (-not $dryRun) { Set-Content -Path $lshostFile -Value $licenseServer -Encoding ASCII }
            Log "  $lshostFile -> $licenseServer" 'Green'
            $infFile = Join-Path $d 'spssprod.inf'
            if (Test-Path $infFile) {
                $txt = Get-Content $infFile
                $new = $txt | ForEach-Object {
                    if ($_ -match '^\s*DaemonHost\s*=') { "DaemonHost=$licenseServer" }
                    elseif ($_ -match '^\s*LicenseType\s*=') { 'LicenseType=Network' }
                    else { $_ }
                }
                if (-not ($new -match '^DaemonHost=')) { $new += "DaemonHost=$licenseServer" }
                if (-not ($new -match '^LicenseType=')) { $new += 'LicenseType=Network' }
                if (-not $dryRun) { Set-Content -Path $infFile -Value $new -Encoding ASCII }
            } else {
                $new = "[Product]`r`nDaemonHost=$licenseServer`r`nLicenseType=Network`r`n"
                if (-not $dryRun) { Set-Content -Path $infFile -Value $new -Encoding ASCII }
            }
            Log "  $infFile -> DaemonHost=$licenseServer" 'Green'
        }
        if (-not $dryRun) {
            Get-Process -Name 'law', 'echoid', 'licadmin' -ErrorAction SilentlyContinue | Stop-Process -Force
        }
    }
    function Set-WinRarLicense($sharePath, $localScriptDir) {
        $rarRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path "$_\WinRAR") } | ForEach-Object { "$_\WinRAR" }
        if (-not $rarRoots) { return }
        $candidates = @()
        if ($sharePath) {
            $candidates += (Join-Path $sharePath 'winrar\rarreg.key')
            $candidates += (Join-Path $sharePath 'rarreg.key')
        }
        if ($localScriptDir) {
            $candidates += (Join-Path $localScriptDir 'winrar\rarreg.key')
            $candidates += (Join-Path $localScriptDir 'rarreg.key')
        }
        $keySrc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if ($keySrc) {
            foreach ($rr in $rarRoots) {
                $dstKey = Join-Path $rr 'rarreg.key'
                if (-not (Test-Path $dstKey) -and -not $dryRun) {
                    Copy-Item $keySrc $dstKey -Force
                    Log "  Injected WinRAR key: $dstKey" 'Green'
                }
            }
        }
    }

    $interactive = -not $env:LAB_TASKS
    # Auto-install CrashWatcher on every launch when missing, so the PC reports itself to LibDesk
    # ("ยังไม่จัดกลุ่ม") without anyone picking it from the menu. Opt out: $env:LAB_NO_AUTO_CW='1'
    $cwAutoPending = $env:LAB_NO_AUTO_CW -ne '1' -and (
        -not (Get-ScheduledTask -TaskName 'Lab_CrashWatcher' -ErrorAction SilentlyContinue) -or
        -not (Test-Path (Join-Path $env:ProgramData 'LabDeploy\crash-watch.ps1')) -or
        -not (Test-Path (Join-Path $env:ProgramData 'LabDeploy\telemetry.token')))
    while ($true) {
        $global:LabExitCode = 0
        $tasks = @()
        $autoOfficeActivate = $false
        $cwAuto = $false
        if ($cwAutoPending -and $interactive) {
            # first pass: install CrashWatcher only, then the normal menu on the next pass
            $cwAutoPending = $false; $cwAuto = $true; $tasks = @('CrashWatcher')
            Log 'CrashWatcher not installed on this PC - installing automatically (reports to LibDesk).' 'Cyan'
        } elseif ($interactive) {
            Write-Host "`n=== Lab Setup ===" -ForegroundColor Cyan
            $tClient1 = New-Object Net.Sockets.TcpClient
            $ar1 = $tClient1.BeginConnect('192.168.10.111', 1688, $null, $null)
            $isCampusOk = $ar1.AsyncWaitHandle.WaitOne(600)
            $tClient1.Close()

            $tClient2 = New-Object Net.Sockets.TcpClient
            $ar2 = $tClient2.BeginConnect('192.168.0.72', 445, $null, $null)
            $isShareOk = $ar2.AsyncWaitHandle.WaitOne(600)
            $tClient2.Close()

            Write-Host "  Network: " -NoNewline -ForegroundColor DarkGray
            if ($isCampusOk) {
                Write-Host "NSRU Campus " -ForegroundColor Green -NoNewline
                if ($isShareOk) { Write-Host "(Wired LAN / Share OK)" -ForegroundColor Green }
                else { Write-Host "(Wi-Fi / Share port 445 restricted)" -ForegroundColor Yellow }
            } else {
                Write-Host "Outside Campus (VPN Needed for internal share)" -ForegroundColor Yellow
            }
            Write-Host ""

            $gNames = @($groups.Keys)
            for ($i = 0; $i -lt $gNames.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $gNames[$i]) }
            Write-Host '  [Q] Quit / Exit' -ForegroundColor DarkGray
            $pick = Read-Host 'Choose'
            if ($pick -eq 'q' -or $pick -eq 'Q') { break }
            if ($pick -notmatch '^\s*\d+\s*$' -or [int]$pick -lt 1 -or [int]$pick -gt $gNames.Count) { continue }
            $chosenGroup = $gNames[[int]$pick - 1]
            foreach ($t in $groups[$chosenGroup]) {
                if ($subMenus.ContainsKey($t)) {
                    $picked = Read-Pick $subMenus[$t] $chosenGroup
                    if ($null -eq $picked) { $tasks = @(); break }
                    $tasks += @($picked)
                } else { $tasks += $t }
            }
            if (-not $tasks) { continue }
        } else {
            $tasks = @($env:LAB_TASKS -split ',' | ForEach-Object { $_.Trim() })
            if ($cwAutoPending -and $tasks -notcontains 'CrashWatcher') { $tasks += 'CrashWatcher'; $cwAuto = $true }
        }
        $pickPackages = $interactive -and ($tasks -contains 'Install')
        Log "Tasks: $($tasks -join ', ')  DryRun: $dryRun" 'Cyan'

    # ============ Cleanup ============
    if ($tasks -contains 'Cleanup' -and $cfg.cleanup.enabled) {
        Log '== Cleanup ==' 'Cyan'
        $excl = @($cfg.cleanup.exclude | ForEach-Object { $_.TrimEnd('\') })
        Get-ChildItem "$env:SystemDrive\Users" -Directory | Where-Object {
            $_.Name -notin @('Public','Default','Default User','All Users') -and $cfg.excludeProfiles -notcontains $_.Name
        } | ForEach-Object {
            $dl = Join-Path $_.FullName 'Downloads'
            if (Test-Path $dl) { Log "Downloads: $dl"; Clear-Tree $dl $excl }
        }
        $sysSkip = '$RECYCLE.BIN','System Volume Information','pagefile.sys','swapfile.sys','hiberfil.sys'
        foreach ($d in $cfg.cleanup.drives) {
            $drive = "$($d.TrimEnd(':\')):"
            if ($drive -ieq $env:SystemDrive) { Log "SKIP $drive (system drive)" 'Yellow'; continue }
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'"
            if (-not $disk -or $disk.DriveType -ne 3) { Log "SKIP $drive (not fixed disk)" 'Yellow'; continue }
            Log "Drive: $drive"
            # confirm before wiping a whole drive (skip with $env:LAB_YES='1')
            if (-not $dryRun -and $env:LAB_YES -ne '1') {
                $ans = Read-Host "DELETE everything on $drive of $env:COMPUTERNAME (except exclude list)? type YES"
                if ($ans -cne 'YES') { Log "SKIP $drive (not confirmed)" 'Yellow'; continue }
            }
            $driveExcl = $excl + ($sysSkip | ForEach-Object { "$drive\$_" })
            Clear-Tree "$drive\" $driveExcl
        }
    }

    # ============ Desktop + per-user leftovers (part of Cleanup) ============
    if ($tasks -contains 'Cleanup') {
        $keepExt = @($cfg.cleanup.desktopKeep | ForEach-Object { $_.ToLower() })   # e.g. .lnk .url = shortcuts stay
        foreach ($u in Get-ChildItem "$env:SystemDrive\Users" -Directory | Where-Object {
                $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') -and $cfg.excludeProfiles -notcontains $_.Name }) {
            foreach ($desk in @("$($u.FullName)\Desktop") + @(Get-ChildItem $u.FullName -Directory -Filter 'OneDrive*' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)\Desktop" })) {
                if (-not (Test-Path $desk)) { continue }
                Log "Desktop: $desk (keep $($keepExt -join ' '))"
                foreach ($it in Get-ChildItem -LiteralPath $desk -Force -ErrorAction SilentlyContinue) {
                    if ($it.Name -eq 'desktop.ini' -or (-not $it.PSIsContainer -and $keepExt -contains $it.Extension.ToLower())) { continue }
                    Remove-Path $it.FullName
                }
            }
            $ut = "$($u.FullName)\AppData\Local\Temp"
            if (Test-Path $ut) { Get-ChildItem $ut -Force -ErrorAction SilentlyContinue | ForEach-Object { if (-not $dryRun) { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } } }
        }
        Log 'Cleanup finished: removed files are kept in Recycle Bin for safe recovery' 'Green'
    }

    # ============ BrowserClean: keep only the main profile, clear its private data ============
    if ($tasks -contains 'BrowserClean') {
        Log '== BrowserClean ==' 'Cyan'
        foreach ($pn in 'chrome', 'msedge') {
            if (Get-Process $pn -ErrorAction SilentlyContinue) {
                Log "  closing $pn" 'Yellow'
                if (-not $dryRun) { Stop-Process -Name $pn -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
            }
        }
        $private = 'Cookies', 'Network\Cookies', 'Login Data', 'Login Data For Account', 'History', 'Web Data',
                   'Top Sites', 'Visited Links', 'Sessions', 'Session Storage', 'Cache', 'Code Cache', 'GPUCache'
        foreach ($u in Get-ChildItem "$env:SystemDrive\Users" -Directory | Where-Object {
                $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') -and $cfg.excludeProfiles -notcontains $_.Name }) {
            foreach ($b in @(@{ n = 'Chrome'; p = "$($u.FullName)\AppData\Local\Google\Chrome\User Data" },
                             @{ n = 'Edge';   p = "$($u.FullName)\AppData\Local\Microsoft\Edge\User Data" })) {
                if (-not (Test-Path $b.p)) { continue }
                # 1. extra profiles (Profile 1, Profile 2, ...) -> delete; Default stays
                foreach ($x in Get-ChildItem $b.p -Directory | Where-Object Name -match '^Profile \d+$') {
                    Log "  $($u.Name) $($b.n): remove $($x.Name)"
                    Remove-Path $x.FullName
                }
                # 2. drop them from Local State so the profile picker does not show ghosts
                $ls = Join-Path $b.p 'Local State'
                if ((Test-Path $ls) -and -not $dryRun) {
                    try {
                        $j = Get-Content $ls -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($j.profile.info_cache) {
                            foreach ($k in @($j.profile.info_cache.PSObject.Properties.Name | Where-Object { $_ -ne 'Default' })) { $j.profile.info_cache.PSObject.Properties.Remove($k) }
                            $j.profile.last_used = 'Default'
                            if ($j.profile.PSObject.Properties['last_active_profiles']) { $j.profile.last_active_profiles = @('Default') }
                            Copy-Item $ls "$ls.bak" -Force
                            [IO.File]::WriteAllText($ls, ($j | ConvertTo-Json -Depth 100 -Compress), (New-Object Text.UTF8Encoding $false))
                        }
                    } catch { Log "  $($b.n) Local State not updated: $($_.Exception.Message)" 'Yellow' }
                }
                # 3. main profile: remove logins, cookies, history, sessions, cache (bookmarks/extensions kept)
                $def = Join-Path $b.p 'Default'
                if (Test-Path $def) {
                    Log "  $($u.Name) $($b.n): clear private data in Default"
                    foreach ($f in $private) { $t = Join-Path $def $f; if (Test-Path $t) { Remove-Path $t } }
                }
            }
        }
    }

    # ============ BrowserSearch: default search = Google (machine policy) ============
    if ($tasks -contains 'BrowserSearch') {
        Log '== BrowserSearch ==' 'Cyan'
        $g = @{
            DefaultSearchProviderEnabled    = 1
            DefaultSearchProviderName       = 'Google'
            DefaultSearchProviderKeyword    = 'google.com'
            DefaultSearchProviderSearchURL  = 'https://www.google.com/search?q={searchTerms}'
            DefaultSearchProviderSuggestURL = 'https://www.google.com/complete/search?output=chrome&q={searchTerms}'
        }
        foreach ($pol in 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge') {
            foreach ($k in $g.Keys) { Set-Reg $pol $k $g[$k] $(if ($g[$k] -is [int]) { 'DWord' } else { 'String' }) }
            Log "  policy set: $pol"
        }
        # Firefox honours enterprise policies on any PC
        $ffDir = "$env:ProgramFiles\Mozilla Firefox\distribution"
        if (Test-Path "$env:ProgramFiles\Mozilla Firefox\firefox.exe") {
            $pj = Join-Path $ffDir 'policies.json'
            if ((Test-Path $pj) -and -not (Select-String $pj -Pattern '"Default"\s*:\s*"Google"' -Quiet)) { Log "  Firefox: $pj exists - add SearchEngines.Default=Google manually" 'Yellow' }
            elseif (-not (Test-Path $pj) -and -not $dryRun) {
                New-Item -ItemType Directory -Force $ffDir | Out-Null
                [IO.File]::WriteAllText($pj, '{"policies":{"SearchEngines":{"Default":"Google"}}}', (New-Object Text.UTF8Encoding $false))
                Log '  Firefox policy set'
            }
        }
        if (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
            Log '  NOTE: PC is not domain-joined. Chrome/Edge may ignore search policies on unmanaged Windows - check chrome://policy and edge://policy' 'Yellow'
        }
    }


    # ============ StopSignIn (Block Microsoft Account, Office Sign-in, Browser Sync) ============
    if ($tasks -contains 'StopSignIn') {
        Log '== Stop Sign-In Policies ==' 'Cyan'
        # 1. Windows: Block Microsoft Accounts (cannot link personal MSA to Windows)
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'NoConnectedUser' 3 'DWord'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount' 'DisableUserAuth' 1 'DWord'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1 'DWord'
        Log '  Windows: Microsoft Accounts blocked (NoConnectedUser=3)' 'Green'

        # 2. Microsoft Office: Block Sign-in prompts & personal accounts
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\SignIn' 'SignInOptions' 3 'DWord'
        $hives = Get-UserHives
        try {
            foreach ($h in $hives) {
                Set-Reg "$($h.Key)\Software\Microsoft\Office\16.0\Common\SignIn" 'SignInOptions' 3 'DWord'
                Set-Reg "$($h.Key)\Software\Microsoft\Office\16.0\Common\General" 'ShownFirstRunOptin' 1 'DWord'
            }
        } finally { Close-UserHives $hives }
        Log '  Office: Sign-in modal & first-run prompt suppressed (SignInOptions=3)' 'Green'

        # 3. Browser: Disable account sync / sign-in on Chrome & Edge
        Set-Reg 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'BrowserSignin' 0 'DWord'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BrowserSignin' 0 'DWord'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SyncDisabled' 1 'DWord'
        Log '  Browsers: Chrome & Edge sign-in / sync disabled' 'Green'
        Log 'Stop Sign-In policies applied successfully.' 'Green'
    }

    # ============ RevertStopSignIn ============
    if ($tasks -contains 'RevertStopSignIn') {
        Log '== Revert Stop Sign-In Policies ==' 'Cyan'
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'NoConnectedUser' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount' -Name 'DisableUserAuth' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableConsumerAccountStateContent' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\SignIn' -Name 'SignInOptions' -ErrorAction SilentlyContinue
        $hives = Get-UserHives
        try {
            foreach ($h in $hives) {
                Remove-ItemProperty -Path "$($h.Key)\Software\Microsoft\Office\16.0\Common\SignIn" -Name 'SignInOptions' -ErrorAction SilentlyContinue
            }
        } finally { Close-UserHives $hives }
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name 'BrowserSignin' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'BrowserSignin' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'SyncDisabled' -ErrorAction SilentlyContinue
        Log 'Stop Sign-In policies reverted: users can sign in normally.' 'Green'
    }

    # ============ RevertBrowserSearch: remove search policies ============
    if ($tasks -contains 'RevertBrowserSearch') {
        Log '== Revert BrowserSearch (Remove policies) ==' 'Cyan'
        $searchKeys = 'DefaultSearchProviderEnabled','DefaultSearchProviderName','DefaultSearchProviderKeyword','DefaultSearchProviderSearchURL','DefaultSearchProviderSuggestURL'
        foreach ($pol in 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge') {
            if (Test-Path $pol) {
                foreach ($k in $searchKeys) {
                    if ((Get-ItemProperty $pol -ErrorAction SilentlyContinue).$k -ne $null) {
                        if ($dryRun) { Log "  [dry] remove $pol\$k" }
                        else { Remove-ItemProperty $pol -Name $k -ErrorAction SilentlyContinue }
                    }
                }
                Log "  policy removed: $pol"
            }
        }
        $ffDir = "$env:ProgramFiles\Mozilla Firefox\distribution"
        $pj = Join-Path $ffDir 'policies.json'
        if (Test-Path $pj) {
            if ($dryRun) { Log "  [dry] remove $pj" }
            else { Remove-Item $pj -Force -ErrorAction SilentlyContinue; Log '  Firefox policy removed' }
        }
        Log 'BrowserSearch reverted: policies removed (users can choose search engine freely)' 'Green'
    }

    # ============ RemoveApps ============
    if ($tasks -contains 'RemoveApps') {
        Log '== RemoveApps ==' 'Cyan'
        foreach ($pattern in $cfg.removeApps) {
            foreach ($app in Get-Installed $pattern) {
                Log "Found: $($app.DisplayName)"
                if ($dryRun) { Log '  [dry] uninstall'; continue }
                if ($app.QuietUninstallString) {
                    $cmd = $app.QuietUninstallString
                } elseif ($app.UninstallString -match 'msiexec' -and $app.PSChildName -match '^\{.+\}$') {
                    $cmd = "msiexec.exe /x $($app.PSChildName) /qn /norestart"
                } else {
                    Log "  MANUAL: no silent uninstall ($($app.UninstallString))" 'Yellow'; continue
                }
                $p = Start-Process cmd.exe -ArgumentList "/c $cmd" -Wait -PassThru -WindowStyle Hidden
                Log "  exit $($p.ExitCode)"
            }
        }
        # Appx bloat (Store apps)
        foreach ($pkg in $cfg.removeAppx) {
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $pkg | ForEach-Object {
                Log "Appx: $($_.DisplayName)"
                if (-not $dryRun) { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName | Out-Null }
            }
            Get-AppxPackage -AllUsers -Name $pkg | ForEach-Object {
                if (-not $dryRun) { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
            }
        }
    }

    # ============ Connect deploy share ============
    # Credential: stored once per machine by admin (never in code/config):
    #   cmdkey /add:<host> /user:<host>\labdeploy /pass
    # Fallback: Get-Credential prompt at runtime.
    $uncShare   = $cfg.deployShare.TrimEnd('\')
    $shareHost  = $uncShare.Split('\')[2]
    $share      = $uncShare
    $shareDrive = $null
    $shareOk    = $false
    $why        = $null  # reason the share failed, shown in the Install menu (reset per menu pass)
    $strictShareTasks = @($tasks | Where-Object { $_ -in 'Install', 'Wallpaper', 'Certs', 'WinRARTheme' })
    # Replace the stored share credential (same vault entry as cmdkey /add) without putting the password on a command line.
    # A stale entry keeps failing on every run and in Explorer and locks labdeploy for every lab PC (threshold 10).
    function Save-ShareCredential([string]$target, [pscredential]$cred) {
        try {
            if (-not ('LabCred.Native' -as [type])) {
                Add-Type -Namespace LabCred -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
    public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
}
[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CredWrite(ref CREDENTIAL cred, int flags);
'@
            }
            $pw = $cred.GetNetworkCredential().Password
            $c = New-Object LabCred.Native+CREDENTIAL
            $c.Type = 2; $c.Persist = 3; $c.TargetName = $target; $c.UserName = $cred.UserName  # 2 = domain password, 3 = enterprise (as cmdkey)
            $c.CredentialBlobSize = [Text.Encoding]::Unicode.GetByteCount($pw)
            $c.CredentialBlob = [Runtime.InteropServices.Marshal]::StringToCoTaskMemUni($pw)
            try { return [LabCred.Native]::CredWrite([ref]$c, 0) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($c.CredentialBlob) }
        } catch { return $false }
    }
    # soft = try the share, fall back quietly (Fonts -> GitHub; KeepAlive/CrashWatcher -> local copy of net-auth.env / telemetry.token)
    $fontTask = @($tasks | Where-Object { $_ -in 'Fonts', 'KeepAlive', 'CrashWatcher' })
    if ($strictShareTasks -or $fontTask) {
        # Fast socket check first (1.5s timeout) to prevent 45-second SMB freeze
        $tSock = New-Object Net.Sockets.TcpClient
        $ar = $tSock.BeginConnect($shareHost, 445, $null, $null)
        $portReachable = $ar.AsyncWaitHandle.WaitOne(1500)
        $tSock.Close()

        if (-not $portReachable) {
            if ($strictShareTasks) {
                Log "FAIL: cannot reach $shareHost port 445 (port 445 blocked on Wi-Fi - connect to wired lab LAN or VPN)" 'Red'
                $global:LabExitCode = 2
            } else {
                Log "[i] $shareHost port 445 unreachable (Wi-Fi/external). Using local copies / GitHub fallback." 'Yellow'
            }
        } elseif (Test-Path "$uncShare\manifest.json") {
            $shareOk = $true; Log "share OK: $uncShare (stored credential)"
        } else {
            if (@(cmdkey "/list:$shareHost" 2>$null) -match 'User:') {
                Log "Stored credential for $shareHost is wrong or outdated (labdeploy password changed?). Enter the new one - it replaces the stored one so this PC stops locking the account." 'Yellow'
            } else {
                Log "No stored credential for $shareHost. Tip: cmdkey /add:$shareHost /user:$shareHost\$($cfg.deployUser) /pass" 'Yellow'
            }
            # unattended run with only soft tasks: never block on a credential dialog
            # (interactive CrashWatcher auto-install asks too: without the share there is no token and the PC never reaches LibDesk)
            $cred = if ($strictShareTasks -or $interactive) { Get-Credential -UserName "$shareHost\$($cfg.deployUser)" -Message "Password for $uncShare" } else { $null }
            if (-not $cred) {
                if ($strictShareTasks) { Log 'FAIL: no credential given' 'Red'; $global:LabExitCode = 2 }
            } else {
                try {
                    $shareDrive = New-PSDrive -Name LabDeploy -PSProvider FileSystem -Root $uncShare -Credential $cred -ErrorAction Stop
                    $share = 'LabDeploy:'; $shareOk = $true; Log "share OK: $uncShare"
                    if (-not $dryRun) {
                        if (Save-ShareCredential $shareHost $cred) { Log "Saved $shareHost credential for next runs (replaces cmdkey entry)" 'Green' }
                        else { Log "Could not save credential - run: cmdkey /add:$shareHost /user:$($cred.UserName) /pass" 'Yellow' }
                    }
                } catch {
                    $m = $_.Exception.Message
                    $why = if ($m -match 'locked out') { 'account is locked out on server (ใส่รหัสผิดเกินจำนวนครั้ง บัญชี labdeploy ถูกล็อกที่ Server 72)' }
                           elseif ($m -match 'password|logon failure|user name') { 'wrong user name or password' }
                           elseif ($m -match 'denied') { 'access denied (account has no permission on share)' }
                           elseif ($m -match 'network path|network name') { 'share name not found' }
                           elseif ($m -match 'multiple connections') { 'already connected with another user (run: net use * /delete)' }
                           else { $m }
                    if ($strictShareTasks) { Log "FAIL connect share: $why" 'Red'; $global:LabExitCode = 2 }
                    else { Log "Notice connect share: $why" 'Yellow' }
                }
            }
        }
        if ($shareOk) { Sync-ShareFile (Join-Path $share 'telemetry.token') (Join-Path $root 'telemetry.token') 'telemetry.token' | Out-Null }
    }

    # ============ Install: read manifest + choose programs ============
    $pkgs = @(); $wingetSel = @($cfg.winget)
    if ($tasks -contains 'Install' -and $shareOk) {
        try { $manifest = Get-Content "$share\manifest.json" -Raw -Encoding UTF8 | ConvertFrom-Json; $pkgs = @($manifest.packages | Where-Object { $_ }) }
        catch { Log "FAIL read manifest.json: $($_.Exception.Message)" 'Red'; $global:LabExitCode = 3 }
    }
    if ($pickPackages) {
        # one list: share packages (with installed version) + winget apps
        $items = @()
        foreach ($p in $pkgs) {
            $iv = (Get-Installed $p.displayNameMatch | Select-Object -First 1).DisplayVersion
            $items += [pscustomobject]@{ Kind = 'pkg'; Ref = $p; Label = ("{0,-48} {1}" -f $p.name, $(if ($iv) { "installed $iv" } else { 'not installed' })) }
        }
        foreach ($id in $cfg.winget) {
            $items += [pscustomobject]@{ Kind = 'winget'; Ref = $id; Label = ("{0,-48} {1}" -f $id, 'winget (latest)') }
        }
        if (-not $shareOk) {
            Write-Host "  [!] ไม่สามารถเชื่อมต่อ Server 72 ($uncShare) ได้: $(if ($why) { $why } else { 'port 445 ถูกปิด หรือไม่ได้ใส่รหัส labdeploy' })" -ForegroundColor Red
            Write-Host "      โปรแกรมหลักจากแชร์ (Office, SPSS ฯลฯ) จะไม่แสดงในรายการ (แสดงเฉพาะ Winget)" -ForegroundColor Yellow
        }

        $selectionConfirmed = $false
        while (-not $selectionConfirmed) {
            Write-Host "`n--- Install Software (Silent Mode) ---" -ForegroundColor Cyan
            for ($i = 0; $i -lt $items.Count; $i++) {
                Write-Host ("  [{0}] {1}" -f ($i + 1), $items[$i].Label)
            }
            Write-Host '  [B] Back to main menu' -ForegroundColor DarkGray
            Write-Host 'Tip: Choose multiple via comma/range (e.g. 1,3,5 or 1-4 / Enter = all)' -ForegroundColor Gray
            $rawPick = Read-Host 'Choose programs'
            if ($rawPick -eq 'b' -or $rawPick -eq 'B') {
                Log 'Install cancelled: back to main menu.' 'Yellow'
                $tasks = @()
                break
            }
            $indices = Parse-IndexList $rawPick $items.Count
            if ($indices.Count -eq 0) {
                Write-Host 'No programs selected. Please try again.' -ForegroundColor Yellow
                continue
            }
            $chosenItems = @($indices | ForEach-Object { $items[$_ - 1] })
            Write-Host "`nSelected to install ($($chosenItems.Count) programs):" -ForegroundColor Green
            foreach ($ci in $chosenItems) {
                $nameStr = if ($ci.Kind -eq 'pkg') { $ci.Ref.name } else { $ci.Ref }
                Write-Host "  * $nameStr" -ForegroundColor White
            }
            Write-Host ''
            $confirm = Read-Host 'Press [Enter] to start silent install, [R] to re-select, [B] to cancel'
            if ($confirm -eq 'b' -or $confirm -eq 'B') {
                Log 'Install cancelled: back to main menu.' 'Yellow'
                $tasks = @()
                break
            }
            if ($confirm -eq 'r' -or $confirm -eq 'R') {
                continue
            }
            # Confirmed
            $sel = $chosenItems
            $pkgs      = @($sel | Where-Object Kind -eq 'pkg'    | ForEach-Object Ref)
            $wingetSel = @($sel | Where-Object Kind -eq 'winget' | ForEach-Object Ref)
            Log "Selected: $((@($pkgs | ForEach-Object name) + $wingetSel) -join ', ')"
            $selectionConfirmed = $true
        }
        if (-not $selectionConfirmed) { continue }
    }

    # ============ Install / Update ============
    if ($tasks -contains 'Install' -and $shareOk) {
        Log '== Install ==' 'Cyan'
        if ($pkgs.Count -eq 0) { Log 'Install: no share packages selected' }
        foreach ($pkg in $pkgs) {
            $tag = "[$($pkg.name)]"
            # guard: only run .exe/.msi installers (direct, or "run" inside a .zip); anything else is never executed
            $ext    = [IO.Path]::GetExtension([string]$pkg.file).ToLower()
            $runExt = if ($ext -eq '.zip') { [IO.Path]::GetExtension([string]$pkg.run).ToLower() } else { $ext }
            if (($pkg.type -and $pkg.type -ne 'installer') -or $runExt -notin '.exe', '.msi' -or
                ($ext -eq '.zip' -and ([string]$pkg.run -match '\.\.|^[\\/]|:'))) {
                Log "$tag SKIP not an installer (type='$($pkg.type)', file='$($pkg.file)', run='$($pkg.run)')" 'Yellow'; continue
            }
            # a. already installed?
            $found = @(Get-Installed $pkg.displayNameMatch)
            $cur = $found | Where-Object DisplayVersion |
                   Sort-Object { try { [version]$_.DisplayVersion } catch { [version]'0.0' } } -Descending | Select-Object -First 1
            $isAlreadyInstalled = $false
            if ($found -and -not $cur) {
                $isAlreadyInstalled = $true
                Log "$tag Already installed -> Skipping installer, checking license directly." 'Green'
            } elseif ($cur) {
                $upToDate = try { [version]$cur.DisplayVersion -ge [version]$pkg.version }
                            catch { [string]$cur.DisplayVersion -ge [string]$pkg.version }
                if ($upToDate) {
                    $isAlreadyInstalled = $true
                    Log "$tag Already installed ($($cur.DisplayVersion)) -> Skipping installer, checking license directly." 'Green'
                } else {
                    Log "$tag UPDATE $($cur.DisplayVersion) -> $($pkg.version)"
                }
            } else {
                Log "$tag INSTALL $($pkg.version)"
            }

            if ($isAlreadyInstalled) {
                # Auto-inject / check license directly for already-installed software!
                if ($pkg.name -like '*SPSS*' -or $pkg.displayNameMatch -like '*SPSS*' -or $pkg.name -like '*Amos*') {
                    Log "$tag Auto-injecting SPSS license config..." 'Cyan'
                    $sDirs = Get-SpssDirs
                    Set-SpssLicense $sDirs $cfg.spss.licenseServer
                    $isPing = Test-NetConnection $cfg.spss.licenseServer -Port 5093 -InformationLevel Quiet -WarningAction SilentlyContinue  # relay port, not ping
                    if ($isPing) {
                        Log "$tag License server ($($cfg.spss.licenseServer)) reachable: OK" 'Green'
                    } else {
                        Log "$tag [!] License server ($($cfg.spss.licenseServer)) unreachable!" 'Yellow'
                        Log "      -> Check SpssLicenseRelay on Server 72 (TCP/UDP 5093), or connect Fortinet SPSS VPN (gwspss.nsru.ac.th:10443)" 'Yellow'
                    }
                }
                elseif ($pkg.name -like '*Office*' -or $pkg.displayNameMatch -like '*Office*') {
                    Log "$tag Auto-running Office KMS verification..." 'Cyan'
                    $tasks += 'Activate'
                }
                elseif ($pkg.name -like '*WinRAR*') {
                    Set-WinRarLicense $share $LabScriptDir
                }
                continue
            }
            if ($dryRun) { continue }

            # b. copy to local temp (never run from UNC)
            $tmpDir = Join-Path $env:TEMP ("LabDeploy_" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
            $dst = Join-Path $tmpDir (Split-Path $pkg.file -Leaf)
            try {
                try { Copy-Item (Join-Path $share $pkg.file) $dst -Force -ErrorAction Stop }
                catch { Log "$tag FAIL copy: $($_.Exception.Message)" 'Red'; $global:LabExitCode = 4; continue }

                # c. verify SHA256
                $hash = (Get-FileHash $dst -Algorithm SHA256).Hash
                if ($hash -ine $pkg.sha256) { Log "$tag FAIL SHA256 mismatch (got $hash) - not run" 'Red'; $global:LabExitCode = 4; continue }

                # c2. zip: extract, then run "run" (relative path inside zip); working dir = extracted folder
                $workDir = $tmpDir
                if ($ext -eq '.zip') {
                    $workDir = Join-Path $tmpDir 'x'
                    Log "$tag unzip ($([math]::Round((Get-Item $dst).Length / 1GB, 1)) GB)..."
                    try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory($dst, $workDir) }
                    catch { Log "$tag FAIL unzip: $($_.Exception.Message)" 'Red'; $global:LabExitCode = 4; continue }
                    Remove-Item $dst -Force
                    $dst = Join-Path $workDir $pkg.run
                    if (-not (Test-Path -LiteralPath $dst)) { Log "$tag FAIL '$($pkg.run)' not found in zip" 'Red'; $global:LabExitCode = 4; continue }
                }

                # d. run (optional "notice": English instructions shown before an interactive installer)
                # optional "noticeFile": text on the share (e.g. license key) shown in the box + copied to clipboard
                $noticeText = $null
                if ($pkg.noticeFile) {
                    try { $noticeText = (Get-Content (Join-Path $share $pkg.noticeFile) -Raw -ErrorAction Stop).Trim() }
                    catch { Log "$tag noticeFile not readable: $($pkg.noticeFile)" 'Yellow' }
                }
                if ($pkg.notice -or $noticeText) {
                    Write-Host ''
                    Write-Host ('=' * 60) -ForegroundColor Yellow
                    Write-Host "  INFO - $($pkg.name)" -ForegroundColor Yellow
                    foreach ($ln in @($pkg.notice)) { if ($ln) { Write-Host "  $ln" -ForegroundColor Yellow } }
                    if ($noticeText) {
                        Write-Host ''
                        foreach ($ln in $noticeText -split "`r?`n") { Write-Host "    $ln" -ForegroundColor White }
                        try { Set-Clipboard -Value $noticeText; Write-Host '  (copied to clipboard)' -ForegroundColor Yellow } catch {}
                    }
                    Write-Host ('=' * 60) -ForegroundColor Yellow
                    Log "$tag notice noted"
                }
                $a = [string]$pkg.args
                if ($pkg.name -like '*SPSS*' -or $pkg.displayNameMatch -like '*SPSS*' -or $pkg.name -like '*Amos*') {
                    if ($a -notmatch 'LSHOST' -and $cfg.spss.licenseServer) {
                        $a = ($a + " LICENSETYPE=`"Network`" LSHOST=`"$($cfg.spss.licenseServer)`" ALLUSERS=1").Trim()
                    }
                }
                if ($dst -like '*.msi') {
                    if ($a -notmatch '/q[n|b|r|f]?' -and $a -notmatch '/quiet') {
                        $a = ($a + ' /qn /norestart').Trim()
                    }
                    Log "$tag Running silent MSI: msiexec.exe /i `"$dst`" $a"
                    $p = Start-Process msiexec.exe -ArgumentList "/i `"$dst`" $a" -WorkingDirectory $workDir -Wait -PassThru
                }
                elseif ($a) {
                    Log "$tag Running silent installer: $dst $a"
                    $p = Start-Process $dst -ArgumentList $a -WorkingDirectory $workDir -Wait -PassThru
                }
                else {
                    Log "$tag Running installer: $dst"
                    $p = Start-Process $dst -WorkingDirectory $workDir -Wait -PassThru
                }
                $code = $p.ExitCode
                if ($code -in 3010, 1641) { $needReboot = $true }
                if ($code -in 0, 3010, 1641) { Log "$tag OK exit $code" 'Green' }
                else { Log "$tag FAIL exit $code" 'Red'; $global:LabExitCode = 4; continue }

                # Kill law.exe if SPSS launched it
                if ($pkg.name -like '*SPSS*' -or $pkg.displayNameMatch -like '*SPSS*' -or $pkg.name -like '*Amos*') {
                    Start-Sleep -Seconds 1
                    Get-Process -Name 'law', 'echoid', 'licadmin' -ErrorAction SilentlyContinue | Stop-Process -Force
                }

                # e. postInstall (current dir = share root)
                if ($pkg.postInstall) {
                    $pp = Start-Process cmd.exe -ArgumentList "/c pushd `"$uncShare`" && $($pkg.postInstall)" -Wait -PassThru -WindowStyle Hidden
                    Log "$tag postInstall exit $($pp.ExitCode)" $(if ($pp.ExitCode -eq 0) { 'Green' } else { 'Yellow' })
                }
            } finally { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
        if ($needReboot) { Log 'REBOOT REQUIRED' 'Yellow' }

        # Auto-trigger post-install licensing / activation to save time
        $hasOffice = @($pkgs | Where-Object { $_.name -like '*Office*' -or $_.displayNameMatch -like '*Office*' }) + @($wingetSel | Where-Object { $_ -like '*Office*' })
        $hasSpss   = @($pkgs | Where-Object { $_.name -like '*SPSS*' -or $_.name -like '*Amos*' -or $_.displayNameMatch -like '*SPSS*' -or $_.displayNameMatch -like '*Amos*' })

        if ($hasSpss -and ($tasks -notcontains 'SpssLicense')) {
            Log "SPSS/Amos installed -> Auto-configuring SPSS license server ($($cfg.spss.licenseServer))..." 'Cyan'
            $tasks += 'SpssLicense'
        }
        if ($hasOffice) {
            $autoOfficeActivate = $true
            if ($tasks -notcontains 'Activate') {
                Log "Office installed -> Auto-running campus KMS activation..." 'Cyan'
                $tasks += 'Activate'
            }
        }
    }

    # ============ Winget apps (latest from vendor via winget) ============
    if ($tasks -contains 'Winget') {
        Log '== Winget ==' 'Cyan'
        $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $wg) { Log 'FAIL: winget not found (install "App Installer" from Microsoft Store)' 'Red'; $global:LabExitCode = 4 }
        else {
            foreach ($id in $wingetSel) {
                $listed = winget list --id $id -e --accept-source-agreements 2>$null | Select-String ([regex]::Escape($id))
                $verb = if ($listed) { 'upgrade' } else { 'install' }
                Log "[$id] $verb"
                if ($dryRun) { continue }
                winget $verb --id $id -e --silent --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
                $code = $LASTEXITCODE
                # 0 ok; 0x8A15002B = no applicable upgrade (already latest)
                if ($code -eq 0 -or $code -eq -1978335189) { Log "[$id] OK" 'Green' }
                else { Log "[$id] FAIL exit $('0x{0:X8}' -f $code)" 'Red'; $global:LabExitCode = 4 }
            }
            Log "Upgrading all installed applications via Winget..." 'Cyan'
            if (-not $dryRun) {
                winget upgrade --all --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
                Log "Winget upgrade --all completed" 'Green'
            }
            Set-WinRarLicense $share $LabScriptDir
        }
    }

    # ============ Wallpaper (Lock / Unlock) ============
    if ($tasks -contains 'Wallpaper' -or $tasks -contains 'Unlock') {
        Log '== Wallpaper ==' 'Cyan'
        $wpAction = if ($tasks -contains 'Unlock') { '2' } else { $null }

        if ($interactive -and -not $wpAction) {
            Write-Host ""
            Write-Host "  [1] Set & Lock Lab Wallpaper (จากเซิร์ฟเวอร์ + ล็อกไม่ให้เปลี่ยน)" -ForegroundColor Cyan
            Write-Host "  [2] Unlock Wallpaper (ปลดล็อกให้เปลี่ยนรูปพื้นหลังได้อิสระ)" -ForegroundColor Yellow
            Write-Host "  [B] Back to main menu" -ForegroundColor DarkGray
            $ansWp = Read-Host "Choose option (1, 2 / B = back)"
            if ($ansWp -eq '1') { $wpAction = '1' }
            elseif ($ansWp -eq '2') { $wpAction = '2' }
            else { Log "Wallpaper: cancelled (no change)." 'Yellow'; $wpAction = $null }
        } elseif (-not $wpAction) {
            $wpAction = '1'
        }

        if ($wpAction -eq '1') {
            if (-not $shareOk) {
                Log "FAIL: share not connected (cannot fetch wallpaper)" 'Red'
            } else {
                # any image in the share's wallpaper folder; menu picks one, otherwise the newest file
                $imgs = @(Get-ChildItem (Join-Path $share $cfg.wallpaper.folder) -File -ErrorAction SilentlyContinue |
                          Where-Object { $_.Extension -in '.jpg', '.jpeg', '.png', '.bmp' } | Sort-Object LastWriteTime -Descending)
                $src = $null
                if ($imgs.Count -eq 1 -or ($imgs.Count -gt 1 -and -not $interactive)) { $src = $imgs[0].FullName }
                elseif ($imgs.Count -gt 1) {
                    $labels = @($imgs | ForEach-Object { '{0,-40} {1:yyyy-MM-dd}' -f $_.Name, $_.LastWriteTime })
                    Write-Host "`n--- Wallpaper Images ---" -ForegroundColor Cyan
                    for ($i = 0; $i -lt $labels.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $labels[$i]) }
                    $w = Read-Host 'Choose one (Enter = newest)'
                    $src = if ($w -match '^\d+$' -and [int]$w -ge 1 -and [int]$w -le $imgs.Count) { $imgs[[int]$w - 1].FullName } else { $imgs[0].FullName }
                }
                $dst = if ($src) { Join-Path $root ('wallpaper' + [IO.Path]::GetExtension($src).ToLower()) }
                if (-not $src) { Log "FAIL: no image in $(Join-Path $share $cfg.wallpaper.folder)" 'Red' }
                else {
                    Log "wallpaper: $(Split-Path $src -Leaf)"
                    # remove old copies with another extension so only the chosen image stays
                    Get-ChildItem $root -Filter 'wallpaper.*' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $dst -and -not $dryRun } | Remove-Item -Force
                    $changed = -not (Test-Path $dst) -or (Get-FileHash $src).Hash -ne (Get-FileHash $dst).Hash
                    if ($changed -and -not $dryRun) { Copy-Item $src $dst -Force; Log "copied new wallpaper" }
                    # Users: read-only on LabSetup folder
                    if (-not $dryRun) { icacls $root /inheritance:r /grant:r 'Administrators:(OI)(CI)F' 'SYSTEM:(OI)(CI)F' 'Users:(OI)(CI)RX' | Out-Null }
                    $hives = Get-UserHives
                    try {
                        foreach ($h in $hives) {
                            Log "user: $($h.Name)"
                            Set-Reg "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Policies\System" 'Wallpaper' $dst 'String'
                            Set-Reg "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Policies\System" 'WallpaperStyle' "$($cfg.wallpaper.style)" 'String'
                            Set-Reg "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" 'NoChangingWallPaper' 1 'DWord'
                        }
                    } finally { Close-UserHives $hives }
                    if (-not $dryRun) { rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True }
                    Log 'Wallpaper set & locked (applies at next sign-in)' 'Green'
                }
            }
        } elseif ($wpAction -eq '2') {
            Log "Unlocking wallpaper..."
            $hives = Get-UserHives
            try {
                foreach ($h in $hives) {
                    foreach ($k in 'System','ActiveDesktop') {
                        $key = "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Policies\$k"
                        foreach ($v in 'Wallpaper','WallpaperStyle','NoChangingWallPaper') {
                            if ((Get-ItemProperty $key -ErrorAction SilentlyContinue).$v -ne $null) {
                                if ($dryRun) { Log "  [dry] remove $key\$v" } else { Remove-ItemProperty $key -Name $v }
                            }
                        }
                    }
                }
            } finally { Close-UserHives $hives }
            if (-not $dryRun) { rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True }
            Log 'Wallpaper unlocked (users can change wallpaper freely)' 'Green'
        }
    }

    # ============ Fonts (all users, skip ones already present) ============
    if ($tasks -contains 'Fonts') {
        Log '== Fonts ==' 'Cyan'
        $fontDir = Join-Path $env:SystemRoot 'Fonts'
        $fontReg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        $fontSrc = $null

        if ($shareOk -and (Test-Path (Join-Path $share $cfg.fonts.folder))) {
            $fontSrc = Join-Path $share $cfg.fonts.folder
            Log "Using fonts from campus share: $fontSrc"
        } elseif ($LabScriptDir -and (Test-Path (Join-Path $LabScriptDir 'fonts'))) {
            $fontSrc = Join-Path $LabScriptDir 'fonts'
            Log "Using fonts from local folder: $fontSrc"
        } else {
            $tmpFontDir = Join-Path $root 'fonts'
            New-Item -ItemType Directory -Force -Path $tmpFontDir | Out-Null
            Log "Downloading standard Thai fonts from GitHub..."
            $fontFiles = @(
                'THSarabun.ttf', 'THSarabun Bold.ttf', 'THSarabun Italic.ttf', 'THSarabun Bold Italic.ttf',
                'THSarabunNew.ttf', 'THSarabunNew Bold.ttf', 'THSarabunNew Italic.ttf', 'THSarabunNew BoldItalic.ttf'
            )
            foreach ($fn in $fontFiles) {
                $targetFile = Join-Path $tmpFontDir $fn
                if (-not (Test-Path $targetFile)) {
                    $encodedFn = [Uri]::EscapeDataString($fn)
                    $url = "https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.7/fonts/$encodedFn"
                    try { Invoke-WebRequest $url -OutFile $targetFile -UseBasicParsing -TimeoutSec 10 }
                    catch { Log "FAIL download font $fn : $($_.Exception.Message)" 'Yellow' }
                }
            }
            $fontSrc = $tmpFontDir
        }

        if ($fontSrc -and (Test-Path $fontSrc)) {
            $added = 0
            foreach ($ft in Get-ChildItem $fontSrc -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.ttf', '.otf' }) {
                $target = Join-Path $fontDir $ft.Name
                if ((Test-Path $target) -and (Get-Item $target).Length -eq $ft.Length) { continue }
                if ($dryRun) { Log "  [dry] font $($ft.Name)"; continue }
                try {
                    Copy-Item $ft.FullName $target -Force -ErrorAction Stop
                    $kind = if ($ft.Extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
                    New-ItemProperty -Path $fontReg -Name "$($ft.BaseName) ($kind)" -Value $ft.Name -PropertyType String -Force | Out-Null
                    $added++
                } catch { Log "  FAIL font $($ft.Name): $($_.Exception.Message)" 'Yellow' }
            }
            Log "Fonts: $added new / updated (others already present). Apps see them after restart/sign-in." 'Green'
        } else {
            Log "FAIL: no fonts found" 'Red'
        }
    }

    # ============ WinRAR theme (every user + Default profile) ============
    if ($tasks -contains 'WinRARTheme' -and $shareOk) {
        Log '== WinRARTheme ==' 'Cyan'
        $themeSrc  = Join-Path $share $cfg.winrarTheme.folder
        $themeName = $cfg.winrarTheme.name
        if (-not (Test-Path $themeSrc)) { Log "FAIL: $themeSrc not found" 'Red' }
        else {
            $profiles = @(Get-ChildItem "$env:SystemDrive\Users" -Directory | Where-Object {
                $_.Name -notin @('Public', 'Default User', 'All Users') -and $cfg.excludeProfiles -notcontains $_.Name })
            foreach ($pr in $profiles) {
                $dst = Join-Path $pr.FullName "AppData\Roaming\WinRAR\Themes\$themeName"
                if ($dryRun) { Log "  [dry] theme -> $dst"; continue }
                New-Item -ItemType Directory -Force -Path $dst | Out-Null
                Copy-Item "$themeSrc\*" $dst -Recurse -Force
            }
            $hives = Get-UserHives
            try {
                foreach ($h in $hives) {
                    Log "user: $($h.Name)"
                    Set-Reg "$($h.Key)\Software\WinRAR\Interface\Themes" 'ActivePath' $themeName 'String'
                }
            } finally { Close-UserHives $hives }
            Log "WinRAR theme '$themeName' set (applies next WinRAR start)" 'Green'
        }
    }

    # ============ Certificates (Trusted Root, thumbprint allowlist only) ============
    if ($tasks -contains 'Certs' -and $shareOk) {
        Log '== Certs ==' 'Cyan'
        $allow = @($cfg.certs.allowThumbprints | ForEach-Object { $_.ToUpper() })
        foreach ($cf in Get-ChildItem (Join-Path $share $cfg.certs.folder) -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.cer', '.crt' }) {
            $c = New-Object Security.Cryptography.X509Certificates.X509Certificate2 $cf.FullName
            if ($allow -notcontains $c.Thumbprint) { Log "  SKIP $($cf.Name): thumbprint $($c.Thumbprint) not in allowlist" 'Yellow'; continue }
            if (Get-ChildItem Cert:\LocalMachine\Root | Where-Object Thumbprint -eq $c.Thumbprint) { Log "  $($c.Subject): already trusted"; continue }
            if ($dryRun) { Log "  [dry] import $($c.Subject)"; continue }
            $store = New-Object Security.Cryptography.X509Certificates.X509Store 'Root', 'LocalMachine'
            $store.Open('ReadWrite'); $store.Add($c); $store.Close()
            Log "  imported $($c.Subject) (expires $($c.NotAfter.ToString('yyyy-MM-dd')))" 'Green'
        }
    }

    # ============ SPSS license (Concurrent: write license server into spssprod.inf, lshost, env) ============
    if ($tasks -contains 'SpssLicense') {
        Log '== SpssLicense ==' 'Cyan'
        $ls = $cfg.spss.licenseServer
        if (-not $ls) { Log 'SKIP: spss.licenseServer is empty in config.json' 'Yellow' }
        else {
            $sDirs = @(Get-SpssDirs)
            if ($sDirs.Count -eq 0) {
                Log 'SKIP: no SPSS or Amos installation found in Program Files or Registry' 'Yellow'
            } else {
                Set-SpssLicense $sDirs $ls
                # TCP 5093 = Sentinel RMS port the relay on Server 72 forwards (ping says nothing about the relay)
                $isPing = Test-NetConnection $ls -Port 5093 -InformationLevel Quiet -WarningAction SilentlyContinue
                if ($isPing) {
                    Log "License server ($ls) reachable: OK" 'Green'
                } else {
                    Log "[!] License server ($ls) unreachable!" 'Yellow'
                    Log "    -> Check SpssLicenseRelay on Server 72 (TCP/UDP 5093), or connect Fortinet SPSS VPN (gwspss.nsru.ac.th:10443)" 'Yellow'
                }
            }
        }
    }

    # ============ Check (read-only status: SPSS, VPN gateways, KMS, share) ============
    if ($tasks -contains 'Check') {
        Log '== Check ==' 'Cyan'
        function Show-Port($label, $h, $port) {
            $ok = $false
            if ($h) {
                $sock = New-Object Net.Sockets.TcpClient
                try {
                    $ar = $sock.BeginConnect($h, $port, $null, $null)
                    $ok = $ar.AsyncWaitHandle.WaitOne(1200)
                } catch { $ok = $false }
                finally { $sock.Close() }
            }
            Log ("  {0,-22} {1}:{2}  {3}" -f $label, $h, $port, $(if ($ok) { 'OK' } else { 'UNREACHABLE' })) $(if ($ok) { 'Green' } else { 'Yellow' })
        }
        foreach ($v in $cfg.vpn) { Show-Port "VPN $($v.name)" $v.gateway $v.port }
        Show-Port 'KMS' $cfg.kms.host 1688
        Show-Port 'Deploy share' ($cfg.deployShare.TrimEnd('\').Split('\')[2]) 445
        $forti = Get-Installed 'FortiClient*' | Select-Object -First 1
        Log ("  FortiClient            {0}" -f $(if ($forti) { $forti.DisplayVersion } else { 'NOT INSTALLED' }))
        foreach ($app in 'IBM SPSS Statistics*', 'IBM SPSS Amos*') {
            $i = Get-Installed $app | Select-Object -First 1
            Log ("  {0,-22} {1}" -f $app.TrimEnd('*'), $(if ($i) { "$($i.DisplayVersion)" } else { 'NOT INSTALLED' }))
        }
        $sDirs = @(Get-SpssDirs)
        foreach ($sd in $sDirs) {
            $lshostFile = Join-Path $sd 'lshost'
            $curHost = if (Test-Path $lshostFile) { (Get-Content $lshostFile -Raw -ErrorAction SilentlyContinue).Trim() } else { $null }
            $infFile = Join-Path $sd 'spssprod.inf'
            $infHost = if (Test-Path $infFile) {
                $m = (Get-Content $infFile | Select-String '^\s*DaemonHost\s*=\s*(.+)$')
                if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { $null }
            } else { $null }
            Log ("  {0}`n      lshost={1}  DaemonHost={2}" -f $sd, $(if ($curHost) { $curHost } else { 'none' }), $(if ($infHost) { $infHost } else { 'none' }))
        }
        if ($cfg.spss.licenseServer) {
            $pong = Test-NetConnection $cfg.spss.licenseServer -Port 5093 -InformationLevel Quiet -WarningAction SilentlyContinue
            Log ("  SPSS license server ($($cfg.spss.licenseServer)) TCP 5093: {0}" -f $(if ($pong) { 'OK' } else { 'UNREACHABLE (check SpssLicenseRelay on Server 72, or Fortinet SPSS VPN)' })) $(if ($pong) { 'Green' } else { 'Yellow' })
        }
    }



    # ============ Auto Wake/Sleep (08:20 - 16:40 Mon-Fri) ============
    if ($tasks -contains 'AutoSleep') {
        Log '== Auto Wake/Sleep ==' 'Cyan'
        Write-Host ""
        Write-Host "  [1] Enable Auto Wake (08:20) & Sleep (16:40) Mon-Fri" -ForegroundColor Cyan
        Write-Host "  [2] Disable / Delete Auto Wake & Sleep tasks" -ForegroundColor Yellow
        Write-Host "  [B] Back to main menu" -ForegroundColor DarkGray
        $choice = Read-Host "Choose option (1, 2 / B = back)"
        if ($choice -eq '1') {
            if ($dryRun) { Log "  [dry] configure Auto Wake/Sleep"; continue }
            # native exe + 2>$null under EAP=Stop throws on PS 5.1, so run powercfg with EAP=Continue.
            # Wake timers by GUID (alias RTCWAKING does not exist); AC+DC, 1 = Enable (Win10/11 default is 2 = important only)
            & {
                $ErrorActionPreference = 'Continue'
                $wakeGuid = 'BD3B718A-0680-4D9D-8AB2-E1D2B4AC806D'
                powercfg /attributes SUB_SLEEP $wakeGuid -ATTRIB_HIDE 2>$null | Out-Null
                powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP $wakeGuid 1 2>$null | Out-Null
                if ($LASTEXITCODE -ne 0) { Log "  WARN: cannot set 'Allow wake timers' (powercfg exit $LASTEXITCODE)" 'Yellow' }
                powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP $wakeGuid 1 2>$null | Out-Null
                powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null
                if ((powercfg /a 2>$null | Out-String) -match 'S0 Low Power Idle') {
                    Log "  WARN: Modern Standby (S0) machine - wake timers may not fire; enable RTC/Power-On by Alarm in BIOS as backup." 'Yellow'
                }
            }
            $days = 'Monday','Tuesday','Wednesday','Thursday','Friday'
            $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            $sleepAct = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, `$false, `$false)`""
            $sleepTrg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At '16:40'
            $sleepSet = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            $wakeAct = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Start-Sleep -Seconds 8; Start-ScheduledTask -TaskName 'NSRU-KeepAlive' -ErrorAction SilentlyContinue`""
            $wakeTrg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At '08:20'
            $wakeSet = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            try {
                Register-ScheduledTask -TaskName 'Lab_AutoSleep' -Action $sleepAct -Trigger $sleepTrg -Principal $principal -Settings $sleepSet -Force | Out-Null
                Register-ScheduledTask -TaskName 'Lab_AutoWake' -Action $wakeAct -Trigger $wakeTrg -Principal $principal -Settings $wakeSet -Force | Out-Null
                Log "Auto Wake (08:20) & Sleep (16:40) configured." 'Green'
            } catch {
                Log "FAIL: Auto Wake/Sleep task registration: $($_.Exception.Message)" 'Red'
            }
        } elseif ($choice -eq '2') {
            if ($dryRun) { Log "  [dry] remove Auto Wake/Sleep tasks"; continue }
            foreach ($tn in 'Lab_AutoSleep', 'Lab_AutoWake') {
                Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue
            }
            Log "Auto Wake/Sleep disabled (scheduled tasks removed)." 'Green'
        } else {
            Log "Auto Wake/Sleep: cancelled (no change)." 'Yellow'
        }
    }

    # ============ Campus Internet KeepAlive (Optional background auto-auth) ============
    if ($tasks -contains 'KeepAlive') {
        Log '== Campus Internet KeepAlive ==' 'Cyan'
        $taskName = 'NSRU-KeepAlive'
        $netAuthDir = Join-Path $root 'net-auth'
        if (-not (Test-Path $netAuthDir)) { New-Item -ItemType Directory -Force -Path $netAuthDir | Out-Null }
        $localEnv = Join-Path $root 'net-auth.env'
        # share not connected = no UNC retry (a failed SMB logon with a stale password counts toward the labdeploy lockout)
        $shareEnv = if ($shareOk) { Join-Path $share 'net-auth.env' } else { $null }

        $kaAction = if (-not $interactive) { '1' } else { $null }
        if ($interactive -and -not $kaAction) {
            $isTaskInstalled = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) -ne $null
            $taskState = if ($isTaskInstalled) { (Get-ScheduledTask -TaskName $taskName).State } else { 'Not installed' }
            $onlineNow = $false
            try {
                $sc = & curl.exe -s -k -m 4 -w "%{http_code}" -o NUL "http://clients3.google.com/generate_204" 2>$null
                $onlineNow = ($sc -eq '204')
            } catch {}

            Write-Host "`n  Internet Status: " -NoNewline
            if ($onlineNow) { Write-Host "ONLINE (Internet active)" -ForegroundColor Green }
            else { Write-Host "OFFLINE (Captive portal / login required)" -ForegroundColor Yellow }
            Write-Host "  Background Task ($taskName): " -NoNewline
            if ($isTaskInstalled) { Write-Host "$taskState" -ForegroundColor Green }
            else { Write-Host "Not installed" -ForegroundColor DarkGray }
            Write-Host "  Credentials (net-auth.env): " -NoNewline
            if (Test-Path $localEnv) { Write-Host "Found locally ($localEnv)" -ForegroundColor Green }
            elseif ($shareEnv -and (Test-Path $shareEnv)) { Write-Host "Found on Server 72 ($shareEnv)" -ForegroundColor Green }
            else { Write-Host "Not found" -ForegroundColor Yellow }
            Write-Host ""

            Write-Host "  [1] Enable & Start background KeepAlive (ติดตั้ง Task เบื้องหลัง 100% ไม่มีหน้าต่าง)" -ForegroundColor Cyan
            Write-Host "  [2] Test login now (ทดสอบล็อกอิน 1 ครั้งทันที + แสดงผลลัพธ์)" -ForegroundColor Cyan
            Write-Host "  [3] Disable & Remove KeepAlive task (ปิดการทำงาน / ถอนการติดตั้ง)" -ForegroundColor Yellow
            Write-Host "  [4] Configure credentials in net-auth.env (ตั้งค่า user/password บน Server 72 หรือเครื่องนี้)" -ForegroundColor White
            Write-Host "  [B] Back to main menu" -ForegroundColor DarkGray
            $ansKa = Read-Host "Choose option (1-4 / B = back)"
            if ($ansKa -in '1','2','3','4') { $kaAction = $ansKa }
            else { Log "KeepAlive: cancelled (no change)." 'Yellow'; $kaAction = $null }
        }

        if ($kaAction -eq '4') {
            Write-Host "`n--- Configure net-auth.env ---" -ForegroundColor Cyan
            $uInput = Read-Host "NSRU Internet Username"
            $pInput = Read-Host "NSRU Internet Password"
            if ($uInput -and $pInput) {
                $envContent = @"
# NSRU Campus LAN Internet Authentication
NSRU_USER=$uInput
NSRU_PASS=$pInput
PORTAL=https://login.nsru.ac.th:1000
INTERVAL=90
STOP_HOUR=-1
"@
                Set-Content -Path $localEnv -Value $envContent -Encoding UTF8
                icacls $localEnv /inheritance:r /grant:r 'Administrators:(F)' 'SYSTEM:(F)' | Out-Null
                Log "Saved credentials locally to $localEnv (secured: Admins & SYSTEM only)" 'Green'
                if ($shareOk) {
                    $saveToShare = Read-Host "Save to Server 72 share ($shareEnv) for other lab PCs? [Y/n]"
                    if ($saveToShare -ne 'n' -and $saveToShare -ne 'N') {
                        try {
                            Copy-Item $localEnv $shareEnv -Force -ErrorAction Stop
                            Log "Copied net-auth.env to Server 72 share: $shareEnv" 'Green'
                        } catch { Log "FAIL write to share: $($_.Exception.Message) - labdeploy is read-only; update net-auth.env on Server 72 or the next KeepAlive run restores the share copy." 'Yellow' }
                    }
                }
            } else { Log "Credentials not entered. Cancelled." 'Yellow' }
        }

        if ($kaAction -in '1', '2') {
            # Server 72 copy wins: fetch when missing or changed there
            [void](Sync-ShareFile $shareEnv $localEnv 'net-auth.env')
            if (-not (Test-Path $localEnv)) {
                Write-Host "`nCredentials not found. Please enter NSRU internet credentials:" -ForegroundColor Yellow
                $uInput = Read-Host "NSRU Internet Username"
                $pInput = Read-Host "NSRU Internet Password"
                if ($uInput -and $pInput) {
                    $envContent = @"
# NSRU Campus LAN Internet Authentication
NSRU_USER=$uInput
NSRU_PASS=$pInput
PORTAL=https://login.nsru.ac.th:1000
INTERVAL=90
STOP_HOUR=-1
"@
                    Set-Content -Path $localEnv -Value $envContent -Encoding UTF8
                    icacls $localEnv /inheritance:r /grant:r 'Administrators:(F)' 'SYSTEM:(F)' | Out-Null
                    Log "Saved credentials to $localEnv" 'Green'
                    if ($shareOk) {
                        try { Copy-Item $localEnv $shareEnv -Force -ErrorAction SilentlyContinue; Log "Also saved to Server 72: $shareEnv" 'Green' } catch {}
                    }
                } else {
                    Log "FAIL: Cannot proceed without credentials." 'Red'
                    $kaAction = $null
                }
            }
        }

        # Deploy KeepAlive files to C:\ProgramData\LabDeploy\net-auth\
        if ($kaAction -in '1', '2') {
            $srcKaPs1 = if ($LabScriptDir -and (Test-Path (Join-Path $LabScriptDir 'net-auth\KeepAlive.ps1'))) { Join-Path $LabScriptDir 'net-auth\KeepAlive.ps1' }
                        elseif ($shareOk -and (Test-Path (Join-Path $share 'net-auth\KeepAlive.ps1'))) { Join-Path $share 'net-auth\KeepAlive.ps1' }
                        else { $null }
            $srcLaunchVbs = if ($LabScriptDir -and (Test-Path (Join-Path $LabScriptDir 'net-auth\launch.vbs'))) { Join-Path $LabScriptDir 'net-auth\launch.vbs' }
                            elseif ($shareOk -and (Test-Path (Join-Path $share 'net-auth\launch.vbs'))) { Join-Path $share 'net-auth\launch.vbs' }
                            else { $null }

            $dstKaPs1 = Join-Path $netAuthDir 'KeepAlive.ps1'
            $dstLaunchVbs = Join-Path $netAuthDir 'launch.vbs'

            if ($srcKaPs1 -and (Test-Path $srcKaPs1)) { Copy-Item $srcKaPs1 $dstKaPs1 -Force }
            if ($srcLaunchVbs -and (Test-Path $srcLaunchVbs)) { Copy-Item $srcLaunchVbs $dstLaunchVbs -Force }
            # Fallback if downloaded directly from GitHub/URL
            if (-not (Test-Path $dstKaPs1)) {
                $kaUrl = "https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.7/net-auth/KeepAlive.ps1"
                try { Invoke-WebRequest $kaUrl -OutFile $dstKaPs1 -UseBasicParsing -TimeoutSec 10 } catch {}
            }
            if (-not (Test-Path $dstLaunchVbs)) {
                $vbsContent = @'
Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\KeepAlive.ps1"
If fso.FileExists(psScript) Then
    cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """"
    WshShell.Run cmd, 0, False
End If
'@
                Set-Content -Path $dstLaunchVbs -Value $vbsContent -Encoding ASCII
            }
        }

        if ($kaAction -eq '2') {
            Log "Testing KeepAlive login once..." 'Cyan'
            $kaScript = Join-Path $netAuthDir 'KeepAlive.ps1'
            if (Test-Path $kaScript) {
                & powershell.exe -ExecutionPolicy Bypass -File $kaScript -Once
                if ($LASTEXITCODE -eq 0) { Log "KeepAlive test login: SUCCESS (Online)" 'Green' }
                else { Log "KeepAlive test login: Finished. (Check if captive portal required / credentials valid)" 'Yellow' }
            } else { Log "FAIL: KeepAlive.ps1 not found in $netAuthDir" 'Red' }
        }

        if ($kaAction -eq '1') {
            Log "Registering background Scheduled Task '$taskName'..." 'Cyan'
            $vbsPath = Join-Path $netAuthDir 'launch.vbs'
            $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //Nologo `"$vbsPath`""
            $trigStartup = New-ScheduledTaskTrigger -AtStartup
            $trigLogon   = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

            try {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigStartup, $trigLogon) -Principal $principal -Settings $settings -Force | Out-Null

                # Add wake-from-sleep trigger (System Resume event) so KeepAlive triggers after sleep/wake
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

                Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                Log "KeepAlive task '$taskName' installed & started successfully (100% hidden background, runs as SYSTEM on boot/logon/wake)." 'Green'
            } catch {
                Log "FAIL register task: $($_.Exception.Message)" 'Red'
            }
        }

        if ($kaAction -eq '3') {
            Log "Removing KeepAlive task '$taskName'..." 'Cyan'
            try {
                Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop | Out-Null
                Log "Task '$taskName' removed." 'Green'
            } catch {
                Log "Task '$taskName' not found or already removed." 'Yellow'
            }
            Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*KeepAlive.ps1*' } | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    # ============ LibDesk Crash Watcher (Scheduled Task) ============
    if ($tasks -contains 'CrashWatcher') {
        Log '== LibDesk Crash Watcher ==' 'Cyan'
        $cwTaskName = 'Lab_CrashWatcher'
        $cwScriptPath = Join-Path $root 'crash-watch.ps1'
        $cwVbsPath = Join-Path $root 'crash-watch.vbs'
        $telemetryUrl = if ($cfg -and $cfg.telemetryUrl) { $cfg.telemetryUrl }
                        elseif ($env:LAB_TELEMETRY_URL) { $env:LAB_TELEMETRY_URL }
                        else { 'https://libdesk.nsru.ac.th/api/computer-lab/telemetry' }
        $camp = if ($cfg -and $cfg.campus) { $cfg.campus } else { 'city' }

        $cwAction = if (-not $interactive -or $cwAuto) { '1' } else { $null }
        if ($interactive -and -not $cwAction) {
            $isCwInstalled = (Get-ScheduledTask -TaskName $cwTaskName -ErrorAction SilentlyContinue) -ne $null
            $cwState = if ($isCwInstalled) { (Get-ScheduledTask -TaskName $cwTaskName).State } else { 'Not installed' }

            Write-Host "`n  Background Task ($cwTaskName): " -NoNewline
            if ($isCwInstalled) { Write-Host "$cwState (Active)" -ForegroundColor Green }
            else { Write-Host "Not installed" -ForegroundColor DarkGray }
            Write-Host "  Telemetry Target: $telemetryUrl (Campus: $camp)"
            Write-Host "  Watcher script: $cwScriptPath"
            Write-Host ""
            Write-Host "  [1] Enable & Start background CrashWatcher (ติดตั้ง Task ตรวจจับจอฟ้า/แครช ระดับ SYSTEM)" -ForegroundColor Cyan
            Write-Host "  [2] Test crash detection & send test telemetry to LibDesk (ทดสอบส่ง 1 ครั้ง)" -ForegroundColor Cyan
            Write-Host "  [3] Disable & Remove CrashWatcher task (ปิดการทำงาน / ถอนการติดตั้ง)" -ForegroundColor Yellow
            Write-Host "  [B] Back to main menu" -ForegroundColor DarkGray
            $ansCw = Read-Host "Choose option (1-3 / B = back)"
            if ($ansCw -in '1','2','3') { $cwAction = $ansCw }
            else { Log "CrashWatcher: cancelled (no change)." 'Yellow'; $cwAction = $null }
        }

        if ($cwAction -in '1', '2') {
            # Token: SYSTEM task cannot see the admin's env, so keep it in a file only SYSTEM/Administrators can read
            # Source order: share file (same pattern as net-auth.env, protected by the labdeploy cmdkey credential) > env > prompt
            $tokFile = Join-Path $root 'telemetry.token'
            $shareTok = if ($shareOk) { Join-Path $share 'telemetry.token' } else { $null }  # no UNC retry, see $shareEnv
            if (-not (Sync-ShareFile $shareTok $tokFile 'telemetry.token')) {
                $tok = $env:LAB_TELEMETRY_TOKEN
                if (-not $tok -and $interactive) {
                    $sec = Read-Host "  LibDesk telemetry token (LAB_TELEMETRY_TOKEN, Enter = skip)" -AsSecureString
                    $tok = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
                }
                if ($tok -and $tok.Trim()) {
                    if (-not $dryRun) { Save-LabTelemetryToken $tok }
                    Log "Telemetry token saved to $tokFile (SYSTEM + Administrators only)." 'Green'
                } else {
                    Log "WARN: no telemetry token — CrashWatcher installs but LibDesk will not receive reports. Set LAB_TELEMETRY_TOKEN and rerun." 'Yellow'
                }
            }
            Log "Hardware ID: $(Get-LabHardwareId) · Domain: $(Get-LabDomain)" 'DarkGray'

            # Deploy crash-watch.ps1
            $scriptContent = @"
# LibDesk Crash & BSOD Watcher (NSRU Computer Lab)
`$ErrorActionPreference = 'SilentlyContinue'
`$root = Join-Path `$env:ProgramData 'LabDeploy'
`$stateFile = Join-Path `$root 'last-crash-check.txt'
`$now = Get-Date

`$lastCheck = if (Test-Path `$stateFile) {
    try { [DateTime]::Parse((Get-Content `$stateFile -Raw).Trim()) } catch { `$now.AddDays(-1) }
} else {
    `$now.AddDays(-1)
}

$LabTelemetryHelpers
function Send-Report(`$title, `$detail) {
    Send-LabEvent '$telemetryUrl' '$camp' 'crash' `$title `$detail 'SYSTEM (CrashWatcher)' | Out-Null
}

# 1. Check BSOD (System Event 1001) or Unexpected Shutdown (Event 6008)
`$bsod = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = `$lastCheck } -MaxEvents 3 -ErrorAction SilentlyContinue
if (-not `$bsod) {
    `$bsod = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008; StartTime = `$lastCheck } -MaxEvents 3 -ErrorAction SilentlyContinue
}
if (`$bsod) {
    foreach (`$ev in `$bsod) {
        `$lbl = if (`$ev.Id -eq 1001) { 'ตรวจพบจอฟ้า (BSOD / BugCheck)' } else { 'ตรวจพบเครื่องดับผิดปกติ (Unexpected Shutdown)' }
        Send-Report -title "`$lbl [`$(`$ev.TimeCreated.ToString('yyyy-MM-dd HH:mm'))]" -detail `$ev.Message
    }
}

# 2. Check Severe Application Crashes (Event 1000)
`$apps = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = `$lastCheck } -MaxEvents 5 -ErrorAction SilentlyContinue
if (`$apps) {
    `$keyTargets = @('WINWORD.EXE', 'EXCEL.EXE', 'POWERPNT.EXE', 'stats.exe', 'spss.exe', 'explorer.exe')
    foreach (`$ev in `$apps) {
        `$found = `$false
        foreach (`$kt in `$keyTargets) {
            if (`$ev.Message -like "*`$kt*") { `$found = `$true; break }
        }
        if (`$found) {
            `$appName = (`$ev.Message -split "`r?`n" | Select-String "Faulting application name: (.*)")[0]
            `$appLabel = if (`$appName) { `$appName.Matches[0].Groups[1].Value } else { 'แอปพลิเคชัน' }
            Send-Report -title "ตรวจพบแอปแครช: `$appLabel [`$(`$ev.TimeCreated.ToString('yyyy-MM-dd HH:mm'))]" -detail `$ev.Message
        }
    }
}

`$now.ToString('o') | Set-Content -Path `$stateFile -Encoding UTF8 -Force
"@
            $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$cwScriptPath""", 0, False
"@
            if (-not $dryRun) {
                Set-Content -Path $cwScriptPath -Value $scriptContent -Encoding UTF8
                Set-Content -Path $cwVbsPath -Value $vbsContent -Encoding ASCII
            }

            if ($cwAction -eq '1') {
                if (-not $dryRun) {
                    $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //Nologo `"$cwVbsPath`""
                    $trigStartup = New-ScheduledTaskTrigger -AtStartup
                    $trigDaily1  = New-ScheduledTaskTrigger -Daily -At '08:30'
                    $trigDaily2  = New-ScheduledTaskTrigger -Daily -At '13:00'
                    $principal   = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
                    $settings    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

                    try {
                        Unregister-ScheduledTask -TaskName $cwTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                        Register-ScheduledTask -TaskName $cwTaskName -Action $action -Trigger @($trigStartup, $trigDaily1, $trigDaily2) -Principal $principal -Settings $settings -Force | Out-Null
                        Start-ScheduledTask -TaskName $cwTaskName -ErrorAction SilentlyContinue
                        Log "CrashWatcher task '$cwTaskName' installed & started successfully (100% hidden, runs as SYSTEM on boot & daily)." 'Green'
                    } catch {
                        Log "FAIL register task: $($_.Exception.Message)" 'Red'
                    }
                } else {
                    Log "  [dry] install scheduled task $cwTaskName"
                }
            } elseif ($cwAction -eq '2') {
                Log "Testing CrashWatcher telemetry to $telemetryUrl..." 'Cyan'
                # eventType 'note' (not 'crash'): a test must not open an incident on an assigned machine
                $sent = Send-LabTelemetry -eventType 'note' -title "[ทดสอบระบบ] CrashWatcher เครื่อง $env:COMPUTERNAME ส่งข้อมูลถึง LibDesk" -detail "ทดสอบการรายงานตัวของเครื่อง — เครื่องใหม่จะอยู่ในกล่อง ยังไม่จัดกลุ่ม ที่หน้า ดูแลคอมพิวเตอร์ แท็บ จัดเครื่องเข้าห้อง"
                if ($sent) { Log "Test telemetry sent. เปิด LibDesk > ดูแลคอมพิวเตอร์ > จัดเครื่องเข้าห้อง แล้วลากเครื่องนี้เข้าห้อง" 'Green' }
                else { Log "Test telemetry NOT sent (no token / no network / rejected)." 'Yellow' }
            }
        }

        if ($cwAction -eq '3') {
            Log "Removing CrashWatcher task '$cwTaskName'..." 'Cyan'
            try {
                Stop-ScheduledTask -TaskName $cwTaskName -ErrorAction SilentlyContinue | Out-Null
                Unregister-ScheduledTask -TaskName $cwTaskName -Confirm:$false -ErrorAction Stop | Out-Null
                Log "Task '$cwTaskName' removed." 'Green'
            } catch {
                Log "Task '$cwTaskName' not found or already removed." 'Yellow'
            }
        }
    }

    # ============ LicenseCheck & Activate (Check Windows, Office, SPSS & fix if expired) ============
    if ($tasks -contains 'LicenseCheck' -or $tasks -contains 'Activate') {
        Log '== License Check & Activation ==' 'Cyan'
        $kms = $cfg.kms.host
        $winAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
        $offAppId = '0ff1ce15-a989-479d-af46-f275c6370663'
        $statusName = @{ 0='Unlicensed'; 1='Licensed'; 2='OOB grace'; 3='OOT grace'; 4='NonGenuine grace'; 5='Notification'; 6='Extended grace' }

        function Get-LicProducts {
            Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
                Where-Object { $_.ApplicationID -in $winAppId, $offAppId } | Sort-Object ApplicationID, Name
        }

        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $gvlk    = $cfg.kms.windowsGvlk.$edition

        $prods = @(Get-LicProducts)
        $spssLs = $cfg.spss.licenseServer

        $osppFiles = @(
            "$env:ProgramFiles\Microsoft Office\root\Office16\OSPP.VBS",
            "$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS",
            "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OSPP.VBS",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS",
            "$env:ProgramFiles\Microsoft Office\Office15\OSPP.VBS",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office15\OSPP.VBS"
        ) | Where-Object { Test-Path $_ }

        $needsFix = $false
        $unlicensedProds = @()

        if (-not $autoOfficeActivate) {
            Write-Host ''
            Write-Host '--- License Status Check ---' -ForegroundColor Cyan

            # Check Windows & Office
            if (-not $prods) {
                Write-Host '  [!] Windows / Office: No licensed products found with keys.' -ForegroundColor Yellow
                $needsFix = $true
            } else {
                foreach ($p in $prods) {
                    $isKms = $p.Description -match 'VOLUME_KMSCLIENT'
                    $isLic = $p.LicenseStatus -eq 1
                    $days = [math]::Round($p.GracePeriodRemaining / 1440, 0)
                    $daysText = if ($isLic -and $isKms) { " ($days days left)" } else { '' }
                    $chan = if ($isKms) { 'KMS' } elseif ($p.ApplicationID -eq $winAppId -and $gvlk) { 'GVLK eligible' } else { 'Retail/OEM' }
                    $stat = $statusName[[int]$p.LicenseStatus]

                    if ($isLic) {
                        Write-Host ("  [OK] {0,-46} {1,-10} {2}{3}" -f $p.Name, $stat, $chan, $daysText) -ForegroundColor Green
                    } else {
                        Write-Host ("  [!]  {0,-46} {1,-10} {2} (EXPIRED/UNLICENSED)" -f $p.Name, $stat, $chan) -ForegroundColor Red
                        $needsFix = $true
                        $unlicensedProds += $p
                    }
                }
            }

            # Check SPSS
            $spssNeedsFix = $false
            $sDirs = @(Get-SpssDirs)
            if ($sDirs.Count -gt 0) {
                $isPing = Test-NetConnection $spssLs -Port 5093 -InformationLevel Quiet -WarningAction SilentlyContinue  # relay port, not ping
                foreach ($sd in $sDirs) {
                    $appName = Split-Path $sd -Leaf
                    $lshostFile = Join-Path $sd 'lshost'
                    $curHost = if (Test-Path $lshostFile) { (Get-Content $lshostFile -Raw -ErrorAction SilentlyContinue).Trim() } else { $null }
                    $infFile = Join-Path $sd 'spssprod.inf'
                    $infHost = if (Test-Path $infFile) {
                        $m = (Get-Content $infFile | Select-String '^\s*DaemonHost\s*=\s*(.+)$')
                        if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { $null }
                    } else { $null }

                    $hostOk = ($curHost -eq $spssLs) -or ($infHost -eq $spssLs) -or ($env:LSHOST -eq $spssLs)
                    if ($hostOk) {
                        Write-Host ("  [OK] SPSS ({0,-16}) Server = {1} (LSHOST OK)" -f $appName, $spssLs) -ForegroundColor Green
                    } else {
                        Write-Host ("  [!]  SPSS ({0,-16}) Server NOT set (Expected: {1})" -f $appName, $spssLs) -ForegroundColor Yellow
                        $needsFix = $true
                        $spssNeedsFix = $true
                    }
                }
                if ($isPing) {
                    Write-Host "       License Server ($spssLs) Network Connection: OK (Connected)" -ForegroundColor Green
                } else {
                    Write-Host "       [!] License Server ($spssLs): No network reply." -ForegroundColor Yellow
                    Write-Host "           -> Check SpssLicenseRelay on Server 72 (TCP/UDP 5093), or connect Fortinet SPSS VPN (gwspss.nsru.ac.th:10443)" -ForegroundColor Yellow
                }
            }
            Write-Host ''
        }

        # Determine if we should proceed with activation / fix
        $proceed = $false
        $chosen = @()

        if ($autoOfficeActivate) {
            # Auto-triggered from Install software: silent activation for Office and SPSS
            $proceed = $true
            $chosen = $prods | Where-Object { $_.ApplicationID -eq $offAppId -and ($_.LicenseStatus -ne 1 -or $_.Description -notmatch 'VOLUME_KMSCLIENT') }
        } elseif ($needsFix) {
            Write-Host '  [!] Found expired, unlicensed, or unconfigured products on this PC.' -ForegroundColor Yellow
            $ans = Read-Host '  Activate and fix licenses now? [Y/n] (Enter = Yes, B = Back)'
            if ($ans -notmatch '^(n|no|b)$') {
                $proceed = $true
                $chosen = if ($unlicensedProds) { $unlicensedProds } else { $prods | Where-Object { $_.LicenseStatus -ne 1 -or $_.Description -notmatch 'VOLUME_KMSCLIENT' } }
            }
        } else {
            Log 'All detected licenses are active and healthy.' 'Green'
            if ($interactive) {
                $ans = Read-Host '  Force re-activate / renew KMS license counter now? [y/N] (Enter = Back)'
                if ($ans -match '^(y|yes)$') {
                    $proceed = $true
                    $chosen = $prods
                }
            }
        }

        if ($proceed) {
            $kmsReachable = Test-NetConnection $kms -Port 1688 -InformationLevel Quiet -WarningAction SilentlyContinue
            if (-not $kmsReachable) {
                Log "FAIL: cannot reach KMS $($kms):1688 (must be on campus network or VPN)" 'Red'
                $global:LabExitCode = 5
            } else {
                $svc = Get-CimInstance SoftwareLicensingService
                if (-not $dryRun) {
                    Invoke-CimMethod -InputObject $svc -MethodName SetKeyManagementServiceMachine -Arguments @{ MachineName = $kms } | Out-Null
                    Invoke-CimMethod -InputObject $svc -MethodName SetKeyManagementServicePort -Arguments @{ PortNumber = [uint32]1688 } | Out-Null
                }
                foreach ($p in $chosen) {
                    $label = $p.Name
                    if ($dryRun) { Log "  [dry] activate $label"; continue }
                    # Windows retail/OEM -> switch to KMS client key first
                    if ($p.ApplicationID -eq $winAppId -and $p.Description -notmatch 'VOLUME_KMSCLIENT') {
                        if (-not $gvlk) { Log "$label : SKIP no GVLK for edition '$edition'" 'Yellow'; continue }
                        try {
                            Invoke-CimMethod -InputObject $svc -MethodName InstallProductKey -Arguments @{ ProductKey = $gvlk } | Out-Null
                            Invoke-CimMethod -InputObject $svc -MethodName RefreshLicenseStatus | Out-Null
                            $p = Get-LicProducts | Where-Object ApplicationID -eq $winAppId | Select-Object -First 1
                            Log "$label : GVLK installed ($edition)"
                        } catch { Log "$label : FAIL install GVLK $($_.Exception.Message)" 'Red'; $global:LabExitCode = 5; continue }
                    }
                    if ($p.Description -notmatch 'VOLUME_KMSCLIENT') {
                        Log "$label : SKIP not a volume (KMS) edition - retail/subscription cannot use KMS" 'Yellow'; continue
                    }
                    try {
                        Invoke-CimMethod -InputObject $p -MethodName Activate -ErrorAction Stop | Out-Null
                        Log "$label : activated successfully" 'Green'
                    } catch {
                        $hr = '0x{0:X8}' -f $_.Exception.HResult
                        Log "$label : FAIL $hr $($_.Exception.Message)" 'Red'; $global:LabExitCode = 5
                    }
                }

                # Trigger OSPP.VBS for Office if present to ensure Click-to-Run activation
                if ($osppFiles -and ($autoOfficeActivate -or ($chosen | Where-Object ApplicationID -eq $offAppId) -or ($unlicensedProds | Where-Object ApplicationID -eq $offAppId))) {
                    foreach ($ospp in $osppFiles) {
                        if ($dryRun) { Log "  [dry] ospp.vbs -> $ospp"; continue }
                        Log "Setting Office KMS host via $ospp..."
                        cscript.exe //nologo $ospp /sethst:$kms | Out-Null
                        $actOut = cscript.exe //nologo $ospp /act
                        $actSummary = ($actOut | Select-String -Pattern '<Product activation' -Context 0,1) -join ' '
                        if ($actOut -match 'successful') {
                            Log "Office KMS activation successful via OSPP" 'Green'
                        } elseif ($actSummary) {
                            Log "OSPP: $actSummary" 'Yellow'
                        }
                    }
                }

                # Fix SPSS if needed or if part of this run
                if ($spssNeedsFix -or $tasks -contains 'SpssLicense' -or ($autoOfficeActivate -and $hasSpss)) {
                    if ($spssLs) {
                        $sDirs = @(Get-SpssDirs)
                        if ($sDirs.Count -gt 0) {
                            Set-SpssLicense $sDirs $spssLs
                            $isPing = Test-NetConnection $spssLs -Port 5093 -InformationLevel Quiet -WarningAction SilentlyContinue  # relay port, not ping
                            if ($isPing) {
                                Log "  SPSS License Server ($spssLs) reachable: OK" 'Green'
                            } else {
                                Log "  [!] SPSS License Server ($spssLs) unreachable!" 'Yellow'
                                Log "      -> Check SpssLicenseRelay on Server 72 (TCP/UDP 5093), or connect Fortinet SPSS VPN (gwspss.nsru.ac.th:10443)" 'Yellow'
                            }
                        }
                    }
                }

                Invoke-CimMethod -InputObject $svc -MethodName RefreshLicenseStatus -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }


    # ============ RemoveAI (Windows Copilot, Recall, AI Search, Click to Do) ============
    if ($tasks -contains 'RemoveAI') {
        Log '== Remove Windows AI ==' 'Cyan'

        # 1. Disable Copilot (System & Per-User Policies)
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 0 'DWord'
        $hives = Get-UserHives
        try {
            foreach ($h in $hives) {
                Set-Reg "$($h.Key)\Software\Policies\Microsoft\Windows\WindowsCopilot" 'TurnOffWindowsCopilot' 1 'DWord'
                Set-Reg "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'ShowCopilotButton' 0 'DWord'
            }
        } finally { Close-UserHives $hives }
        Log '  Copilot: disabled via Group Policy & taskbar button hidden' 'Green'

        # 2. Disable Windows Recall (AI Data Analysis & Optional Feature)
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 'DWord'
        $hives = Get-UserHives
        try {
            foreach ($h in $hives) {
                Set-Reg "$($h.Key)\Software\Policies\Microsoft\Windows\WindowsAI" 'DisableAIDataAnalysis' 1 'DWord'
            }
        } finally { Close-UserHives $hives }
        if (-not $dryRun) {
            dism.exe /Online /Disable-Feature /FeatureName:Recall /NoRestart /Quiet 2>$null | Out-Null
        }
        Log '  Windows Recall: disabled via policy & optional feature disabled' 'Green'

        # 3. Disable AI Search / Bing in Windows Search
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 0 'DWord'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0 'DWord'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1 'DWord'
        $hives = Get-UserHives
        try {
            foreach ($h in $hives) {
                Set-Reg "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Search" 'BingSearchEnabled' 0 'DWord'
            }
        } finally { Close-UserHives $hives }
        Log '  Windows Search: Bing web search & AI suggestions disabled' 'Green'

        # 4. Remove Copilot, Recall, AI Provisioned AppX Packages
        $aiPatterns = '*Copilot*', '*Recall*', '*Windows.Ai*'
        foreach ($pattern in $aiPatterns) {
            Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                Log "  Remove Appx: $($_.Name)"
                if (-not $dryRun) { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
            }
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -like $pattern | ForEach-Object {
                Log "  Remove Provisioned: $($_.DisplayName)"
                if (-not $dryRun) { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
            }
        }
        Log 'Windows AI components removed and disabled successfully.' 'Green'
    }

    # ============ RevertRemoveAI ============
    if ($tasks -contains 'RevertRemoveAI') {
        Log '== Revert Remove Windows AI ==' 'Cyan'
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HubsSidebarEnabled' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowCloudSearch' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'ConnectedSearchUseWeb' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'DisableWebSearch' -ErrorAction SilentlyContinue
        $hives = Get-UserHives
        try {
            foreach ($h in $hives) {
                Remove-ItemProperty -Path "$($h.Key)\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name 'TurnOffWindowsCopilot' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name 'ShowCopilotButton' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path "$($h.Key)\Software\Policies\Microsoft\Windows\WindowsAI" -Name 'DisableAIDataAnalysis' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Search" -Name 'BingSearchEnabled' -ErrorAction SilentlyContinue
            }
        } finally { Close-UserHives $hives }
        if (-not $dryRun) {
            dism.exe /Online /Enable-Feature /FeatureName:Recall /NoRestart /Quiet 2>$null | Out-Null
        }
        Log 'Windows AI policies reverted: Copilot and Recall can be re-enabled.' 'Green'
    }

    # ============ Tune (safe tweaks only) ============
    if ($tasks -contains 'Tune') {
        Log '== Tune ==' 'Cyan'
        if (-not $dryRun) { powercfg -setactive SCHEME_MIN; Log 'power plan: High performance' }
        $hives = Get-UserHives
        try {
            foreach ($h in $hives) {
                Set-Reg "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" 'VisualFXSetting' 2 'DWord'
            }
        } finally { Close-UserHives $hives }
        if (-not $dryRun) {
            Get-ChildItem $env:TEMP, "$env:SystemRoot\Temp" -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Log 'temp cleared'
        }
    }

    # ============ RevertTune: restore Balanced power plan & default visual effects ============
    if ($tasks -contains 'RevertTune') {
        Log '== Revert Tune (Restore defaults) ==' 'Cyan'
        if (-not $dryRun) {
            powercfg -setactive SCHEME_BALANCED
            Log 'power plan: Balanced (Default)'
        }
        $hives = Get-UserHives
        try {
            foreach ($h in $hives) {
                # VisualFXSetting 0 = Let Windows decide what's best for my computer (Default)
                Set-Reg "$($h.Key)\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" 'VisualFXSetting' 0 'DWord'
            }
        } finally { Close-UserHives $hives }
        Log 'Tune reverted: Balanced power plan & default visual effects restored' 'Green'
    }

    if ($shareDrive) { Remove-PSDrive -Name LabDeploy -Force -ErrorAction SilentlyContinue; Log 'share disconnected' }
    $statusLabel = if ($interactive) { "Task finished (code $global:LabExitCode)" } else { "Done (exit $global:LabExitCode)" }
    Log "$statusLabel. Log: $logFile" $(if ($global:LabExitCode) { 'Yellow' } else { 'Green' })
    # failed run = setup_action (not 'crash'): crash opens an incident on assigned machines in LibDesk
    $evType = if ($global:LabExitCode -ne 0) { 'setup_action' } elseif ($tasks -contains 'InstallApps') { 'app_update' } else { 'setup_action' }
    $evTitle = if ($global:LabExitCode -ne 0) { "lab-setup failed (code $global:LabExitCode): $($tasks -join ', ')" } else { "lab-setup: $($tasks -join ', ')" }
    Send-LabTelemetry -eventType $evType -title $evTitle -detail "Status: $statusLabel`nTasks: $($tasks -join ', ')" | Out-Null 

        if ($interactive -and $cwAuto) {
            continue  # auto-install pass done, go straight to the menu
        } elseif ($interactive) {
            Write-Host ""
            Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "Press Enter to return to main menu (or Q to Quit)..." -ForegroundColor Cyan
            $ans = Read-Host
            if ($ans -eq 'q' -or $ans -eq 'Q') { break }
        } else {
            break
        }
    }
}

# Exit codes: 0 ok, 1 not admin/config/host guard, 2 share connect, 3 manifest, 4 package failed, 5 activation failed
$global:LabExitCode = 0
Invoke-LabSetup
$global:LASTEXITCODE = $global:LabExitCode
if ($PSCommandPath) { exit $global:LabExitCode }   # saved-file run; irm|iex keeps the window open
