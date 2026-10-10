# lab-setup

Lab PC setup for Windows 11 Pro (NSRU lab). One command, menu driven.

## Run (main)

PowerShell **as Administrator** on a lab PC (campus network):

```powershell
irm x66clrf.github.io/lab-setup/lab | iex
```

First time on a PC it asks once for the `labdeploy` share password, then shows the menu. `lab/index.html` only runs `lab.ps1` + `config.json` from `\\192.168.0.72\LabDeploy\lab\`, so edit them on the share - no push needed.

## Run (double-click)

On a lab PC open `\\192.168.0.72\LabDeploy\lab\` and double-click **run.cmd** (asks for admin, then shows the menu).
Config is read from `config.json` next to `lab.ps1` on the share, so edits there apply immediately.

## Run (alternative: pinned GitHub copy, SHA256 checked)

PowerShell **as Administrator**:

```powershell
irm x66clrf.github.io/lab-setup/go.txt | iex
```

`go.txt` downloads `lab.ps1` from the pinned tag and refuses to run it if the SHA256 does not match.

One-time per lab PC (read-only share account; password typed by admin, stored in Windows Credential Manager, never in this repo):

```powershell
cmdkey /add:192.168.0.72 /user:192.168.0.72\labdeploy /pass
```

## Menu

```
=== Lab Setup ===
  [1] Install Software (Office, SPSS, Share packages, Winget)
  [2] Optimize & Clean (Cleanup, BrowserClean, RemoveApps, Tune)
  [3] Diagnostics & Licenses (Network status, Windows/Office/SPSS KMS check & fix)
  [4] Lab Settings & Policies (Fonts, Certs, WinRAR theme, Wallpaper, Search)
  [5] Background Automation (Auto Wake/Sleep, KeepAlive, LibDesk Crash Watcher)
```

In every sub-list: numbers or ranges like `1,3,5` or `1-4`, Enter = default all (revert tasks excluded), or `B` to go back.

| Task | What it does |
|---|---|
| Cleanup | Every user: Downloads & Desktop files/folders moved to Recycle Bin for safe recovery (shortcuts `.lnk`/`.url` kept), user Temp cleared; data drives in `config.json` (asks `YES` per drive) |
| BrowserClean | Chrome/Edge: delete extra profiles (Profile 1, 2...), keep Default; clear its logins, cookies, history, sessions, cache (bookmarks/extensions kept) |
| RemoveApps | Silent-uninstall adware / 3rd-party antivirus (Defender takes over) |
| Install | Install/update packages from `\\192.168.0.72\LabDeploy\manifest.json`. Multi-selection with ranges/re-select loop, 100% silent install (`/qn /norestart`), automatically activates Office KMS and configures SPSS license server upon install. |
| Winget | Install/upgrade latest WinRAR, Foxit Reader via winget |
| LicenseCheck | Inspect Windows, Office, and SPSS license health (licensed, days remaining, KMS, DaemonHost). Prompts to auto-fix/renew if any license is expired or missing. |
| KeepAlive | Optional background daemon for campus LAN captive portal. Runs 100% headless (zero console window) as SYSTEM task, reads credentials from `\\192.168.0.72\LabDeploy\net-auth.env` or local cache. |
| CrashWatcher | Background Scheduled Task (`Lab_CrashWatcher`) running as SYSTEM. Detects BSOD (BugCheck 1001), unexpected shutdowns (6008), and critical app crashes (1000). Reports to LibDesk telemetry to flag machine caution for KPI resolution. |
| Fonts | Thai fonts from share `fonts\` or local/online fallback for all users |
| Certs | Trusted Root import, thumbprint allowlist only |
| WinRARTheme | WinRAR theme for all users |
| Wallpaper | Pick any image in share `wallpaper\` (newest if not asked), locked (Personalize greyed out) |
| BrowserSearch | Google as default search via machine policy (Chrome, Edge, Firefox) |
| RevertBrowserSearch | Remove search engine policies from Chrome, Edge, and Firefox |
| Tune | High performance power plan, lighter visual effects, clear temp |
| RevertTune | Restore Balanced power plan and default Windows visual effects |
| SpssLicense | Write SPSS/Amos concurrent license server into `spssprod.inf` |
| Check | Read-only status: VPN gateways, KMS, share, FortiClient/SPSS/Amos, SPSS license host |
| Unlock | Remove wallpaper lock |

Options: `$env:LAB_DRYRUN='1'` (show only), `$env:LAB_TASKS='Install,Fonts'` (skip menu), `$env:LAB_YES='1'` (no drive prompt).

Log: `C:\ProgramData\LabDeploy\lab.log`.
Exit codes: 0 ok, 1 not admin / config / host guard, 2 share connect, 3 manifest, 4 package failed, 5 activation failed.

## Release a new version

```powershell
.\release.ps1 -Tag v1.1     # pins lab.ps1 to the tag, rewrites go.txt with the new SHA256
```

Then commit, create tag `v1.1` on that commit, push commit + tag.

Installers, license keys and `manifest.json` live on the internal share, never in this repo.
