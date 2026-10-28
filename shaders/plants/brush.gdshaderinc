// Plants and litter brushed aside by the ants walking through them (the keeper, 2026-10-29: "when ants walk past or
// bump into them, let them move"). The view sends the ants drawn nearest the camera (outworld_creatures.gd
// _brush_ants): a blade, a weed's leaf, a fallen leaf within an ant's reach is pushed away from it, pressed down a
// little and trembles while the ant is in it - the view only, the simulation never sees it.

uniform vec4 ants[32];       // xyz: an ant's drawn middle (world), w: how far its legs reach (0: none)
uniform int ant_n = 0;

vec3 brushed(vec3 wp, float f) {
	vec3 push = vec3(0.0);
	if (f <= 0.002) {
		return push;                 // (a blade's foot: nothing to bend - most of the grass's points, skipped)
	}
	for (int i = 0; i < ant_n; i++) {
		vec4 a = ants[i];
		vec3 d = wp - a.xyz;
		float r = a.w;
		float l2 = d.x * d.x + d.z * d.z;
		if (l2 < r * r && d.y > -r && d.y < 40.0) {          // (a blade's tip far above the ant: it leans with its foot)
			float l = sqrt(l2);
			vec2 dir = l > 0.001 ? d.xz / l : vec2(1.0, 0.0);
			float k = (r - l) / r;
			push.xz += dir * k * r * 0.9;
			push.y -= k * 0.25 * r;
			push.xz += vec2(sin(TIME * 23.0 + float(i) * 1.7), cos(TIME * 19.0 + float(i) * 2.3)) * k * 0.12 * r;
		}
	}
	return push * f;
}
