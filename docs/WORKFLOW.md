# แนวทางการทำงาน

## หนึ่งรอบงาน (หนึ่งเวอร์ชัน)
1. **ข้อมูลจริงก่อน** — ค้นพฤติกรรม/รูปร่างจริง ขอภาพอ้างอิงจากผู้ใช้ จดลง `docs/BIOLOGY.md` และเก็บภาพใน `reference/`
2. **รายการตรวจความสมจริง** — เขียนข้อสั้นๆ ว่าต้องเห็นอะไรถึงจะถือว่าเหมือนจริง (เช่น "ท้องแฟบ ไม่หด", "เปิดรังไหมด้านหัว")
3. **ลงมือ** — โมเดลทำใน Blender (`tools/blender/`), พฤติกรรมที่มีผลต่อรังอยู่ใน `scripts/sim/`, ภาพเคลื่อนไหวล้วนอยู่ใน `scripts/view/`
4. **ตรวจ** — `powershell -ExecutionPolicy Bypass -File tools/check.ps1` (ระหว่างทำใช้ `-Quick`)
   - ถ้าตั้งใจเปลี่ยนผลการจำลอง: รัน `-UpdateBaseline` และเขียนใน CHANGELOG ว่าเปลี่ยนอะไร
5. **ดูด้วยตา** — ถ่ายภาพด้วย `--shot` (ตัวเลือกอยู่หัว `scripts/game/main.gd`) เก็บใน `shots/vX.Y.Z/` แล้วเปิดดูจริงทุกครั้ง
6. **ปล่อยเวอร์ชัน** — เพิ่ม `config/version` ใน `project.godot`, เขียน `CHANGELOG.md`, รัน `tools/build.ps1`, commit + push
7. **ของที่ยังไม่ทำ** — ลง "รายการค้าง" ใน `docs/ROADMAP.md` ทันที อย่าเก็บไว้ในหัว

## เพิ่มของใหม่
- อาหารชนิดใหม่: รายการใน `scripts/sim/food_kinds.gd` (+ `_food_<ชนิด>()` ภาพ 3 มิติ, ภาพ 2 มิติ, โมเดล Blender ถ้ามี)
- ศัตรูชนิดใหม่: ไฟล์ใน `scripts/sim/enemies/` + ลงทะเบียนใน `ENEMY_KINDS` (+ ภาพ, โมเดล)
- ข้อความบันทึกผู้เลี้ยงใหม่: ค่าคงที่ใน `scripts/sim/text_th.gd`
- ข้อมูลที่ต้องเซฟเพิ่ม: ทำตาม "เปลี่ยนรูปแบบเซฟ" ใน ARCHITECTURE.md — ห้ามเปลี่ยน `to_dict()` โดยไม่มีขั้นแปลง

## กฎขนาดไฟล์
- ไฟล์โค้ดเกิน ~500 บรรทัด → แยก (ใช้ชั้น `extends` ตาม `docs/ARCHITECTURE.md`, เครื่องมือ `tools/dev/split_gd.py`)
- ของชนิดใหม่ (ศัตรู, อาหาร, วรรณะ) ให้เป็นไฟล์ของตัวเอง อย่าเพิ่ม `match` ยาวๆ ในไฟล์กลาง
- `mesh_kit.gd` (~576 บรรทัด): มีโมเดลสำรองแบบเก่าของเพลี้ย/จิ้งหรีด/ต้นไม้ — ลบได้เมื่อแน่ใจว่าไฟล์ Blender ครบทุกที่

## เซฟของผู้เล่น
- ห้ามแตะเซฟจริง (`%APPDATA%\Godot\app_userdata\AntFarm\saves`) ในการทดสอบ — ใช้ `--sandbox`
- ทดสอบกับรังจริงของผู้ใช้: คัดลอก `saves/slot1.*` ไป `sandbox/saves/` แล้ว `tests/real_save_test.gd` (ผู้ใช้อนุญาตแล้ว 2026-10-11)
- เปลี่ยนรูปแบบเซฟได้ก็ต่อเมื่อมีระบบแปลงเซฟเก่าแล้ว (ดู ARCHITECTURE.md)

## ผลงานที่ส่งให้ผู้ใช้
- ปิดเกมก่อน build ถ้าเกมเปิดอยู่ `build.ps1` จะสลับทางลัดให้หลังปิดเกม — บอกผู้ใช้ให้ปิดแล้วเปิดใหม่
- `build/versions/` เก็บ 5 เวอร์ชันล่าสุด + เวอร์ชัน x.y.0 ของแต่ละ PART (ลบตัวอื่นได้ ผู้ใช้อนุญาตแล้ว)

## Blender
- เปิด Blender → กด N → แท็บ BlenderMCP → Connect (port 9876)
- สร้างโมเดล: `python tools/blender/bl.py tools/blender/build_ant.py VARIANT=worker LOD=hi [SHOT=png VIEW=3q|side|top]`
  หรือ `build_props.py WHAT=aphid|cricket|plant|spider|centipede|beetle|fly [VARIANT=0..2] [SHOT=png] [VIEW=top|side]` — ไฟล์ออกไปที่ `assets/models/<กลุ่ม>/`
  (ตัวสร้างแต่ละชนิดอยู่ใน `tools/blender/props/<ชนิด>.py`; `build_props.py` มีแค่เครื่องมือกลางและตัวเลือก WHAT;
  Blender สร้างซ้ำได้ไฟล์ต่างกันเล็กน้อยทุกครั้ง จึงสร้างใหม่เฉพาะชนิดที่แก้)
- โมเดลมดต้องรักษาจุดหมุนข้อต่อและรหัสส่วนร่างกาย (ARCHITECTURE.md) ไม่อย่างนั้นอนิเมชันพัง
