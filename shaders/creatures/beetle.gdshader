shader_type spatial;
render_mode diffuse_burley;
// Ground beetle (see tools/blender/build_props.py ground_beetle()). COLOR.a = part id / 16:
// 0 body, 1 head, 2/3 antennae, 4-9 legs (FL, FR, ML, MR, HL, HR), 10 mandibles.
// Legs: jointed, their feet set down and left where they are while the body goes over them, in alternating tripods
// (leg_ik.gdshaderinc; UV.x = the leg's piece; the joints come from the model's .json). Antenna bases (7.7, 3.6, 0.72 * side),
// mandibles (8.2, 3.1, 0.6 * side) - tools/blender/props/beetle.py (the body raised BE_UP = 0.65 there).
// INSTANCE_CUSTOM: x = gait phase (one turn = a stride of ground covered), y = 1 striking (mandibles snap, abdomen raised to spray) /
// 2 dead (legs drawn up; the view lays it on its back), z = clock, w = unused here (+2 held).
// The armour is black with a violet-blue metallic sheen that shows at grazing angles.

varying float shell;
varying vec3 obj;      // the point on the model at rest (the elytra's rows of granules)

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

#include "res://shaders/terrain/ground_h.gdshaderinc"
#include "res://shaders/creatures/leg_ik.gdshaderinc"

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float state = INSTANCE_CUSTOM.y;
	float t = INSTANCE_CUSTOM.z;
	bool dead = state > 1.5;
	shell = part <= 1.0 ? 1.0 : 0.0;
	obj = VERTEX;
	if (part >= 4.0 && part <= 9.0) {
		int i = int(part) - 4;
		float li = floor((part - 4.0) / 2.0);
		float side = mod(part - 4.0, 2.0) < 0.5 ? -1.0 : 1.0;
		// alternating tripods: front and hind of one side with the middle of the other
		float grp = ((mod(li, 2.0) < 0.5) == (side < 0.0)) ? 0.0 : 0.5;
		vec3 a = leg_ankle(i, gait / TAU + grp, 1.0);     // (standing still the legs stay as they were in the step)
		if (dead) {
			// on its back: the legs drawn in over the belly, the feet up
			a = vec3(hip[i].x * 0.9 + 0.3, hip[i].y - 3.0, 3.0 * side);     // (tried with tools/dev/leg_clip.py: 0.27% of the legs in the body)
		}
		leg_place(i, UV.x, a, VERTEX, NORMAL);
	} else if (part == 2.0 || part == 3.0) {
		float side = part == 2.0 ? -1.0 : 1.0;
		vec3 piv = vec3(7.7, 3.6, 0.72 * side);
		float a = sin(t * 2.6 + side) * 0.18 + (dead ? -0.4 : 0.0);
		mat3 R = rot_y(a * side) * rot_z(0.08 * sin(t * 1.9 + side));
		VERTEX = piv + R * (VERTEX - piv);
		NORMAL = R * NORMAL;
	} else if (part == 10.0) {
		float side = VERTEX.z < 0.0 ? -1.0 : 1.0;
		float open = state > 0.5 && !dead ? 0.05 + 0.3 * max(0.0, sin(t * 14.0)) : 0.25;
		vec3 piv = vec3(8.2, 3.1, 0.6 * side);
		mat3 R = rot_y(open * side);
		VERTEX = piv + R * (VERTEX - piv);
		NORMAL = R * NORMAL;
	}
	if (state > 0.5 && !dead && part == 0.0 && VERTEX.x < -4.0) {
		VERTEX.y += (-4.0 - VERTEX.x) * 0.12;      // abdomen tip raised to spray
	}
	VERTEX = follow_ground(VERTEX, MODEL_MATRIX);     // every part of the body stands on the floor under it
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = mix(base, vec3(0.05, 0.05, 0.16), fres * 0.18 * shell);    // (black: a faint violet-blue at grazing angles - v0.12.33: at 0.45 the whole beetle read violet)
	METALLIC = 0.12 * shell;
	ROUGHNESS = mix(0.5, 0.4, shell);
	if (shell > 0.5 && obj.x < 2.1 && obj.y > 3.3) {
		// elytra: lengthwise rows of fine granules (Carabus violaceus: "almost smooth, fine granules in indistinct lines")
		float row = smoothstep(0.82, 0.97, abs(sin(obj.z * 7.5)));
		float bead = 0.5 + 0.5 * sin(obj.x * 16.0 + floor(obj.z * 7.5 / PI) * 1.7);
		float g = row * (0.55 + 0.45 * bead);
		ALBEDO *= 1.0 - 0.6 * g;
		ROUGHNESS = mix(ROUGHNESS, 0.55, g);
	}
	SPECULAR = 0.4;
}
