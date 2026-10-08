@echo off
setlocal EnableDelayedExpansion
title NSRU Lab Setup - SPSS

:: 1. ตรวจสอบและขอสิทธิ์ Administrator อัตโนมัติ (ใช้ /k เพื่อไม่ให้หน้าต่างดับ)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/k \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: กำหนดโฟลเดอร์ทำงานบนเครื่องลูก
set "DEPLOY_DIR=%ProgramData%\LabDeploy"
if not exist "%DEPLOY_DIR%" mkdir "%DEPLOY_DIR%"

:: 2. ตรวจสอบอินเทอร์เน็ต
:CHECK_NET
echo.
echo [1/4] Checking Internet connection...
ping -n 1 1.1.1.1 >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Internet is not connected.
    echo Please connect Wi-Fi / LAN and login to internet.
    pause
    goto CHECK_NET
)
echo [OK] Internet connected.

:: 3. ตรวจสอบเครือข่ายภายใน มรนว.
echo.
echo [2/4] Checking NSRU campus network...
powershell -NoProfile -Command "$t = New-Object Net.Sockets.TcpClient; $a = $t.BeginConnect('192.168.10.111', 1688, $null, $null); if ($a.AsyncWaitHandle.WaitOne(1000)) { exit 0 } else { exit 1 }"
if %errorlevel% equ 0 (
    echo [OK] Inside NSRU campus network.
    powershell -NoProfile -Command "$t = New-Object Net.Sockets.TcpClient; $a = $t.BeginConnect('192.168.0.72', 445, $null, $null); if (-not $a.AsyncWaitHandle.WaitOne(800)) { exit 1 } else { exit 0 }"
    if !errorlevel! neq 0 (
        echo [i] Note: Campus Wi-Fi detected - Share port 445 restricted [normal on Wi-Fi, OK on wired lab LAN].
    ) else (
        echo [OK] Campus SMB share reachable.
    )
) else (
    echo [i] Outside campus network [connect FortiClient VPN if campus share is needed].
)

:: 4. ตั้งค่าระบบ Sleep 16:40 และ Wake 08:20 (ตัวเลือกเสริม)
echo.
echo [3/4] Auto Sleep/Wake Schedule (Optional - Lab PC only)
set "ENABLE_SLEEP="
set /p ENABLE_SLEEP="Enable Auto Sleep 16:40 and Wake 08:20 Mon-Fri? [y/N] (Default N): "
if /i "!ENABLE_SLEEP!"=="y" (
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKING 1 >nul 2>&1
    powercfg /setactive SCHEME_CURRENT >nul 2>&1
    schtasks /create /tn "Lab_AutoSleep" /tr "powershell -Command Add-Type -Assembly System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false)" /sc weekly /d MON,TUE,WED,THU,FRI /st 16:40 /ru "SYSTEM" /f >nul 2>&1
    powershell -NoProfile -Command "$act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c ping 1.1.1.1 -n 1'; $trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At '08:20'; $set = New-ScheduledTaskSettingsSet -WakeToRun; Register-ScheduledTask -TaskName 'Lab_AutoWake' -Action $act -Trigger $trg -Settings $set -User 'SYSTEM' -Force | Out-Null"
    echo [OK] Auto Sleep/Wake configured.
) else (
    echo [i] Skipped Auto Sleep/Wake.
    schtasks /delete /tn "Lab_AutoSleep" /f >nul 2>&1
    schtasks /delete /tn "Lab_AutoWake" /f >nul 2>&1
)

:: 5. เริ่มรันสคริปต์
echo.
echo [4/4] Starting Lab Setup...
copy /y "%~f0" "%DEPLOY_DIR%\setup.bat" >nul 2>&1

:: เลือกรัน: ถ้ามี lab.ps1 อยู่ข้างๆ ให้รันจากไฟล์ตรง ถ้าไม่มีให้ดึงออนไลน์จาก main
if exist "%~dp0lab.ps1" (
    echo [i] Running local lab.ps1...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lab.ps1"
) else (
    echo [i] Fetching online script from main branch...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; (Invoke-WebRequest 'https://raw.githubusercontent.com/X66CLRF/lab-setup/main/lab.ps1' -UseBasicParsing).Content | iex"
)

echo.
echo ========================================================
echo  Execution finished. Press any key to exit...
echo ========================================================
pause >nul
