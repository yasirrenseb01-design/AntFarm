# หน้าร้าน itch.io — AntFarm: Legion of the Unseen (PART EA-R ข้อ R6)

ร่างโดย session คลาวด์ 2026-10-29 จาก v0.11.74 — ทุกข้อความตรวจกับ `CHANGELOG.md`, `docs/BIOLOGY.md` และ `lang/strings.csv` แล้ว
(ตัวเลขสเปกมาจาก v0.11.14 / v0.11.0 ใน CHANGELOG เท่านั้น) — ผู้ใช้ตรวจแล้วค่อยวาง

**วิธีวาง:** ตัวแก้ข้อความของ itch.io เป็นแบบ rich text — เปิดไฟล์นี้บน GitHub (ภาพที่แสดงผลแล้ว) คัดลอกส่วน "คำอธิบายหลัก"
ทั้งก้อนตั้งแต่หัว **Keep a colony…** จนจบส่วนไทย แล้ววางในช่อง Description หัวข้อ ตัวหนา รายการ และลิงก์จะติดไปด้วย
(ถ้าวางแล้วเป็นตัว `##` ดิบ แปลว่าคัดลอกจากไฟล์ดิบ ให้คัดลอกจากหน้าที่แสดงผลแทน)

ต้องกรอกเองหลังรัน `tools/package.ps1`: ขนาด zip และรหัส SHA-256 (บรรทัดที่มี `‹…›`)

---

## 1. ค่าที่ต้องกรอกในฟอร์ม itch.io (Create new project)

| ช่องในฟอร์ม | ค่า | หมายเหตุ |
|---|---|---|
| Title | `AntFarm: Legion of the Unseen` | |
| Project URL | `antfarm-legion-of-the-unseen` (หรือสั้นกว่านั้นตามชอบ) | เปลี่ยนทีหลังได้ แต่ลิงก์เก่าจะเสีย |
| Short description or tagline | ดูข้อ 2 (ข้อความสั้น ≤ 140 ตัวอักษร) | |
| Classification | **Games** | |
| Kind of project | **Downloadable** | ไฟล์ zip ให้ดาวน์โหลด |
| Release status | **Early access** | ถ้าในรายการไม่มีคำนี้ ให้เลือก In development แล้วใส่คำว่า Early Access ในคำอธิบาย (มีอยู่แล้ว) |
| Pricing | **$0 or donate** (= จ่ายตามใจ ขั้นต่ำ 0) | Suggested donation ใส่หรือเว้นว่างก็ได้ |
| Uploads | `AntFarm-v‹เวอร์ชัน›-windows.zip` ติ๊ก **Windows** | ไฟล์จาก `build/release/` |
| Description | ดูข้อ 3 (อังกฤษก่อน ไทยตามหลัง) | |
| Genre | **Simulation** | |
| Tags (สูงสุด 10) | `ants`, `insects`, `simulation`, `life-simulation`, `nature`, `realistic`, `relaxing`, `virtual-pet`, `wallpaper`, `3d` | ถ้าอยากได้คำเกี่ยวกับเวลาเดินต่อตอนปิดเกม เปลี่ยน `3d` เป็น `idle` |
| AI generation disclosure | **Yes** → เลือกหมวดเสียง (**Sound / Audio**: เพลง) | เพลงพื้นหลัง 2 เพลงสร้างด้วย Gemini; ชื่อหมวดในฟอร์มอาจต่างจากนี้เล็กน้อย — ดูข้อ 5 ท้ายไฟล์ |
| App store links | เว้นว่าง | |
| Custom noun | เว้นว่าง | |
| Community | **Comments** เปิด | ใช้รับรายงานบั๊กคู่กับ Discord |
| Visibility & access | **Draft** ระหว่างตรวจ → **Public** วันที่ 2 พ.ย. 2026 | |
| Details → Languages | English, Thai | |
| Details → Inputs | Keyboard, Mouse | |
| Details → Average session | A few minutes / About a half-hour (ตามชอบ) | |
| Details → Links | Discord: https://discord.gg/ReXz7AFgrG | |
| Cover image | ภาพข้อ 5 ลำดับที่ 1 (itch แนะนำ 630×500) | |
| Screenshots | ภาพข้อ 5 ลำดับที่ 2–8 (3–5 ภาพแรกสำคัญที่สุด) | |

