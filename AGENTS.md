# lab-setup — คู่มือสำหรับ AI agent

เครื่องมือตั้งค่าเครื่องแล็บ Windows 11 Pro ของ มรนว. (เมนู `lab.ps1`: ติดตั้งโปรแกรม, ปรับแต่งเครื่อง, เปิดใช้ Windows/Office ผ่าน KMS, ฟอนต์/ใบรับรอง, เช็กสถานะ) — repo อยู่ที่ `~/Documents/GitHub/lab-setup`

## กฎเหล็ก (งานนี้ทำลายข้อมูลได้)
- **ห้ามรัน `lab.ps1`, `run.cmd`, `go.txt` หรือเมนูใด ๆ เอง** เว้นแต่ผู้ใช้สั่งชัด ๆ และบอกว่าเป็นเครื่องแล็บ — ห้ามรันบนเครื่องส่วนตัวของผู้ใช้
- งานที่ลบข้อมูล: `Cleanup` (ลบ Downloads/Desktop ทุกผู้ใช้, ล้างไดรฟ์ข้อมูล), `BrowserClean` (ล้างโปรไฟล์ Chrome/Edge), `RemoveApps` — ต้องขออนุมัติผู้ใช้ทีละงานก่อนเสมอ
- งาน `Activate` ใช้ KMS ของมหาวิทยาลัยเท่านั้น
- **ห้ามเขียนรหัสผ่าน share `labdeploy` หรือ secret ใด ๆ ลงไฟล์/commit** (เก็บใน Windows Credential Manager ผ่าน `cmdkey` โดยผู้ดูแลพิมพ์เอง)
- แก้สคริปต์แล้วให้รันเฉพาะตรวจไวยากรณ์/โหมดแห้งก่อน (เช่น parse ด้วย PowerShell) ห้ามทดลองกับเครื่องจริง
- `config.json` และ `lab.ps1` จริงถูกใช้จาก share `\\192.168.0.72\LabDeploy\lab\` — แก้ใน repo แล้วต้องบอกผู้ใช้ว่าต้องคัดลอกขึ้น share/release เอง (`release.ps1`)

## repo เพื่อนบ้าน (`~/Documents/GitHub/`)
- `claude-config` — ตั้งค่า agent ทุกเครื่อง (`sync-claude.ps1`)
- ไม่เกี่ยวกับ `design-system` (ไม่ใช่เว็บ)