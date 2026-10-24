# โครงสร้างโปรแกรม AntFarm

## หลักใหญ่
- **การจำลอง (`scripts/sim/`) แยกขาดจากภาพ (`scripts/view/`)** — การจำลองเป็นข้อมูลล้วน ไม่มี Node รันแบบ headless ได้
  (self-test, จำลองช่วงปิดเกม) และต้องได้ผลเหมือนเดิมทุกครั้งเมื่อใช้ seed เดิม (deterministic) ห้ามใช้ `randf()` ทั่วไปใน sim ให้ใช้ `sim.rng`
- **ภาพอ่านการจำลอง แต่ไม่แก้** — ยกเว้นการกระทำของผู้เล่น (`place_food`, `add_rock`, `add_water` ...) ส่วนภาพเคลื่อนไหวที่ sim ไม่รู้
  (มดในรังเดินตามอุโมงค์, อนิเมชันวงจรชีวิต) เป็นของ view ล้วน ใช้ `randf()` ได้ และไม่ถูกเซฟ
- **เหตุการณ์จาก sim ไปภาพ**: `sim.events` (รายการล่าสุด `{n, k, s}`, ไม่ถูกเซฟ) — view จำ `n` ล่าสุดที่เห็นแล้ว เช่น `nest_lifecycle.gd`
- **บันทึกผู้เลี้ยง**: `sim._log(T.<ชื่อ>)` → สัญญาณ `logged`; ข้อความภาษาไทยทั้งหมดของการจำลองอยู่ที่ `scripts/sim/text_th.gd`
- **ภาพอ่านเหตุการณ์** ผ่าน `view/common/event_feed.gd` (แต่ละมุมมองมี feed ของตัวเอง: `take()` ได้เหตุการณ์ใหม่, `skip()` ข้ามของเก่า)

## ตารางชนิดของ (เพิ่มของใหม่ = เพิ่มรายการ ไม่ต้องไล่แก้หลายไฟล์)
- **อาหาร** `scripts/sim/food_kinds.gd` (`KINDS`): ค่าการจำลอง, เวลาเก็บ, ข้อความตอนเจอ, ปุ่มวางของ, ท่าที่มดยืนกิน, การกลบดิน
  - ภาพ 3 มิติ: ฟังก์ชัน `_food_<ชนิด>()` ใน `view/outworld/parts/outworld_props.gd` (ไม่มีก็ได้ก้อนเรียบๆ แทน)
- **ศัตรู** `scripts/sim/enemies/<ชนิด>.gd` (static `spawn(sim)`, `step(sim, c) -> bool`, `CHASED`) ลงทะเบียนใน `ENEMY_KINDS` ของ `sim/parts/sim_enemies.gd`;
  ตัวที่อยู่ในกล่องอยู่ใน `sim.creatures` (Dictionary ที่มี `kind`, `pos`, ... ถูกเซฟตรงๆ)
  - ภาพ 3 มิติ: `_update_spider()` ใน `outworld_creatures.gd` (PART 6 จะแยกเป็นไฟล์ละชนิดแบบเดียวกัน)
- **การต่อสู้** (`sim/parts/sim_enemies.gd`): มดสถานะ `Ant.DEFEND` วิ่งหาศัตรู (`ant.foe` = id) แล้วเกาะ (`busy > 0`)
  ไปกับตัวศัตรูที่จุดเกาะรอบตัว, ลดพลังชีวิต `hp` ด้วยกรด; สนามกลิ่นเตือนภัย `sim.alarm` (ระเหยเร็ว); ศัตรูกัดกลับผ่าน `sim._bite()`,
  สะบัดผ่าน `sim._shake_off()`; ตาย → อาหาร `<ชนิด>_dead` ในตารางอาหาร; `ant.hurt` = บาดเจ็บถาวร (เดินช้าลง)
  - ภาพ: กิจกรรม 13 (เกาะ กัด พ่นกรด) และ 14 (วิ่งตื่นตกใจ) ใน `shaders/ants/ant.gdshader`; กลิ่นเตือนภัยสีแดงในชั้นกลิ่นบนพื้น
  - ทดสอบภาพ: `--enemy=wolf_spider --fight=<tick>` (จัดศัตรูไว้ข้างรังแล้วเดินเวลา)
