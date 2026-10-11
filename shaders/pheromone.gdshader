shader_type canvas_item;
// Softens the coarse pheromone grid so trails read as a faint haze on the soil, not pixel steps.

vec4 tap(sampler2D tex, vec2 uv, float w) {
	vec4 s = texture(tex, uv);
	return vec4(s.rgb * s.a, s.a) * w;   // premultiply so empty cells don't tint the blend
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * 0.8;
	vec4 c = tap(TEXTURE, UV, 0.28);
	c += tap(TEXTURE, UV + vec2(px.x, 0.0), 0.12);
	c += tap(TEXTURE, UV - vec2(px.x, 0.0), 0.12);
	c += tap(TEXTURE, UV + vec2(0.0, px.y), 0.12);
	c += tap(TEXTURE, UV - vec2(0.0, px.y), 0.12);
	c += tap(TEXTURE, UV + px, 0.06);
	c += tap(TEXTURE, UV - px, 0.06);
	c += tap(TEXTURE, UV + vec2(px.x, -px.y), 0.06);
	c += tap(TEXTURE, UV + vec2(-px.x, px.y), 0.06);
	COLOR = vec4(c.rgb / max(c.a, 0.001), smoothstep(0.0, 0.85, c.a) * 0.85);
}
