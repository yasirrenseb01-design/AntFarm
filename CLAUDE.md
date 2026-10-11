# AntFarm

เกมจำลองการเลี้ยงมดแบบสมจริง ผู้ใช้สื่อสารเป็นภาษาไทย ตอบเป็นภาษาไทย

- แผนงานและสถานะของแต่ละส่วน: `docs/ROADMAP.md` (อัปเดตช่องติ๊กเมื่อทำส่วนไหนเสร็จ)
- ต้นแบบเว็บที่ใช้อ้างอิงระบบการจำลอง: `prototype/ant-farm.html`
- Engine: Godot 4.7.2 แบบ GDScript (`E:\Godot_v4.7.2-stable_win64_console.exe` สำหรับรันแบบ headless/command line)
- ทำงานทีละส่วนตามที่ผู้ใช้เลือก ไม่ทำล่วงหน้าหลายส่วนพร้อมกัน
- เวอร์ชัน `0.PART.รอบแก้` อยู่ใน `project.godot` (`config/version`); ทุกครั้งที่ส่งงานให้ผู้ใช้ลอง: เพิ่มเลขเวอร์ชัน, เขียน `CHANGELOG.md`, รัน `tools/build.ps1` (ทางลัดบนเดสก์ท็อปเปิด `build/AntFarm.exe`)
- รังเริ่มต้นคือราชินีตัวเดียว; การทดสอบที่ต้องการรัง 14 ตัวต้องใส่ `--workers=14`
- ทดสอบได้ด้วย `--selftest`, `--shot` (ดูหัวไฟล์ `scripts/main.gd`) — สคริปต์ที่มี parse error จะทำให้ Godot ค้าง ให้ใช้ `timeout` และ `--check-only` ก่อน
- โค้ดอยู่บน GitHub (private): https://github.com/yasirrenseb01-design/AntFarm — branch หลัก `main`; ส่งงานแต่ละเวอร์ชันแล้ว commit + push
- Cloud session (Linux, ไม่มีการ์ดจอ, ไม่มี Godot ติดมา): ทำงานโค้ด/ระบบจำลองได้ แต่สร้าง `AntFarm.exe` และจับภาพหน้าจอไม่ได้ → ส่งงานเป็น branch/PR แล้วให้ session บนเครื่องผู้ใช้ pull, ทดสอบภาพ และรัน `tools/build.ps1`
- Blender 5.0 (`C:\Program Files\Blender Foundation\Blender 5.0\blender.exe`) ต่อผ่าน MCP ที่ `.mcp.json` (`uvx blender-mcp`, add-on "MCP for Blender" ฟังที่ localhost:9876 — ผู้ใช้ต้องเปิด Blender แล้วกด Connect ใน sidebar แท็บ BlenderMCP); โมเดลจาก Blender ต้องเก็บรหัสส่วนร่างกายไว้ใน vertex color alpha (id/16) ให้ `shaders/ant.gdshader` ขยับได้เหมือนเดิม
