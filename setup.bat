@echo off
setlocal EnableDelayedExpansion
title NSRU Lab Setup - SPSS

:: 1. ตรวจสอบและขอสิทธิ์ Administrator อัตโนมัติ (ใช้ /k เพื่อไม่ให้หน้าต่างดับ)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/k pushd \"\"%~dp0\"\" && call \"%~nx0\"' -Verb RunAs"
    exit /b
)
pushd "%~dp0"

:: กำหนดโฟลเดอร์ทำงานบนเครื่องลูก
set "DEPLOY_DIR=%ProgramData%\LabDeploy"
if not exist "%DEPLOY_DIR%" mkdir "%DEPLOY_DIR%"

:: 2. ตรวจสอบอินเทอร์เน็ต
:CHECK_NET
echo.
echo [1/3] Checking Internet connection...
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
echo [2/3] Checking NSRU campus network...
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

:: 4. เริ่มรันสคริปต์
echo.
echo [3/3] Starting Lab Setup...
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
popd
pause >nul
