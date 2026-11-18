extends RefCounted
## Brood laid on the floor of another chamber because its own is full (nest_piles: BroodPlaces.spill, v0.13.27) is carried
## there by a nurse, not shown there at once: hidden until a nurse has walked to the pile it comes from, picked it up and
## set it down in that chamber (v0.13.30; the keeper's rule, 2026-11: brood moves only when an ant carries it). `nv` is the
## nest view; its `_spill_wait`: item's view tag -> {kind, from, to, s, h (the nurse), phase 0 to the pile / 1 carrying,
## done (set by nest_mates._arrive), t}. View only: the simulation never sees it, and a nest opened again lays all out anew.
## [Inference: nurses spread a crowded brood into the next chambers by carrying it, one item at a time - as they move
## piles (nest_mates "carry"); no count of how fast Lasius niger nurses do so was found.]

const MAX_CARRIERS := 3           # nurses carrying spilled brood at once
const GIVE_UP := 45.0             # seconds: no nurse got it there by then - shown where it lies (never hidden for good)


## Whether the item just laid at `to` (on another chamber's floor, from the pile round `from`) waits for a nurse: not while
## a whole pile is being moved (those carriers bring it, nest_mates "carry"), nor in the first layout of a nest opened.
static func hold(nv, v: int, kind: String, from: Vector3, to: Vector3, s: float) -> bool:
	if nv._brood_gen == 0 or nv._moved < nv.sim.larvae.size() or nv._moved_p < nv.sim.pupae.size():
		return false
	if room_at(nv, from) == room_at(nv, to):
		return false
	nv._spill_wait[v] = {"kind": kind, "from": from, "to": to, "s": s, "h": null, "phase": 0, "done": false, "t": 0.0}
	_log("held %s %d: chamber %d -> %d" % [kind, v, room_at(nv, from), room_at(nv, to)])
	nv._placed[v].wait = true
	return true


## Each frame: nurses sent for what waits, picked up at its pile, carried, set down - then shown (the brood laid out again).
static func step(nv, dt: float) -> void:
	if nv._spill_wait.is_empty():
		return
	var busy := 0
	for v in nv._spill_wait:
		if nv._spill_wait[v].h != null:
			busy += 1
	for v in nv._spill_wait.keys():
		var w: Dictionary = nv._spill_wait[v]
		w.t += dt
		var h = w.h
		if h != null and (not nv._mates.has(h) or (w.phase < 2 and not h.has("deliver") and not w.done)
				or (w.phase == 2 and not h.has("script"))):
			w.h = null                     # (taken for something else, or gone out: another nurse)
			h = null
			busy -= 1
		if w.t > GIVE_UP or not nv._placed.has(v):
			_log("gave up %s %d after %.1f s (phase %d)" % [w.kind, v, w.t, w.phase])
			_end(nv, v, h)
			continue
		if h == null:
			if busy >= MAX_CARRIERS:
				continue
			h = _nurse_near(nv, w.from)
			if h == null:
				continue
			busy += 1
			w.h = h
			w.phase = 0
			w.done = false
			h.deliver = w                  # (nest_mates._arrive sets done: at the pile, then where it goes)
			h.goal = room_at(nv, w.from)
			h.rest = 0
			h.wander = 0
		elif w.done and w.phase == 0:
			w.phase = 1                    # at the pile: up with it, off to its chamber
			_log("picked up %s %d by worker #%d" % [w.kind, v, int(h.get("wid", -1))])
			w.done = false
			h.deliver = w
			h.carry = true
			h.item = "cocoon" if w.kind == "pupae" else ""
			h.load_s = w.s
			h.goal = room_at(nv, w.to)
			h.rest = 0
			h.wander = 0
		elif w.done and w.phase == 1:
			# in its chamber: on across the floor to where it lies, the load held out in front, and set down there; when the
			# way in is blocked (the brood heaped by the entrance: it stops on the wall there, 1.4-2 voxels up) it is shown
			# where it lies, 2-7 voxels off - as a pile moved by the "carry" nurses is (nest_mates)
			var at: Vector3 = h.get("vp", Vector3(h.cell))
			var dir: Vector3 = ((w.to as Vector3) - at) * Vector3(1, 0, 1)
			if dir.length_squared() < 0.01 or not nv._open_walk(at, w.to):
				_log("carried %s %d in %.1f s, no way on: %.1f voxels from where it lies" % [w.kind, v, w.t, at.distance_to(w.to)])
				_end(nv, v, null)          # (no straight way on: shown where it lies)
				continue
			dir = dir.normalized()
			w.phase = 2
			nv._hire(h, (w.to as Vector3) - dir * (1.35 if w.kind == "pupae" else 1.0) * float(w.s), (w.to as Vector3) + dir * 3.0, nv.ACT_CARRY)
			h.carry = true
			h.item = "cocoon" if w.kind == "pupae" else ""
			h.load_s = w.s
		elif w.phase == 2:
			var at: Vector3 = (h.script.pos as Vector3) - Vector3(0, 0.45, 0)
			if nv._flat_d(at, h.script.goal) < 0.3:
				_log("carried %s %d in %.1f s, set down %.1f voxels from where it lies" % [w.kind, v, w.t, at.distance_to(w.to)])
				_end(nv, v, h)             # set down just in front of its head


static func _end(nv, v: int, h) -> void:
	if h != null and nv._mates.has(h):
		h.erase("deliver")
		h.carry = false
		h.item = ""
		nv._release(h)                 # (off its walk to the spot, if it was on one)
	nv._spill_wait.erase(v)
	if nv._placed.has(v):
		nv._placed[v].erase("wait")
	nv._brood_sig = []                 # (laid out again: shown now)


## (dev: SPILL_LOG=1 prints each item held, carried or given up)
static func _log(t: String) -> void:
	if OS.has_environment("SPILL_LOG"):
		print("spill: ", t)


## A nurse (or an ant resting) free to go, the nearest to p; null if none.
static func _nurse_near(nv, p: Vector3):
	var best = null
	var bd := INF
	for m in nv._mates:
		if not m.get("role", "") in ["nurse", "idle"] or m.has("script") or m.has("deliver") or m.get("carry", false) \
				or m.get("leaving", false):
			continue
		var d := Vector3(m.cell).distance_squared_to(p)
		if d < bd:
			bd = d
			best = m
	return best


## The chamber (index in nv._rooms) whose floor is nearest p.
static func room_at(nv, p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in nv._rooms.size():
		for q in nv._rooms[i].spots:
			var d := p.distance_squared_to(q)
			if d < bd:
				bd = d
				best = i
	return best
