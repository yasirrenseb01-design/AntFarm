extends RefCounted
## Biology parameters for Lasius niger (black garden ant).
## Durations are days at optimum temperature; consumption is units per day.

## What the species page (view/ui/species_window.gd) says about it, before a colony starts. Each line: [text, where it
## comes from] - a study of L. niger itself, of ants in general, keepers' advice, or my own inference (docs/BIOLOGY.md).
const CARD := {
	"blurb": "มดที่พบมากที่สุดในสวนและทุ่งหญ้าทั่วยุโรป ตัวดำ ขนาดเล็ก 3.5–5 มม. รังหนึ่งมีราชินีตัวเดียว เป็นมดที่คนเลี้ยงมดนิยมเริ่มเลี้ยงเป็นชนิดแรก",
	"traits": [
		["ราชินีตั้งรังเองตัวเดียว: ขังตัวในห้องเล็กใต้ดิน เลี้ยงลูกรุ่นแรกด้วยไขมันและกล้ามเนื้อปีกในตัว ไม่ออกมากินเลยจนมดงานรุ่นแรกออก", "งานวิจัย L. niger (Janet 1907), AntWiki"],
		["เลี้ยงเพลี้ยเอาน้ำหวาน: ใช้หนวดเคาะหลังเพลี้ยให้ปล่อยหยดน้ำหวาน และไล่ผู้ล่าอย่างเต่าทองออกจากกลุ่มเพลี้ย", "งานวิจัย L. niger (Banks 1962)"],
		["ไม่มีเหล็กไน: สู้ด้วยการกัดแล้วงอท้องพ่นกรดฟอร์มิก และรุมกันดึงขาศัตรูจนขยับไม่ได้", "มดวงศ์ย่อย Formicinae ทั่วไป"],
		["ชวนพวกไปหาอาหารด้วยทางกลิ่นจากปลายท้อง และปล่อยกลิ่นเตือนภัยเมื่อเจอศัตรู", "งานวิจัย L. niger (Bestmann 1992)"],
		["ราชินีอายุยืนมาก: บันทึกในที่เลี้ยงนานเกือบ 29 ปี (มีบันทึกเดียว)", "งานวิจัย L. niger (Kutter & Stumper 1969)"],
	],
	"difficulty": "ง่าย — เหมาะกับมือใหม่",
	"care": [
		["กินง่าย: น้ำหวาน (น้ำผึ้ง เพลี้ย) กับแมลงเล็กๆ เป็นโปรตีนให้ตัวอ่อน", "คำแนะนำผู้เลี้ยง"],
		["อยู่ได้ที่อุณหภูมิห้อง ลูกมดโตเร็วที่สุดราว 20–28°C ต่ำกว่า ~13°C หยุดโต", "คำแนะนำผู้เลี้ยง + ค่าในเกม"],
		["ต้องจำศีลหน้าหนาว (ราวปลาย ต.ค.–ต้น มี.ค.) ไม่อย่างนั้นราชินีวางไข่น้อยลงเรื่อยๆ", "คำแนะนำผู้เลี้ยง"],
		["รังใหม่โตช้า: จากไข่ใบแรกถึงมดงานตัวแรกราว 6–10 สัปดาห์ ปีแรกยังมีมดไม่มาก", "คำแนะนำผู้เลี้ยง + Wikipedia"],
	],
}

const DATA := {
	"id": "lasius_niger",
	"name": "Lasius niger",
	"name_th": "มดดำสวน",

	# Brood development at optimum (~28 °C); slows linearly toward dev_min_c and stops below it.
	"egg_days": 10.0,
	"larva_days": 13.0,
	"pupa_days": 11.0,
	"dev_min_c": 13.0,
	"dev_opt_c": 28.0,
	"dev_hot_c": 33.0,
	"dev_lethal_c": 38.0,

	# Surface activity by air temperature.
	"forage_min_c": 8.0,
	"forage_opt_c": 22.0,
	"forage_hot_c": 32.0,
	"forage_max_c": 40.0,

	# Workers. Young adults nurse, older ones forage (age polyethism).
	"worker_life_min": 300.0,
	"worker_life_max": 700.0,
	"callow_days": 3.0,
	"nurse_until_days": 20.0,
	"nurse_until_hungry": 9.0,
	"larvae_per_nurse": 6.0,
	"forager_daily_risk": 0.012,

	# Queen (monogyne colony). Egg output scales with how many workers can rear brood.
	"queen_eggs_max": 30.0,
	"queen_eggs_base": 3.0,
	"queen_eggs_per_worker": 0.4,

	# Food. Adults run on sugar; larvae and egg production need protein.
	"sugar_worker": 0.08,
	"sugar_queen": 0.5,
	"sugar_larva": 0.04,
	"protein_larva": 0.25,
	"protein_egg": 0.05,
	"starve_days_worker": 7.0,
	"starve_days_queen": 12.0,
	"larva_starve_days": 3.0,

	# Nest moisture (0..1). Eggs dry out below the range, mould grows above it.
	"humidity_ok_min": 0.35,
	"humidity_ok_max": 0.9,

	# Movement in outworld px per tick (1 px ≈ 0.5 mm).
	"walk_speed": 0.7,

	# Colony founding and habits that set this species apart (read by the simulation and the views,
	# so another species can differ without new code paths).
	"founding": "claustral",          # the queen seals herself in and raises the first brood on her reserves
	"queen_reserve": 90.0,            # her fat body + dissolved wing muscle, in food units
	"founding_eggs": 3,               # eggs already laid when the colony starts
	"nanitic_size": [0.8, 0.04, 0.72, 0.9],   # first workers: mean, spread, min, max (1.0 = 4.2 mm worker)
	"tends_aphids": true,             # milks aphids for honeydew
	"buries_prey": true,              # piles soil on large prey it is exploiting

	"body_color": Color(0.085, 0.062, 0.05),
	"callow_color": Color(0.5, 0.36, 0.24),
}
