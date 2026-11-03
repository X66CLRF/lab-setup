@echo off
setlocal
title [NSRU] Lab Check
rem Read-only health check (changes nothing). PASS = ready. FAIL = shows which button fixes it.
rem Also adds this PC (name, MAC, IP) to pc-list.csv on the flash drive.
rem   0-CHECK.cmd install    check silently at every logon, popup only on a problem
rem   0-CHECK.cmd uninstall  remove that
set "ARG="
if /i "%~1"=="install" set "ARG=-Install"
if /i "%~1"=="uninstall" set "ARG=-Uninstall"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0net-auth\lab-check.ps1" %ARG%
echo.
pause
