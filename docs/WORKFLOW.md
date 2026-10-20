# แนวทางการทำงาน

## หนึ่งรอบงาน (หนึ่งเวอร์ชัน)
1. **ข้อมูลจริงก่อน** — ค้นพฤติกรรม/รูปร่างจริง ขอภาพอ้างอิงจากผู้ใช้ จดลง `docs/BIOLOGY.md` และเก็บภาพใน `reference/`
2. **รายการตรวจความสมจริง** — เขียนข้อสั้นๆ ว่าต้องเห็นอะไรถึงจะถือว่าเหมือนจริง (เช่น "ท้องแฟบ ไม่หด", "เปิดรังไหมด้านหัว")
3. **ลงมือ** — โมเดลทำใน Blender (`tools/blender/`), พฤติกรรมที่มีผลต่อรังอยู่ใน `scripts/sim/`, ภาพเคลื่อนไหวล้วนอยู่ใน `scripts/view/`
4. **ตรวจ** — `powershell -ExecutionPolicy Bypass -File tools/check.ps1` (ระหว่างทำใช้ `-Quick`)
   - ถ้าตั้งใจเปลี่ยนผลการจำลอง: รัน `-UpdateBaseline` และเขียนใน CHANGELOG ว่าเปลี่ยนอะไร
5. **ดูด้วยตา** — ถ่ายภาพด้วย `tools/dev/gd.sh --path . -- --shot=...` (ตัวเลือกอยู่หัว `scripts/game/main.gd`) แล้วเปิดดูจริงทุกครั้ง
   - ของที่เคลื่อนไหว: ภาพต่อเนื่อง `--seq=9 --seq-every=3 --seq-speed=0.5` (+ `--at-ant=walker`) แล้ว `python tools/dev/strip.py`
   - ของชิ้นใหม่: ดูทั้งมุมต่ำและมุมบน, เทียบขนาดกับตาราง "ขนาดจริง" ใน BIOLOGY.md
   - ระบบที่กระทบการอยู่รอดของรัง: `tests/year_run.gd -- wild 0 1100 alone <seed>` อย่างน้อย 2 seed + แบบดูแล
6. **ปล่อยเวอร์ชัน** — เพิ่ม `config/version` ใน `project.godot`, เขียน `CHANGELOG.md`, รัน `tools/build.ps1`, commit + push
7. **ของที่ยังไม่ทำ** — ลง `docs/roadmap/BACKLOG.md` ทันที อย่าเก็บไว้ในหัว; PART เสร็จ → ย้ายรายละเอียดไป `docs/roadmap/DONE.md`

## รายการตรวจก่อนส่ง (ทุกเวอร์ชัน)
- [ ] `tools/check.ps1` ผ่าน (เปลี่ยนผลจำลองตั้งใจ → `-UpdateBaseline` + บอกใน CHANGELOG)
- [ ] ดูภาพจริงของสิ่งที่แก้ (ข้อ 5) — ไม่ใช่แค่ test ผ่าน; ข้อความใหม่อยู่ใน `lang/strings.csv` ทั้งไทยและอังกฤษ ดูภาพทั้งสองภาษา
- [ ] ขนาดไฟล์: `git ls-files '*.gd' '*.py' | xargs wc -l | sort -rn | head` — เกิน ~500 แยก
- [ ] เอกสาร: ARCHITECTURE (ชั้นไฟล์, รหัสกิจกรรม, รูปแบบเซฟ), BIOLOGY (ข้อมูล/ขนาดใหม่), ROADMAP (สถานะ) + roadmap/BACKLOG (ค้าง/ไอเดีย)
- [ ] พลาดอะไรในรอบนี้ → เพิ่มใน `docs/LESSONS.md`
- [ ] เวอร์ชัน + CHANGELOG + `tools/dev/release.sh` (ตรวจ+สร้าง เฉพาะเมื่อผ่าน) + commit/push

## เพิ่มของใหม่
- อาหารชนิดใหม่: รายการใน `scripts/sim/food_kinds.gd` (+ `_food_<ชนิด>()` ภาพ 3 มิติ, ภาพ 2 มิติ, โมเดล Blender ถ้ามี)
- ศัตรูชนิดใหม่: ไฟล์ใน `scripts/sim/enemies/` + ลงทะเบียนใน `ENEMY_KINDS` (+ ภาพ, โมเดล)
- ข้อความบันทึกผู้เลี้ยงใหม่: ค่าคงที่ใน `scripts/sim/text_th.gd`
- ข้อมูลที่ต้องเซฟเพิ่ม: ทำตาม "เปลี่ยนรูปแบบเซฟ" ใน ARCHITECTURE.md — ห้ามเปลี่ยน `to_dict()` โดยไม่มีขั้นแปลง

