// The ants' surface (shaders/ants/ant.gdshader, ant_alate.gdshader): one fragment for both. With GLASS_WINGS defined (the
// alates' own material, PART 0.14 step 11) an alate's wings are see-through for real - a pale clear membrane, the veins
// near solid; without it (the workers, the queen: their material is opaque) they were a screen door - three pixels in
// four left out - which from afar read as a grid (the keeper, 2026-11-21: "the wings look like a checker pattern").

void fragment() {
	if (limb > 0.5 && dot(cut_plane.xyz, wpos) > cut_plane.w) {
		discard;                         // a leg or antenna in front of the nest's cut (the body is never cut: hollow inside)
	}
	float vein = clamp((UV.x - 20.0) / 10.0, 0.0, 1.0);      // (UV.x on a wing: 20 + 10 x the vein value - ant/wings.py)
#ifndef GLASS_WINGS
	if (wing > 0.5) {
		// (v0.14.3, the keeper's photo reference/alate_gyne_side_user.png: the membrane nearly clear, the veins brown) three
		// pixels in four left out of the membrane, the veins kept
		ivec2 fc = ivec2(FRAGCOORD.xy);
		if (UV.x > 29.0 && ((fc.x & 1) + (fc.y & 1)) != 0) {
			discard;
		}
	}
#endif
	// a stretched crop shows amber honeydew through the pale membranes between the plates
	vec3 base = COLOR.rgb * mix(vec3(1.0), limb_gain, limb);
	if (wing > 0.5) {
		// a wing's own colours, not the body's tint: a pale glassy membrane, amber-brown veins and stigma
		base = mix(vec3(0.07, 0.04, 0.02), vec3(0.72, 0.72, 0.7), smoothstep(0.8, 0.98, vein));
	}
	// the plates stay dark; between them the stretched pale membranes show, a little amber from the honeydew
	ALBEDO = mix(base, vec3(0.4, 0.33, 0.24), stretch * gband * 0.4);
	ROUGHNESS = 0.4;
	SPECULAR = 0.55;
	RIM = rim_amount;
	RIM_TINT = 0.6;
#ifdef GLASS_WINGS
	// the membrane faint and glassy (a little light caught along it), the veins and the stigma near solid
	float membrane = smoothstep(0.8, 0.98, vein);
	ALPHA = wing > 0.5 ? mix(0.9, 0.12, membrane) : 1.0;     // (the fore and hind wings of both sides lie over each other)
	if (wing > 0.5) {
		ALBEDO = mix(vec3(0.07, 0.04, 0.02), vec3(0.6, 0.58, 0.54), membrane);     // (clear, a little smoky)
	}
	if (wing > 0.5) {
		ROUGHNESS = 0.15;
		SPECULAR = 0.8;
	}
#endif
}
