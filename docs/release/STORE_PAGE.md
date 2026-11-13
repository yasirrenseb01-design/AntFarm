# หน้าร้าน itch.io — AntFarm: Legion of the Unseen (PART EA-R ข้อ R6)

ร่างโดย session คลาวด์ 2026-10-29 จาก v0.11.74 — ทุกข้อความตรวจกับ `CHANGELOG.md`, `docs/BIOLOGY.md` และ `lang/strings.csv` แล้ว
(ตัวเลขสเปกมาจาก v0.11.14 / v0.11.0 ใน CHANGELOG เท่านั้น) — ผู้ใช้ตรวจแล้วค่อยวาง

**วิธีวาง:** ตัวแก้ข้อความของ itch.io เป็นแบบ rich text — เปิดไฟล์นี้บน GitHub (ภาพที่แสดงผลแล้ว) คัดลอกส่วน "คำอธิบายหลัก"
ทั้งก้อนตั้งแต่หัว **Keep a colony…** จนจบส่วนไทย แล้ววางในช่อง Description หัวข้อ ตัวหนา รายการ และลิงก์จะติดไปด้วย
(ถ้าวางแล้วเป็นตัว `##` ดิบ แปลว่าคัดลอกจากไฟล์ดิบ ให้คัดลอกจากหน้าที่แสดงผลแทน)

ไม่ใส่รหัส SHA-256 บนหน้าร้าน (ผู้ใช้ 2026-11-05): รหัสเปลี่ยนทุกครั้งที่ทำ zip ใหม่ ถ้าลืมแก้จะไม่ตรงกับไฟล์

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
| Pricing | **Paid: minimum price $1.49** ("$1.49 USD or more", ผู้ใช้เปลี่ยน 2026-11-07; ตอนปล่อย 2026-11-04 เป็น $0 or donate) | ตั้งราคาที่โปรเจกต์ ไม่ตั้งราคาแยกรายไฟล์ เพื่อให้ขึ้นราคาภายหลังโดยผู้ซื้อเดิมไม่เสียสิทธิ์; สัญญากับผู้เล่นใน Discord: ซื้อแล้วได้อัปเดตฟรีตลอด รวมสายพันธุ์ใหม่ |
| Uploads | `AntFarm-v‹เวอร์ชัน›-windows.zip` ติ๊ก **Windows** | ไฟล์จาก `build/release/` |
| Uploads (เดโมฟรี, ตั้งแต่ v0.13.18) | `AntFarm-v‹เวอร์ชัน›-demo-windows.zip` ติ๊ก **Windows** และ **This file is a demo and can be downloaded for free** | `tools/package.ps1` ทำทั้งสองไฟล์; เดโม: ตู้ 2 แปลงป่า 1 รังละ 150 ร้านซื้อไม่ได้ (`scripts/game/demo.gd`) เซฟเล่นต่อในเกมเต็มได้ |
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

**ฉบับสั้น (ผู้ใช้ 2026-11-14, สำหรับรอบลงร้าน 0.13):** "ข้อความหน้าร้านยาวเกินไป ... หาจุดเด่นที่เด่นจริง ๆ ของเวอร์ชันที่ลง
ส่วนการเปรียบเทียบ/พัฒนาการอัปเดตไปลง devlog" — ทุกข้อตรวจกับตัวเกม v0.13.17 แล้ว (ไม่ใส่ของที่ยังไม่มี); ฉบับยาวเดิมอยู่ใน git (ก่อน commit นี้)

**Raise a colony of black garden ants — from a single queen to a nest of hundreds.**

*AntFarm: Legions of the Unseen* is a calm, detailed ant-keeping game built on real research into the black garden ant,
*Lasius niger*. Nothing is scripted: every ant has its own job, its own stomach and its own life.

### What makes it different

- **Every ant is an individual.** Young workers nurse the brood, older ones forage. Each carries food in its own crop,
  heads out when it is hungry and shares food mouth to mouth.
- **They dig the nest themselves.** Tunnels and chambers grow as the colony grows — no two nests alike.
  Look through the soil, cut the nest open and follow any ant.
- **The colony lives on while you are away.** Close the game; when you come back, a report tells you who was born,
  who died and how the nest grew.
- **A living desktop wallpaper.** One click puts your nest behind your desktop icons.
- **Predators.** Wolf spiders, stone centipedes and ground beetles hunt in the outworld. Your workers grab their legs,
  pin them down and spray formic acid.
- **Your own keeper's room.** Keep several tanks, winter your colonies in the fridge, and fill a plate album as they grow.

**Early Access** — playable from start to finish and still growing. Mating flights and a second species, the leafcutter ant,
are on the way.

**Windows 10/11 (64-bit) · graphics with Vulkan.** Windows may say "Windows protected your PC" because the game is not signed
yet — click *More info*, then *Run anyway*. No internet, accounts, ads or tracking.

*The two background music tracks were generated with Google Gemini.*

Bugs, ideas and chat: **Discord https://discord.gg/ReXz7AFgrG** — English and Thai welcome.

---