- **มดรายตัว** (v0.8.22): `ant.task` (`TASK_CALLOW/NURSE/RESERVE/DIG`, ข้างนอก `TASK_OUT`) ตั้งทุกรอบรังใน `sim_colony._colony`;
  `ant.threshold(TH_*)` เกณฑ์ตอบสนองรายตัว (คำนวณจาก id ไม่ต้องเซฟ) — ตัวที่เกณฑ์ต่ำออกหากิน/ขนศพ/สู้/ขุดก่อน และเลิกเป็นพี่เลี้ยงคนละอายุ
  - ภาพในรัง: `nest_rest._bind_workers()` มดที่วาดหนึ่งตัวต่อมดงานจริงที่อยู่ในรัง (`mate.wid`); มดที่ออกไปเดินขึ้นปากรังก่อน,
    มดที่เพิ่งกลับ (`ant.came_in`) เดินเข้าจากปากรัง; มดขุดวาดแยก (`_dig_vis`) ผูกกับมดหน้าที่ขุดตามลำดับ id
- **การลากเหยื่อ** (v0.8.20): `Ant.DRAG` (`foe` = seed ของอาหาร, `ang` = ตำแหน่งที่จับ) — `sim_foragers._step_drags()`, อาหารที่มี `drag` ในตาราง
- **วรรณะ** `ant.caste`: `Ant.WORKER` (ตอนนี้ทุกตัว), `Ant.GYNE`, `Ant.MALE` (PART 10)
- **สายพันธุ์** `scripts/sim/species/lasius_niger.gd` (`sim.sp`): ตัวเลขชีววิทยา + นิสัยเฉพาะ (`founding`, `queen_reserve`, `founding_eggs`,
  `nanitic_size`, `tends_aphids`, `buries_prey`) — โค้ดอ่านจากที่นี่ ไม่เขียนค่าตายตัว

## โฟลเดอร์
```
scripts/
  game/        main.gd (จุดเริ่ม), save_store.gd, desktop_mode.gd (โหมดวอลเปเปอร์ PART 11), title.gd (หน้าแรก + กล้องเดินชมรัง),
               single_instance.gd (เกมเดียวต่อเครื่อง: ตัวที่สองบอกตัวแรกให้ขึ้นมา, พอร์ต 47815), parts/ (main_base, main_camera)
  dev/         dev_tools.gd (--shot, --selftest), ตัวเลือกบรรทัดคำสั่งอยู่หัว main.gd
  sim/         simulation.gd + parts/ (sim_state, sim_base, sim_foragers, sim_enemies, sim_warmth, sim_colony, sim_duties), lang.gd (ภาษา),
               ant.gd, climate.gd, nest_volume.gd (+ parts/nest_voxels, nest_chambers), pheromone_field.gd, species/
  view/
    common/    ant_model3d.gd (โหลด .antmesh ของมด + ค่าการก้าว), mesh_kit.gd + parts/mesh_kit_base (โมเดลของในกล่อง + โหลด asset)
    outworld/  พื้นที่หาอาหาร 3 มิติ: outworld_view.gd + parts/ (scene, props, creatures, camera),
               ground_data.gd (ภาพผิวดิน, ภาพกลิ่นทาง, ของประดับ, แสงฟ้า, เครื่องมือที่เลือก — เดิมอยู่ในมุมบน 2 มิติ ลบ v0.11.5),
               prop_heights.gd (ความสูงของกรวด/มอส/กิ่งไม้/ใบไม้ ให้มดปีนข้าม — ตัวมดและเท้าใน shader),
               garden_layout.gd (จัดของประดับฉากสวนเป็นกลุ่ม: หินใหญ่นอกมุมแปลง มอส กรวด ใบไม้ ดงหญ้า; v0.11.37),
               scenery_draw.gd (สร้างเมชของประดับจากผังใน ground_data; แยกจาก outworld_scene v0.11.37)
    nest/      รังใต้ดิน 3 มิติ: nest_view.gd + parts/ (scene, camera, brood, lifecycle, bodies, mates), nest_mesher.gd
    ui/        hud.gd + parts/ (base, colonies, enemies, controls, panel), draw_kit.gd (วาดมด 2 มิติในภาพตัดขวางของแผงข้าง), species_window.gd (เลือกชนิดมดตอนเริ่มรังใหม่), paper.gd (สไตล์สมุดบันทึก: กระดาษคราฟต์ ธีมหน้าต่าง เสียงดินสอ), ant_tip.gd (คลิกเลือกมด: กล่องสถานะ — ฉากต่างๆ มี pick_ant()/info_for()),
               sounds.gd (เสียงเตือน), music.gd (เพลงพื้นหลัง 2 เพลงจากไฟล์ `assets/audio/music/` เล่นสลับกัน)
shaders/       ants/, creatures/, terrain/ (+ ground_h.gdshaderinc: ความสูงพื้นข้างนอก ใช้ร่วมพื้นกับสัตว์), plants/
assets/models/ ants/, prey/, plants/   (ไฟล์ .antmesh/.json ที่ Blender สร้าง — ห้ามแก้มือ ให้รันสคริปต์ Blender ใหม่)
tools/         build.ps1 (สร้าง + ลบ build เก่าเอง + คอมไพล์ AntDesk.exe), check.ps1, desktop/antdesk.cs (ตัวช่วย Win32 ของโหมดวอลเปเปอร์),
               blender/ (build_ant.py + ant/<ส่วน>.py, build_props.py + props/<ชนิด>.py, bl.py),
               dev/ (gd.sh เปิด Godot อย่างปลอดภัย, split_gd.py แยกไฟล์, strip.py รวมภาพต่อเนื่อง)
tests/         save_test, migration_test (+ fixtures/save_vN), reach_test, real_save_test, rock_test, nest_debug,
               year_run (จำลองหลายปี, แบบ alone = ไม่ดูแล), baselines/
reference/     ภาพอ้างอิงจากผู้ใช้ + ที่มา (ไม่รวมเข้าเกม)
```

