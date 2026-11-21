// A mated queen's wings shed on the ground (outworld_flight.gd, PART 0.14 step 11): the very wings of the gyne model
// (part 12 of assets/models/ants/gyne_hi.antmesh), coloured as on her (ant_frag.gdshaderinc GLASS_WINGS): a pale clear
// membrane, the brown veins and stigma near solid. UV.x = 20 + 10 x the vein value (tools/blender/ant/wings.py).
shader_type spatial;
render_mode diffuse_burley, depth_prepass_alpha, cull_disabled;

void fragment() {
	float vein = clamp((UV.x - 20.0) / 10.0, 0.0, 1.0);
	float membrane = smoothstep(0.8, 0.98, vein);
	ALBEDO = mix(vec3(0.07, 0.04, 0.02), vec3(0.6, 0.58, 0.54), membrane);
	ALPHA = mix(0.9, 0.16, membrane);
	ROUGHNESS = mix(0.4, 0.15, membrane);
	SPECULAR = 0.8;
}
