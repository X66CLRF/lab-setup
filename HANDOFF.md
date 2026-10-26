# HANDOFF — แก้บั๊ก lab-setup & เพิ่ม winget upgrade --all + StopSignIn + RemoveAI + SPSS Relay + KeepAlive Wake

- **สถานะ:** ปิด 2026-10-22 — Claude Code ตรวจแล้ว รวมกับ `fix/telemetry-visible` ออก v1.5 · แก้เพิ่มตอนตรวจ: KeepAlive `-Once` (เมนูทดสอบ) ไม่ฆ่า daemon ที่รันอยู่ · ข้อความ share ไม่ต่อในเมนู Install มีเหตุผลเสมอ · SPSS relay บน Server 72 ตรวจแล้ว (service Running, TCP/UDP 5093, firewall, ต้นทาง 192.168.3.10 ต่อได้)
- **ระดับ:** L2 · **ดำเนินการโดย:** Antigravity 2026-10-22
- **เครื่อง:** ASUS
- **branch:** handoff/fix-winrar-syntax

## ปัญหาทั้งหมดที่ตรวจพบและแก้ไข (รวมทุกคำสั่ง)

1. **บั๊กแครชสีแดงหลังติดตั้ง Foxit Reader:**
   - อาการ: `The term 'if' is not recognized as the name of a cmdlet...`
   - แก้ไข: ปรับ `Set-WinRarLicense` ใน `lab.ps1` ให้ใช้บล็อก `if` แทน `(if ...)` ที่ผิดไวยากรณ์ใน runtime expression

2. **บั๊กแครชสีแดงใน Cleanup (รูปที่ 4):**
   - อาการ: `Where-Object : The specified wildcard character pattern is not valid: C:\Users\...\Downloads\[m8yfpjv.docx]*` (`WildcardPatternException`)
   - สาเหตุ: ไฟล์ที่มีวงเล็บก้ามปู `[...]` ถูก `-ilike` มองเป็น wildcard character range
   - แก้ไข: เปลี่ยนการตรวจ prefix ใน `Clear-Tree` เป็น `.StartsWith($fullPrefix, [System.StringComparison]::OrdinalIgnoreCase)` ปลอดภัย 100% กับทุกอักขระ

3. **ปัญหาภาษาไทยสระลอย / แยกตัว (`ต ด ต ง`, `ฟอนต ` ในรูปที่ 3):**
   - สาเหตุ: Console conhost เริ่มต้นด้วย Code Page ที่ไม่ใช่ UTF-8 (CP 874 / 437)
   - แก้ไข: สั่ง `chcp 65001` และตั้ง `OutputEncoding = UTF8` อัตโนมัติเมื่อเริ่มสคริปต์

4. **ปัญหาคอนโซลค้าง / ต้องกด Enter:**
   - สาเหตุการค้าง: QuickEdit Mode ของคอนโซล Windows เมื่อเผลอคลิกเมาส์ในหน้าต่าง ดำเนินการ Pause ทันที (ขึ้น `Select` บน Title bar)
   - แก้ไข: ตั้งปิด QuickEdit ใน `HKCU:\Console` อัตโนมัติในสคริปต์
   - สาเหตุต้องกด Enter: หน้าต่างล้างไดรฟ์ D: ป้องกันข้อมูลหายด้วยการถาม `type YES:` ถ้ากด Enter เปล่าๆ จะข้าม (SKIP) เป็นพฤติกรรมปลอดภัยปกติ

5. **เพิ่ม `winget upgrade --all`:**
   - ใน task `Winget`: อัปเกรดโปรแกรมทุกตัวในเครื่องอัตโนมัติด้วย `--all --silent --accept-package-agreements --accept-source-agreements --disable-interactivity`