## ไฟล์ที่แยกเป็นชั้น (layer chain)
ไฟล์ใหญ่แยกเป็นลำดับชั้นด้วย `extends "res://...path.gd"` — ชั้นล่างสุดเก็บตัวแปรทั้งหมด แต่ละชั้นเรียกได้เฉพาะฟังก์ชันของชั้นตัวเองหรือชั้นที่ต่ำกว่า
ไฟล์ชั้นบนสุดอยู่ที่ path เดิม คนอื่น preload ไฟล์นี้
| ระบบ | ลำดับชั้น (ล่าง → บน) |
|---|---|
| การจำลอง | `sim_state` (ค่าคงที่ ตัวแปร รูปแบบเซฟ; แยก v0.11.8) ← `sim_base` (setup, เวลา, การกระทำของผู้เล่น, ชื่อ) ← `sim_foragers` ← `sim_enemies` ← `sim_warmth` (อุณหภูมิแต่ละห้องตามความลึก ห้องของลูกมดและราชินี; v0.11.19) ← `sim_colony` ← `sim_duties` (เวรในรังทุกครึ่งชั่วโมง, `top_ants`, `duty_of`; ใหม่ v0.11.8) ← `simulation` (step, เซฟ) |
| รัง (การจำลอง) | `nest_voxels` (ช่องดิน, ขุดทั้งห้อง, ความหนาแน่นให้ mesher, เซฟ) ← `nest_chambers` (แผนห้อง) ← `nest_volume` (มดขุด) — แยก v0.8.5 |
| รัง 3 มิติ | `nest_scene` ← `nest_camera` ← `nest_brood` ← `nest_piles` (กองลูกมด: ของแต่ละชิ้นอยู่ที่เดิม; แยก v0.8.31) ← `nest_lifecycle` ← `nest_feet` (ขา: ก้าวตามระยะที่ตัวไปจริง, จำที่วางเท้าของแต่ละกลุ่มขาส่งให้ shader เป็น `feet_tex`; แยก v0.11.33) ← `nest_bodies` (เดินตามทาง, ตัวกันชน; แยก v0.8.5) ← `nest_rest` (ที่หยุดพัก, ตัวพ้นดิน/ผนัง, ก้าวหลบเมื่อถูกเบียด, ผูกมดที่วาดกับมดงานจริง; แยก v0.8.55) ← `nest_soil` (ตัวพ้นดิน: ดันออกจากผนัง, คลำด้วยหนวด, เชิดหัว/ยกท้อง; แยก v0.11.26) ← `nest_contact` (มองข้างหน้าแล้วชะลอ/หยุด, ปีนข้ามมดและลูกมดจากรูปทรงจริง, หันหนีผนังและขอบที่ไม่มีพื้น, ดันออกจากผนังอุโมงค์; ใหม่ v0.8.63) ← `nest_duties` (มดเล่นตามเวรของการจำลอง: บทบาท, คู่ป้อนน้ำหวาน/เลียตัว; ใหม่ v0.11.9) ← `nest_mates` ← `nest_view` (setup, refresh, input) |
| โมเดลของในกล่อง | `mesh_kit_base` (เครื่องมือสร้าง, asset, หิน/ใบไม้/หญ้า/ต้นถั่ว) ← `mesh_kit` (เพลี้ย, จิ้งหรีด, ลูกมด, แมลงวัน, แมงมุม) — แยก v0.8.5 |
| พื้นดิน 3 มิติ | `outworld_scene` ← `outworld_props` ← `outworld_crowd` ← `outworld_creatures` ← `outworld_camera` ← `outworld_view` |
| HUD | `hud_base` ← `hud_colonies` ← `hud_enemies` ← `hud_stars` (มดเด่น) ← `hud_controls` ← `hud_panel` ← `hud` |
| เกม | `main_base` ← `main_camera` ← `dev/dev_tools` ← `main` |

