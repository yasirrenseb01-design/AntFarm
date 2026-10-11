# โครงสร้างโปรแกรม AntFarm

## หลักใหญ่
- **การจำลอง (`scripts/sim/`) แยกขาดจากภาพ (`scripts/view/`)** — การจำลองเป็นข้อมูลล้วน ไม่มี Node รันแบบ headless ได้
  (self-test, จำลองช่วงปิดเกม) และต้องได้ผลเหมือนเดิมทุกครั้งเมื่อใช้ seed เดิม (deterministic) ห้ามใช้ `randf()` ทั่วไปใน sim ให้ใช้ `sim.rng`
- **ภาพอ่านการจำลอง แต่ไม่แก้** — ยกเว้นการกระทำของผู้เล่น (`place_food`, `add_rock`, `add_water` ...) ส่วนภาพเคลื่อนไหวที่ sim ไม่รู้
  (มดในรังเดินตามอุโมงค์, อนิเมชันวงจรชีวิต) เป็นของ view ล้วน ใช้ `randf()` ได้ และไม่ถูกเซฟ
- **เหตุการณ์จาก sim ไปภาพ**: `sim.events` (รายการล่าสุด `{n, k, s}`, ไม่ถูกเซฟ) — view จำ `n` ล่าสุดที่เห็นแล้ว เช่น `nest_lifecycle.gd`
- **บันทึกผู้เลี้ยง**: `sim._log()` → สัญญาณ `logged`

## โฟลเดอร์
```
scripts/
  game/        main.gd (จุดเริ่ม), save_store.gd, parts/ (main_base, main_camera)
  dev/         dev_tools.gd (--shot, --selftest), ตัวเลือกบรรทัดคำสั่งอยู่หัว main.gd
  sim/         simulation.gd + parts/ (sim_base, sim_foragers, sim_enemies, sim_colony),
               ant.gd, climate.gd, nest_volume.gd, pheromone_field.gd, species/
  view/
    common/    ant_model3d.gd (โหลด .antmesh ของมด), mesh_kit.gd (โมเดลของในกล่อง + โหลด asset)
    outworld/  พื้นที่หาอาหาร 3 มิติ: outworld_view.gd + parts/ (scene, props, creatures, camera)
    nest/      รังใต้ดิน 3 มิติ: nest_view.gd + parts/ (scene, camera, brood, lifecycle, mates), nest_mesher.gd
    surface2d/ มุมบน 2 มิติ: world_view.gd, ant_batch.gd, draw_kit.gd
    ui/        hud.gd + parts/ (base, colonies, controls, panel)
shaders/       ants/, creatures/, terrain/, plants/
assets/models/ ants/, prey/, plants/   (ไฟล์ .antmesh/.json ที่ Blender สร้าง — ห้ามแก้มือ ให้รันสคริปต์ Blender ใหม่)
tools/         build.ps1, check.ps1, blender/ (build_ant.py, build_props.py, bl.py), dev/split_gd.py
tests/         save_test, reach_test, real_save_test, rock_test, nest_debug, baselines/
reference/     ภาพอ้างอิงจากผู้ใช้ + ที่มา (ไม่รวมเข้าเกม)
```

## ไฟล์ที่แยกเป็นชั้น (layer chain)
ไฟล์ใหญ่แยกเป็นลำดับชั้นด้วย `extends "res://...path.gd"` — ชั้นล่างสุดเก็บตัวแปรทั้งหมด แต่ละชั้นเรียกได้เฉพาะฟังก์ชันของชั้นตัวเองหรือชั้นที่ต่ำกว่า
ไฟล์ชั้นบนสุดอยู่ที่ path เดิม คนอื่น preload ไฟล์นี้
| ระบบ | ลำดับชั้น (ล่าง → บน) |
|---|---|
| การจำลอง | `sim_base` (สถานะ, setup, เวลา, การกระทำของผู้เล่น) ← `sim_foragers` ← `sim_enemies` ← `sim_colony` ← `simulation` (step, เซฟ) |
| รัง 3 มิติ | `nest_scene` ← `nest_camera` ← `nest_brood` ← `nest_lifecycle` ← `nest_mates` ← `nest_view` (setup, refresh, input) |
| พื้นดิน 3 มิติ | `outworld_scene` ← `outworld_props` ← `outworld_creatures` ← `outworld_camera` ← `outworld_view` |
| HUD | `hud_base` ← `hud_colonies` ← `hud_controls` ← `hud_panel` ← `hud` |
| เกม | `main_base` ← `main_camera` ← `dev/dev_tools` ← `main` |