---

## 2. ข้อความสั้น

**Tagline (1 บรรทัด, ใส่ใต้ชื่อในคำอธิบาย):**
> A colony of black garden ants that digs its own nest, grows from a single queen, and lives on even while the game is closed.

**Short description (ช่อง "Short description or tagline", 128 ตัวอักษร):**
> Raise real black garden ants: they dig their own nest, live on while the game is closed, and can even be your desktop wallpaper.

ไทย (ไว้ใช้ที่อื่น เช่นโพสต์ Discord — ช่องของ itch ใช้อังกฤษ):
> เลี้ยงมดดำสวนตามธรรมชาติจริง มดขุดรังเอง รังมีชีวิตต่อแม้ปิดเกม และเป็นวอลเปเปอร์เดสก์ท็อปได้

---

## 3. คำอธิบายหลัก (วางในช่อง Description)

**Keep a colony of black garden ants — from one queen to a nest of hundreds.**

*AntFarm: Legion of the Unseen* is a quiet, detailed ant-keeping game about the black garden ant, *Lasius niger*.
A single queen seals herself underground and raises her first workers alone. From there the colony is on its own: the ants dig
the nest, tend the brood, farm aphids for honeydew, fight off predators and survive the winter. You keep them fed and watered,
watch, and learn.

**Early Access** — the game is playable from start to finish, but still growing. See *What is not in Early Access yet* below.

### Real ants, from real research