ถ้าฟังก์ชันใหม่ต้องเรียกฟังก์ชันชั้นสูงกว่า ให้ย้ายฟังก์ชันใหม่ขึ้นไปอยู่ชั้นนั้น (Godot จะ error "Function not found in base self")
แยกไฟล์เพิ่มได้ด้วย `python tools/dev/split_gd.py plan.json` (ดูหัวไฟล์)

- ดินที่โหลด: `nest_voxels` ชั้น `y_lo`..`ny-1` (สวน: ลงไปได้ถึง `y_floor` = ny−200, ใต้ y = 0; `extend_down`), `idx()` นับจาก `y_lo`, `hy()` = ความสูงที่โหลด; ภาพใช้ `vol_org`/`vol_size` (`nest_scene._set_vol_shape`)
- ทรงรัง: `sim/parts/nest_chambers.gd` `_plan_new` (ห้องลูกปัดตามอุโมงค์ + กิ่งที่ก้น; นิสัย wind/lean/bush), ผนังห้องเป็นแฉก `_lobe`

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
- `shaders/ants/ant.gdshader` หมุนแต่ละส่วนรอบข้อต่อ (จุดหมุนใน design units × K) ตาม INSTANCE_CUSTOM = (จังหวะเดิน, กิจกรรม, นาฬิกา, ปริมาณการเดิน);
  x = จังหวะเดิน (< 512) + 512 × รหัสการงอเอว/คอให้ตัวแนบพื้น (`ant_model3d.gd gait_x`, ในรัง: `nest_rest._fit_at`); z = นาฬิกา (< 600) + 600 × รหัสการงอซ้ายขวาตอนเลี้ยว (`clock_z`)
- รหัสกิจกรรม: 0 เดิน, 1 พัก, 2 ขุด/กัด, 3 แตะหนวด, 4 ทำความสะอาด, 5 วางไข่, 6 ป้อนอาหาร, 7 ดูแลตัวอ่อน, 8 คาบของ, 9 รีดเพลี้ย, 10 ดื่ม, 11 ตาย,
  12 เพิ่งออกจากรังไหม, 13 สู้ (งับ+พ่นกรด), 14 ตื่นตกใจวิ่งเข้าหา, 15 หยุดสำรวจ (ส่ายหัว), 16 เดินตามทางกลิ่น (หนวดเคาะพื้น); +100 = ท้องเต็มน้ำหวาน
