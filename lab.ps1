# lab.ps1 - Lab PC setup (Windows 11 Pro)
# Run in PowerShell as Administrator (short bootstrap, verifies this file's SHA256):
#   irm x66clrf.github.io/lab-setup/go.txt | iex
# Direct:
#   irm https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.0/lab.ps1 | iex
# Dry run (list actions, change nothing):   $env:LAB_DRYRUN='1'; irm ... | iex
# Skip menu (comma list):                   $env:LAB_TASKS='Install,Fonts'; irm ... | iex
#   Tasks: Cleanup BrowserClean RemoveApps Tune Install Winget Activate Fonts Certs WinRARTheme Wallpaper BrowserSearch SpssLicense Check Unlock
# Skip "type YES" before wiping data drives:  $env:LAB_YES='1'

# Folder of this script when run as a file (run.cmd on the share); empty for irm|iex
$LabScriptDir = if ($PSCommandPath) { Split-Path $PSCommandPath -Parent }

# Pin to a tag/commit, never 'main'
$LabConfigUrl = 'https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.0/config.json'

function Invoke-LabSetup {
    $ErrorActionPreference = 'Stop'
    $dryRun = $env:LAB_DRYRUN -eq '1'
    # Menu groups: installing software is separate from optimizing the PC
    $groups = [ordered]@{
        'Install software (choose programs)'           = @('Install', 'Winget')
        'Optimize PC (Cleanup, BrowserClean, RemoveApps, Tune)' = @('Optimize')
        'Activate Windows / Office (campus KMS)'       = @('Activate')
        'Lab settings (Fonts, Certs, WinRAR theme, Wallpaper, Google search, SPSS license)' = @('Settings')
        'Check status (VPN, KMS, share, SPSS)'         = @('Check')
        'Unlock wallpaper'                             = @('Unlock')
    }
    $subMenus = @{
        'Optimize' = @('Cleanup', 'BrowserClean', 'RemoveApps', 'Tune')
        'Settings' = @('Fonts', 'Certs', 'WinRARTheme', 'Wallpaper', 'BrowserSearch', 'SpssLicense')
    }
    function Read-Pick($items, $title) {
        # returns selected items; Enter/0 = all
        Write-Host "`n--- $title ---" -ForegroundColor Cyan
        for ($i = 0; $i -lt $items.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $items[$i]) }
        $s = Read-Host 'Choose (e.g. 1,3 / Enter = all)'
        if ($s -notmatch '\d') { return $items }
        $s -split '[,\s]+' | Where-Object { $_ -match '^\d+$' -and [int]$_ -ge 1 -and [int]$_ -le $items.Count } | ForEach-Object { $items[[int]$_ - 1] }
    }
    $interactive = -not $env:LAB_TASKS
    if (-not $interactive) { $tasks = $env:LAB_TASKS -split ',' | ForEach-Object { $_.Trim() } }
    else {
        Write-Host "`n=== Lab Setup ===" -ForegroundColor Cyan
        $gNames = @($groups.Keys)
        for ($i = 0; $i -lt $gNames.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $gNames[$i]) }
        Write-Host '  [Q] Quit'
        $pick = Read-Host 'Choose'
        if ($pick -notmatch '^\s*\d+\s*$' -or [int]$pick -lt 1 -or [int]$pick -gt $gNames.Count) { return }
        $tasks = @()
        foreach ($t in $groups[$gNames[[int]$pick - 1]]) {
            if ($subMenus.ContainsKey($t)) { $tasks += @(Read-Pick $subMenus[$t] $gNames[[int]$pick - 1]) } else { $tasks += $t }
        }
        if (-not $tasks) { Write-Host 'Nothing selected.'; return }
    }
    $pickPackages = $interactive -and ($tasks -contains 'Install')   # per-program selection happens after the share connects

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

    Log "Tasks: $($tasks -join ', ')  DryRun: $dryRun" 'Cyan'
    # config source: $env:LAB_CONFIG path > config.json next to this script (run.cmd on the share) > GitHub tag
    $cfgPath = if ($env:LAB_CONFIG) { $env:LAB_CONFIG }
               elseif ($LabScriptDir -and (Test-Path (Join-Path $LabScriptDir 'config.json'))) { Join-Path $LabScriptDir 'config.json' }
    try { $cfg = if ($cfgPath) { Log "config: $cfgPath"; Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json }
                 else { Log "config: $LabConfigUrl"; Invoke-RestMethod -Uri $LabConfigUrl -UseBasicParsing } }
    catch { Log "FAIL load config: $($_.Exception.Message)" 'Red'; $global:LabExitCode = 1; return }

    # --- safety guard: only lab machines ---
    if ($env:COMPUTERNAME -notmatch $cfg.allowedHostPattern) {
        Log "STOP: $env:COMPUTERNAME not match allowedHostPattern '$($cfg.allowedHostPattern)'" 'Red'; $global:LabExitCode = 1; return
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
    function Remove-Path($p) {
        if ($dryRun) { Log "  [dry] delete $p"; return }
        try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop; Log "  deleted $p" }
        catch { Log "  FAIL $p : $($_.Exception.Message)" 'Yellow' }
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
        if (-not $dryRun) { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Log 'Recycle Bin emptied' }
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
    if ($tasks | Where-Object { $_ -in 'Install', 'Wallpaper', 'Fonts', 'Certs', 'WinRARTheme' }) {
        if (Test-Path "$uncShare\manifest.json") { $shareOk = $true; Log "share OK: $uncShare (stored credential)" }
        elseif (-not (Test-NetConnection $shareHost -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
            Log "FAIL: cannot reach $shareHost port 445 (offline, wrong subnet, or blocked by firewall)" 'Red'
        } else {
            Log "No stored credential for $shareHost. Tip: cmdkey /add:$shareHost /user:$shareHost\$($cfg.deployUser) /pass" 'Yellow'
            $cred = Get-Credential -UserName "$shareHost\$($cfg.deployUser)" -Message "Password for $uncShare"
            if (-not $cred) { Log 'FAIL: no credential given' 'Red' }
            else {
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
                    Log "FAIL connect share: $why" 'Red'
                }
            }
        }
        if (-not $shareOk) { $global:LabExitCode = 2 }
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
        $chosen = @(Read-Pick @($items | ForEach-Object Label) 'Install software')
        $sel = @($items | Where-Object { $chosen -contains $_.Label })
        $pkgs      = @($sel | Where-Object Kind -eq 'pkg'    | ForEach-Object Ref)
        $wingetSel = @($sel | Where-Object Kind -eq 'winget' | ForEach-Object Ref)
        Log "Selected: $((@($pkgs | ForEach-Object name) + $wingetSel) -join ', ')"
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
                    Write-Host "  ACTION NEEDED - $($pkg.name)" -ForegroundColor Yellow
                    foreach ($ln in @($pkg.notice)) { if ($ln) { Write-Host "  $ln" -ForegroundColor Yellow } }
                    if ($noticeText) {
                        Write-Host ''
                        foreach ($ln in $noticeText -split "`r?`n") { Write-Host "    $ln" -ForegroundColor White }
                        try { Set-Clipboard -Value $noticeText; Write-Host '  (copied to clipboard - press Ctrl+V in the installer)' -ForegroundColor Yellow } catch {}
                    }
                    Write-Host ('=' * 60) -ForegroundColor Yellow
                    Log "$tag notice shown"
                    if ($interactive) { [void](Read-Host 'Press Enter to start the installer') }
                }
                $a = [string]$pkg.args
                if ($dst -like '*.msi') { $p = Start-Process msiexec.exe -ArgumentList "/i `"$dst`" $a" -WorkingDirectory $workDir -Wait -PassThru }
                elseif ($a)             { $p = Start-Process $dst -ArgumentList $a -WorkingDirectory $workDir -Wait -PassThru }
                else                    { $p = Start-Process $dst -WorkingDirectory $workDir -Wait -PassThru }
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

    # ============ Wallpaper (lock) ============
    if ($tasks -contains 'Wallpaper' -and $shareOk) {
        Log '== Wallpaper ==' 'Cyan'
        # any image in the share's wallpaper folder; menu picks one, otherwise the newest file
        $imgs = @(Get-ChildItem (Join-Path $share $cfg.wallpaper.folder) -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -in '.jpg', '.jpeg', '.png', '.bmp' } | Sort-Object LastWriteTime -Descending)
        $src = $null
        if ($imgs.Count -eq 1 -or ($imgs.Count -gt 1 -and -not $interactive)) { $src = $imgs[0].FullName }
        elseif ($imgs.Count -gt 1) {
            $labels = @($imgs | ForEach-Object { '{0,-40} {1:yyyy-MM-dd}' -f $_.Name, $_.LastWriteTime })
            Write-Host "`n--- Wallpaper ---" -ForegroundColor Cyan
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
            Log 'Wallpaper applies at next sign-in' 'Green'
        }
    }

    # ============ Fonts (all users, skip ones already present) ============
    if ($tasks -contains 'Fonts' -and $shareOk) {
        Log '== Fonts ==' 'Cyan'
        $fontSrc = Join-Path $share $cfg.fonts.folder
        $fontDir = Join-Path $env:SystemRoot 'Fonts'
        $fontReg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
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
        Log "Fonts: $added new (others already installed). Apps see them after restart/sign-in." 'Green'
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
    $spssInfs = @(Get-ChildItem "$env:ProgramFiles\IBM" -Recurse -Filter 'spssprod.inf' -ErrorAction SilentlyContinue)
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
                if (($txt -join "`n") -eq ($new -join "`n")) { Log "  $($inf.FullName): already set"; continue }
                if ($dryRun) { Log "  [dry] $($inf.FullName) -> DaemonHost=$ls"; continue }
                Copy-Item $inf.FullName "$($inf.FullName).bak" -Force
                Set-Content $inf.FullName $new -Encoding ASCII
                Log "  $($inf.FullName) -> DaemonHost=$ls (backup .bak)" 'Green'
            }
        }
    }

    # ============ Check (read-only status: SPSS, VPN gateways, KMS, share) ============
    if ($tasks -contains 'Check') {
        Log '== Check ==' 'Cyan'
        function Show-Port($label, $h, $port) {
            $ok = $h -and (Test-NetConnection $h -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue)
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

    # ============ Unlock wallpaper (undo) ============
    if ($tasks -contains 'Unlock') {
        Log '== Unlock wallpaper ==' 'Cyan'
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
    }

    # ============ Activate (university KMS, volume license) ============
    # Detects every Windows/Office product with a key installed right now, shows a list, activates the chosen ones.
    if ($tasks -contains 'Activate') {
        Log '== Activate ==' 'Cyan'
        $kms = $cfg.kms.host
        $winAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
        $offAppId = '0ff1ce15-a989-479d-af46-f275c6370663'
        $statusName = @{ 0='Unlicensed'; 1='Licensed'; 2='OOB grace'; 3='OOT grace'; 4='NonGenuine grace'; 5='Notification'; 6='Extended grace' }
        function Get-LicProducts {
            Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
                Where-Object { $_.ApplicationID -in $winAppId, $offAppId } | Sort-Object ApplicationID, Name
        }
        $svc = Get-CimInstance SoftwareLicensingService

        # Windows not on a KMS channel -> offer GVLK for its edition
        $winProd = Get-LicProducts | Where-Object ApplicationID -eq $winAppId | Select-Object -First 1
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $gvlk    = $cfg.kms.windowsGvlk.$edition

        $prods = @(Get-LicProducts)
        if (-not $prods) { Log 'No Windows/Office product with a key found' 'Yellow' }
        else {
            Write-Host ''
            for ($i = 0; $i -lt $prods.Count; $i++) {
                $p = $prods[$i]
                $kmsOk = $p.Description -match 'VOLUME_KMSCLIENT'
                $chan  = if ($kmsOk) { 'KMS' } elseif ($p.ApplicationID -eq $winAppId -and $gvlk) { "$(($p.Description -split ',')[-1].Trim()) -> GVLK" } else { ($p.Description -split ',')[-1].Trim() + ' (not KMS)' }
                Write-Host ("  [{0}] {1,-55} {2,-14} {3}" -f ($i + 1), $p.Name, $statusName[[int]$p.LicenseStatus], $chan)
            }
            $sel = if ($interactive) { Read-Host 'Activate which? (e.g. 1,3 / Enter = all not licensed)' } else { '' }
            $chosen = if ($sel -match '\d') {
                $sel -split '[,\s]+' | Where-Object { $_ -match '^\d+$' -and [int]$_ -ge 1 -and [int]$_ -le $prods.Count } | ForEach-Object { $prods[[int]$_ - 1] }
            } else { $prods | Where-Object { $_.LicenseStatus -ne 1 -or $_.Description -notmatch 'VOLUME_KMSCLIENT' } }

            if (-not $chosen) { Log 'Activate: nothing to do (all licensed)' 'Green' }
            elseif (-not (Test-NetConnection $kms -Port 1688 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
                Log "FAIL: cannot reach KMS $($kms):1688 (must be on campus network)" 'Red'; $global:LabExitCode = 5
            } else {
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
                        Log "$label : activated" 'Green'
                    } catch {
                        $hr = '0x{0:X8}' -f $_.Exception.HResult
                        Log "$label : FAIL $hr $($_.Exception.Message)" 'Red'; $global:LabExitCode = 5
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
    Log "Done (exit $global:LabExitCode). Log: $logFile" $(if ($global:LabExitCode) { 'Red' } else { 'Green' })
}

# Exit codes: 0 ok, 1 not admin/config/host guard, 2 share connect, 3 manifest, 4 package failed, 5 activation failed
$global:LabExitCode = 0
Invoke-LabSetup
$global:LASTEXITCODE = $global:LabExitCode
if ($PSCommandPath) { exit $global:LabExitCode }   # saved-file run; irm|iex keeps the window open
