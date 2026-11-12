// The litter and small stones on the outworld floor under a creature (v0.13.4, the keeper 2026-11-12: "it walks
// through things - let it climb the stones, walk over the leaves"): the same height grid the ants walk up over
// (view/outworld/prop_heights.gd, handed over by outworld_props as for the ant shader). The body is lifted by the
// highest litter under its middle and front and back; each foot is set on the litter (or the ground) under it, the leg
// stretching between. Call after follow_ground(), with `leg` 1 on a leg's vertices (0 on the body) and its height in
// the model at rest (`rest_y`). A body on its back is left as it is.

uniform sampler2D prop_tex : filter_linear;
uniform vec2 prop_size = vec2(1.0);
uniform float has_props = 0.0;

// follow_ground() (each vertex onto the floor under it, by the body's up) faded out while the body is on its side,
// rolling over: there its up is near level and the sums threw the vertices far up and down - the body looked
// stretched as it turned over (v0.13.6, the keeper 2026-11-13)
vec3 follow_ground_soft(vec3 v, mat4 M) {
	float up = abs(normalize(M[1].xyz).y);
	return mix(v, follow_ground(v, M), smoothstep(0.6, 0.95, up));
}

float prop_at(vec2 xz) {
	return has_props > 0.5 ? texture(prop_tex, xz / prop_size).r : 0.0;
}

// half_len: half the body's length in the model (the front and back samples)
vec3 on_props(vec3 v, mat4 M, float leg, float rest_y, float half_len) {
	if (has_props < 0.5 || M[1].y < 0.0) {
		return v;
	}
	vec3 o = M[3].xyz;
	vec3 fwd = M[0].xyz;
	float lift = max(prop_at(o.xz), max(prop_at(o.xz + fwd.xz * half_len), prop_at(o.xz - fwd.xz * half_len)));
	float dy = lift;
	if (leg > 0.5) {
		vec3 w = (M * vec4(v, 1.0)).xyz;
		float foot = 1.0 - smoothstep(0.15, 1.6, rest_y);      // (the foot itself on the litter, the knee with the body)
		dy = mix(lift, prop_at(w.xz), foot);
	}
	return v + inverse(mat3(M)) * vec3(0.0, dy, 0.0);
}