- ขา: IK บนข้อต่อของ `LEGS` ใน `tools/blender/ant/legs.py` (ต้องตรงกับค่าใน shader) — ดู "รูปแบบไฟล์ .antmesh"
- ตัวกันชนในรัง (`nest_bodies.gd`): มดงาน = วงกลม 2 วงตามลำตัว, ราชินี = แคปซูล (`QUEEN_HEAD/TAIL/R`), ช่องที่ราชินีนอนอยู่ (`_queen_cells`) มดเดินอ้อม
  - มองข้างหน้า (`nest_contact._gap_ahead`, `m.fgap` คูณทั้งความเร็วบนทางและการเลื่อนของตัวที่วาด), ปีนข้าม (`_climb`: ทุกส่วนของตัวตาม `CLIMB_PARTS`
    อยู่เหนือมด/ลูกมดข้างใต้, ทำหลังวางตัวบนพื้น; `m.over` = ความสูงที่ยก, `over_on` = ตัวที่ปีนข้าม, `cross_on` = ตัวที่ขวางนานจนต้องปีน)
  - ตรวจด้วย `--bodies` (`scripts/dev/body_check.gd`: วัด 3 มิติจากรูปทรงโมเดล) — อย่าใช้ `--trace` brood/mate overlaps ที่ดูแค่แนวราบ
- สัตว์ข้างนอก (`shaders/creatures/*`): ทุกจุดของตัวยึดกับพื้นใต้ตัวเอง (`follow_ground` ใน `ground_h.gdshaderinc`) — ต้องส่ง `mound_h/mound_r/nest_xz` ให้ material
- `limb_gain` (shader uniform) ทำให้ขา/หนวด/กรามสีอ่อนกว่าตัว (ราชินีสีส้มอำพัน)

## รูปแบบไฟล์ .antmesh
- `ANT2` (โมเดลมด): เหมือน `ANTM` แต่มี float ที่ 11 ต่อจุด = ท่อนขา (1 โคนขา, 2 ต้นขา, 3 หน้าแข้ง, 4 เท้า; 0 = ไม่ใช่ขา
  หรือโมเดลไกล) ส่งเข้า shader ทาง `UV.x` — shader ใช้ IK บนข้อต่อของ `LEGS` ใน `tools/blender/ant/legs.py` (ต้องตรงกันสองที่)
- การก้าว: `ant_model3d.gd` (`STRIDE_A`, `stride_scale`, `duty`, `stride_len`, `gait_w`) คู่กับค่าใน shader;
  มุมมองเดินจังหวะก้าวด้วย "ระยะทางที่เดินจริง ÷ ความยาวก้าว" เท้าจึงไม่ไถล; `INSTANCE_CUSTOM.w` = mv + ขนาดก้าว×100
`"ANTM"`, จำนวน vertex (u32), จำนวน index (u32), ต่อ vertex 10 float (ตำแหน่ง xyz, normal xyz, สี rgba), แล้ว index u32
(หน้าเรียงตามเข็มนาฬิกาแบบ Godot) — โหลดด้วย `ant_model3d.gd load_antmesh()`; ของในกล่องโหลดผ่าน `mesh_kit.gd asset("prey/aphid_adult")`
ต้นถั่วมีไฟล์ `.json` คู่กัน เก็บเส้นลำต้น (ให้เพลี้ยและมดเกาะ)

## เซฟ
- `scripts/game/save_store.gd`: 3 ช่อง (`user://saves/slotN.antfarm` บีบอัด zstd + `slotN.json` สรุปสำหรับเมนู), เขียนไฟล์ชั่วคราวก่อนแทนที่
- เนื้อหา = `sim.to_dict()` (ข้อมูลล้วน ไม่มี path ของสคริปต์ — ย้ายไฟล์ได้โดยเซฟไม่พัง), `SAVE_VERSION` ใน `sim_state.gd` (ตอนนี้ 11)
- **เปลี่ยนรูปแบบเซฟ:** เพิ่ม `SAVE_VERSION` + ขั้นแปลง `_vN_to_vN+1()` ใน `scripts/sim/save_migrations.gd` + ขยาย `tests/migration_test.gd`
- ตอนโหลด (`scripts/game/main.gd`): เซฟเก่ากว่า → สำรองเป็น `slotN.before-vX.antfarm` แล้วแปลง; เซฟจากเกมใหม่กว่า → เล่นรังทดลอง
  และ**ไม่บันทึกทับ**; อ่านไม่ได้ → สำรองเป็น `slotN.unreadable-<เวลา>.antfarm` แล้วเริ่มรังใหม่ (บอกผู้เล่นทุกกรณี)
