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
## Nest volume, layer 1 of 5 (split from scripts/sim/nest_volume.gd in v0.8.5): the voxel block, access, carving, the
## mesher's density, counting/distances.
## Layers: parts/nest_voxels <- parts/nest_ground <- parts/nest_store <- parts/nest_chambers <- nest_volume.
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
# the soil below y = 0 is there but not yet held (a garden nest, up to 30 cm deep): the layers from y_lo up are, and
# more are taken in below as the ants dig near the bottom of them (extend_down), down to y_floor. Coordinates stay
# as they are (the surface at ny - 1); a formicarium's soil ends at y = 0 (y_lo = y_floor = 0), as every nest's did.
var y_lo := 0
var y_floor := 0
# Sideways the same (PART 0.12 step 5a): only the box x_lo .. nx - 1, z_lo .. nz - 1 of the tank's soil is held, the rest
# is soil not yet dug near (solid). Coordinates are the tank's own - never below 0 (x < 0 / Vector3i(-1, ...) stand for
# "none" in many places) - so the box grows sideways by taking in more, the coordinates staying as they are.
var x_lo := 0
var z_lo := 0
const DEEP_LAYERS := 200                # how deep a garden nest's soil goes (voxels: 30 cm)
const EXTEND_BY := 16                   # layers taken in at a time (one mesh chunk)
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
var dug := 0                       # blocks dug out since it was loaded (the keeper's Colony Harmony points; not saved)
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
	y_lo = 0
	y_floor = 0
	x_lo = 0
	z_lo = 0
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


## Stones and roots (worked out in parts/nest_ground.gd): never dug through.
func is_hard(v: Vector3i) -> bool:
	return not hard.is_empty() and inside(v) and hard[idx(v)] == 1


# ---------------------------------------------------------------- voxel access

## The layers held: y_lo .. ny - 1.
func hy() -> int:
	return ny - y_lo


## The columns and rows held across: x_lo .. nx - 1, z_lo .. nz - 1.
func wx() -> int:
	return nx - x_lo


func wz() -> int:
	return nz - z_lo


func idx(c: Vector3i) -> int:
	# z-major: each z slice is contiguous (a 3D texture layer)
	return ((c.z - z_lo) * (ny - y_lo) + c.y - y_lo) * (nx - x_lo) + c.x - x_lo


func inside(c: Vector3i) -> bool:
	return c.x >= x_lo and c.y >= y_lo and c.z >= z_lo and c.x < nx and c.y < ny and c.z < nz


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
	if x < x_lo or y < y_lo or z < z_lo or x >= nx or y >= ny or z >= nz:
		return 0.0
	return 1.0 if rho[((z - z_lo) * (ny - y_lo) + y - y_lo) * (nx - x_lo) + x - x_lo] >= AIR else 0.0


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
	for y in range(maxi(y_lo, int(center.y - r.y)), mini(ny, int(center.y + r.y) + 2)):
		for z in range(maxi(z_lo, int(center.z - r.z)), mini(nz, int(center.z + r.z) + 2)):
			for x in range(maxi(x_lo, int(center.x - r.x)), mini(nx, int(center.x + r.x) + 2)):
				if room_q(Vector3(x, y, z) - center, r) <= 1.0:
					rho[idx(Vector3i(x, y, z))] = 0
					_mark(Vector3i(x, y, z))


func carve_ellipsoid(center: Vector3, r: Vector3) -> void:
	for y in range(maxi(y_lo, int(center.y - r.y)), mini(ny, int(center.y + r.y) + 2)):
		for z in range(maxi(z_lo, int(center.z - r.z)), mini(nz, int(center.z + r.z) + 2)):
			for x in range(maxi(x_lo, int(center.x - r.x)), mini(nx, int(center.x + r.x) + 2)):
				var q := (Vector3(x, y, z) - center) / r
				if q.length_squared() <= 1.0:
					rho[idx(Vector3i(x, y, z))] = 0
					_mark(Vector3i(x, y, z))


func carve_line(a: Vector3, b: Vector3, radius: float) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		carve_ellipsoid(p, Vector3.ONE * radius)


