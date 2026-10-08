@echo off
setlocal EnableDelayedExpansion
title NSRU Lab Setup - SPSS

:: 1. ตรวจสอบและขอสิทธิ์ Administrator อัตโนมัติ
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: กำหนดโฟลเดอร์ทำงานบนเครื่องลูก
set "DEPLOY_DIR=%ProgramData%\LabDeploy"
if not exist "%DEPLOY_DIR%" mkdir "%DEPLOY_DIR%"

:: 2. ตรวจสอบอินเทอร์เน็ต
:CHECK_NET
echo [1/4] Checking Internet connection...
ping -n 1 1.1.1.1 >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [!] Internet is not connected.
    echo Please connect Wi-Fi / LAN and login to internet.
    pause
    goto CHECK_NET
)
echo [OK] Internet connected.

:: 3. ตรวจสอบเครือข่ายภายใน (Share 192.168.0.72 หรือ SPSS License 192.168.3.10)
echo [2/4] Checking campus network reachability...
powershell -NoProfile -Command "$t = New-Object Net.Sockets.TcpClient; $a = $t.BeginConnect('192.168.0.72', 445, $null, $null); if (-not $a.AsyncWaitHandle.WaitOne(1500)) { $t.Close(); exit 1 } else { $t.EndConnect($a); $t.Close(); exit 0 }"
if %errorlevel% neq 0 (
    echo.
    echo [!] Cannot reach campus share (192.168.0.72:445).
    echo Checking FortiClient VPN...
    
    set "FORTI_CLI=%ProgramFiles%\Fortinet\FortiClient\FortiSSLVPNcli.exe"
    set "FORTI_GUI=%ProgramFiles%\Fortinet\FortiClient\FortiClient.exe"
    if not exist "!FORTI_CLI!" set "FORTI_CLI=%ProgramFiles(x86)%\Fortinet\FortiClient\FortiSSLVPNcli.exe"
    if not exist "!FORTI_GUI!" set "FORTI_GUI=%ProgramFiles(x86)%\Fortinet\FortiClient\FortiClient.exe"

    if exist "!FORTI_CLI!" (
        echo Found FortiClient CLI.
        set /p VPN_USER="Enter your NSRU account: "
        echo Connecting to gwspss.nsru.ac.th:10443...
        "!FORTI_CLI!" connect -s gwspss.nsru.ac.th:10443 -u !VPN_USER!
    ) else if exist "!FORTI_GUI!" (
        echo Launching FortiClient... Please connect to SPSS VPN (gwspss.nsru.ac.th).
        start "" "!FORTI_GUI!"
        pause
    )
) else (
    echo [OK] Campus network reachable.
)

:: 4. ตั้งค่าระบบ Sleep 16:40 และ Wake 08:20 (จันทร์-ศุกร์)
echo [3/4] Configuring Auto Sleep (16:40) and Wake (08:20)...
:: เปิด RTC Wake timers ใน Windows
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKING 1 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1

:: Task สั่ง Sleep 16:40
schtasks /create /tn "Lab_AutoSleep" /tr "powershell -Command Add-Type -Assembly System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false)" /sc weekly /d MON,TUE,WED,THU,FRI /st 16:40 /ru "SYSTEM" /f >nul 2>&1

:: Task สั่ง Wake 08:20
powershell -NoProfile -Command ^
  "$act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c ping 1.1.1.1 -n 1'; " ^
  "$trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At '08:20'; " ^
  "$set = New-ScheduledTaskSettingsSet -WakeToRun; " ^
  "Register-ScheduledTask -TaskName 'Lab_AutoWake' -Action $act -Trigger $trg -Settings $set -User 'SYSTEM' -Force | Out-Null"
echo [OK] Schedule configured.

:: 5. คัดลอก/ดาวน์โหลดไฟล์ลงเครื่อง และเริ่มรันสคริปต์
echo.
echo [4/4] Starting Lab Setup...
copy /y "%~f0" "%DEPLOY_DIR%\setup.bat" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; irm x66clrf.github.io/lab-setup/lab | iex"

if %errorlevel% neq 0 (
    echo.
    echo Script finished with exit code %errorlevel%.
    pause
)