- ความปลอดภัย (v0.11.14, `docs/release/SECURITY_REVIEW.md`): ไฟล์ใน `user://` ถือว่าใครก็แก้ได้ — เซฟอ่านด้วย `bytes_to_var` (ไม่สร้าง object)
  จำกัดขนาด แล้วผ่าน `scripts/sim/save_check.gd` (หลังแปลง: ค่าครบ ชนิดตรงกับรังที่เกมสร้างเอง ขนาด voxel/กริด/แถวมดลงตัว) ก่อน `from_dict`;
  `settings.cfg` อ่านเป็นข้อความก่อน (`Store._settings_file`); เพิ่มค่าใหม่ในเซฟ → ถ้าตัวโหลดอ่านด้วย `d.get(...)` ให้ใส่ใน `SaveCheck.OPTIONAL`
- รูปแบบ v1→v2 (v0.5.8): มดมี `caste`, แมงมุมตัวเดียว (`spider`) → รายการ `creatures`
- รูปแบบ v2→v3 (v0.6.0): มดมี `foe`, `hurt`; ศัตรูมี `id`, `hp`, `held`; เพิ่มสนาม `alarm` และ `next_cid`
- รูปแบบ v3→v4 (v0.7.0): `scenario` ("keeper"/"wild"), `start_doy`, `cold_days`, `fridge_on`, `fat`; climate มี `scenario`, `fridge`;
  ราชินีมี `rested` — เซฟเก่าทั้งหมดกลายเป็นฉาก "ชุดเลี้ยง"
- รูปแบบ v4→v5 (v0.7.1): `sugar_income`, `sugar_spend` (ค่าเฉลี่ยราวหนึ่งสัปดาห์ของน้ำตาลที่หามาได้/ที่กิน — ราชินีวางไข่ตามนี้)
- รูปแบบ v5→v6 (v0.7.3): `stats.dead` = มดงานเท่านั้น + `stats.dead_by` (starve/thirst/old/out/enemy/other),
  `stats.brood_dead` = ไข่/ตัวอ่อน/ดักแด้ที่ตาย (เซฟเก่า: ยอดเดิมทั้งหมดเป็น `other`)
- ไฟล์เซฟตัวอย่างของแต่ละรูปแบบอยู่ใน `tests/fixtures/` (สร้างจากโค้ดเวอร์ชันนั้น) — เปลี่ยนรูปแบบครั้งใหม่ให้เพิ่มไฟล์ของรูปแบบล่าสุดก่อนเปลี่ยน
- ทดสอบโดยไม่แตะเซฟจริง: `--sandbox` ใช้ `user://sandbox/`

## ภาษา (v0.11.12, PART EA-R R1)
- คำทุกคำที่ผู้เล่นเห็นอยู่ใน `lang/strings.csv` คอลัมน์ `keys,th,en` (แถวที่ขึ้นต้น `#` คือหัวข้อกลุ่ม); รหัสเป็นคำอังกฤษสั้นๆ (`tip_age_size`)
  — **ห้ามเขียนข้อความไทยในโค้ด** (`tests/lang_test.gd` ตรวจ) เพิ่มข้อความใหม่ = เพิ่มแถวใน CSV ทั้งสองภาษา `%` ต้องเหมือนกันและเรียงเหมือนกัน
- `scripts/sim/lang.gd` (`L`) อ่าน CSV ตอนเริ่ม (`lang/strings.csv.import` = "keep": Godot ไม่แปลงเป็น .translation แก้ CSV แล้วเปิดเกมใหม่ก็เห็น)
  ใส่ `TranslationServer`; Node ใช้ `tr("key")`, ที่อื่น (การจำลอง, static, ค่าคงที่) `L.t("key")` / `L.f("key", [ค่า])`;
  ค่าคงที่เก็บรหัส (`NAME`, `CARD`, `AWAY_RATES`, `NEW_*`, `SHOWN`, `STAR_COMING`, `MONTHS`) แล้วแปลตรงที่แสดง
- ภาษาเริ่มต้น: settings `lang` ถ้ามี ไม่งั้น `OS.get_locale_language()` "th" → ไทย อื่นๆ → อังกฤษ; `--lang=th|en` (dev);
  เปลี่ยนในหน้าต่างตั้งค่า → เซฟ + โหลดฉากใหม่ (`main._change_language`)