ถ้าฟังก์ชันใหม่ต้องเรียกฟังก์ชันชั้นสูงกว่า ให้ย้ายฟังก์ชันใหม่ขึ้นไปอยู่ชั้นนั้น (Godot จะ error "Function not found in base self")
แยกไฟล์เพิ่มได้ด้วย `python tools/dev/split_gd.py plan.json` (ดูหัวไฟล์)

## หน่วยวัด
| ที่ใช้ | หน่วย | เท่ากับ |
|---|---|---|
| พื้นที่หาอาหารในการจำลอง | px | 0.5 มม. (กล่อง 1200×750 px = 60×37.5 ซม.) |
| รัง (voxel) และโลก 3 มิติข้างนอก | unit | 1.5 มม. = 1 voxel = 3 px (`outworld U = 1/3`) |
| โมเดลมด (ออกแบบ) | design unit | ~0.5 มม.; ส่งออกคูณ `K = 0.34` → มดงานยาว ~2.8 unit (4.2 มม.) |
| เวลา | tick | 1 วันในเกม = 3600 tick = 60 วินาทีที่ 1× |

แกน Godot: x หน้า, y ขึ้น, z ขวา; Blender (z ขึ้น) แปลงด้วย `G(x,y,z) = (x, -z, y)`

## โมเดลมดและอนิเมชัน
- โมเดลมาจาก `tools/blender/build_ant.py` → `assets/models/ants/{worker,queen}_{hi,lo}.antmesh` (hi ตอนซูมใกล้, lo ตอนไกล)
- vertex color = ตัวคูณสีบนสี tint ของแต่ละตัว; **alpha = รหัสส่วนร่างกาย / 16**:
  0 ลำตัว, 1 หัว, 2/3 หนวดซ้าย/ขวา, 4–9 ขา (หน้าซ้าย, หน้าขวา, กลางซ้าย, กลางขวา, หลังซ้าย, หลังขวา), 10 ท้อง, 11 กราม ("ซ้าย" = ด้าน -z)
- `shaders/ants/ant.gdshader` หมุนแต่ละส่วนรอบข้อต่อ (จุดหมุนใน design units × K) ตาม INSTANCE_CUSTOM = (จังหวะเดิน, กิจกรรม, นาฬิกา, ปริมาณการเดิน)
- รหัสกิจกรรม: 0 เดิน, 1 พัก, 2 ขุด/กัด, 3 แตะหนวด, 4 ทำความสะอาด, 5 วางไข่, 6 ป้อนอาหาร, 7 ดูแลตัวอ่อน, 8 คาบของ, 9 รีดเพลี้ย, 10 ดื่ม, 11 ตาย, 12 เพิ่งออกจากรังไหม; +100 = ท้องเต็มน้ำหวาน
- `limb_gain` (shader uniform) ทำให้ขา/หนวด/กรามสีอ่อนกว่าตัว (ราชินีสีส้มอำพัน)

## รูปแบบไฟล์ .antmesh
`"ANTM"`, จำนวน vertex (u32), จำนวน index (u32), ต่อ vertex 10 float (ตำแหน่ง xyz, normal xyz, สี rgba), แล้ว index u32
(หน้าเรียงตามเข็มนาฬิกาแบบ Godot) — โหลดด้วย `ant_model3d.gd load_antmesh()`; ของในกล่องโหลดผ่าน `mesh_kit.gd asset("prey/aphid_adult")`
ต้นถั่วมีไฟล์ `.json` คู่กัน เก็บเส้นลำต้น (ให้เพลี้ยและมดเกาะ)

## เซฟ
- `scripts/game/save_store.gd`: 3 ช่อง (`user://saves/slotN.antfarm` บีบอัด zstd + `slotN.json` สรุปสำหรับเมนู), เขียนไฟล์ชั่วคราวก่อนแทนที่
- เนื้อหา = `sim.to_dict()` (ข้อมูลล้วน ไม่มี path ของสคริปต์ — ย้ายไฟล์ได้โดยเซฟไม่พัง), `SAVE_VERSION` ใน `sim_base.gd`
- **ข้อควรระวัง:** ตอนนี้ถ้า `SAVE_VERSION` ไม่ตรง เกมจะเริ่มรังใหม่ — ต้องทำระบบแปลงเซฟเก่า (migration) ก่อนเปลี่ยนรูปแบบเซฟครั้งแรก (แผน v0.5.8)
- ทดสอบโดยไม่แตะเซฟจริง: `--sandbox` ใช้ `user://sandbox/`
