@echo off
setlocal
title NSRU Lab Setup
rem Lab setup launcher (double-click). Works before the internet login:
rem   1. lab.ps1 next to this file   2. Server 72 share   3. LAN server (libdesk)   4. GitHub
rem No internet check here: lab PCs are offline until the captive portal login, which is what KeepAlive does.

rem Re-launch as Administrator if needed (/k keeps the window open on errors)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Requesting Administrator privileges...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/k pushd \"\"%~dp0\"\" && call \"%~nx0\"' -Verb RunAs"
    exit /b
)
pushd "%~dp0"

set "DEPLOY_DIR=%ProgramData%\LabDeploy"
if not exist "%DEPLOY_DIR%" mkdir "%DEPLOY_DIR%"
copy /y "%~f0" "%DEPLOY_DIR%\setup.bat" >nul 2>&1

if exist "%~dp0lab.ps1" goto RUN_LOCAL
if exist "\\192.168.0.72\LabDeploy\lab\lab.ps1" goto RUN_SHARE
goto RUN_WEB

:RUN_LOCAL
echo [i] Running lab.ps1 next to this file...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lab.ps1"
goto DONE

:RUN_SHARE
echo [i] Running lab.ps1 from Server 72 share...
pushd "\\192.168.0.72\LabDeploy\lab"
powershell -NoProfile -ExecutionPolicy Bypass -File "\\192.168.0.72\LabDeploy\lab\lab.ps1"
popd
goto DONE

:RUN_WEB
echo [i] Share not reachable - trying LAN server, then GitHub (both verify the lab.ps1 SHA256)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; $s = $null; foreach ($u in 'https://libdesk.nsru.ac.th/lab-setup/go.txt', 'https://x66clrf.github.io/lab-setup/go.txt') { try { $s = [string](Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 10).Content; Write-Host ('[OK] ' + $u); break } catch { Write-Host ('[i] cannot reach ' + $u) } }; if (-not $s) { Write-Host '[!] No share, no LAN server, no internet. Plug in the lab LAN cable (or a hotspot) and run again.' -ForegroundColor Red; exit 1 }; Invoke-Expression $s"
goto DONE

:DONE
echo.
echo ========================================================
echo  Finished. Press any key to close...
echo ========================================================
popd
pause >nul
