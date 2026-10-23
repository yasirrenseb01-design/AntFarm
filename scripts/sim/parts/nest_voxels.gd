extends RefCounted
## Underground nest: a block of soil voxels that workers excavate one bite at a time.
##
## Digging follows simple stigmergic rules seen in real Lasius:
##  - diggers are drawn to spots where nestmates dug recently (digging pheromone)
##  - tunnel tips are favoured over widening an existing tunnel, and digging trends downward
##  - inside a chamber site (around queen/brood) widening is allowed, but chambers stay flat
##  - the colony stops when the open volume matches its population (Buhl et al. 2004)
## Chambers are flat, elongated bulges along the galleries (Lasius: ~1–2 cm wide, 3–5 cm long, a few mm
## high, galleries 1.5–5 mm; Wang et al. 1995), with solid soil between them. Nobody plans them: they
## grow where workers crowd round brood (Römer & Roces 2014) — the plan here stands for that outcome.
## Each bite is carried up the tunnels and dropped on the surface, building the crater mound.
## Nest volume, layer 1 of 3 (split from scripts/sim/nest_volume.gd in v0.8.5): the voxel block,
## access, carving, the mesher's density, counting/distances, save and load.
## Layers: parts/nest_voxels <- parts/nest_chambers <- nest_volume.
const VOXEL_MM := 1.5
const AIR := 128            # density below this is open space
const BITE := 128           # density removed per bite (two bites empty a voxel)
const STEP_EVERY := 4       # ticks per one-voxel move ≈ 0.37 mm/tick, the pace of surface ants
const CHUNK := 16
const DIG_TAU := 0.35 * 3600.0   # ticks for the digging pheromone to fade by 1/e
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var nx := 64
var ny := 72
var nz := 64
var slab := false                       # true = thin glass ant-farm instead of a soil block
var rho := PackedByteArray()            # soil density 0..255 per voxel
# What the soil holds besides earth, from the plot's seed (lay_out_soil; saved): stones and roots the ants dig round
# (never through), and how deep the stiff clay and the loose sand below it start. {} = the plain soil every nest had
# before v0.11.18 (clay from 14 voxels down, sand from 40).
#   "stones": [[x, y, z, r], ...]   "roots": [[ax, ay, az, bx, by, bz, r], ...]   "clay": voxels   "sand": voxels
var soil := {}
var hard := PackedByteArray()           # 1 where a stone or a root is (worked out from soil, not saved)
var dug_at := PackedInt32Array()        # tick of the most recent bite at/near each voxel
var dist := PackedInt32Array()          # steps to the entrance through open space, -1 if cut off
var dirty: Dictionary = {}              # chunk coords (Vector3i) whose mesh must be rebuilt
var air := 0
var proj := PackedInt32Array()       # open voxels along z for each (x, y): the side-view outline
var excavated := 0                      # bites dumped on the surface
var chambers: Array = []                # {"c": Vector3, "r": float, "goal": float, "kind": String}
var diggers: Array = []                 # {"cell", "prev", "carry", "dir", "id"}
var entrance := Vector3i.ZERO
var entrance_r := 1.0                   # how wide the entrance shaft is meant to be (widened as traffic grows; daily)
var entrance_done := 1.0                # the width the entrance shaft was last found dug out to
var work_left := 0                      # planned soil still to dig (a new chamber, its shaft, a wider shaft; daily)
var work_at := Vector3i(-1, -1, -1)     # an open voxel at the face of that work (diggers make for it; daily)
var work_dist := PackedInt32Array()     # steps through open space to work_at per voxel, -1 = not reached (daily)
var tick := 0
var rng: RandomNumberGenerator
var _dist_age := 0
var _next_id := 0