## กฎขนาดไฟล์
- ไฟล์โค้ดเกิน ~500 บรรทัด → แยก (ใช้ชั้น `extends` ตาม `docs/ARCHITECTURE.md`, เครื่องมือ `tools/dev/split_gd.py`)
- ของชนิดใหม่ (ศัตรู, อาหาร, วรรณะ) ให้เป็นไฟล์ของตัวเอง อย่าเพิ่ม `match` ยาวๆ ในไฟล์กลาง
- ไฟล์ที่แยกแล้วเขียนหัวไฟล์ว่า "split from <ไฟล์เดิม> in vX.Y.Z" และลำดับชั้น เพื่อตามกลับได้ (ตารางใน ARCHITECTURE)
- สคริปต์ Blender ที่โต: แยกเป็นไฟล์ย่อยแล้วให้ไฟล์หลัก `exec` ตามลำดับ (`tools/blender/props/`, `tools/blender/ant/`)
- `mesh_kit.gd`: มีโมเดลสำรองแบบเก่าของเพลี้ย/จิ้งหรีด/ต้นไม้ — ลบได้เมื่อแน่ใจว่าไฟล์ Blender ครบทุกที่

## เอกสารที่โตได้
- `docs/roadmap/BACKLOG.md` เกิน ~300 บรรทัด → แยกเป็น `docs/roadmap/backlog/PART<N>.md` ให้ไฟล์หลักเหลือแค่สารบัญ
- `CHANGELOG.md` เกิน ~600 บรรทัด → ย้ายเวอร์ชันของ PART ที่เสร็จนานแล้วไป `docs/changelog/PART<N>.md` (ไฟล์หลักเก็บ 2 PART ล่าสุด + ลิงก์)
- `docs/LESSONS.md` จัดหมวด (การรัน/ความสมจริง/เครื่องมือ) เกิน ~200 บรรทัดค่อยแยกตามหมวด

## เซฟของผู้เล่น
- ห้ามแตะเซฟจริง (`%APPDATA%\Godot\app_userdata\AntFarm\saves`) ในการทดสอบ — ใช้ `--sandbox`
- ทดสอบกับรังจริงของผู้ใช้: คัดลอก `saves/slot1.*` ไป `sandbox/saves/` แล้ว `tests/real_save_test.gd` (ผู้ใช้อนุญาตแล้ว 2026-10-11)
- เปลี่ยนรูปแบบเซฟได้ก็ต่อเมื่อมีระบบแปลงเซฟเก่าแล้ว (ดู ARCHITECTURE.md)

## ผลงานที่ส่งให้ผู้ใช้
- ปิดเกมก่อน build ถ้าเกมเปิดอยู่ `build.ps1` จะสลับทางลัดให้หลังปิดเกม — บอกผู้ใช้ให้ปิดแล้วเปิดใหม่
- `build.ps1` ลบ build เก่าเอง (เก็บ 5 เวอร์ชันล่าสุด + x.y.0 ของทุก PART) — ห้ามลบใน `build/versions` ด้วยมือ
- `build/versions/` เก็บ 5 เวอร์ชันล่าสุด + เวอร์ชัน x.y.0 ของแต่ละ PART (ลบตัวอื่นได้ ผู้ใช้อนุญาตแล้ว)

## Blender
- เปิด Blender → กด N → แท็บ BlenderMCP → Connect (port 9876)
- สร้างโมเดล: `python tools/blender/bl.py tools/blender/build_ant.py VARIANT=worker LOD=hi [SHOT=png VIEW=3q|side|top]`
  หรือ `build_props.py WHAT=aphid|cricket|plant|spider|centipede|beetle|fly [VARIANT=0..2] [SHOT=png] [VIEW=top|side]` — ไฟล์ออกไปที่ `assets/models/<กลุ่ม>/`
  (ตัวสร้างแต่ละชนิดอยู่ใน `tools/blender/props/<ชนิด>.py`; `build_props.py` มีแค่เครื่องมือกลางและตัวเลือก WHAT;
  Blender สร้างซ้ำได้ไฟล์ต่างกันเล็กน้อยทุกครั้ง จึงสร้างใหม่เฉพาะชนิดที่แก้)
- โมเดลมดต้องรักษาจุดหมุนข้อต่อและรหัสส่วนร่างกาย (ARCHITECTURE.md) ไม่อย่างนั้นอนิเมชันพัง
