shader_type spatial;
render_mode diffuse_burley;
#include "res://shaders/ants/ant_core.gdshaderinc"

void fragment() {
	// a stretched crop shows amber honeydew through the pale membranes between the plates
	vec3 base = COLOR.rgb * mix(vec3(1.0), limb_gain, limb);
	ALBEDO = mix(base, vec3(0.42, 0.27, 0.1), stretch * 0.55);
	ROUGHNESS = 0.4;
	SPECULAR = 0.55;
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
