extends RefCounted
## Surface-nets mesher for the nest soil, one 16³ chunk at a time.
## Voxel centres sit on integer coordinates; one mesh unit = one voxel (1.5 mm).

const CH := 16
# corner i of a cube: bit0 = +x, bit1 = +y, bit2 = +z
const EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]


static func build(nest, k: Vector3i) -> ArrayMesh:
	var o := k * CH
	var S := CH + 3                       # density samples from o-1 .. o+CH+1
	var dens := PackedFloat32Array()
	dens.resize(S * S * S)
	var any_air := false
	var any_solid := false
	for z in S:
		for y in S:
			for x in S:
				var v: float = nest.density(o.x + x - 1, o.y + y - 1, o.z + z - 1)
				dens[(z * S + y) * S + x] = v
				if v >= 0.5:
					any_solid = true
				else:
					any_air = true
	if not (any_air and any_solid):
		return null

	var C := S - 1
	var vid := PackedInt32Array()
	vid.resize(C * C * C)
	vid.fill(-1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var pinned := PackedByteArray()        # vertices on the chunk's overlap border stay put so chunks meet
	var cd := PackedFloat32Array()
	cd.resize(8)
	var base := Vector3(o) - Vector3.ONE
	for z in C:
		for y in C:
			for x in C:
				var mask := 0
				for i in 8:
					var v := dens[((z + (i >> 2)) * S + (y + ((i >> 1) & 1))) * S + x + (i & 1)]
					cd[i] = v
					if v >= 0.5:
						mask |= 1 << i
				if mask == 0 or mask == 255:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in EDGES:
					var a: int = e[0]
					var b: int = e[1]
					if (cd[a] >= 0.5) != (cd[b] >= 0.5):
						var t := (0.5 - cd[a]) / (cd[b] - cd[a])
						var pa := Vector3(a & 1, (a >> 1) & 1, a >> 2)
						var pb := Vector3(b & 1, (b >> 1) & 1, b >> 2)
						acc += pa.lerp(pb, t)
						cnt += 1
				var gx := (cd[1] + cd[3] + cd[5] + cd[7]) - (cd[0] + cd[2] + cd[4] + cd[6])
				var gy := (cd[2] + cd[3] + cd[6] + cd[7]) - (cd[0] + cd[1] + cd[4] + cd[5])
				var gz := (cd[4] + cd[5] + cd[6] + cd[7]) - (cd[0] + cd[1] + cd[2] + cd[3])
				vid[(z * C + y) * C + x] = verts.size()
				verts.append(base + Vector3(x, y, z) + acc / cnt)
				# cubes shared with a neighbouring chunk (two on each side) are pinned in both, so seams match
				pinned.append(1 if (x <= 1 or y <= 1 or z <= 1 or x >= C - 2 or y >= C - 2 or z >= C - 2) else 0)
				norms.append(-Vector3(gx, gy, gz).normalized())

	var tris := PackedInt32Array()
	for z in range(1, CH + 1):
		for y in range(1, CH + 1):
			for x in range(1, CH + 1):
				var s0 := dens[(z * S + y) * S + x] >= 0.5
				# edge along +x: shared by cubes (x, y-1..y, z-1..z)
				if (dens[(z * S + y) * S + x + 1] >= 0.5) != s0:
					_quad(tris, verts, vid, C, Vector3(1 if s0 else -1, 0, 0),
						Vector3i(x, y - 1, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x, y - 1, z))
				if (dens[(z * S + y + 1) * S + x] >= 0.5) != s0:
					_quad(tris, verts, vid, C, Vector3(0, 1 if s0 else -1, 0),
						Vector3i(x - 1, y, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x - 1, y, z))
				if (dens[((z + 1) * S + y) * S + x] >= 0.5) != s0:
					_quad(tris, verts, vid, C, Vector3(0, 0, 1 if s0 else -1),
						Vector3i(x - 1, y - 1, z), Vector3i(x, y - 1, z), Vector3i(x, y, z), Vector3i(x - 1, y, z))
	if tris.is_empty():
		return null
	var relaxed := _relax(verts, norms, tris, pinned, base)   # packed arrays are copied: take the results back
	verts = relaxed[0]
	norms = relaxed[1]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = tris
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _quad(tris: PackedInt32Array, verts: PackedVector3Array, vid: PackedInt32Array, C: int, n: Vector3,
		a: Vector3i, b: Vector3i, c: Vector3i, d: Vector3i) -> void:
	var ia := vid[(a.z * C + a.y) * C + a.x]
	var ib := vid[(b.z * C + b.y) * C + b.x]
	var ic := vid[(c.z * C + c.y) * C + c.x]
	var id := vid[(d.z * C + d.y) * C + d.x]
	if ia < 0 or ib < 0 or ic < 0 or id < 0:
		return
	# Godot treats clockwise triangles as front faces; the front must face the open side (n)
	var cr := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
	if cr.dot(n) < 0.0:
		tris.append_array([ia, ib, ic, ia, ic, id])
	else:
		tris.append_array([ia, ic, ib, ia, id, ic])


## Smooth the dug surfaces: pull each vertex toward the average of its mesh neighbours, kept inside
## its own voxel cell, so tunnels read as rounded burrows instead of stair-stepped blocks.
static func _relax(verts: PackedVector3Array, norms: PackedVector3Array, tris: PackedInt32Array,
		pinned: PackedByteArray, base: Vector3) -> Array:
	var n := verts.size()
	var nbr: Array = []
	nbr.resize(n)
	for i in n:
		nbr[i] = PackedInt32Array()
	for k in range(0, tris.size(), 3):
		var a := tris[k]
		var b := tris[k + 1]
		var c := tris[k + 2]
		nbr[a].append_array([b, c])
		nbr[b].append_array([a, c])
		nbr[c].append_array([a, b])
	var home := PackedVector3Array()          # each vertex keeps near the voxel cell it was made in
	home.resize(n)
	for i in n:
		home[i] = (verts[i] - base).floor()
	for it in 4:
		var out := verts.duplicate()
		for i in n:
			if pinned[i] == 1:
				continue
			var ns: PackedInt32Array = nbr[i]
			if ns.is_empty():
				continue
			var avg := Vector3.ZERO
			for j in ns:
				avg += verts[j]
			avg /= ns.size()
			var cell := home[i]
			out[i] = verts[i].lerp(avg, 0.5).clamp(base + cell - Vector3.ONE * 0.35, base + cell + Vector3.ONE * 1.35)
		verts = out
	# shading normals from the smoothed surface itself
	var acc := PackedVector3Array()
	acc.resize(n)
	acc.fill(Vector3.ZERO)
	for k in range(0, tris.size(), 3):
		var a := tris[k]
		var b := tris[k + 1]
		var c := tris[k + 2]
		var fnorm := (verts[c] - verts[a]).cross(verts[b] - verts[a])
		acc[a] += fnorm
		acc[b] += fnorm
		acc[c] += fnorm
	for i in n:
		if pinned[i] == 0 and acc[i].length_squared() > 0.0:
			norms[i] = acc[i].normalized() if acc[i].dot(norms[i]) >= 0.0 else -acc[i].normalized()
	return [verts, norms]
