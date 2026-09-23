# lab-setup

Lab PC setup for Windows 11 Pro (NSRU lab). One command, menu driven.

## Run (main: from the share, campus network)

On a lab PC open `\\192.168.0.72\LabDeploy\lab\` and double-click **run.cmd** (asks for admin, then shows the menu).
Config is read from `config.json` next to `lab.ps1` on the share, so edits there apply immediately.

## Run (alternative: from GitHub)

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
  [1] Install software (choose programs)      -> list of share packages + winget apps, pick by number
  [2] Optimize PC (Cleanup, RemoveApps, Tune)  -> pick which
  [3] Activate Windows / Office (campus KMS)
  [4] Lab settings (Fonts, Certs, WinRAR theme, Wallpaper, SPSS license) -> pick which
  [5] Check status (VPN, KMS, share, SPSS)
  [6] Unlock wallpaper
```

In every sub-list: numbers like `1,3`, or Enter = all.

| Task | What it does |
|---|---|
| Cleanup | Every user: Downloads emptied, Desktop files/folders deleted (shortcuts `.lnk`/`.url` kept), user Temp, Recycle Bin; data drives in `config.json` (asks `YES` per drive) |
| BrowserClean | Chrome/Edge: delete extra profiles (Profile 1, 2...), keep Default; clear its logins, cookies, history, sessions, cache (bookmarks/extensions kept) |
| RemoveApps | Silent-uninstall adware / 3rd-party antivirus (Defender takes over) |
| Install | Install/update packages from `\\192.168.0.72\LabDeploy\manifest.json` (SHA256 checked; `.exe`/`.msi`, or `.zip` + `run`; English `notice`/`noticeFile` shown for interactive installers) |
| Winget | Install/upgrade latest WinRAR, Foxit Reader via winget |
| Activate | List Windows/Office products found now, activate chosen ones on campus KMS |
| Fonts | Thai fonts from share `fonts\` for all users |
| Certs | Trusted Root import, thumbprint allowlist only |
| WinRARTheme | WinRAR theme for all users |
| Wallpaper | Pick any image in share `wallpaper\` (newest if not asked), locked (Personalize greyed out) |
| BrowserSearch | Google as default search via machine policy (Chrome, Edge, Firefox) |
| Tune | High performance power plan, lighter visual effects, clear temp |
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