## The way through the open nest from a to b widened to r (half-widths, voxels) - not through a stone or a root: the
## queen's way to another chamber (sim_warmth). Returns the voxels dug out. [inference: Lasius workers dig passages to
## their own width and the queen is broader - she gets through, and the workers widen the way; no measurement found]
func widen_way(a: Vector3, b: Vector3, r: Vector3) -> int:
	var from := Vector3i(roundi(a.x), roundi(a.y), roundi(a.z))
	var to := Vector3i(roundi(b.x), roundi(b.y), roundi(b.z))
	if not is_open(from) or not is_open(to):
		return 0
	var came := {from: from}
	var q: Array[Vector3i] = [from]
	var head := 0
	while head < q.size() and not came.has(to):
		var c := q[head]
		head += 1
		for d in DIRS:
			var n := c + d
			if not came.has(n) and is_open(n):
				came[n] = c
				q.append(n)
	if not came.has(to):
		return 0
	var dug := 0
	var c := to
	while c != from:
		for y in range(maxi(y_lo, int(c.y - r.y)), mini(ny - 1, int(c.y + r.y) + 1)):
			for z in range(maxi(z_lo + 1, int(c.z - r.z)), mini(nz - 1, int(c.z + r.z) + 1)):
				for x in range(maxi(x_lo + 1, int(c.x - r.x)), mini(nx - 1, int(c.x + r.x) + 1)):
					var v := Vector3i(x, y, z)
					var k := idx(v)
					if rho[k] >= AIR and not is_hard(v) and ((Vector3(v) - Vector3(c)) / r).length_squared() <= 1.0:
						rho[k] = 0
						_mark(v)
						dug += 1
		c = came[c]
	if dug > 0:
		_recount()
		_bfs()
	return dug


func _mark(c: Vector3i) -> void:
	# surface nets reads one cell across chunk borders, so neighbours' chunks change too
	dirty[Vector3i(floori(c.x / float(CHUNK)), floori(c.y / float(CHUNK)), floori(c.z / float(CHUNK)))] = true
	for d in DIRS:
		var n := c + d
		dirty[Vector3i(floori(n.x / float(CHUNK)), floori(n.y / float(CHUNK)), floori(n.z / float(CHUNK)))] = true


func _recount() -> void:
	air = 0
	var h := hy()
	var w := wx()
	proj.resize(w * h)                  # (row y - y_lo, column x - x_lo)
	proj.fill(0)
	for z in wz():
		for y in h:
			for x in w:
				if rho[(z * h + y) * w + x] < AIR:
					air += 1
					proj[y * w + x] += 1


var dist_ver := 0                      # counts changes to dist (_bfs, a voxel opened: nest_volume._bite)
var _bfs_key := []                     # (what the last _bfs saw: the same open space gives the same distances)


## Steps to the entrance through open space, every voxel (breadth first). Flat indices, no Vector3i or calls in the
## loop, as _work_paths: ~6x faster than walking DIRS with idx()/inside() (v0.12.2; the same distances, which do not
## depend on the order).
func _bfs() -> void:
	_bfs_key = [air, y_lo, entrance, dist.size()]
	dist_ver += 1
	dist.fill(-1)
	var rows := ny - y_lo
	var w := wx()
	var deep := wz()
	var up := w
	var back := rows * w
	var d := dist
	var r := rho
	var q := PackedInt32Array()
	q.resize(maxi(air, 0) + 2)
	var first := idx(entrance)
	d[first] = 0
	q[0] = first
	var h := 0
	var t := 1
	while h < t:
		var i: int = q[h]
		h += 1
		var dc: int = d[i] + 1
		var x := i % w
		var row := i / w
		var yy := row % rows
		var zz := row / rows
		if t + 6 > q.size():
			q.resize(q.size() * 2)          # (air counted short: never in a nest made by the game)
		if x + 1 < w and r[i + 1] < AIR and d[i + 1] < 0:
			d[i + 1] = dc
			q[t] = i + 1
			t += 1
		if x > 0 and r[i - 1] < AIR and d[i - 1] < 0:
			d[i - 1] = dc
			q[t] = i - 1
			t += 1
		if yy + 1 < rows and r[i + up] < AIR and d[i + up] < 0:
			d[i + up] = dc
			q[t] = i + up
			t += 1
		if yy > 0 and r[i - up] < AIR and d[i - up] < 0:
			d[i - up] = dc
			q[t] = i - up
			t += 1
		if zz + 1 < deep and r[i + back] < AIR and d[i + back] < 0:
			d[i + back] = dc
			q[t] = i + back
			t += 1
		if zz > 0 and r[i - back] < AIR and d[i - back] < 0:
			d[i - back] = dc
			q[t] = i - back
			t += 1
	dist = d


## The periodic recount of distances, skipped while the open space is as it was (openings only ever add to `air`).
func _bfs_if_changed() -> void:
	if _bfs_key != [air, y_lo, entrance, dist.size()]:
		_bfs()
