# การเข้ารหัสไฟล์เกม (PART EA-R, v0.11.17)

ไฟล์ทั้งหมดในตัวเกม (สคริปต์, โมเดล, รูป, คำแปล) ถูกเข้ารหัส AES-256 อยู่ใน `AntFarm.exe` — เปิดดูด้วยเครื่องมือแกะ Godot ทั่วไปไม่ได้
ต้องมีกุญแจที่ฝังอยู่ในตัว exe (กันคนทั่วไปได้ คนที่ตั้งใจจริงยังหากุญแจในตัว exe ได้ ไม่มีเกมไหนกันได้ 100%)
เซฟของผู้เล่นไม่ได้เข้ารหัส (ไม่เกี่ยว)

## ของที่อยู่นอก repo (เครื่องนี้เท่านั้น — สำรองไว้)
| ไฟล์ | คืออะไร |
|---|---|
| `E:\GodotBuild\antfarm_pck.key` | กุญแจ 64 ตัวอักษร (hex) — **ห้ามใส่ใน repo / ห้ามส่งให้ใคร** |
| `E:\GodotBuild\templates\antfarm_release_x86_64.exe` | ตัวเกม Godot 4.7.2 ที่ compile เองโดยฝังกุญแจไว้ (export template) |
| `E:\GodotBuild\godot\` | ซอร์ส Godot 4.7.2-stable + ชุด D3D12 SDK (`bin\build_deps`) |
| `E:\GodotBuild\llvm-mingw-20261006-ucrt-x86_64\` | ตัว compile C++ (ไม่ต้องติดตั้ง) |
| `E:\GodotBuild\build_template.sh` | สคริปต์ compile (Git Bash): `bash /e/GodotBuild/build_template.sh` ~10 นาที, log ที่ `build.log` |

- `tools/build.ps1` อ่านกุญแจจากไฟล์ข้างบนใส่ `GODOT_SCRIPT_ENCRYPTION_KEY` ตอน export แล้วลบทิ้ง; ไม่มีกุญแจหรือ template → build ไม่ผ่าน (ไม่มีทางปล่อยตัวไม่เข้ารหัสโดยไม่ตั้งใจ)
- `export_presets.cfg`: `encrypt_pck=true`, `encrypt_directory=true`, `encryption_include_filters="*"`, `custom_template/release=` ชี้ไปที่ template ข้างบน
- compile ด้วย `production=yes d3d12=yes accesskit=no` (โหมดวอลเปเปอร์ต้องใช้ D3D12; accesskit = ตัวอ่านหน้าจอสำหรับผู้พิการทางสายตา ต้องดาวน์โหลด SDK เพิ่ม ไว้ทีหลัง)
- Cloud session (Linux) build exe ไม่ได้อยู่แล้ว ไม่ต้องมีกุญแจ

## ถ้ากุญแจหาย
ไม่มีผลกับผู้เล่นหรือเซฟ: สร้างกุญแจใหม่ (`python -c "import secrets;print(secrets.token_hex(32))" > E:\GodotBuild\antfarm_pck.key`)
แล้ว compile template ใหม่ด้วย `build_template.sh` (กุญแจกับ template ต้องเป็นคู่เดียวกันเสมอ)

## อัปเดต Godot เป็นเวอร์ชันใหม่
ต้อง clone ซอร์สเวอร์ชันนั้น (`git clone --depth 1 --branch <ver>-stable`), รัน `misc/scripts/install_d3d12_sdk_windows.py --mingw_prefix=...` แล้ว compile ใหม่

## ตรวจแล้ว (2026-10-21)
- exe ที่เข้ารหัส: ค้นข้อความในเกม ("Keeper's field notebook"), ชื่อไฟล์สคริปต์ (`res://scripts`), ชื่อตัวแปรในโค้ด — ไม่เจอเลย
  (ตัวที่ไม่เข้ารหัสเจอชื่อไฟล์สคริปต์)
- เปิดสำเนารังผู้เล่น (`--testsave=mine3`) ได้ปกติ ภาษา โมเดล ฟอนต์ครบ; โหมดวอลเปเปอร์เปิดใหม่ด้วย D3D12 แล้วเกาะเดสก์ท็อปได้ (`desktop_mode.log`: `driver d3d12`)