func setup(r: RandomNumberGenerator, glass_slab := false, founding := false) -> void:
	rng = r
	slab = glass_slab
	if slab:
		nx = 110
		ny = 72
		nz = 5
	var n := nx * ny * nz
	rho.resize(n)
	rho.fill(255)
	dug_at.resize(n)
	dug_at.fill(-1000000)
	dist.resize(n)
	dist.fill(-1)
	# where the queen came down and began to dig: anywhere on the block, not only its middle - with room left round
	# it for the nest to grow (every nest used to start dead centre, its shaft straight down: the keeper saw all the
	# nests alike, 2026-10-23). A generator of its own from the colony's seed: the simulation's draws stay as they were.
	# [inference: a mated queen digs in where she lands; the start is otherwise not studied]
	var g := RandomNumberGenerator.new()
	g.seed = (r.seed * 2654435761 + 0x51E77A3B) & 0x7fffffff      # (mixed: seeds one apart start far apart)
	var ex := nx / 2 + roundi(g.randf_range(-0.3, 0.3) * nx if slab else g.randf_range(-0.2, 0.2) * nx)
	var ez := nz - 2 if slab else nz / 2 + roundi(g.randf_range(-0.2, 0.2) * nz)
	entrance = Vector3i(ex, ny - 1, ez)
	# in a glass farm the ants work against the front pane; the back layers stay soil
	var mid := Vector3(ex, 0, ez)
	var flat := 2.9 if slab else 0.0
	# the queen's shaft slants a little, its own way, and bends once (Lasius founding tunnels are short and seldom
	# plumb [inference]); her chamber opens off its foot to one side
	var ang := g.randf() * TAU
	var lean := Vector3(cos(ang), 0.0, 0.0 if slab else sin(ang))
	var side := lean.rotated(Vector3.UP, g.randf_range(-1.2, 1.2))
	if slab:
		side = Vector3(1.0 if side.x >= 0.0 else -1.0, 0.0, 0.0)      # (along the pane)
	if founding:
		# what a lone queen digs after her mating flight: a short shaft and one small chamber
		var bend := Vector3(mid.x, ny - 5, mid.z) + lean * g.randf_range(0.5, 2.0)
		var foot := Vector3(mid.x, ny - 9, mid.z) + lean * g.randf_range(1.5, 3.5)
		carve_line(Vector3(entrance), bend, 1.0)
		carve_line(bend, foot, 1.0)
		var fc := foot + side * 1.5 + Vector3(0, -2, 0)
		carve_room(fc, Vector3(6.0, 2.2, 6.0 - (2.6 if slab else 0.0)))   # ~1.8 cm across
		chambers.append({"c": fc, "r": 6.0, "goal": 6.0, "kind": "queen"})
		_recount()
		_bfs()
		return
	# A three-month-old nest: the queen's shaft, her chamber, and a first brood chamber.
	var foot2 := Vector3(mid.x, ny - 18, mid.z) + lean * g.randf_range(2.0, 4.0)
	carve_line(Vector3(entrance), foot2, 1.2)
	var qc := foot2 + side * 3.0 + Vector3(0, -2, 0)
	carve_room(qc, Vector3(4.5, 2.0, 4.5 - flat))
	chambers.append({"c": qc, "r": 4.5, "goal": 5.0, "kind": "queen"})
	var top := Vector3(entrance).lerp(foot2, 8.0 / 17.0)
	var bc := top - side * 6.0 + Vector3(0, -1, 0)
	carve_line(top, bc, 1.1)
	carve_room(bc, Vector3(4.0, 1.8, 4.0 - flat))
	chambers.append({"c": bc, "r": 4.0, "goal": 4.5, "kind": "brood"})
	_recount()
	_bfs()


# ---------------------------------------------------------------- what is in the soil

