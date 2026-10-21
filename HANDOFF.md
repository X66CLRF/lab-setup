# HANDOFF — แก้บั๊กติดตั้งโปรแกรม all: WinRAR syntax crash & ปลดล็อกแชร์ Server 72

- **สถานะ:** เสร็จสิ้น (รอ Claude ตรวจ L3 หรือ merge เข้า main)
- **ระดับ:** L2 · **ดำเนินการโดย:** Antigravity 2026-10-21
- **เครื่อง:** ASUS
- **branch:** handoff/fix-winrar-syntax

## ปัญหาที่พบและสาเหตุ (จากรูปหน้าจอที่ผู้ใช้ส่งมา)

1. **บั๊กแครชสีแดงหลังติดตั้ง Foxit Reader:**
   - อาการ: `Invoke-Expression : The term 'if' is not recognized as the name of a cmdlet...` ที่บรรทัด Invoke-Expression แล้วเด้งหลุดกลับ `C:\Windows\system32>`
   - สาเหตุ: ในฟังก์ชัน `Set-WinRarLicense` (บรรทัด 368) มีการเขียน `(if ($sharePath) { ... })` โดยไม่มีเครื่องหมาย `$` นำหน้า (`$(`) ทำให้ PowerShell 5.1 ใน expression `(...)` ตีความคำว่า `if` เป็นชื่อ cmdlet/คำสั่ง ไม่ใช่ keyword `if` จึงแครชและสั่งหยุดสคริปต์ทันทีเมื่อรัน Winget เสร็จ

2. **บัญชี `labdeploy` บน Server 72 ถูกล็อก (`Account active: Locked`):**
   - อาการ: หน้าจอขึ้น `Notice connect share: The referenced account is currently locked out`
   - สาเหตุ: เครื่องแล็บยังไม่มี credentials (`No stored credential for 192.168.0.72`) และมีการต่อเชื่อมผิดเกิน 10 ครั้ง (Lockout threshold = 10) บัญชี `labdeploy` บน Server 72 จึงถูก Windows ล็อกเอาต์ ทำให้เครื่องแล็บดึง `manifest.json` เพื่อลง Office / SPSS ไม่ได้ แสดงเฉพาะ Winget เท่านั้น

3. **แชร์ `LabDeploy` บน Server 72 ถูกจำกัดจำนวนผู้ใช้ `Maximum users: 1`:**
   - สาเหตุ: มีการตั้งขีดจำกัดแชร์ไว้ที่ 1 connection ทำให้เครื่องในแล็บเครื่องที่ 2+ เชื่อมต่อไม่ติดและเกิดข้อผิดพลาดสะสม

---

## สิ่งที่ทำแล้ว

1. **แก้บั๊กใน `lab.ps1`:**
   - แก้ `Set-WinRarLicense`: เปลี่ยนจากการใช้ `(if ...)` มาเป็นบล็อก `if` ชัดเจน ปลอดภัย 100% ไม่เกิด runtime error อีก
   - เพิ่มการดักจับ `The referenced account is currently locked out` ในฟังก์ชันต่อแชร์ ให้แสดงข้อความภาษาไทยชัดเจน
   - ปรับข้อความเตือนเมื่อเชื่อมต่อ Server 72 ไม่สำเร็จในขั้นตอน `Install` ให้แจ้งเตือนสีแดงชัดเจนว่าไม่สามารถลง Office/SPSS ได้ (เหลือเฉพาะ Winget)
   - ตรวจสอบไวยากรณ์ PowerShell: `Parser::ParseFile` ผ่าน 0 error, UTF-8 BOM + CRLF 1786 บรรทัดถูกต้องสมบูรณ์

2. **ดำเนินการบน Server 72 ผ่าน SSH:**
   - ปลดล็อกบัญชี `labdeploy`: รัน `net user labdeploy /active:yes` (สถานะปัจจุบัน: `Account active: Yes`)
   - ขยายขีดจำกัดผู้ใช้แชร์ `LabDeploy`: รัน `net share LabDeploy /unlimited` (สถานะปัจจุบัน: `Maximum users: No limit`)

---

## สิ่งที่ต้องทำต่อที่เครื่องแล็บ

1. ที่เครื่องแล็บ ให้เปิด Command Prompt / PowerShell รันคำสั่งจำรหัสผ่าน:
   ```cmd
   cmdkey /add:192.168.0.72 /user:192.168.0.72\labdeploy /pass
   ```
   (ใส่รหัสผ่านของบัญชี `labdeploy`)

2. หากมี session ค้าง ให้เคลียร์ก่อน:
   ```cmd
   net use * /delete /y
   ```

3. เมื่อ merge branch นี้แล้ว ให้สร้าง tag ใหม่ (`release.ps1`) หรือคัดลอก `lab.ps1` ไปวางทับที่ `\\192.168.0.72\LabDeploy\lab\lab.ps1`