**เลี้ยงมดดำสวน ตั้งแต่ราชินีตัวเดียวจนเป็นรังหลายร้อยตัว**

*AntFarm: Legions of the Unseen* เป็นเกมเลี้ยงมดแบบละเอียดและผ่อนคลาย สร้างจากงานวิจัยจริงของมดดำสวน (*Lasius niger*)
ไม่มีอะไรเขียนบทไว้ล่วงหน้า มดทุกตัวมีงาน มีกระเพาะ และมีชีวิตของตัวเอง

### จุดเด่น

- **มดทุกตัวเป็นตัวของตัวเอง** มดอายุน้อยเลี้ยงลูก มดอายุมากออกหาอาหาร แต่ละตัวเก็บอาหารในกระเพาะของตัวเอง หิวเมื่อไหร่ก็ออกไปหา
  และป้อนอาหารกันปากต่อปาก
- **มดขุดรังเอง** อุโมงค์และห้องขยายตามขนาดรัง ไม่มีรังไหนเหมือนกัน มองทะลุดิน ตัดดูหน้าตัดรัง และตามมดตัวไหนก็ได้
- **รังมีชีวิตต่อตอนคุณไม่อยู่** ปิดเกมไปแล้วกลับมา จะมีสรุปว่าใครเกิด ใครตาย รังโตแค่ไหน
- **วอลเปเปอร์ที่มีชีวิต** คลิกเดียว รังมดไปอยู่หลังไอคอนบนเดสก์ท็อป
- **ศัตรู** แมงมุมหมาป่า ตะขาบหิน และด้วงดินออกล่าบนพื้นที่หาอาหาร มดงานงับขา ตรึงไว้ แล้วพ่นกรดฟอร์มิก
- **ห้องของผู้เลี้ยง** เลี้ยงได้หลายตู้ ส่งรังเข้าตู้เย็นจำศีลหน้าหนาว และสะสมภาพในสมุดภาพเมื่อรังโตขึ้น

**Early Access** — เล่นได้ครบตั้งแต่ต้นจนจบ และยังเพิ่มของต่อเรื่อย ๆ การบินผสมพันธุ์และสายพันธุ์ที่ 2 มดตัดใบ กำลังมา

**Windows 10/11 (64 บิต) · การ์ดจอที่รองรับ Vulkan** Windows อาจขึ้น "Windows protected your PC" เพราะเกมยังไม่ได้เซ็นชื่อดิจิทัล
กด *More info* แล้ว *Run anyway* เกมไม่ต่ออินเทอร์เน็ต ไม่มีบัญชี โฆษณา หรือการเก็บสถิติ

*เพลงพื้นหลังสองเพลงสร้างด้วย Google Gemini*

แจ้งบั๊ก เสนอไอเดีย และพูดคุย: **Discord https://discord.gg/ReXz7AFgrG** — ใช้ภาษาไทยหรืออังกฤษก็ได้

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

**ถ่ายแล้ว (v0.11.82, 2026-11-03):** `shots/store/` (ไม่อยู่ใน git) — 01 ราชินีกับลูกมด (ปก: ครอปเป็น 630×500), 02 รังทั้งรัง, 03 พื้นที่หาอาหาร,
05 ในรังพร้อม UI, 06 แท็บสถิติ, 07 ห้อง Home, 08 ร้านค้า, 09 โหมดป่า — ยังไม่มี: การสู้กับศัตรู (กล้องไม่ได้หันไปที่แมงมุม), วอลเปเปอร์, ระหว่างที่คุณไม่อยู่;
ถ่ายจากตัว dev (ภาพเหมือนตัว exe) ด้วยรังที่สร้างตอนถ่าย ไม่ได้ใช้เซฟผู้เล่น

ภาพทั้งหมดต้องมาจากเกมจริงเวอร์ชันที่ปล่อย ไม่ตกแต่งเพิ่ม (กฎของหน้าร้าน: ห้ามโฆษณาสิ่งที่เกมยังไม่มี)

---

## 5. ข้อควรตัดสินใจก่อนกด Public (ให้ผู้ใช้เลือก)

- **AI disclosure ของโค้ด:** โค้ดเกมเขียนร่วมกับผู้ช่วย AI (Claude Code) — ฟอร์มของ itch ถามเรื่องเนื้อหาที่สร้างด้วย AI;
  ร่างนี้แจ้งเฉพาะเพลงตามที่ตกลงไว้ ถ้าจะแจ้งเรื่องโค้ดด้วยให้เพิ่มหนึ่งบรรทัดในส่วน *AI-generated content* และติ๊กในฟอร์ม
- **เงื่อนไขของ Gemini:** ตรวจว่าใช้เพลงที่สร้างด้วย Gemini ในเกมที่ขายได้ (จดไว้ใน BACKLOG ตั้งแต่ 2026-10-24; ยังไม่ได้ตรวจ และเกมขายจริงแล้วตั้งแต่ 2026-11-07)
- **ชื่อในเครดิต:** กรอกชื่อผู้สร้างใน `docs/release/CREDITS.txt` ก่อนรัน `tools/package.ps1`
