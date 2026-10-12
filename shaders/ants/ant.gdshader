shader_type spatial;
render_mode diffuse_burley;
#include "res://shaders/ants/ant_core.gdshaderinc"

void fragment() {
	// a stretched crop shows amber honeydew through the pale membranes between the plates
	vec3 base = COLOR.rgb * mix(vec3(1.0), limb_gain, limb);
	// the plates stay dark; between them the stretched pale membranes show, a little amber from the honeydew
	ALBEDO = mix(base, vec3(0.4, 0.33, 0.24), stretch * gband * 0.4);
	ROUGHNESS = 0.4;
	SPECULAR = 0.55;
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
