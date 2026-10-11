shader_type spatial;
render_mode diffuse_burley;
// Wolf spider walk (see MeshKit.spider): COLOR.a = part id (0 body, 1-4 left legs, 5-8 right legs).
// INSTANCE_CUSTOM: x = gait phase, y = 1 while striking (2 = dead, legs curled), z = clock,
// w = how much it is walking.

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float strike = INSTANCE_CUSTOM.y;
	float t = INSTANCE_CUSTOM.z;
	float mv = INSTANCE_CUSTOM.w;
	if (part >= 1.0) {
		float li = mod(part - 1.0, 4.0);
		float side = part < 4.5 ? -1.0 : 1.0;
		// alternating tetrapods: L1 R2 L3 R4 against R1 L2 R3 L4
		float grp = mod(li + (side < 0.0 ? 0.0 : 1.0), 2.0) * PI;
		float ph = gait + grp;
		float sw = sin(ph) * 0.3 * mv + 0.03 * sin(t * 0.8 + li) * (1.0 - mv);
		float lift = max(0.0, cos(ph)) * 0.35 * mv;
		if (strike > 0.5 && strike < 1.5 && li < 1.5) {   // front legs raised to grab
			lift = 0.6 + 0.2 * sin(t * 8.0);
		}
		if (strike > 1.5) {                        // dead: legs curled in over the body
			sw = 0.25 * (1.5 - li);
			lift = -1.3;
		}
		vec3 piv = vec3(2.4 - li * 0.75, 1.9, 0.9 * side);
		mat3 R = rot_y(sw * side) * rot_x(-lift * side);
		VERTEX = piv + R * (VERTEX - piv);
		NORMAL = R * NORMAL;
	} else {
		VERTEX.y += 0.08 * sin(gait * 2.0) * mv;    // body bobs with the stride
	}
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));    // vertex colours are authored in sRGB
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	RIM = 0.4;
	RIM_TINT = 0.7;
}
