shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Nest soil. A vertical cut plane facing the camera slices the block open; where the cut passes
// through solid soil we see back faces, which are shaded as the flat cut surface (a "cap").

uniform vec4 cut_plane = vec4(0.0, 0.0, 1.0, 100000.0);   // xyz = normal toward the camera, w = offset
uniform float top_y = 72.0;
uniform float humidity = 0.6;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform sampler3D vol : filter_linear;      // soil voxels (1 = solid)
uniform vec3 vol_size = vec3(64.0, 72.0, 64.0);
uniform vec3 vol_org = vec3(0.0);           // the voxel the volume starts at (a deep garden nest: below y = 0)
// what is in the soil (nest_voxels.gd soil): stones (xyz, radius) and roots (a.xyz, radius; b.xyz), voxel units, and
// where the clay and the sand start (voxels below the top)
uniform int n_stones = 0;
uniform vec4 stones[24];
uniform int n_roots = 0;
uniform vec4 roots_a[4];
uniform vec4 roots_b[4];
uniform float clay_top = 14.0;
uniform float sand_top = 41.0;

// The soil as the mesher sees it (nest_voxels.gd density()): each voxel solid or open, softened with its six
// neighbours - from the interpolated voxels (7 samples; close to interpolating the softened ones).
float raw(vec3 p) {
	vec3 q = p - vol_org;
	if (any(lessThan(q, vec3(-0.5))) || any(greaterThan(q, vol_size - 0.5))) {
		return 0.0;                     // outside the block counts as open
	}
	return texture(vol, (q + 0.5) / vol_size).r;
}
float soft(vec3 p) {
	float r = raw(p);
	float n = raw(p + vec3(1, 0, 0)) + raw(p - vec3(1, 0, 0)) + raw(p + vec3(0, 1, 0))
		+ raw(p - vec3(0, 1, 0)) + raw(p + vec3(0, 0, 1)) + raw(p - vec3(0, 0, 1));
	return mix(0.05 * n, 0.4 + 0.1 * n, r);     // (soil softened 0.1 per open neighbour, open space 0.05 per solid one)
}

varying vec3 w;
varying vec3 wn;

void vertex() {
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(vec3 p, vec3 n, float s) {
	vec3 b = abs(n) + 0.001;
	b /= (b.x + b.y + b.z);
	return texture(grain, p.zy * s).r * b.x + texture(grain, p.xz * s).r * b.y + texture(grain, p.xy * s).r * b.z;
}

vec3 soil(vec3 p, vec3 n) {
	float depth = top_y - p.y;
	float wob = sin(p.x * 0.11) * 1.6 + sin(p.z * 0.07 + 1.3) * 1.4 + (texture(grain, p.xz * 0.02).r - 0.5) * 4.0;
	vec3 loam = vec3(0.30, 0.20, 0.12);
	vec3 clay = vec3(0.62, 0.38, 0.22);
	vec3 sand = vec3(0.80, 0.66, 0.45);
	vec3 c = mix(loam, clay, smoothstep(clay_top - 3.0, clay_top + 3.0, depth + wob));
	c = mix(c, sand, smoothstep(sand_top - 4.0, sand_top + 4.0, depth + wob));
	float g = tri(p, n, 0.06);
	float f = tri(p, n, 0.55);
	c *= 0.72 + 0.56 * g;
	c *= 0.82 + 0.36 * f;
	c = mix(c, vec3(0.78, 0.7, 0.58), smoothstep(0.8, 0.93, f) * 0.6);     // pale grains and grit
	// a stone or a root where the wall or the cut meets one (the voxels round them are left undug)
	for (int i = 0; i < n_stones; i++) {
		vec4 s = stones[i];
		float lump = (texture(grain, (p.xy + p.zx) * 0.11 + float(i) * 0.17).r - 0.5) * 1.1;
		float d = length(p - s.xyz) - s.w - lump;
		if (d < 0.6) {
			// a pebble: grey to buff, speckled, a darker rim where the soil meets it
			float tone = fract(sin(float(i) * 12.9898) * 43758.5453);
			vec3 rock = mix(vec3(0.48, 0.47, 0.45), vec3(0.72, 0.66, 0.56), tone);
			float speck = tri(p, n, 1.3);
			rock *= 0.82 + 0.3 * g + 0.25 * smoothstep(0.6, 0.85, speck) - 0.2 * smoothstep(0.3, 0.1, speck);
			rock *= mix(1.0, 0.72, smoothstep(-0.35, 0.05, d));
			c = mix(rock / mix(1.15, 0.8, humidity), c, smoothstep(0.02, 0.22, d));    // (not darkened with the damp soil)
		}
	}
	for (int i = 0; i < n_roots; i++) {
		vec3 a = roots_a[i].xyz;
		vec3 ab = roots_b[i].xyz - a;
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.001), 0.0, 1.0);
		float d = length(p - (a + ab * t)) - roots_a[i].w;
		if (d < 0.6) {
			float streak = 0.8 + 0.3 * sin(t * length(ab) * 3.0 + f * 4.0);
			vec3 root = vec3(0.42, 0.27, 0.15) * streak * (0.8 + 0.4 * f);
			c = mix(root, c, smoothstep(0.1, 0.6, d));
		}
	}
	c *= mix(1.15, 0.8, humidity);                                          // damp soil is darker
	// leaf litter and moss on the very top of the block
	if (n.y > 0.6 && depth < 1.2) {
		float moss = smoothstep(0.55, 0.75, tri(p, n, 0.04));
		c = mix(vec3(0.27, 0.19, 0.11) * (0.8 + 0.4 * f), vec3(0.24, 0.33, 0.13), moss);
	}
	return c;
}

void fragment() {
	vec3 pn = cut_plane.xyz;
	if (dot(pn, w) > cut_plane.w) {
		discard;
	}
	vec3 p = w;
	vec3 n = wn;
	if (!FRONT_FACING) {
		// looking at the inside of the soil: the cut face. Where the cut passes through solid soil it is put at the
		// cut in the depth buffer, so nothing inside the soil behind it shows through (an ant's leg or gaster in a
		// wall, an ant in a tunnel behind). Where the voxels say open it is not discarded (that left a dark gap
		// where the smoothed soil surface curves into a wall, between the floor and the face): it stays at its own
		// depth, so in the open it is only seen where no tunnel wall is in front of it - in that gap.
		vec3 ro = CAMERA_POSITION_WORLD;
		vec3 rd = normalize(w - ro);
		float t = (cut_plane.w - dot(pn, ro)) / dot(pn, rd);
		p = ro + rd * t;
		n = pn;
		NORMAL = -normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);   // Godot flips back-face normals after this
		ALBEDO = soil(p, n) * 1.05;
		if (soft(p) >= 0.5) {
			vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
			DEPTH = clip.z / clip.w;
		} else {
			DEPTH = FRAGCOORD.z;
		}
	} else {
		// tunnel walls are packed smooth by the ants: a touch darker and less grainy
		vec3 c = soil(p, n);
		float wall = smoothstep(0.4, -0.2, n.y) * step(top_y - p.y, top_y - 0.5);
		ALBEDO = mix(c, c * 0.78, wall * 0.5);
		DEPTH = FRAGCOORD.z;
	}
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