## Stones, roots and the depth of the clay for this colony's patch of ground (a generator of its own). Kept clear of
## what is dug already and of the entrance shaft. [inference: a garden's soil has pebbles and roots in it, and ants
## dig round them; the layer depths are chosen to differ by a few cm]
func lay_out_soil(seed_v: int) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = seed_v
	var stones := []
	var roots := []
	var mid := Vector2(entrance.x, entrance.z)
	var want := g.randi_range(12, 24)
	for attempt in 200:
		if stones.size() >= want:
			break
		var r := g.randf_range(1.6, 2.6) if g.randf() < 0.65 else g.randf_range(2.6, 4.8)       # 5-14 mm across
		var c := Vector3(g.randf_range(r + 1.0, nx - 2.0 - r), g.randf_range(r + 2.0, ny - 4.0 - r),
			(nz - 2.5) if slab else g.randf_range(r + 1.0, nz - 2.0 - r))
		if g.randf() < 0.6:
			# most where the nest is dug: within ~3 cm of the entrance shaft, in the top 8 cm
			c.x = clampf(mid.x + g.randf_range(-22.0, 22.0), r + 1.0, nx - 2.0 - r)
			c.y = g.randf_range(ny - 55.0, ny - 6.0 - r)
			if not slab:
				c.z = clampf(mid.y + g.randf_range(-22.0, 22.0), r + 1.0, nz - 2.0 - r)
		if Vector2(c.x, c.z).distance_to(mid) < r + 5.0 and c.y > ny - 30:
			continue                                   # (not in the way of the entrance shaft)
		if _open_near(c, r + 3.0):
			continue
		var clear := true
		for o in stones:
			if c.distance_to(Vector3(o[0], o[1], o[2])) < r + float(o[3]) + 2.0:
				clear = false
		if clear:
			stones.append([c.x, c.y, c.z, r])
	for i in g.randi_range(2, 4):
		# a root down from the surface, slanting
		var a := Vector3(g.randf_range(4.0, nx - 5.0), ny - 1.0, (nz - 2.5) if slab else g.randf_range(4.0, nz - 5.0))
		if Vector2(a.x, a.z).distance_to(mid) < 7.0:
			continue
		var dir := Vector3(g.randf_range(-0.6, 0.6), -1.0, 0.0 if slab else g.randf_range(-0.6, 0.6)).normalized()
		var b := a + dir * g.randf_range(20.0, 48.0)
		b = b.clamp(Vector3(2, 3, 1 if slab else 2), Vector3(nx - 3, ny - 1, nz - 2 if slab else nz - 3))
		var rr := g.randf_range(0.6, 1.1)
		var ok := true
		for k in 9:
			if _open_near(a.lerp(b, k / 8.0), rr + 2.0):
				ok = false
		if ok:
			roots.append([a.x, a.y, a.z, b.x, b.y, b.z, rr])
	var clay := g.randf_range(9.0, 20.0)
	soil = {"stones": stones, "roots": roots, "clay": clay, "sand": clay + g.randf_range(18.0, 34.0)}
	_stamp_hard()


## Marks the stones' and roots' voxels hard (and solid).
func _stamp_hard() -> void:
	hard.resize(nx * ny * nz)
	hard.fill(0)
	for s in soil.get("stones", []):
		var c := Vector3(s[0], s[1], s[2])
		var r: float = s[3]
		for y in range(maxi(0, floori(c.y - r)), mini(ny, ceili(c.y + r) + 1)):
			for z in range(maxi(0, floori(c.z - r)), mini(nz, ceili(c.z + r) + 1)):
				for x in range(maxi(0, floori(c.x - r)), mini(nx, ceili(c.x + r) + 1)):
					if Vector3(x, y, z).distance_to(c) <= r:
						_harden(Vector3i(x, y, z))
	for rt in soil.get("roots", []):
		var a := Vector3(rt[0], rt[1], rt[2])
		var b := Vector3(rt[3], rt[4], rt[5])
		var r: float = rt[6]
		var ab := b - a
		var lo := Vector3i(floori(minf(a.x, b.x) - r), floori(minf(a.y, b.y) - r), floori(minf(a.z, b.z) - r))
		var hi := Vector3i(ceili(maxf(a.x, b.x) + r), ceili(maxf(a.y, b.y) + r), ceili(maxf(a.z, b.z) + r))
		for y in range(maxi(0, lo.y), mini(ny, hi.y + 1)):
			for z in range(maxi(0, lo.z), mini(nz, hi.z + 1)):
				for x in range(maxi(0, lo.x), mini(nx, hi.x + 1)):
					var p := Vector3(x, y, z)
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
					if p.distance_to(a + ab * t) <= r:
						_harden(Vector3i(x, y, z))


func _harden(v: Vector3i) -> void:
	var i := idx(v)
	if rho[i] >= AIR:                      # (never where it is dug already)
		hard[i] = 1


func is_hard(v: Vector3i) -> bool:
	return not hard.is_empty() and inside(v) and hard[idx(v)] == 1