- **บันทึกผู้เลี้ยง** (`sim.log_entries`, เซฟ v11): `{"day", "clock", "key", "args", "kind"}` — `T.<name>` ใน `text_th.gd` คือรหัส `log_<name>`;
  ค่าที่เป็นคำ (ชื่อศัตรู สาเหตุตาย) ใส่เป็น `L.k(key)`; แสดงด้วย `L.entry_text(e)` / `L.stamp(e)`; บรรทัดที่เซฟก่อน v0.11.12 เป็น `{"stamp", "text"}` ไทย แสดงตามเดิม

## โหมดเดสก์ท็อป (PART 11)
- `scripts/game/desktop_mode.gd` + ตัวช่วย `tools/desktop/antdesk.cs` → `build/AntDesk.exe` (คอมไพล์ด้วย csc ของ .NET Framework 4 ที่มากับ Windows,
  ไม่ต้องติดตั้ง SDK) วางข้าง `AntFarm.exe`; เกมเรียก `attach <hwnd>` / `detach <hwnd>` / `covered` **ในเธรดเสมอ** — ถ้าเรียกบนเธรดหลัก
  ตัวช่วยแก้หน้าต่างเกมข้ามโปรเซส Windows ส่งข้อความกลับมาที่เธรดหลักที่กำลังรอ = deadlock
- Windows 11 24H2+ ("raised desktop": Progman มี `WS_EX_NOREDIRECTIONBITMAP`): หน้าต่างเกมเป็นลูกของ Progman แบบ layered ทึบ วางใต้
  `SHELLDLL_DefView` (ไอคอน), WorkerW (วอลเปเปอร์เดิม) ล่างสุด — แบบเดียวกับ Lively; รุ่นเก่า: ลูกของ WorkerW; ข้อความ `0x052C` ต้องใช้ `0xD, 1`
- **ต้องวาดด้วย Direct3D 12** — Vulkan, OpenGL, ANGLE มองไม่เห็นในชั้นนี้ (ทดสอบแล้ว 2026-10-16: Vulkan ทั้งแบบ layered/ไม่ layered/ใน WorkerW,
  D3D12 เห็นทั้งบน Intel UHD และ RTX 3050) แต่เกมปกติวาดด้วย Vulkan (D3D12 บน Intel UHD การ์ดรีเซ็ตตัวในฉากหนัก): กดปุ่ม "วอลเปเปอร์"
  เกมเซฟแล้ว**เปิดตัวเองใหม่** `--rendering-driver d3d12 --rendering-method mobile -- --desktop` (main.gd `_enter_desktop`) แล้วปิดตัวเก่า
  หลัง 2 วินาที (ปิดทันทีตอนเพิ่งเปิดเกม = crash); ครั้งแรกที่ใช้ D3D12 คอมไพล์ shader นาน (เห็นหน้า Godot เป็นวอลเปเปอร์ก่อน)
- มีแอปเปิดเต็มจอบัง (`covered` ทุก 2 วินาที ในเธรด): หยุดวาด (`render_loop_enabled`) และข้ามงานของภาพ แต่การจำลองเดินต่อ
- บันทึกของโหมดนี้: `user://desktop_mode.log` (เปิดตัวใหม่แล้วไม่มี console)
- ตรวจบนเดสก์ท็อปจริง: `--desktop --no-cover-check --quit-after=<s>` (หรือ `--desktop-after=<s>` เหมือนกดปุ่มกลางเกม) แล้ว**รอจน log บอกว่าเกาะแล้ว
  + ~10 วินาที** ค่อยถ่ายจอขณะย่อหน้าต่าง (ผู้ใช้อนุญาตให้ย่อหน้าต่างชั่วคราว 2026-10-16); ก่อนรอบใหม่ให้แน่ใจว่าเกมรอบก่อนปิดแล้ว
  (หน้าต่างที่ยังค้างอยู่ทับหน้าต่างใหม่) — `AntDesk.exe zorder` ดูลูกของ Progman, `info <hwnd>` ดูสถานะหน้าต่าง;
  `AntDesk.exe snap/snapdwm` จับภาพที่ GPU วาดในหน้าต่างลูกไม่ได้ — ใช้ตรวจไม่ได้