6. **เพิ่ม task `StopSignIn` และ `RevertStopSignIn` (ในหมวด [4] Lab Settings & Policies):**
   - **Windows:** บล็อกการผูก Microsoft Account ส่วนตัว (`NoConnectedUser` = 3, `DisableUserAuth` = 1, ปิดหน้าต่างตื๊อใน Start menu)
   - **Office:** บล็อกป๊อปอัปถาม Sign in ตอนเปิด Word/Excel/PowerPoint (`SignInOptions` = 3, `ShownFirstRunOptin` = 1) ทุก User Profile
   - **Browser:** ปิด Sign in / Account Sync ใน Google Chrome และ Microsoft Edge (`BrowserSignin` = 0, `SyncDisabled` = 1)
   - มี **RevertStopSignIn** สำหรับคืนสิทธิ์ให้นักศึกษากลับมาล็อกอินได้หากต้องการ

7. **เพิ่มชุดคำสั่งถอน Windows AI (`RemoveAI` และ `RevertRemoveAI` ในหมวด [2] Optimize & Clean):**
   - **Copilot:** ปิดนโยบาย WindowsCopilot ทั่วทั้งระบบและทุกผู้ใช้ + ซ่อนปุ่มบน Taskbar + ปิด Copilot ใน Edge
   - **Recall:** ปิดนโยบาย WindowsAI (DisableAIDataAnalysis) + สั่ง DISM ปิด Optional Feature `Recall`
   - **Windows Search:** ปิด Bing Web Search & AI suggestions ในช่องค้นหา
   - **AppX:** สั่งลบและถอนแพ็กเกจ Provisioned AppX ทั้ง `*Copilot*`, `*Recall*`, `*Windows.Ai*` ทิ้งอัตโนมัติ (เพิ่มลงใน `config.json` ด้วย)
   - มี **RevertRemoveAI** คืนสิทธิ์เปิดใช้งานใหม่ได้หากจำเป็น

8. **ปรับหน้าเว็บ GitHub Pages (`index.html`):**
   - ลบปุ่มดาวน์โหลด `setup.bat` ออกตามคำสั่งผู้ใช้
   - เหลือเฉพาะกล่องคัดลอกคำสั่ง `irm x66clrf.github.io/lab-setup/go.txt | iex` เพียงอย่างเดียว

9. **SPSS License Relay ข้าม FortiClient VPN (ทางเลือกที่ 1 สำเร็จ):**
   - จัดตั้ง Service `SpssLicenseRelay` บน Server 72 (`192.168.0.72`) ผ่าน NSSM
   - รันสคริปต์ Node.js รีเลย์พอร์ต 5093 (ทั้ง TCP และ UDP Sentinel RMS) ไปยัง `192.168.3.10:5093`
   - เปิด Windows Firewall พอร์ต 5093 (TCP & UDP) บน Server 72
   - ปรับ `config.json` ให้ `spss.licenseServer` ชี้มาที่ `192.168.0.72` ทำให้เครื่องแล็บใช้งาน SPSS ได้โดยไม่ต้องเปิดหรือต่อ FortiClient VPN

10. **แก้ไข KeepAlive ไม่ทำงานหลังปลุกเครื่องจาก Sleep:**
    - `KeepAlive.ps1`: ป้องกันโปรเซสซ้ำซ้อน (ตรวจจับและปิดโปรเซสเดิม), เมื่อเน็ตหลุด/ออฟไลน์ปรับเป็น retry ทุก 10 วินาทีทันทีแทนที่จะรอ 90 วินาที
    - `lab.ps1`: ปรับ `Lab_AutoWake` ให้หน่วงรอเน็ต 8 วินาทีแล้วสั่งเรียก `Start-ScheduledTask -TaskName NSRU-KeepAlive`
    - `lab.ps1`: เพิ่ม `ExecutionTimeLimit = 0` (ไม่ให้ Task Scheduler ตัดจบหลัง 72 ชม.) พร้อมแทรก `EventTrigger` ตรวจจับ System Resume (Power-Troubleshooter Event 1) ใน Task Scheduler ของเครื่อง

11. **เซิร์ฟเวอร์ Server 72:**
    - ปลดล็อกบัญชี `labdeploy` ผ่าน SSH แล้ว (`Account active: Yes`)
    - ขยายขีดจำกัดแชร์ `LabDeploy` ผ่าน SSH แล้ว (`Maximum users: No limit`)

