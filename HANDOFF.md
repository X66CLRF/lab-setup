# HANDOFF — แก้บั๊ก lab-setup & เพิ่ม winget upgrade --all + StopSignIn + RemoveAI + ปรับหน้าเว็บ

- **สถานะ:** เสร็จสิ้น (รอ Claude ตรวจ L3 หรือ merge เข้า main)
- **ระดับ:** L2 · **ดำเนินการโดย:** Antigravity 2026-10-21
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

9. **เซิร์ฟเวอร์ Server 72:**
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
