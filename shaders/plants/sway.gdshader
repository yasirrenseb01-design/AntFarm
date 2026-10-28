shader_type spatial;
render_mode diffuse_burley, cull_disabled;
// Plants and litter that move in the air: vertex colour alpha says how far each point may bend
// (0 = rooted, 1 = a grass tip). The gusts drift across the box as a travelling wave.

uniform float wind = 0.4;
uniform bool srgb_colors = true;     // vertex colours authored in sRGB (meshes) or already linear (grass)
uniform float roughness_v = 0.75;
uniform vec3 backlight = vec3(0.25, 0.3, 0.12);
uniform float wither = 0.0;          // 0 green .. 1 winter-dead straw (outdoors, in the cold months)
uniform float frost = 0.0;           // hoarfrost on cold mornings
uniform bool leaf_veins = false;
#include "res://shaders/plants/brush.gdshaderinc"     // fallen leaves: UV = (stalk to tip 0..1, across -1..1) - midrib, side veins, browned edge

void vertex() {
	float f = COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = TIME * 1.6 + wp.x * 0.06 + wp.z * 0.045;
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + wp.x * 0.012);
	vec3 off = vec3(sin(ph), 0.3 * sin(ph * 2.3 + 1.0), 0.55 * cos(ph * 0.8 + wp.z * 0.04)) * wind * gust * f;
	off.y -= wither * f * f * 1.2;      // dead blades flop over
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off * (1.0 - 0.5 * wither);
	// brushed by ants: blades and stalks by how far they bend; a fallen leaf only pressed down and stirred a little
	vec3 b = leaf_veins ? brushed(wp, 0.3) * vec3(0.15, 1.0, 0.15) : brushed(wp, f);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * b;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (srgb_colors) {
		c = pow(c, vec3(2.2));
	}
	// green leaves fade to straw and brown (only the green parts: stems, aphids and soil keep their colour)
	float green = clamp((c.g - max(c.r, c.b)) * 6.0, 0.0, 1.0);
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(c, vec3(l * 1.45, l * 1.05, l * 0.55), wither * green);
	c = mix(c, vec3(0.75, 0.8, 0.85), frost * 0.55 * smoothstep(0.0, 0.6, NORMAL.y * 0.5 + 0.5));
	if (leaf_veins) {
		vec2 q = UV;
		float mid = 1.0 - smoothstep(0.025, 0.07, abs(q.y));
		float f = fract((q.x - abs(q.y) * 0.32) * 8.5);
		float side = smoothstep(0.86, 0.95, f) * (1.0 - smoothstep(0.8, 0.98, abs(q.y))) * step(0.06, q.x);
		float spot = smoothstep(0.62, 0.8, fract(sin(dot(floor(q * vec2(26.0, 9.0)), vec2(12.9898, 78.233))) * 43758.5453));
		c *= 1.0 + 0.38 * mid + 0.2 * side;                                  // (the veins dry paler than the blade)
		c *= mix(1.0, 0.68, smoothstep(0.72, 1.0, abs(q.y)) + 0.3 * smoothstep(0.85, 1.0, q.x));   // browned edges and tip
		c *= 1.0 - 0.18 * spot;                                             // blotches
	}
	ALBEDO = c;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.35;
	BACKLIGHT = backlight * (1.0 - 0.7 * wither);     // thin leaves glow a little with the sun behind them
}