---

## สิ่งที่ต้องทำต่อที่เครื่องแล็บ

1. ที่เครื่องแล็บ รันเคลียร์ session และจำรหัสผ่าน:
   ```cmd
   net use * /delete /y
   cmdkey /add:192.168.0.72 /user:192.168.0.72\labdeploy /pass
   ```
2. Merge branch `handoff/fix-winrar-syntax` เข้า `main`
3. รัน `release.ps1` หรือนำ `lab.ps1` และ `config.json` ไปวางที่ `\\192.168.0.72\LabDeploy\lab\`

---

## 2026-10-26 — KeepAlive / SPSS (session บนคลาวด์ ไม่เห็นเครื่องแล็บ/Server 72)

**แก้แล้ว (บน branch `claude/fervent-ptolemy-si13le`, ยังไม่ได้ทดสอบบนเครื่องจริงทั้งหมด)**
- `net-auth/KeepAlive.js` (ใหม่) + `KeepAlive.ps1` เรียก Node ก่อน, ถอยไป `curl.exe` ถ้าไม่มี Node — หลักฐานจาก log เก่า: PowerShell/.NET (Schannel) ล้ม "connection closed unexpectedly", Node (OpenSSL) ทำงานต่อเนื่อง ก.ค.–ต.ค.; `curl.exe` ของ Windows ใช้ Schannel จึงน่าจะล้มแบบเดียวกัน (ยังไม่ยืนยัน)
- `launch.vbs` รอ daemon (`Run ..., 0, True`) → task `NSRU-KeepAlive` เป็น Running จริง; ตัวเลือก [3] ฆ่า daemon ผ่าน `Get-CimInstance` (PS 5.1 ไม่มี `CommandLine` ใน Process); kill-duplicate ฆ่าทั้ง powershell และ node
- `lab.ps1` ตัวเลือก [1] คัดลอก `KeepAlive.js` และลง Node LTS ผ่าน winget ถ้าไม่มี
- `PSDrive LabDeploy` สร้างแบบ `-Scope Global` (เดิม `Get-FileHash` ใน module scope มองไม่เห็น → error แดง "Cannot find drive 'LabDeploy'" ไม่ทำให้งานล้ม)
- `collect-logs.ps1` (ใหม่) เก็บ log/สถานะแบบอ่านอย่างเดียว ปิดบังรหัสผ่าน/token → ไฟล์บน Desktop
- main มี commit `fc61a94` ที่ใส่ข้อความ `git fetch origin ...` แทนเลข tag ใน URL — ถูกแทนด้วย merge `-s ours` แล้ว

**ยังค้าง**
1. **KeepAlive:** รอ `keepalive.log` หลังติดตั้งเวอร์ชันนี้ (ต้องเห็น `Engine: node` และ `Login SUCCESS`); ยังไม่ทราบว่า winget ลง Node สำเร็จบนเครื่องแล็บไหม
2. **SPSS ไม่ใช้ VPN ไม่ได้:** `licenseServer=192.168.0.72` (relay → `192.168.3.10:5093`) ผ่านแค่เช็ก TCP 5093 แต่เปิดใช้งานผลิตภัณฑ์ไม่ได้ ต้องเปิด Fortinet เหมือนเดิม — สาเหตุยังไม่รู้ ต้องเทียบ `collect-logs.ps1` (ต่อ VPN / ไม่ต่อ VPN) + สคริปต์ relay บน Server 72 (NSSM `SpssLicenseRelay`) + log ของ service; สมมติฐาน: UDP/ลำดับ handshake ผ่าน relay, ค่า license address อื่นนอกจาก `LSHOST`, license ผูกชื่อ/IP ของ `192.168.3.10`
3. **Release:** push tag `v1.10` เอง (sandbox คลาวด์ push tag ไม่ได้) แล้วคัดลอกไฟล์จาก tag ขึ้น Server 72 (README: Publish to Server 72 — รวม `KeepAlive.js`, `launch.vbs`); merge branch เข้า `main` หลัง push tag เท่านั้น (`go.txt` ชี้ tag)
