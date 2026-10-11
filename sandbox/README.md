# ทดสอบ lab.ps1 ใน Windows Sandbox

ทดลองทุกเมนูของ `lab.ps1` ใน Windows ชั่วคราวที่ทิ้งได้ ไม่แตะเครื่องจริง

- เครื่อง Windows 11 Pro เปิดฟีเจอร์ครั้งเดียว (Administrator แล้วรีบูต):
  `Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All`
- รัน: `.\sandbox\Start-LabSandbox.ps1` (ค่าเริ่มต้น `-Mode Dry` = `LAB_DRYRUN=1` ไม่เปลี่ยนอะไร)
  - `-Mode Real` รันจริงใน sandbox (ทิ้งทั้งก้อนเมื่อปิดหน้าต่าง)
  - `-Tasks Fonts,Tune` เลือกบางงาน
- ผล: `~\LabSandboxResults\<เวลา>\summary.md` + log รายงาน

## ที่ทำ
1. parse ทุก `.ps1` (ไวยากรณ์ + BOM)
2. รัน `lab.ps1` ทีละงานแบบไม่มีเมนู (`LAB_TASKS`, `LAB_YES=1`) ใช้ `config.json` สำเนาที่ปิด telemetry (ไม่ยิง libdesk จริง) และปิด host guard
3. สรุปรหัสออก จำนวนบรรทัด `[dry]` และบรรทัด error ต่องาน

## ข้อจำกัด
- sandbox **ไม่มีเครือข่าย** (ตั้งใจ ป้องกันยิง libdesk/แตะ share): งานที่ต้องใช้ share, KMS, winget, ดาวน์โหลด ขึ้น `NEEDS-NETWORK` — ทดสอบจริงบนเครื่องแล็บด้วย `LAB_DRYRUN=1`
- Windows ใน sandbox เป็นเครื่องใหม่: ไม่มี Office/SPSS/Chrome จริง งานที่ถอน/ตั้งค่าโปรแกรมเหล่านั้นจึงแค่พิสูจน์ว่าสคริปต์เดินถูก ไม่ใช่ผลกับเครื่องแล็บจริง
- ผ่าน sandbox ≠ ปลอดภัยบนเครื่องแล็บ: `Cleanup`, `BrowserClean`, `RemoveApps` ลบข้อมูลจริง ให้รันเครื่องจริงทีละงานตามกฎ `AGENTS.md`
