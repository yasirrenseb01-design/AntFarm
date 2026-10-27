shader_type spatial;
// The Home's walls and ceiling (the keeper, 2026-10-28: "it looks like a game from the early 2000s"): a flat colour with
// the soft dimming real rooms have where two surfaces meet - into the corners, along the floor and the ceiling - that
// the mobile renderer has no ambient occlusion for; and a faint plaster texture. Positions in the room's own metres
// (to_room: the room drawn scaled round a box in the game, keeper_room.gd).

uniform vec3 albedo : source_color = vec3(0.9, 0.82, 0.69);
uniform float rough = 0.92;
uniform vec2 room = vec2(4.0, 2.6);      // the room's width (x and z) and height
uniform mat4 to_room = mat4(1.0);
varying vec3 rp;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() { rp = (to_room * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float hw = room.x * 0.5;
	float dw = min(hw - abs(rp.x), hw - abs(rp.z));       // to the nearest wall
	float df = rp.y;                                      // to the floor
	float dc = room.y - rp.y;                             // to the ceiling
	// a surface lying in a wall is near "a wall" at 0: what counts is the other ones it meets
	float on_wall = 1.0 - step(0.02, dw);
	float wall2 = on_wall > 0.5 ? (hw - min(abs(rp.x), abs(rp.z))) : dw;      // (on a wall: the corner, the other wall)
	float occ = 0.22 * (1.0 - smoothstep(0.0, 0.5, wall2)) + 0.18 * (1.0 - smoothstep(0.0, 0.35, df))
		+ 0.14 * (1.0 - smoothstep(0.0, 0.4, dc));
	float plaster = vn(rp.xy * 40.0 + rp.zz * 40.0) * 0.5 + vn(rp.xz * 9.0 + rp.yy * 9.0) * 0.5;
	ALBEDO = albedo * (1.0 - clamp(occ, 0.0, 0.45)) * (0.97 + 0.06 * plaster);
	ROUGHNESS = rough;
}
