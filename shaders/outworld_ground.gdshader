shader_type spatial;
render_mode diffuse_burley;
// Floor of the 3D outworld box. Uses the same soil, damp-patch and grain textures as the top-down
// view, a fine detail noise for close-ups, the pheromone trails, and the crater of excavated soil
// around the nest entrance. ground_h() must match OutworldView.ground_h() (ants walk on it).

uniform sampler2D soil_tex : source_color, filter_linear_mipmap;
uniform sampler2D damp_tex : source_color, filter_linear_mipmap;
uniform sampler2D grain_tex : source_color, filter_linear_mipmap;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D pher_tex : source_color, filter_linear;
uniform float pher_on = 1.0;
uniform vec2 world_size = vec2(400.0, 250.0);
uniform vec2 nest_xz = vec2(160.0, 133.3);
uniform float mound_h = 0.5;
uniform float mound_r = 4.0;
uniform float wet = 0.0;

varying vec2 wp;

float ground_h(vec2 p) {
	float h = 0.8 * sin(p.x * 0.021 + 1.3) * cos(p.y * 0.027 + 0.4) + 0.45 * sin(p.x * 0.057 + p.y * 0.043 + 2.0);
	float d = length(p - nest_xz);
	float k = (d - mound_r) / (mound_r * 0.6);
	h += mound_h * exp(-k * k) + mound_h * 0.5 * (1.0 - smoothstep(0.0, mound_r, d));
	h -= 1.6 * (1.0 - smoothstep(0.6, 1.9, d));
	return h;
}

void vertex() {
	wp = VERTEX.xz;
	VERTEX.y = ground_h(wp);
	float e = 0.6;
	float hx = ground_h(wp + vec2(e, 0.0)) - ground_h(wp - vec2(e, 0.0));
	float hz = ground_h(wp + vec2(0.0, e)) - ground_h(wp - vec2(0.0, e));
	NORMAL = normalize(vec3(-hx, 2.0 * e, -hz));
}

void fragment() {
	vec2 uv = wp / world_size;
	vec3 c = texture(soil_tex, uv).rgb;
	vec4 d = texture(damp_tex, uv);
	c = mix(c, d.rgb, d.a);
	vec4 g = texture(grain_tex, uv);
	c = mix(c, g.rgb, g.a);
	float det = texture(detail, wp / 9.0).r * 0.6 + texture(detail, wp / 2.3).r * 0.4;
	c *= 0.78 + 0.42 * det;
	// individual sand grains, only resolved when the camera is close
	float fine = texture(detail, wp / 0.55).r;
	float near = 1.0 - smoothstep(30.0, 90.0, length(VERTEX));
	c *= mix(1.0, 0.7 + 0.6 * fine, near);
	// fresh excavated soil on the crater is paler and finer than the surface around it
	float dn = length(wp - nest_xz);
	float m = (1.0 - smoothstep(mound_r * 0.9, mound_r * 1.9, dn)) * clamp(mound_h * 2.0, 0.0, 1.0);
	c = mix(c, vec3(0.5, 0.39, 0.27) * (0.85 + 0.3 * det), m * 0.7);
	vec4 ph = texture(pher_tex, uv);
	float pa = ph.a * pher_on;
	c = mix(c, ph.rgb * 0.75, pa * 0.55);
	c *= mix(0.08, 1.0, smoothstep(0.9, 2.2, dn));     // the dark mouth of the nest
	ALBEDO = c * mix(1.0, 0.62, wet);
	ROUGHNESS = mix(0.95, 0.35, wet);
	SPECULAR = mix(0.25, 0.6, wet);
}
