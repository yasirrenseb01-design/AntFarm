shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Nest soil. A vertical cut plane facing the camera slices the block open; where the cut passes
// through solid soil we see back faces, which are shaded as the flat cut surface (a "cap").

uniform vec4 cut_plane = vec4(0.0, 0.0, 1.0, 100000.0);   // xyz = normal toward the camera, w = offset
uniform float top_y = 72.0;
uniform float humidity = 0.6;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform sampler3D vol : filter_linear;      // soil density per voxel (1 = solid)
uniform vec3 vol_size = vec3(64.0, 72.0, 64.0);

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
	vec3 c = mix(loam, clay, smoothstep(11.0, 17.0, depth + wob));
	c = mix(c, sand, smoothstep(37.0, 45.0, depth + wob));
	float g = tri(p, n, 0.06);
	float f = tri(p, n, 0.55);
	c *= 0.72 + 0.56 * g;
	c *= 0.82 + 0.36 * f;
	c = mix(c, vec3(0.78, 0.7, 0.58), smoothstep(0.8, 0.93, f) * 0.6);     // pale grains and grit
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
		vec3 ro = CAMERA_POSITION_WORLD;
		vec3 rd = normalize(w - ro);
		float t = (cut_plane.w - dot(pn, ro)) / dot(pn, rd);
		p = ro + rd * t;
		// where the plane passes through open tunnel there is no cap: look inside instead
		if (texture(vol, (p + 0.5) / vol_size).r < 0.5) {
			discard;
		}
		n = pn;
		NORMAL = -normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);   // Godot flips back-face normals after this
		ALBEDO = soil(p, n) * 1.05;
		// put the cap at the cut plane in the depth buffer so ants behind solid soil stay hidden
		vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
		DEPTH = clip.z / clip.w;
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
