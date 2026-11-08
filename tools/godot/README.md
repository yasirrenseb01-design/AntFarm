# ตัวเกม Godot ที่ compile เอง (export template)

เก็บเข้า repo เมื่อ 2026-11-08: เดิมของสองอย่างนี้อยู่แค่ใน `E:\GodotBuild` ถ้าไดรฟ์เสียต้องหาทางแก้ใหม่หมด
รายละเอียดทั้งหมดอยู่ที่ `docs/release/ENCRYPTION.md`

| ไฟล์ | คืออะไร |
|---|---|
| `window_icon.patch` | แก้ซอร์ส Godot 4.7.2-stable 9 บรรทัด (`platform/windows/display_server_windows.cpp`): หน้าต่างเกมใช้ไอคอนราชินีแทนไอคอนว่างของ Windows (v0.11.77) |
| `build_template.sh` | สำเนาสคริปต์ compile template (ตัวจริงที่ใช้อยู่ `E:\GodotBuild\build_template.sh`) — **อ่านกุญแจจากไฟล์ ไม่มีกุญแจอยู่ในสคริปต์** |

## สร้างใหม่ทั้งหมดบนเครื่องใหม่
1. `git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot E:\GodotBuild\godot`
2. `cd E:\GodotBuild\godot && git apply E:\AntFarm\tools\godot\window_icon.patch`
3. วางกุญแจ (ที่สำรองไว้นอกเครื่อง) เป็น `E:\GodotBuild\antfarm_pck.key` และตัว compile llvm-mingw ตาม ENCRYPTION.md
4. `bash tools/godot/build_template.sh` (~10 นาที) แล้วตรวจไอคอนตาม ENCRYPTION.md

ถ้ากุญแจหาย: สร้างกุญแจใหม่แล้ว compile ใหม่ได้ ไม่กระทบผู้เล่นหรือเซฟ (ENCRYPTION.md) แต่ template กับกุญแจต้องเป็นคู่เดียวกันเสมอ
**ห้ามใส่กุญแจในโฟลเดอร์นี้หรือที่ไหนใน repo**