## Any stone or root within r of p.
func hard_near(p: Vector3, r: float) -> bool:
	if hard.is_empty():
		return false
	for y in range(maxi(0, floori(p.y - r)), mini(ny, ceili(p.y + r) + 1)):
		for z in range(maxi(0, floori(p.z - r)), mini(nz, ceili(p.z + r) + 1)):
			for x in range(maxi(0, floori(p.x - r)), mini(nx, ceili(p.x + r) + 1)):
				if hard[(z * ny + y) * nx + x] == 1 and Vector3(x, y, z).distance_to(p) <= r:
					return true
	return false


func _open_near(p: Vector3, r: float) -> bool:
	for y in range(maxi(0, floori(p.y - r)), mini(ny, ceili(p.y + r) + 1)):
		for z in range(maxi(0, floori(p.z - r)), mini(nz, ceili(p.z + r) + 1)):
			for x in range(maxi(0, floori(p.x - r)), mini(nx, ceili(p.x + r) + 1)):
				if is_open(Vector3i(x, y, z)) and Vector3(x, y, z).distance_to(p) <= r:
					return true
	return false


## Where the stiff clay and the loose sand start (voxels below the surface).
func clay_top() -> float:
	return float(soil.get("clay", 14.0))


func sand_top() -> float:
	return float(soil.get("sand", 40.0))


# ---------------------------------------------------------------- voxel access

func idx(c: Vector3i) -> int:
	return (c.z * ny + c.y) * nx + c.x   # z-major: each z slice is contiguous (uploaded as a 3D texture layer)


