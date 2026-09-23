@echo off
rem Lab setup launcher. Double-click from \\192.168.0.72\LabDeploy\lab\
rem First time on each lab PC (read-only share account):
rem   cmdkey /add:192.168.0.72 /user:192.168.0.72\labdeploy /pass

rem Re-launch as Administrator if needed
net session >nul 2>&1 || (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lab.ps1"
echo.
pause
