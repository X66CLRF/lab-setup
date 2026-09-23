# lab-setup

Lab PC setup for Windows 11 Pro.

One-time per lab PC (admin types the `labdeploy` password; stored in Windows Credential Manager, never in this repo):

```powershell
cmdkey /add:192.168.0.72 /user:192.168.0.72\labdeploy /pass
```

Then run as Administrator (no password prompt):

```powershell
irm https://raw.githubusercontent.com/X66CLRF/lab-setup/v1.0/lab.ps1 | iex
```

Dry run: `$env:LAB_DRYRUN='1'` before the command.
Pick tasks: `$env:LAB_TASKS='Install,Wallpaper'` (Cleanup, RemoveApps, Install, Wallpaper, Tune, Unlock).

Log: `C:\ProgramData\LabDeploy\lab.log`.
Exit codes: 0 ok, 1 not admin / config / host guard, 2 share connect, 3 manifest, 4 package failed.

Installers, license files and `manifest.json` live on the internal share (`deployShare` in `config.json`), never in this repo.
