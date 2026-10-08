# lab.ps1 - Lab PC setup (Windows 11 Pro)
# Run in PowerShell as Administrator (short bootstrap, verifies this file's SHA256):
#   irm x66clrf.github.io/lab-setup/go.txt | iex
# Direct:
#   irm https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.0/lab.ps1 | iex
# Dry run (list actions, change nothing):   $env:LAB_DRYRUN='1'; irm ... | iex
# Skip menu (comma list):                   $env:LAB_TASKS='Install,Fonts'; irm ... | iex
#   Tasks: Cleanup BrowserClean RemoveApps Tune Install Winget Activate LicenseCheck Fonts Certs WinRARTheme Wallpaper BrowserSearch SpssLicense Check Unlock AutoSleep KeepAlive
# Skip "type YES" before wiping data drives:  $env:LAB_YES='1'

# Folder of this script when run as a file (run.cmd on the share); empty for irm|iex
$LabScriptDir = if ($PSCommandPath) { Split-Path $PSCommandPath -Parent }

# Pin to main
$LabConfigUrl = 'https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.0/config.json'

function Invoke-LabSetup {
    $ErrorActionPreference = 'Stop'
    $dryRun = $env:LAB_DRYRUN -eq '1'
    # Menu groups: installing software is separate from optimizing the PC
    $groups = [ordered]@{
        'Install software & auto-activate (Office, SPSS, share, winget)' = @('Install', 'Winget')
        'Optimize PC (Cleanup, BrowserClean, RemoveApps, Tune)'          = @('Optimize')
        'Check & fix licenses (ตรวจไลเซนส์ Windows, Office, SPSS - ต่ออายุ)' = @('LicenseCheck')
        'Lab settings (Fonts, Certs, WinRAR theme, Wallpaper, Google search)' = @('Settings')
        'Check network status (VPN gateways, KMS, share ports)'         = @('Check')
        'Wallpaper (Set & Lock / Unlock)'                               = @('Wallpaper')
        'Auto Wake/Sleep schedule (08:20 / 16:40)'                      = @('AutoSleep')
        'Campus Internet KeepAlive (ล็อกอินเน็ตอัตโนมัติเบื้องหลัง - ตัวเลือกเฉพาะเครื่อง)' = @('KeepAlive')
    }
    $subMenus = @{
        'Optimize' = @('Cleanup', 'BrowserClean', 'RemoveApps', 'Tune')
        'Settings' = @('Fonts', 'Certs', 'WinRARTheme', 'BrowserSearch', 'SpssLicense')
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
        # returns selected items; Enter/0 = all; B = back to main menu
        Write-Host "`n--- $title ---" -ForegroundColor Cyan
        for ($i = 0; $i -lt $items.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $items[$i]) }
        Write-Host '  [B] Back to main menu' -ForegroundColor DarkGray
        $s = Read-Host 'Choose (e.g. 1,3,5 or 1-3 / Enter = all / B = back)'
        if ($s -eq 'b' -or $s -eq 'B') { return $null }
        if ($s -notmatch '\d') { return $items }
        $indices = Parse-IndexList $s $items.Count
        if ($indices.Count -eq 0) { return $null }
        $indices | ForEach-Object { $items[$_ - 1] }
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
            if ($exclusions | Where-Object { $_ -ilike "$full\*" }) { Clear-Tree $full $exclusions; continue }
            Remove-Path $full
        }
    }
    function Get-Installed($pattern) {
        $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pattern }
    }

    $interactive = -not $env:LAB_TASKS
    while ($true) {
        $global:LabExitCode = 0
        $tasks = @()
        $autoOfficeActivate = $false
        if ($interactive) {
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
            $tasks = $env:LAB_TASKS -split ',' | ForEach-Object { $_.Trim() }
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
    $strictShareTasks = @($tasks | Where-Object { $_ -in 'Install', 'Wallpaper', 'Certs', 'WinRARTheme' })
    $fontTask = @($tasks | Where-Object { $_ -eq 'Fonts' })
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
                Log "[i] $shareHost port 445 unreachable (Wi-Fi/external). Will use local/GitHub fonts fallback." 'Yellow'
            }
        } elseif (Test-Path "$uncShare\manifest.json") {
            $shareOk = $true; Log "share OK: $uncShare (stored credential)"
        } else {
            Log "No stored credential for $shareHost. Tip: cmdkey /add:$shareHost /user:$shareHost\$($cfg.deployUser) /pass" 'Yellow'
            $cred = Get-Credential -UserName "$shareHost\$($cfg.deployUser)" -Message "Password for $uncShare"
            if (-not $cred) {
                if ($strictShareTasks) { Log 'FAIL: no credential given' 'Red'; $global:LabExitCode = 2 }
            } else {
                try {
                    $shareDrive = New-PSDrive -Name LabDeploy -PSProvider FileSystem -Root $uncShare -Credential $cred -ErrorAction Stop
                    $share = 'LabDeploy:'; $shareOk = $true; Log "share OK: $uncShare"
                } catch {
                    $m = $_.Exception.Message
                    $why = if ($m -match 'password|logon failure|user name') { 'wrong user name or password' }
                           elseif ($m -match 'denied') { 'access denied (account has no permission on share)' }
                           elseif ($m -match 'network path|network name') { 'share name not found' }
                           elseif ($m -match 'multiple connections') { 'already connected with another user (run: net use * /delete)' }
                           else { $m }
                    if ($strictShareTasks) { Log "FAIL connect share: $why" 'Red'; $global:LabExitCode = 2 }
                    else { Log "Notice connect share: $why" 'Yellow' }
                }
            }
        }
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
        if (-not $shareOk) { Write-Host '  (share not connected - only winget apps listed)' -ForegroundColor Yellow }

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
            if ($found -and -not $cur) { Log "$tag SKIP installed (no DisplayVersion to compare)"; continue }
            if ($cur) {
                $upToDate = try { [version]$cur.DisplayVersion -ge [version]$pkg.version }
                            catch { [string]$cur.DisplayVersion -ge [string]$pkg.version }
                if ($upToDate) { Log "$tag SKIP installed $($cur.DisplayVersion) >= $($pkg.version)"; continue }
                Log "$tag UPDATE $($cur.DisplayVersion) -> $($pkg.version)"
            } else { Log "$tag INSTALL $($pkg.version)" }
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
                    $url = "https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.0/fonts/$encodedFn"
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

    # ============ SPSS license (Concurrent: write license server into spssprod.inf) ============
    $ibmRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path "$_\IBM") } | ForEach-Object { "$_\IBM" }
    $spssInfs = @($ibmRoots | ForEach-Object { Get-ChildItem $_ -Recurse -Filter 'spssprod.inf' -ErrorAction SilentlyContinue })
    if ($tasks -contains 'SpssLicense') {
        Log '== SpssLicense ==' 'Cyan'
        $ls = $cfg.spss.licenseServer
        if (-not $ls) { Log 'SKIP: spss.licenseServer is empty in config.json' 'Yellow' }
        elseif (-not $spssInfs) { Log 'SKIP: no spssprod.inf found (SPSS/Amos not installed?)' 'Yellow' }
        else {
            foreach ($inf in $spssInfs) {
                $txt = Get-Content $inf.FullName
                $new = $txt | ForEach-Object { if ($_ -match '^\s*DaemonHost\s*=') { "DaemonHost=$ls" } elseif ($_ -match '^\s*LicenseType\s*=') { 'LicenseType=Network' } else { $_ } }
                if (-not ($new -match '^DaemonHost=')) { $new += "DaemonHost=$ls" }
                if (-not ($new -match '^LicenseType=')) { $new += 'LicenseType=Network' }
                if (($txt -join "`n") -ne ($new -join "`n")) {
                    if ($dryRun) { Log "  [dry] $($inf.FullName) -> DaemonHost=$ls"; continue }
                    Copy-Item $inf.FullName "$($inf.FullName).bak" -Force
                    Set-Content $inf.FullName $new -Encoding ASCII
                    Log "  $($inf.FullName) -> DaemonHost=$ls (backup .bak)" 'Green'
                } else {
                    Log "  $($inf.FullName): already set"
                }
                # Sentinel LM lshost file in the same directory
                $lsHostFile = Join-Path $inf.DirectoryName 'lshost'
                if (-not (Test-Path $lsHostFile) -or (Get-Content $lsHostFile -ErrorAction SilentlyContinue).Trim() -ne $ls) {
                    if (-not $dryRun) { Set-Content -Path $lsHostFile -Value $ls -Encoding ASCII }
                    Log "  $lsHostFile -> $ls" 'Green'
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
        foreach ($inf in $spssInfs) {
            $kv = @{}; Get-Content $inf.FullName | Where-Object { $_ -match '^\s*(DaemonHost|LicenseType)\s*=\s*(.*)$' } | ForEach-Object { $kv[$Matches[1]] = $Matches[2] }
            Log ("  {0}`n      LicenseType={1}  DaemonHost={2}" -f $inf.FullName, $kv.LicenseType, $kv.DaemonHost)
            if ($kv.DaemonHost) {
                $pong = Test-Connection $kv.DaemonHost -Count 1 -Quiet -ErrorAction SilentlyContinue
                Log ("      license server ping: {0}" -f $(if ($pong) { 'OK' } else { 'no reply (connect SPSS VPN if off-campus)' })) $(if ($pong) { 'Green' } else { 'Yellow' })
            }
        }
        if ($cfg.spss.licenseServer) { Log "  config spss.licenseServer = $($cfg.spss.licenseServer)" }
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
            powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKING 1 2>$null | Out-Null
            powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null
            schtasks /create /tn "Lab_AutoSleep" /tr "powershell -Command Add-Type -Assembly System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState('Suspend', `$false, `$false)" /sc weekly /d MON,TUE,WED,THU,FRI /st 16:40 /ru "SYSTEM" /f 2>$null | Out-Null
            $act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c ping 1.1.1.1 -n 1'
            $trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At '08:20'
            $set = New-ScheduledTaskSettingsSet -WakeToRun
            Register-ScheduledTask -TaskName 'Lab_AutoWake' -Action $act -Trigger $trg -Settings $set -User 'SYSTEM' -Force | Out-Null
            Log "Auto Wake (08:20) & Sleep (16:40) configured." 'Green'
        } elseif ($choice -eq '2') {
            if ($dryRun) { Log "  [dry] remove Auto Wake/Sleep tasks"; continue }
            schtasks /delete /tn "Lab_AutoSleep" /f 2>$null | Out-Null
            schtasks /delete /tn "Lab_AutoWake" /f 2>$null | Out-Null
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
        $shareEnv = if ($shareOk) { Join-Path $share 'net-auth.env' } else { "\\$shareHost\LabDeploy\net-auth.env" }

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
            elseif (Test-Path $shareEnv) { Write-Host "Found on Server 72 ($shareEnv)" -ForegroundColor Green }
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
                        } catch { Log "FAIL write to share: $($_.Exception.Message)" 'Yellow' }
                    }
                }
            } else { Log "Credentials not entered. Cancelled." 'Yellow' }
        }

        if ($kaAction -in '1', '2') {
            # Ensure local env exists (fetch from 72 if missing)
            if (-not (Test-Path $localEnv)) {
                if (Test-Path $shareEnv) {
                    try {
                        Copy-Item $shareEnv $localEnv -Force
                        icacls $localEnv /inheritance:r /grant:r 'Administrators:(F)' 'SYSTEM:(F)' | Out-Null
                        Log "Fetched net-auth.env from Server 72 -> $localEnv" 'Green'
                    } catch { Log "FAIL copy net-auth.env from share: $($_.Exception.Message)" 'Yellow' }
                }
            }
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
                $kaUrl = "https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.0/net-auth/KeepAlive.ps1"
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
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

            try {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigStartup, $trigLogon) -Principal $principal -Settings $settings -Force | Out-Null
                Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                Log "KeepAlive task '$taskName' installed & started successfully (100% hidden background, runs as SYSTEM on boot/logon)." 'Green'
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
        $ibmRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path "$_\IBM") } | ForEach-Object { "$_\IBM" }
        $spssInfs = @($ibmRoots | ForEach-Object { Get-ChildItem $_ -Recurse -Filter 'spssprod.inf' -ErrorAction SilentlyContinue })
        $spssLs   = $cfg.spss.licenseServer

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
            if ($spssInfs) {
                foreach ($inf in $spssInfs) {
                    $appName = Split-Path (Split-Path $inf.FullName -Parent) -Leaf
                    $curHost = $null
                    Get-Content $inf.FullName | Where-Object { $_ -match '^\s*DaemonHost\s*=\s*(.+)$' } | ForEach-Object { $curHost = $Matches[1].Trim() }
                    if ($curHost -eq $spssLs) {
                        Write-Host ("  [OK] SPSS ({0,-16}) DaemonHost = {1}" -f $appName, $curHost) -ForegroundColor Green
                    } else {
                        Write-Host ("  [!]  SPSS ({0,-16}) DaemonHost = {1} (Expected: {2})" -f $appName, $(if ($curHost) { $curHost } else { 'NOT SET' }), $spssLs) -ForegroundColor Yellow
                        $needsFix = $true
                        $spssNeedsFix = $true
                    }
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
                    if ($spssLs -and $spssInfs) {
                        foreach ($inf in $spssInfs) {
                            $txt = Get-Content $inf.FullName
                            $new = $txt | ForEach-Object { if ($_ -match '^\s*DaemonHost\s*=') { "DaemonHost=$spssLs" } elseif ($_ -match '^\s*LicenseType\s*=') { 'LicenseType=Network' } else { $_ } }
                            if (-not ($new -match '^DaemonHost=')) { $new += "DaemonHost=$spssLs" }
                            if (-not ($new -match '^LicenseType=')) { $new += 'LicenseType=Network' }
                            if (($txt -join "`n") -ne ($new -join "`n")) {
                                if (-not $dryRun) {
                                    Copy-Item $inf.FullName "$($inf.FullName).bak" -Force
                                    Set-Content $inf.FullName $new -Encoding ASCII
                                }
                                Log "  $($inf.FullName) -> DaemonHost=$spssLs (backup .bak)" 'Green'
                            } else {
                                Log "  $($inf.FullName): already set to $spssLs"
                            }
                            $lsHostFile = Join-Path $inf.DirectoryName 'lshost'
                            if (-not (Test-Path $lsHostFile) -or (Get-Content $lsHostFile -ErrorAction SilentlyContinue).Trim() -ne $spssLs) {
                                if (-not $dryRun) { Set-Content -Path $lsHostFile -Value $spssLs -Encoding ASCII }
                                Log "  $lsHostFile -> $spssLs" 'Green'
                            }
                        }
                    }
                }

                Invoke-CimMethod -InputObject $svc -MethodName RefreshLicenseStatus -ErrorAction SilentlyContinue | Out-Null
            }
        }
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

    if ($shareDrive) { Remove-PSDrive -Name LabDeploy -Force -ErrorAction SilentlyContinue; Log 'share disconnected' }
    $statusLabel = if ($interactive) { "Task finished (code $global:LabExitCode)" } else { "Done (exit $global:LabExitCode)" }
    Log "$statusLabel. Log: $logFile" $(if ($global:LabExitCode) { 'Yellow' } else { 'Green' })

        if ($interactive) {
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
