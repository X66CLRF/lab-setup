@echo off
setlocal EnableDelayedExpansion
title Update NSRU-KeepAlive
echo ========================================================
echo   Updating NSRU-KeepAlive to latest version...
echo ========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$src = '%~dp0'.TrimEnd('\'); & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $src 'update.ps1')"
echo.
pause
