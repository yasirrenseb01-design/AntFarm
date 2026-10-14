shader_type spatial;
// The white outline round the ant the keeper has selected (click): the same animated body, grown a little along
// its normals and drawn from the inside only, so a white rim shows round it.
render_mode unshaded, cull_front;
#define OUTLINE
#include "res://shaders/ants/ant_core.gdshaderinc"

void fragment() {
	if (dot(cut_plane.xyz, wpos) > cut_plane.w) {
		discard;                         // in front of the nest's cut
	}
	ALBEDO = vec3(1.0);
}
