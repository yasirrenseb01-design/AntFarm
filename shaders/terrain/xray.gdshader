shader_type spatial;
render_mode cull_back, diffuse_burley;
// "See into the soil", dollhouse style: every tunnel and chamber is drawn with its real earthen
// walls, but only the walls on the far side of each opening (the ones facing the camera) — the near
// walls and the block's outer skin are left out, so you look straight into every room at once.

uniform vec3 box_max = vec3(63.0, 71.0, 63.0);   // voxel centre of the far corner
uniform float box_min_y = 0.0;                   // the lowest layer of the soil held (a deep garden nest: below 0)
uniform float top_y = 71.0;
uniform float humidity = 0.6;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;

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
	c *= 0.72 + 0.56 * tri(p, n, 0.06);
	float f = tri(p, n, 0.55);
	c *= 0.82 + 0.36 * f;
	c = mix(c, vec3(0.78, 0.7, 0.58), smoothstep(0.8, 0.93, f) * 0.6);
	c *= mix(1.15, 0.8, humidity);
	return c;
}

void fragment() {
	// the block's outer skin sits half a voxel outside the outermost voxel centres
	if (w.x < -0.05 || w.z < -0.05 || w.y < box_min_y - 0.05 || w.x > box_max.x + 0.05 || w.z > box_max.z + 0.05
			|| w.y > box_max.y + 0.05) {
		discard;
	}
	vec3 c = soil(w, wn);
	// floors read lighter than ceilings, helping the eye tell up from down inside the rooms
	c *= 0.85 + 0.25 * clamp(wn.y, 0.0, 1.0);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
