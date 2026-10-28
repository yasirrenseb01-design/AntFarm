// Height of the 3D outworld floor, shared by the ground and the creatures that walk on it.
// Must match OutworldView.ground_h() (scripts/view/outworld/parts/outworld_scene.gd).
uniform vec2 nest_xz = vec2(160.0, 133.3);
uniform float mound_h = 0.5;
uniform float mound_r = 4.0;

float ground_h(vec2 p) {
	// (v0.11.71, the keeper: "a little more up and down" - broad swells up to ~1 cm, smaller rises and dips between;
	// it was +-2 mm)
	float h = 3.6 * sin(p.x * 0.017 + 1.3) * cos(p.y * 0.023 + 0.4) + 1.6 * sin(p.x * 0.049 + p.y * 0.037 + 2.0)
		+ 0.6 * sin(p.x * 0.13 + 0.7) * sin(p.y * 0.11 + 1.9);
	float d = length(p - nest_xz);
	float k = (d - mound_r) / (mound_r * 0.6);
	h += mound_h * exp(-k * k) + mound_h * 0.5 * (1.0 - smoothstep(0.0, mound_r, d));
	h -= 1.6 * (1.0 - smoothstep(0.6, 1.9, d));
	return h;
}

// A long body (a centipede, a spider's legs) follows the ground under every part of it: the instance is
// tilted to the slope under its middle, so each vertex is moved by how far the real floor under it
// differs from that tilted plane.
vec3 follow_ground(vec3 v, mat4 M) {
	vec3 w = (M * vec4(v, 1.0)).xyz;
	vec3 o = M[3].xyz;
	vec3 n = normalize(M[1].xyz);
	n *= sign(n.y);                      // a body lying on its back is turned over: its up is the floor's
	float plane = ground_h(o.xz) - (n.x * (w.x - o.x) + n.z * (w.z - o.z)) / max(n.y, 0.2);
	float dy = ground_h(w.xz) - plane;
	return v + inverse(mat3(M)) * vec3(0.0, dy, 0.0);
}
