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

## Run (campus LAN, no internet login yet)

A PC that is not logged in to the captive portal cannot reach GitHub: `irm …github.io…` returns the portal login page and fails with `System.Xml.XmlDocument is not recognized`. Use the LAN copy on Server 72 (same `lab.ps1`, same SHA256 check):

```powershell
irm https://libdesk.nsru.ac.th/lab-setup/go.txt | iex
```

Served by an IIS virtual directory `/lab-setup` under the libdesk site -> `C:\Websites\static\lab-setup\` (`go.txt` = `go-lan.txt`, `lab.ps1`, `config.json`, `web.config` from `lan/`). Public files only; secrets stay on the LabDeploy share.

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
| KeepAlive | Optional background daemon for campus LAN captive portal. Runs 100% headless (zero console window) as SYSTEM task, reads credentials from a local copy of `\\192.168.0.72\LabDeploy\net-auth.env`, re-synced from the share on every KeepAlive run (changed on Server 72 = updated here; share unreachable = local copy kept). `labdeploy` is read-only, so change the password in the share file on the server, not via option [4]. |
| CrashWatcher | Background Scheduled Task (`Lab_CrashWatcher`) running as SYSTEM. Detects BSOD (BugCheck 1001), unexpected shutdowns (6008), and critical app crashes (1000). Reports to LibDesk (`telemetryUrl`) with `hardwareId` (BIOS serial > MAC > UUID) + domain; new machines land in LibDesk > ดูแลคอมพิวเตอร์ > **จัดเครื่องเข้าห้อง** ("ยังไม่จัดกลุ่ม") until an admin drags them into a campus room — only crashes of assigned machines open incidents. Needs the shared token (LibDesk `LAB_TELEMETRY_TOKEN`): option [1]/[2] syncs it from the share on every run (`\\<host>\LabDeploy\telemetry.token`, protected by the labdeploy cmdkey credential like `net-auth.env`), else `$env:LAB_TELEMETRY_TOKEN`, else prompts, then stores it in `%ProgramData%\LabDeploy\telemetry.token` (SYSTEM + Administrators only). **Never put the token in `config.json` (public) or commit it.** No token = nothing is sent. |
| Fonts | Thai fonts from share `fonts\` or local/online fallback for all users |
| Certs | Trusted Root import, thumbprint allowlist only |
| WinRARTheme | WinRAR theme for all users |
| Wallpaper | Pick any image in share `wallpaper\` (newest if not asked), locked (Personalize greyed out) |
| BrowserSearch | Google as default search via machine policy (Chrome, Edge, Firefox) |
| RevertBrowserSearch | Remove search engine policies from Chrome, Edge, and Firefox |
| BrowserHome | Browser opens YouTube on start via machine policy (Chrome, Edge, Firefox) — karaoke room |
| RevertBrowserHome | Remove startup-page policies from Chrome and Edge (Firefox: manual if policies.json shared) |
| Tune | High performance power plan, lighter visual effects, clear temp |
| RevertTune | Restore Balanced power plan and default Windows visual effects |
| SpssLicense | Write SPSS/Amos concurrent license server into `spssprod.inf` |
| Check | Read-only status: VPN gateways, KMS, share, FortiClient/SPSS/Amos, SPSS license host |
| Unlock | Remove wallpaper lock |

Options: `$env:LAB_DRYRUN='1'` (show only), `$env:LAB_TASKS='Install,Fonts'` (skip menu), `$env:LAB_YES='1'` (no drive prompt), `$env:LAB_NO_AUTO_CW='1'` (do not auto-install CrashWatcher). Every launch (run.cmd / setup.bat / go.txt) installs CrashWatcher silently first when the PC does not have it yet, so new PCs appear in LibDesk "ยังไม่จัดกลุ่ม" with no menu pick.

Log: `C:\ProgramData\LabDeploy\lab.log`.
Exit codes: 0 ok, 1 not admin / config / host guard, 2 share connect, 3 manifest, 4 package failed, 5 activation failed.

## Release a new version

```powershell
.\release.ps1 -Tag v1.1     # pins lab.ps1 to the tag, rewrites go.txt with the new SHA256
```

Then commit, create tag `v1.1` on that commit, push commit + tag.

### Publish to Server 72

Copy the files **from the tag** (`git show v1.1:<path>`, so hashes match `go.txt` byte for byte), keeping the old share files as `<name>.bak-pre<tag>-<time>`:

| From the tag | To Server 72 |
| :--- | :--- |
| `lab.ps1`, `config.json` | `C:\LabDeploy\lab\` and `C:\Websites\static\lab-setup\` |
| `net-auth/KeepAlive.ps1`, `net-auth/KeepAlive.js`, `net-auth/launch.vbs` | `C:\LabDeploy\net-auth\` |
| `go-lan.txt` | `C:\Websites\static\lab-setup\go.txt` |
| `lan/web.config` | `C:\Websites\static\lab-setup\web.config` |

Check: `irm https://libdesk.nsru.ac.th/lab-setup/go.txt` shows the new SHA256, and the hash of `…/lab-setup/lab.ps1` equals it.

Installers, license keys and `manifest.json` live on the internal share, never in this repo.
