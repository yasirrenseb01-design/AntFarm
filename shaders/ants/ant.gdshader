shader_type spatial;
render_mode diffuse_burley;
#include "res://shaders/ants/ant_core.gdshaderinc"

void fragment() {
	if (limb > 0.5 && dot(cut_plane.xyz, wpos) > cut_plane.w) {
		discard;                         // a leg or antenna in front of the nest's cut (the body is never cut: hollow inside)
	}
	if (wing > 0.5) {
		// an alate's wing: a thin smoky membrane - drawn see-through by leaving out every other pixel of it (a screen
		// door: the ants are drawn opaque), the veins (darker in the vertex colour) kept
		ivec2 fc = ivec2(FRAGCOORD.xy);
		// (v0.14.3, the keeper's photo reference/alate_gyne_side_user.png: the membrane nearly clear, the veins brown) three
		// pixels in four left out of the membrane, the veins kept
		if (UV.x > 29.0 && ((fc.x & 1) + (fc.y & 1)) != 0) {      // (UV.x: 20 + 10 x the vein value - ant/wings.py)
			discard;
		}
	}
	// a stretched crop shows amber honeydew through the pale membranes between the plates
	vec3 base = COLOR.rgb * mix(vec3(1.0), limb_gain, limb);
	if (wing > 0.5) {
		// a wing's own colours, not the body's tint: a pale glassy membrane, amber-brown veins and stigma
		float vein = clamp((UV.x - 20.0) / 10.0, 0.0, 1.0);
		base = mix(vec3(0.07, 0.04, 0.02), vec3(0.72, 0.72, 0.7), smoothstep(0.8, 0.98, vein));
	}
	// the plates stay dark; between them the stretched pale membranes show, a little amber from the honeydew
	ALBEDO = mix(base, vec3(0.4, 0.33, 0.24), stretch * gband * 0.4);
	ROUGHNESS = 0.4;
	SPECULAR = 0.55;
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
