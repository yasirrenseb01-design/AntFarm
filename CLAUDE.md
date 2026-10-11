# AntFarm

เกมจำลองการเลี้ยงมดแบบสมจริง (มดดำสวน *Lasius niger*) ผู้ใช้สื่อสารเป็นภาษาไทย ตอบเป็นภาษาไทย

## อ่านก่อนทำงาน
- `docs/ROADMAP.md` แผนแต่ละ PART, สถานะ, งานถัดไป และ **รายการค้าง** (อัปเดตทุกครั้งที่ทำเสร็จหรือเว้นอะไรไว้)
- `docs/WORKFLOW.md` ขั้นตอนหนึ่งรอบงาน, กฎขนาดไฟล์ (~500 บรรทัด), เรื่องเซฟและ Blender
- `docs/ARCHITECTURE.md` โฟลเดอร์, ไฟล์ที่แยกเป็นชั้น (`extends` path), หน่วยวัด, รหัสส่วนร่างกายมด, รูปแบบ `.antmesh`
- `docs/BIOLOGY.md` ข้อมูลชีววิทยาและแหล่งอ้างอิง (ภาพอ้างอิงใน `reference/`)

## กฎสำคัญ
- ทำงานทีละ PART ตามที่ผู้ใช้เลือก ไม่ทำล่วงหน้าหลายส่วนพร้อมกัน
- Godot 4.7.2 GDScript: `E:\Godot_v4.7.2-stable_win64_console.exe` — สคริปต์ที่มี parse error ทำให้ Godot ค้าง ใช้ `timeout` และ `--check-only` ก่อนรัน
- ตรวจทุกอย่างก่อนส่ง: `powershell -ExecutionPolicy Bypass -File tools/check.ps1` (`-Quick` ระหว่างทำ)
- ส่งงาน: เพิ่ม `config/version` (`0.PART.รอบแก้`) ใน `project.godot`, เขียน `CHANGELOG.md`, รัน `tools/build.ps1` (ทางลัดบนเดสก์ท็อปเปิด `build/AntFarm.exe`), commit + push
- รังเริ่มต้นคือราชินีตัวเดียว; ทดสอบรัง 14 ตัวใส่ `--workers=14`; ห้ามแตะเซฟจริงของผู้เล่น (ใช้ `--sandbox`)
- การจำลองต้อง deterministic (ใช้ `sim.rng` ไม่ใช่ `randf()`)
- GitHub (private): https://github.com/yasirrenseb01-design/AntFarm — branch `main`
- Cloud session (Linux ไม่มี Godot/การ์ดจอ): ทำโค้ดได้ แต่สร้าง exe/จับภาพไม่ได้ → ส่งเป็น branch/PR ให้ session บนเครื่องผู้ใช้ทดสอบภาพและ build
- Blender 5.0 (`C:\Program Files\Blender Foundation\Blender 5.0\blender.exe`) ผ่าน MCP (`.mcp.json`, add-on ฟัง localhost:9876 — ผู้ใช้ต้องกด Connect) หรือ `tools/blender/bl.py`