- **Modelled on published studies** of *Lasius niger* and related ants (the main sources are listed in the game's CREDITS.txt).
- **Life cycle:** egg about 10 days, larva about 13, pupa about 11 at around 28 °C; development stops in the cold. Larvae spin cocoons,
  nurses open them at the head end and pull the new worker out; young pale *callows* darken over a few days.
- **A colony that thinks for itself:** young workers stay inside as nurses, older ones go out foraging. Ants share food mouth to mouth
  (*trophallaxis*), lay scent trails to food, and many workers simply rest — just as real colonies do.
- **Honeydew farming:** ants climb broad bean plants and stroke black bean aphids with their antennae for drops of honeydew.
- **Realistic walking:** six legs that plant and lift in a real ant's stepping pattern, antennae that tap the ground on a scent trail,
  ants that carry, drag, groom and clean each other.

### A nest the ants dig themselves

- The ants decide where to dig. Tunnels and chambers grow — and go deeper — as the colony grows; no two nests look the same.
- Look through the soil, cut the nest open, and follow any ant underground or up in the outworld.
- Choose a **formicarium** on your desk or **Wild mode**: a sunny garden plot with four seasons, rain and wild prey.

### Time keeps running while you are away

- Close the game and the colony lives on. Choose how fast time runs while it is closed — real time, or one game day per 6 hours,
  1 hour or 15 minutes — or stop it altogether.
- When you come back, the game works out what happened (up to 120 game days) and shows a *While you were away* report:
  who was born, who died, how the nest grew.
- An optional helper waters and feeds a formicarium while you are gone.

### Desktop wallpaper mode

- One click puts the living nest **behind your desktop icons** as your wallpaper. It stops drawing while windows cover it, to save power.
- Click the ant icon in the system tray to come back to the game.

### Your Home, Colony Harmony and the shop

- Walk around your own room in first person: a desk with your ant tanks, a window that follows your computer's clock,
  and a wintering fridge.
- Your colonies earn **Colony Harmony** in real time — new workers, ants that survive a fight, ants feeding each other, digging.
  Speeding up the game does not earn it faster.
- Spend it in the **shop**: extra tanks, a second, bigger tank with a larger outworld, and shelves to put tanks on.
  Every tank is another colony (and another Wild mode plot).

### Predators

- **Wolf spiders**, **stone centipedes** and **ground beetles** hunt in the outworld. Set how often they turn up on their own,
  or spend Colony Harmony to release one and watch.
- Workers sound the alarm, grab legs and antennae, pin the attacker down and spray formic acid — black garden ants have no sting.
  A big colony can swarm all over an enemy; a young one hides in the nest. Whatever they kill becomes food.

### Winter in the fridge

- Black garden ants need a winter rest. In November the journal reminds you; send the tank into the wintering fridge,
  where the temperature eases down to about 6–7 °C. After six weeks of cold the queen is ready to lay again in spring —
  skip it and she lays fewer eggs.

### Get to know your ants

- **Click any ant** to see what it is doing, and **give it a name** — as many as you like.
- **Top ants** lists the busiest ant in each line of work and every ant you have named. When a named ant dies,
  you are told how and at what age.
- A keeper's journal records the colony's life; F9 hides everything on screen and F8 tours the nest for clean screenshots and clips.

### What is not in Early Access yet

- **Ant farm extensions** (a glass ant farm joined to a tank with a clear tube, ants living in both) — planned after release.
- **Decorations:** a decoration shop and placing plants, stones, leaves, twigs and mossy rocks in a tank before you start.
- **Arranging your room** (moving shelves and tanks yourself) — not decided yet. The door in the Home is "coming soon".
- **Mating flights** (winged queens and males), **other ant species**, **rival colonies**.
- **Wallpaper mode:** main monitor only; poking the ants on the desktop and starting with Windows are not there yet.
- Windows only for now. Big colonies (hundreds of ants) are heavy on the CPU; making them lighter is planned after release.

### System requirements (measured, not guessed)

- **OS:** Windows 10 or 11, 64-bit
- **Graphics:** a graphics card with **Vulkan** (wallpaper mode also needs **Direct3D 12**)
- **Tested on:** Intel Core i5-12450H laptop, 16 GB RAM — both its **Intel UHD** integrated graphics and an **NVIDIA RTX 3050 Laptop**
  - Intel UHD (low quality, 1600×900, 300 ants): about 117 fps in the outworld, about 43 fps inside the nest
  - RTX 3050: about 120 fps, about 810 MB RAM, about 185 MB video memory
  - Large nests are limited by the CPU: a processor slower than a 12th-gen Core i5 will get fewer frames with hundreds of ants
- The game picks graphics quality for you the first time (low on Intel graphics, high on NVIDIA/AMD); change it in Settings,
  along with a frame cap of 30 / 60 / unlimited.
- So far the game has only been tested on the machine above — please tell us how it runs on yours.

### Install

1. Download the zip and unzip it anywhere (keep **AntFarm.exe** and **AntDesk.exe** in the same folder).
2. Run **AntFarm.exe**.
3. Windows may show **"Windows protected your PC"** because the game is not digitally signed yet: click **More info**, then **Run anyway**.

Saves live in `%APPDATA%\Godot\app_userdata\AntFarm\` (saved every minute and on exit). The game does not go online, has no account,
ads or tracking — see PRIVACY.txt in the zip. SHA-256 of the zip: `‹วางรหัสจาก .sha256›`

### AI-generated content

The two background music tracks, *Where the Tall Trees Lean* and *Under the Canopy*, were generated with Google Gemini.

### Bugs, ideas and chat

Join the **Discord: https://discord.gg/ReXz7AFgrG** — or leave a comment on this page. English and Thai are both welcome.

---

**เลี้ยงมดดำสวน ตั้งแต่ราชินีตัวเดียวจนเป็นรังหลายร้อยตัว**

*AntFarm: Legion of the Unseen* เป็นเกมเลี้ยงมดดำสวน (*Lasius niger*) แบบละเอียดและผ่อนคลาย ราชินีตัวเดียวปิดตัวเองอยู่ใต้ดินและเลี้ยงมดงาน
รุ่นแรกเอง จากนั้นรังดูแลตัวเอง มดขุดรัง เลี้ยงลูก เลี้ยงเพลี้ยเอาน้ำหวาน สู้กับผู้ล่า และผ่านหน้าหนาว ส่วนคุณให้น้ำ ให้อาหาร เฝ้าดู และเรียนรู้

**Early Access** — เล่นได้ครบตั้งแต่ต้นจนจบ แต่ยังเพิ่มของต่อเรื่อยๆ ดู *สิ่งที่ยังไม่มีใน Early Access* ด้านล่าง

### มดจริงตามงานวิจัย

- **จำลองตามงานวิจัยที่ตีพิมพ์** เรื่องมดดำสวนและมดใกล้เคียง (แหล่งหลักอยู่ใน CREDITS.txt ของเกม)
- **วงจรชีวิต:** ไข่ราว 10 วัน ตัวอ่อนราว 13 วัน ดักแด้ราว 11 วัน ที่ราว 28°C หนาวแล้วหยุดพัฒนา ตัวอ่อนชักใยเป็นรังไหม พี่เลี้ยงกัดเปิดด้านหัว
  ดึงตัวใหม่ออกมา มดตัวใหม่ (callow) สีซีดแล้วเข้มขึ้นในไม่กี่วัน
- **รังที่คิดเอง:** มดอายุน้อยอยู่ในรังเป็นพี่เลี้ยง มดอายุมากออกหาอาหาร มดป้อนอาหารกันปากต่อปาก (trophallaxis) ทิ้งเส้นทางกลิ่นไปหาอาหาร
  และมดงานจำนวนมากแค่พักอยู่เฉยๆ เหมือนรังจริง
- **เลี้ยงเพลี้ย:** มดปีนต้นถั่วปากอ้า เอาหนวดเคาะหลังเพลี้ยถั่วดำเพื่อรับหยดน้ำหวาน
- **เดินสมจริง:** ขาหกขาก้าวและวางตามจังหวะก้าวของมดจริง หนวดเคาะพื้นตอนตามทางกลิ่น มดคาบของ ลากของ ทำความสะอาดตัวและเลียตัวให้เพื่อน

### รังที่มดขุดเอง

- มดเลือกที่ขุดเอง อุโมงค์และห้องขยายและลึกลงตามขนาดรัง ไม่มีรังไหนหน้าตาเหมือนกัน
- มองทะลุดิน ตัดดูภาพหน้าตัดรัง และตามมดตัวไหนก็ได้ทั้งใต้ดินและบนพื้นที่หาอาหาร
- เลือก **ชุดเลี้ยง (formicarium)** บนโต๊ะ หรือ **โหมดป่า**: แปลงสวนกลางแดด มีสี่ฤดู ฝน และเหยื่อในธรรมชาติ

### เวลาเดินต่อตอนปิดเกม

- ปิดเกมแล้วรังยังมีชีวิตต่อ เลือกได้ว่าตอนปิดเวลาเดินเร็วแค่ไหน — เวลาจริง หรือ 1 วันในเกมต่อ 6 ชั่วโมง 1 ชั่วโมง 15 นาที — หรือหยุดเวลาไว้
- เปิดกลับมา เกมคำนวณสิ่งที่เกิดขึ้น (สูงสุด 120 วันในเกม) แล้วสรุปให้ใน *ระหว่างที่คุณไม่อยู่* ใครเกิด ใครตาย รังโตแค่ไหน
- เลือกให้ผู้ช่วยเติมน้ำและให้อาหารชุดเลี้ยงตอนคุณไม่อยู่ได้

### โหมดวอลเปเปอร์เดสก์ท็อป

- คลิกเดียว รังมดที่มีชีวิตไปอยู่ **หลังไอคอนบนเดสก์ท็อป** เป็นวอลเปเปอร์ หยุดวาดตอนมีหน้าต่างบังเพื่อประหยัดไฟ
- คลิกไอคอนมดที่ถาดระบบเพื่อกลับเข้าเกม

### ห้อง Home, Colony Harmony และร้านค้า

- เดินในห้องของคุณเองแบบมุมมองบุคคลที่หนึ่ง มีโต๊ะกับตู้เลี้ยงมด หน้าต่างที่กลางวันกลางคืนตามนาฬิกาเครื่อง และตู้เย็นจำศีล
- รังของคุณสะสมแต้ม **Colony Harmony** ตามเวลาจริง — จากมดงานเกิดใหม่ มดที่รอดจากการสู้ มดป้อนอาหารกัน และการขุดดิน เร่งเวลาในเกมก็ไม่ได้แต้มเร็วขึ้น
- ใช้แต้มใน **ร้านค้า**: ตู้เล็กเพิ่ม ตู้ที่ 2 ที่ใหญ่ขึ้นพร้อมพื้นที่หาอาหารกว้างขึ้น และชั้นวางตู้ ทุกตู้คือรังใหม่อีกรัง (และแปลงในโหมดป่าเพิ่มอีกแปลง)

### ศัตรู

- **แมงมุมหมาป่า** **ตะขาบหิน** และ **ด้วงดิน** ออกล่าบนพื้นที่หาอาหาร ตั้งได้ว่าให้มาเองบ่อยแค่ไหน หรือใช้แต้ม Colony Harmony ปล่อยเข้ามาดูการสู้
- มดส่งกลิ่นเตือนภัย งับขาและหนวด ตรึงศัตรูไว้แล้วพ่นกรดฟอร์มิก (มดดำสวนไม่มีเหล็กไน) รังใหญ่รุมเกาะทั่วตัวศัตรู รังเล็กหลบอยู่ในรัง
  ศัตรูที่ถูกฆ่ากลายเป็นอาหาร

### จำศีลในตู้เย็น

- มดดำสวนต้องพักหนาว เข้าเดือนพฤศจิกายนบันทึกจะเตือน ย้ายตู้เข้าตู้เย็นจำศีล อุณหภูมิค่อยๆ ลดลงจนเหลือราว 6–7°C ครบหกสัปดาห์
  ราชินีพร้อมวางไข่อีกครั้งในฤดูใบไม้ผลิ — ถ้าข้ามไป เธอจะวางไข่น้อยลง

### รู้จักมดของคุณ

- **คลิกมดตัวไหนก็ได้** เพื่อดูว่ากำลังทำอะไร และ **ตั้งชื่อ** ได้ไม่จำกัด
- **มดเด่น** รวมมดที่ทำงานแต่ละอย่างมากที่สุดและมดทุกตัวที่คุณตั้งชื่อ มดที่มีชื่อตาย เกมจะบอกสาเหตุและอายุ
- บันทึกผู้เลี้ยงจดชีวิตของรัง; F9 ซ่อนทุกอย่างบนจอ F8 ให้กล้องเดินชมรังเอง ไว้ถ่ายภาพหรือคลิป

### สิ่งที่ยังไม่มีใน Early Access

- **แอนท์ฟาร์มต่อขยาย** (ตู้แอนท์ฟาร์มกระจกต่อกับตู้ด้วยท่อใส มดอยู่ได้ทั้งสองส่วน) — วางแผนไว้หลังปล่อย
- **ของตกแต่ง:** ร้านของตกแต่ง และวางต้นไม้ หิน ใบไม้แห้ง กิ่งไม้ ก้อนมีมอส ในตู้ก่อนเริ่มเลี้ยง
- **จัดห้องเอง** (ย้ายชั้นวางและตู้) — ยังไม่ได้ตัดสินใจ ประตูในห้อง Home ยังขึ้น "อัปเดตเร็วๆ นี้"
- **การบินผสมพันธุ์** (ราชินีและตัวผู้มีปีก), **มดสายพันธุ์อื่น**, **มดรังอื่นมาแย่งพื้นที่**
- **โหมดวอลเปเปอร์:** จอหลักจอเดียว ยังจิ้มมดบนเดสก์ท็อปไม่ได้ และยังเปิดพร้อม Windows ไม่ได้
- ตอนนี้มีแค่ Windows รังใหญ่ (หลายร้อยตัว) ใช้ CPU มาก — จะทำให้เบาลงหลังปล่อย

### สเปกเครื่อง (จากที่วัดจริง)

- **ระบบ:** Windows 10 หรือ 11 แบบ 64 บิต
- **การ์ดจอ:** ต้องรองรับ **Vulkan** (โหมดวอลเปเปอร์ต้องใช้ **Direct3D 12** ด้วย)
- **เครื่องที่ทดสอบ:** โน้ตบุ๊ก Intel Core i5-12450H, RAM 16 GB — ทั้งการ์ดจอในตัว **Intel UHD** และ **NVIDIA RTX 3050 Laptop**
  - Intel UHD (คุณภาพต่ำ, 1600×900, มด 300 ตัว): บนพื้นที่หาอาหารราว 117 fps ในรังราว 43 fps
  - RTX 3050: ราว 120 fps ใช้ RAM ราว 810 MB หน่วยความจำการ์ดจอราว 185 MB
  - รังใหญ่ติดที่ CPU: CPU ที่ช้ากว่า Core i5 รุ่นที่ 12 จะได้เฟรมน้อยลงเมื่อมีมดหลายร้อยตัว
- ครั้งแรกเกมเลือกคุณภาพภาพให้เอง (การ์ดจอ Intel = ต่ำ, NVIDIA/AMD = สูง) เปลี่ยนได้ในตั้งค่า พร้อมจำกัดเฟรม 30 / 60 / ไม่จำกัด
- ตอนนี้ทดสอบแค่เครื่องข้างบนเครื่องเดียว — ช่วยบอกหน่อยว่าเครื่องคุณเล่นแล้วเป็นอย่างไร

### วิธีติดตั้ง

1. ดาวน์โหลด zip แล้วแตกไฟล์ไว้ที่ไหนก็ได้ (เก็บ **AntFarm.exe** กับ **AntDesk.exe** ไว้ในโฟลเดอร์เดียวกัน)
2. เปิด **AntFarm.exe**
3. Windows อาจขึ้น **"Windows protected your PC"** เพราะเกมยังไม่ได้เซ็นชื่อดิจิทัล: กด **More info** แล้วกด **Run anyway**

เซฟอยู่ที่ `%APPDATA%\Godot\app_userdata\AntFarm\` (เซฟเองทุกนาทีและตอนปิด) เกมไม่ต่ออินเทอร์เน็ต ไม่มีบัญชี โฆษณา หรือการเก็บสถิติ —
ดู PRIVACY.txt ใน zip · SHA-256 ของ zip: `‹วางรหัสจาก .sha256›`

### เนื้อหาที่สร้างด้วย AI

เพลงพื้นหลังสองเพลง *Where the Tall Trees Lean* และ *Under the Canopy* สร้างด้วย Google Gemini

### แจ้งบั๊ก เสนอไอเดีย และพูดคุย

เข้า **Discord: https://discord.gg/ReXz7AFgrG** — หรือคอมเมนต์ใต้หน้านี้ ใช้ภาษาไทยหรืออังกฤษก็ได้

---

## 4. ภาพหน้าจอที่ต้องถ่าย (ทำบนเครื่องผู้ใช้)

ถ่ายจากตัวเกมที่ build แล้ว ภาษาอังกฤษ 1920×1080 กด **F9** ซ่อนหน้าจอเมื่อต้องการภาพสะอาด (ยกเว้นภาพที่ตั้งใจให้เห็น UI)
ใช้สำเนารังผ่าน `--sandbox` ห้ามแตะเซฟจริง — รังใหญ่ใช้รังที่เลี้ยงมานานของผู้ใช้ (สำเนา) หรือ `--workers=14` แล้วเร่งเวลา

| # | ฉาก | ต้องเห็นอะไรในภาพ |
|---|---|---|
| 1 | **ปก (cover 630×500)** — ในรังมุมใกล้ | ราชินีกลางห้อง มีกองไข่/ตัวอ่อน/รังไหม และพี่เลี้ยงรอบๆ ซ่อน UI; ครอปให้ราชินีอยู่กลาง เหลือที่ให้ชื่อเกมถ้าจะใส่ทีหลัง |
| 2 | ภาพตัดรังทั้งรัง | อุโมงค์และห้องหลายชั้นที่มดขุดเอง (รังหลักร้อยตัว) ใช้ระนาบตัด/มองทะลุดิน เห็นความลึก |
| 3 | พื้นที่หาอาหาร + เพลี้ย | มดปีนต้นถั่วปากอ้า เคาะหลังเพลี้ยถั่วดำ และเส้นมดเดินระหว่างรังกับอาหาร |
| 4 | การสู้กับศัตรู | มดรุมเกาะแมงมุมหมาป่า (หรือด้วงดิน/ตะขาบหิน) รังใหญ่ เห็นมดงับขา ซ่อน UI |
| 5 | ห้อง Home | มุมมองบุคคลที่หนึ่ง: โต๊ะกับตู้เลี้ยง ชั้นวาง ตู้เย็นจำศีล หน้าต่าง มือเป็นเคอร์เซอร์ และแท็บ Colony Harmony/ร้านค้ามุมขวาบน |
| 6 | ร้านค้าเปิดอยู่ | หน้าร้าน (ตู้ที่ 2, ตู้เล็กเพิ่ม, ชั้นวาง) พร้อมแต้มและราคา ภาษาอังกฤษ |
| 7 | โหมดวอลเปเปอร์ | เดสก์ท็อป Windows ที่มีรังมดเป็นพื้นหลังและไอคอนอยู่ข้างหน้า (ใช้เดสก์ท็อปที่ไม่มีไฟล์ส่วนตัว) |
| 8 | ระหว่างที่คุณไม่อยู่ + มดเด่น | หน้าต่างสรุป "While you were away" หลังเปิดเกมกลับมา; หรือกล่องข้อมูลมดที่ตั้งชื่อแล้ว + แผง Top ants |
| 9 | (ถ้ามีที่) จำศีลในตู้เย็น | ตู้อยู่ในตู้เย็นใน Home หรือในรังตอนหนาวที่มดรวมกลุ่มกัน |
| 10 | (ถ้ามีที่) โหมดป่า | แปลงสวนกลางแดด ใบไม้แห้ง วัชพืช มดเดินบนพื้น |

ภาพทั้งหมดต้องมาจากเกมจริงเวอร์ชันที่ปล่อย ไม่ตกแต่งเพิ่ม (กฎของหน้าร้าน: ห้ามโฆษณาสิ่งที่เกมยังไม่มี)

---

## 5. ข้อควรตัดสินใจก่อนกด Public (ให้ผู้ใช้เลือก)

- **AI disclosure ของโค้ด:** โค้ดเกมเขียนร่วมกับผู้ช่วย AI (Claude Code) — ฟอร์มของ itch ถามเรื่องเนื้อหาที่สร้างด้วย AI;
  ร่างนี้แจ้งเฉพาะเพลงตามที่ตกลงไว้ ถ้าจะแจ้งเรื่องโค้ดด้วยให้เพิ่มหนึ่งบรรทัดในส่วน *AI-generated content* และติ๊กในฟอร์ม
- **เงื่อนไขของ Gemini:** ตรวจว่าใช้เพลงที่สร้างด้วย Gemini ในเกมที่รับเงินบริจาคได้ (จดไว้ใน BACKLOG ตั้งแต่ 2026-10-24)
- **ชื่อในเครดิต:** กรอกชื่อผู้สร้างใน `docs/release/CREDITS.txt` ก่อนรัน `tools/package.ps1`
