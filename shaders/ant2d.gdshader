shader_type canvas_item;
// Top-down ant animation. UV.x = body-part id (see ant_batch.gd); INSTANCE_CUSTOM per ant:
//   x = gait phase   y = activity (0 walk, 2 bite/cut, 3 antennate, 9 milk aphids, 10 drink)
//   z = animation clock (s)   w = how much it is walking (0..1)

mat2 rot(float a) { float c = cos(a); float s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

void vertex() {
	float part = floor(UV.x + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float act = floor(INSTANCE_CUSTOM.y + 0.5);
	float t = INSTANCE_CUSTOM.z;
	float mv = INSTANCE_CUSTOM.w;
	vec2 v = VERTEX;
	if (part >= 4.0 && part <= 9.0) {
		// legs swing around the hip in alternating tripods; standing ants shift slightly
		float li = floor((part - 4.0) / 2.0);
		float side = mod(part - 4.0, 2.0) < 0.5 ? -1.0 : 1.0;
		float grp = ((mod(li, 2.0) < 0.5) == (side < 0.0)) ? 0.0 : PI;
		float sw = sin(gait + grp) * 0.32 * mv + 0.03 * sin(t * 1.1 + li * 2.0 + side) * (1.0 - mv);
		if ((act == 2.0 || act == 9.0) && li < 0.5) {
			sw = 0.25 * sin(t * 9.0 + side * 1.6);        // front legs working at the food
		}
		float hipx = li < 0.5 ? 0.85 : (li < 1.5 ? 0.25 : -0.35);
		vec2 piv = vec2(hipx, 0.45 * side);
		v = piv + rot(-sw * side) * (v - piv);
	} else if (part == 2.0 || part == 3.0) {
		// antennae sweep while walking, drum fast on a nestmate, stroke aphids, dab at food
		float side = part == 2.0 ? -1.0 : 1.0;
		float sp = 3.0;
		float amp = 0.22;
		if (act == 3.0) { sp = 13.0; amp = 0.35; }
		if (act == 9.0) { sp = 7.0; amp = 0.4; }
		if (act == 2.0 || act == 10.0) { sp = 5.0; amp = 0.18; }
		vec2 piv = vec2(2.55, 0.45 * side);
		float a = sin(t * sp + side * 1.4) * amp + (act == 3.0 ? -0.15 * side : 0.0);
		v = piv + rot(a) * (v - piv);
	} else if (part == 1.0) {
		// head thrusts while cutting prey, dips while drinking
		if (act == 2.0) v.x += 0.22 * max(0.0, sin(t * 11.0));
		if (act == 10.0) v.x += 0.1 * sin(t * 4.0);
	} else if (part == 10.0) {
		float b = 1.0 + 0.02 * sin(t * 1.7);
		vec2 piv = vec2(-0.8, 0.0);
		v = piv + (v - piv) * b;
	}
	VERTEX = v;
}
