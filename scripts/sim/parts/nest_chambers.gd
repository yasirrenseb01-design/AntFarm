extends "res://scripts/sim/parts/nest_voxels.gd"
## Nest volume, layer 2 of 3 (split from scripts/sim/nest_volume.gd in v0.8.5): the chamber plan
## (shapes, sizes, where new chambers go).


## Which part of the nest plan a voxel belongs to: 2 = inside a chamber, 1 = on a shaft toward a
## planned chamber, 0 = unplanned soil.
func _plan_at(c: Vector3i) -> int:
	var p := Vector3(c)
	var on_shaft := false
	for ch in chambers:
		if ch.get("open", true) and chamber_q(p, ch) <= 1.0:
			return 2
		if ch.has("from"):
			var a: Vector3 = ch.from
			var b: Vector3 = ch.c
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if p.distance_to(a + ab * t) <= 1.3:
				on_shaft = true
	return 1 if on_shaft else 0


## Half-axes of a chamber's planned shape: long, wide (across), high. Flat: about two ants high.
func chamber_axes(ch: Dictionary) -> Vector3:
	var g: float = ch.goal
	if slab:     # seen edge-on against the glass: a room one ant-layer deep, so a little higher and shorter
		return Vector3(minf(g, 10.0), clampf(2.2 + g * 0.08, 2.2, 3.0), 1.0)
	return Vector3(g, clampf(1.7 + g * 0.06, 1.7, 2.4), maxf(2.6, g * 0.6))


## Where a point lies relative to a chamber's planned shape (<= 1 inside), turned to its heading.
func chamber_q(p: Vector3, ch: Dictionary) -> float:
	var d: Vector3 = p - ch.c
	var yaw: float = ch.get("yaw", 0.0)
	var ax := chamber_axes(ch)
	if slab:
		return room_q(Vector3(d.x, d.y, 0.0), ax)     # one layer deep: no heading
	var u := d.x * cos(yaw) + d.z * sin(yaw)
	var v := -d.x * sin(yaw) + d.z * cos(yaw)
	return room_q(Vector3(u, d.y, v), ax)


func _chamber_volume(ch: Dictionary) -> float:
	var ax := chamber_axes(ch)
	return 4.0 / 3.0 * PI * ax.x * ax.y * (1.0 if slab else ax.z)


## The bottom of the deepest chamber (voxel y).
func _lowest_chamber() -> float:
	var low := float(ny)
	for ch in chambers:
		low = minf(low, float(ch.c.y) - chamber_axes(ch).y)
	return low


# ---------------------------------------------------------------- chambers

## Called by the colony once a day. Chambers grow while brood is crowded; a growing colony also
## plans a new chamber a little deeper and sinks a shaft down to it, giving the stacked layout of
## Lasius nests (flat chambers in series along vertical shafts).
func plan_chambers(brood: int, workers: int, target_air := 0) -> String:
	var event := ""
	for ch in chambers:
		if not ch.get("open", true) and is_open(Vector3i(ch.c)):
			ch.open = true
			event = "opened"
	# how big a chamber gets grows with the colony: ~1.5 cm long for a founding queen, up to ~4 cm
	var cap := clampf(5.0 + workers / 20.0, 5.0, 13.0)
	var planned := 0.0
	var floor_cap := 0.0
	for ch in chambers:
		planned += _chamber_volume(ch)
		if ch.get("open", true):
			var ax := chamber_axes(ch)
			floor_cap += PI * ax.x * (1.0 if slab else ax.z) * 1.5
	var load := brood + workers * 0.3
	var short := target_air > 0 and planned < target_air * 0.8      # the colony needs more room
	if load > floor_cap * 0.7 or short:
		# crowded brood: workers widen the chamber they crowd in (the smallest one that can still grow)
		var best := -1
		for i in chambers.size():
			var ch: Dictionary = chambers[i]
			if ch.get("open", true) and ch.goal < cap and (best < 0 or ch.goal < chambers[best].goal):
				best = i
		if best >= 0:
			chambers[best].goal = minf(cap, chambers[best].goal + 0.5)
			if event == "" and load > floor_cap * 0.7 and int(chambers[best].goal * 2.0) % 4 == 0:
				event = "grown"         # told now and then, not every day it grows
			return event
	var wanted := 1 if workers < 10 else 2          # a founding queen makes do with one chamber
	var pending := 0
	for ch in chambers:
		if not ch.get("open", true):
			pending += 1
	if pending > 0 or chambers.size() >= 24 or (chambers.size() >= wanted and not short):
		return event
	# a new chamber: beside an existing one on the same level (nests are top-heavy) or a level deeper,
	# reached by a gallery from the side of the old chamber
	for attempt in 60:
		var src: Dictionary = chambers[rng.randi() % chambers.size()]
		var depth: float = ny - float(src.c.y)
		var sideways := rng.randf() < (0.65 if depth < 30.0 else 0.35)
		var ang := rng.randf() * TAU
		var reach := rng.randf_range(src.goal + 8.0, src.goal + 14.0) if sideways else rng.randf_range(4.0, 12.0)
		var off := Vector3(cos(ang) * reach, rng.randf_range(-2.0, 1.0) if sideways else -rng.randf_range(8.0, 13.0), sin(ang) * reach)
		if slab:
			off.x = (reach if cos(ang) >= 0.0 else -reach) * (1.0 if sideways else 0.6)
			off.z = 0.0
		var site := Vector3(src.c) + off
		if site.x < 8 or site.x > nx - 9 or site.y < 6 or site.y > ny - 9 or site.z < (1 if slab else 8) or site.z > nz - (2 if slab else 9):
			continue
		var ok := true
		for ch in chambers:
			if site.distance_to(ch.c) < ch.goal + 9.0:
				ok = false
				break
		if ok:
			var dir := (site - Vector3(src.c)) * Vector3(1, 0, 1)
			var from: Vector3 = Vector3(src.c) + (dir.normalized() * float(src.goal) * 0.7 if dir.length() > 0.1 else Vector3.ZERO)
			chambers.append({"c": site, "r": 3.5, "goal": 3.5, "kind": "brood", "from": from, "open": false,
				"yaw": ang + rng.randf_range(-0.6, 0.6)})
			return "planned"
	return event
