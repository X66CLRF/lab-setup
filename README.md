# lab-setup

Lab PC setup for Windows 11 Pro (NSRU lab). One command, menu driven.

## Run

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

| Task | What it does |
|---|---|
| Cleanup | Empty every user's Downloads + data drives in `config.json` (asks `YES` per drive) |
| RemoveApps | Silent-uninstall adware / 3rd-party antivirus (Defender takes over) |
| Install | Install/update packages from `\\192.168.0.72\LabDeploy\manifest.json` (SHA256 checked; `.exe`/`.msi`, or `.zip` + `run`; English `notice`/`noticeFile` shown for interactive installers) |
| Winget | Install/upgrade latest WinRAR, Foxit Reader via winget |
| Activate | List Windows/Office products found now, activate chosen ones on campus KMS |
| Fonts | Thai fonts from share `fonts\` for all users |
| Certs | Trusted Root import, thumbprint allowlist only |
| WinRARTheme | WinRAR theme for all users |
| Wallpaper | Lab wallpaper, locked (Personalize greyed out) |
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
