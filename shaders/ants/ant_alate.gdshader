// The alates (winged gynes and males, PART 0.14): the ants' shader with their wings truly see-through (ant_frag
// GLASS_WINGS) - drawn in the transparent pass, a depth pre-pass keeping the body's own parts in order; both faces of
// the thin wings. Only the alates' few use it (nest_alates.gd, outworld_flight.gd): the workers stay opaque.
shader_type spatial;
render_mode diffuse_burley, depth_prepass_alpha, cull_disabled;
#define GLASS_WINGS
#include "res://shaders/ants/ant_core.gdshaderinc"
#include "res://shaders/ants/ant_frag.gdshaderinc"
