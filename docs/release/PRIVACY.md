# ความเป็นส่วนตัว / Privacy — AntFarm

## ภาษาไทย

**AntFarm ไม่เก็บและไม่ส่งข้อมูลของคุณไปที่ไหนเลย**

- เกมไม่ต่ออินเทอร์เน็ต ไม่มีบัญชี ไม่มีโฆษณา ไม่มีสถิติการใช้งาน ไม่มีการรายงานข้อผิดพลาดอัตโนมัติ
- ทุกอย่างที่เกมเขียนอยู่ในเครื่องคุณ ในโฟลเดอร์ `%APPDATA%\Godot\app_userdata\AntFarm\`
  - `saves\` — รังมดของคุณ 3 ช่อง (รวมชื่อมดที่คุณตั้ง) และสำเนาสำรองก่อนอัปเดตรูปแบบเซฟ
  - `settings.cfg` — การตั้งค่า (ภาษา เสียงเพลง ช่องเซฟที่เล่นอยู่ ฯลฯ)
  - `desktop_mode.log` — บันทึกการเข้า/ออกโหมดวอลเปเปอร์ (ขนาดหน้าต่างและชื่อไดรเวอร์การ์ดจอ) ไว้ช่วยหาสาเหตุเมื่อมีปัญหา
  - `logs\` — log ของ Godot (ข้อความที่เกมพิมพ์ระหว่างเล่น)
- ลบโฟลเดอร์นี้ = ลบทุกอย่างที่เกมเก็บไว้ (รังมดหายด้วย)
- **พอร์ตในเครื่อง:** ตอนเปิดเกม เกมเปิดพอร์ต `127.0.0.1:47815` ไว้ฟังเฉพาะในเครื่องคุณเอง (เครื่องอื่นต่อเข้ามาไม่ได้)
  เพื่อให้เปิดเกมได้ทีละตัว — ถ้ากดเปิดเกมซ้ำ ตัวใหม่บอกตัวที่เปิดอยู่ให้ขึ้นมาข้างหน้าแล้วปิดตัวเอง ไม่มีข้อมูลอื่นผ่านพอร์ตนี้
- **AntDesk.exe** (ข้าง AntFarm.exe) ใช้แค่ตอนเปิดโหมดวอลเปเปอร์ เพื่อวางหน้าต่างเกมไว้หลังไอคอนบนเดสก์ท็อป
  และดูว่ามีหน้าต่างอื่นบังเดสก์ท็อปอยู่ไหม (เพื่อหยุดวาดตอนมองไม่เห็น) — ไม่อ่านเนื้อหาของหน้าต่างอื่น ไม่ต่อเน็ต

## English

**AntFarm does not collect your data and sends nothing anywhere.**

- The game never connects to the internet: no account, no ads, no usage statistics, no automatic crash reports.
- Everything the game writes stays on your computer, in `%APPDATA%\Godot\app_userdata\AntFarm\`:
  - `saves\` — your 3 colony slots (including the names you give ants) and backups made before a save-format update
  - `settings.cfg` — your settings (language, music volume, the slot you play, …)
  - `desktop_mode.log` — a note each time the wallpaper mode starts or stops (window size and graphics driver name), to help find problems
  - `logs\` — Godot's log (what the game prints while it runs)
- Deleting that folder removes everything the game keeps (including your colonies).
- **Local port:** while it runs, the game listens on `127.0.0.1:47815`, on your own computer only (no other computer can reach it),
  so that only one copy runs at a time: if you start the game again, the new copy asks the running one to come forward and closes.
  Nothing else goes through this port.
- **AntDesk.exe** (next to AntFarm.exe) is used only in wallpaper mode, to place the game window behind the desktop icons and to see
  whether another window covers the desktop (so the game stops drawing while it cannot be seen). It does not read what other windows
  show and does not use the internet.
