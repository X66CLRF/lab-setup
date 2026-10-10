# HANDOFF — จัดระเบียบเมนู lab-setup 5 หมวด + เพิ่ม Revert

- **สถานะ:** รอตรวจ
- **ระดับ:** L3 · **ส่งให้:** Claude Code · **จาก:** Antigravity 2026-10-10
- **เครื่อง:** BURT
- **branch:** handoff/menu-reorg · **commit ล่าสุด:** 195882d

## เป้าหมาย
จัดระเบียบเมนู `lab.ps1` จาก 9 ข้อซ้ำซ้อน เหลือ 5 หมวดหลักตามกลุ่มหน้าที่ พร้อมเพิ่มตัวเลือก Revert ให้ Tune และ BrowserSearch และคง Safety Guards ทั้งหมด 100%

## ทำแล้ว
1. จัดกลุ่ม `$groups` เหลือ 5 หมวดหลัก:
   - [1] Install Software (Office, SPSS, Share packages, Winget)
   - [2] Optimize & Clean (Cleanup, BrowserClean, RemoveApps, Tune)
   - [3] Diagnostics & Licenses (Network status, Windows/Office/SPSS KMS check & fix)
   - [4] Lab Settings & Policies (Fonts, Certs, WinRAR theme, Wallpaper, Search)
   - [5] Background Automation (Auto Wake/Sleep, KeepAlive, LibDesk Crash Watcher)
2. อัปเกรด `Read-Pick`: รองรับ Label ภาษาไทยสวยงาม, คืนค่า Task name ถูกต้อง, และ `Enter` (default all) จะข้าม task ที่ขึ้นต้นด้วย `Revert` เสมอ เพื่อความปลอดภัย
3. เพิ่ม `RevertBrowserSearch`: ลบ registry policies ของ Google Chrome, Edge และลบ `policies.json` ของ Firefox คืนสิทธิ์ให้ผู้ใช้
4. เพิ่ม `RevertTune`: คืนค่า Power Plan เป็น `SCHEME_BALANCED` และ `VisualFXSetting` เป็น 0 (Let Windows decide)
5. ตรวจสอบไวยากรณ์ PowerShell: `Parser::ParseFile` ผ่าน 0 error, UTF-8 BOM + CRLF ถูกต้อง
6. อัปเดตเอกสาร `README.md`
7. commit & push ขึ้น branch `handoff/menu-reorg` (commit `195882d`)

## เหลือ (เรียงตามลำดับ)
1. Claude Code หรือผู้ดูแล ตรวจ diff บน branch `handoff/menu-reorg` — L3
2. merge `handoff/menu-reorg` เข้า `main` — L3
3. หากต้องการปล่อยเวอร์ชัน tag รัน `.\release.ps1 -Tag v1.1` แล้วคัดลอกขึ้นแชร์ `\\192.168.0.72\LabDeploy\lab\`

## ตรวจยังไงว่าเสร็จ
- `git diff main...handoff/menu-reorg`
- PowerShell syntax: `$errs = $null; $toks = $null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\lab.ps1), [ref]$toks, [ref]$errs); $errs.Count` (ต้องได้ 0)

## ห้าม / ระวัง
- ห้ามรัน `lab.ps1` บนเครื่องเดฟส่วนตัว (รันเฉพาะเครื่องแล็บ Windows 11)
- ไฟล์ `lab.ps1` ต้องคง UTF-8 BOM + CRLF เสมอ เพื่อให้ Windows PowerShell 5.1 ไม่พังกับภาษาไทย