func inside(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < nx and c.y < ny and c.z < nz


func is_open(c: Vector3i) -> bool:
	return inside(c) and rho[idx(c)] < AIR


## Soil density as seen by the mesher (view only): solid or open, softened with the six neighbours so burrows
## come out rounded rather than square. Soil is softened toward open space by 0.1 per open neighbour, open space
## toward soil by only 0.05 per solid one (it was 0.1 too: a one-voxel tunnel - an ant's width - was drawn 0.4 of a
## voxel wide, and every ant walking it had its body in the walls). Outside the block counts as air so the block
## gets faces.
func density(x: int, y: int, z: int) -> float:
	var n := _solid(x - 1, y, z) + _solid(x + 1, y, z) + _solid(x, y - 1, z) + _solid(x, y + 1, z) + _solid(x, y, z - 1) + _solid(x, y, z + 1)
	return 0.4 + 0.1 * n if _solid(x, y, z) > 0.5 else 0.05 * n


func _solid(x: int, y: int, z: int) -> float:
	if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz:
		return 0.0
	return 1.0 if rho[(z * ny + y) * nx + x] >= AIR else 0.0


func walkable(c: Vector3i) -> bool:
	if not is_open(c):
		return false
	for d in DIRS:
		var n := c + d
		if not inside(n) or rho[idx(n)] >= AIR:
			return true
	return false


## A chamber's shape: a level floor (ants flatten it) under a low domed ceiling. d is measured from the
## centre, ax are the half-axes (long, high, wide); <= 1 inside.
static func room_q(d: Vector3, ax: Vector3) -> float:
	var h := pow(d.x / ax.x, 2.0) + pow(d.z / ax.z, 2.0)
	var v := d.y / ax.y
	return h + (v * v if v > 0.0 else pow(-v, 6.0))


## Carve a whole chamber at once (setting up a nest).
func carve_room(center: Vector3, r: Vector3) -> void:
	for y in range(maxi(0, int(center.y - r.y)), mini(ny, int(center.y + r.y) + 2)):
		for z in range(maxi(0, int(center.z - r.z)), mini(nz, int(center.z + r.z) + 2)):
			for x in range(maxi(0, int(center.x - r.x)), mini(nx, int(center.x + r.x) + 2)):
				if room_q(Vector3(x, y, z) - center, r) <= 1.0:
					rho[(z * ny + y) * nx + x] = 0
					_mark(Vector3i(x, y, z))


func carve_ellipsoid(center: Vector3, r: Vector3) -> void:
	for y in range(maxi(0, int(center.y - r.y)), mini(ny, int(center.y + r.y) + 2)):
		for z in range(maxi(0, int(center.z - r.z)), mini(nz, int(center.z + r.z) + 2)):
			for x in range(maxi(0, int(center.x - r.x)), mini(nx, int(center.x + r.x) + 2)):
				var q := (Vector3(x, y, z) - center) / r
				if q.length_squared() <= 1.0:
					rho[(z * ny + y) * nx + x] = 0
					_mark(Vector3i(x, y, z))


func carve_line(a: Vector3, b: Vector3, radius: float) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		carve_ellipsoid(p, Vector3.ONE * radius)


func _mark(c: Vector3i) -> void:
	# surface nets reads one cell across chunk borders, so neighbours' chunks change too
	dirty[Vector3i(floori(c.x / float(CHUNK)), floori(c.y / float(CHUNK)), floori(c.z / float(CHUNK)))] = true
	for d in DIRS:
		var n := c + d
		dirty[Vector3i(floori(n.x / float(CHUNK)), floori(n.y / float(CHUNK)), floori(n.z / float(CHUNK)))] = true


func _recount() -> void:
	air = 0
	proj.resize(nx * ny)
	proj.fill(0)
	for z in nz:
		for y in ny:
			for x in nx:
				if rho[(z * ny + y) * nx + x] < AIR:
					air += 1
					proj[y * nx + x] += 1


func _bfs() -> void:
	dist.fill(-1)
	var q: Array[Vector3i] = [entrance]
	dist[idx(entrance)] = 0
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var dc := dist[idx(c)]
		for d in DIRS:
			var n := c + d
			if inside(n):
				var i := idx(n)
				if dist[i] < 0 and rho[i] < AIR:
					dist[i] = dc + 1
					q.append(n)


func volume_cm3() -> float:
	return air * pow(VOXEL_MM / 10.0, 3.0)


func depth_cm() -> float:
	var deepest := ny
	for c in chambers:
		deepest = mini(deepest, int(c.c.y - c.r * 0.5))
	return (ny - deepest) * VOXEL_MM / 10.0


# ---------------------------------------------------------------- save / load

## Everything that affects how digging continues, so a loaded nest carries on exactly where it was.
func to_dict() -> Dictionary:
	return {"nx": nx, "ny": ny, "nz": nz, "slab": slab, "rho": rho, "dug_at": dug_at, "dist": dist,
		"excavated": excavated, "chambers": chambers, "diggers": diggers, "entrance": entrance, "tick": tick,
		"dist_age": _dist_age, "next_id": _next_id, "entrance_r": entrance_r, "work_left": work_left, "work_at": work_at, "work_dist": work_dist, "entrance_done": entrance_done,
		"soil": soil}


func from_dict(r: RandomNumberGenerator, d: Dictionary) -> void:
	rng = r
	nx = d.nx
	ny = d.ny
	nz = d.nz
	slab = d.slab
	rho = d.rho
	dug_at = d.dug_at
	dist = d.dist
	excavated = d.excavated
	chambers = d.chambers
	diggers = d.diggers
	entrance = d.entrance
	tick = d.tick
	_dist_age = d.dist_age
	_next_id = d.next_id
	entrance_r = float(d.get("entrance_r", -1.0))       # (older saves: worked out by the simulation after loading)
	work_left = int(d.get("work_left", -1))
	work_at = d.get("work_at", Vector3i(-1, -1, -1))
	work_dist = d.get("work_dist", PackedInt32Array())
	entrance_done = float(d.get("entrance_done", 1.0))
	soil = {}
	var sd = d.get("soil", {})              # (saves before v0.11.18: plain soil)
	if sd is Dictionary:
		for k in ["clay", "sand"]:
			if sd.get(k) is float or sd.get(k) is int:
				soil[k] = clampf(float(sd[k]), 2.0, float(ny))
		for k in ["stones", "roots"]:
			var rows := []
			for row in sd.get(k, []) if sd.get(k) is Array else []:
				if row is Array and row.size() == (4 if k == "stones" else 7) and row.all(func(v): return v is float or v is int):
					rows.append(row)
			soil[k] = rows.slice(0, 64)
	# nests dug before v0.8.2 left open voxels at half density, which drew as blocky steps
	for i in rho.size():
		if rho[i] < AIR:
			rho[i] = 0
	_recount()
	_stamp_hard()
