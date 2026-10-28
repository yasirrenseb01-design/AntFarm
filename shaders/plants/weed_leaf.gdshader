shader_type spatial;
render_mode diffuse_burley, cull_disabled;
// Leaves of the garden's low weeds (scripts/view/common/weed_mesh.gd). The mesh is a bent strip as wide as the
// leaf's widest point; its outline, veins and colour are drawn here, so they stay sharp however close the camera is.
//   UV  : x across the strip -1..1, y from the leaf's base 0 to its tip 1
//   UV2 : x the kind (0 plantain, 1 dandelion, 2 clover leaflet, 3 stalk), y a random number for this leaf
//   COLOR: rgb the leaf's green (sRGB), a how far the wind bends it (as shaders/plants/sway.gdshader)

uniform float wind = 0.4;
uniform float wither = 0.0;          // 0 green .. 1 winter-dead straw
uniform float frost = 0.0;
uniform vec3 backlight = vec3(0.1, 0.16, 0.04);
#include "res://shaders/plants/brush.gdshaderinc"

void vertex() {
	float f = COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = TIME * 1.6 + wp.x * 0.06 + wp.z * 0.045;
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + wp.x * 0.012);
	vec3 off = vec3(sin(ph), 0.3 * sin(ph * 2.3 + 1.0), 0.55 * cos(ph * 0.8 + wp.z * 0.04)) * wind * gust * f;
	off.y -= wither * f * f * 1.2;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off * (1.0 - 0.5 * wither);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * brushed(wp, max(f, 0.25));      // (an ant walking over the rosette)
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// half the leaf's width at v (1 = the strip's edge)
float half_width(int kind, float v, float sd) {
	if (kind == 0) {
		// broad-leaved plantain: a long stalk, then a broad egg-shaped blade
		float t = clamp((v - 0.24) / 0.76, 0.0, 1.0);
		float blade = pow(sin(3.14159 * t), 0.7) * (1.0 - 0.18 * t);
		return max(blade, 0.07 * (1.0 - smoothstep(0.24, 0.4, v)) + 0.035);
	}
	if (kind == 1) {
		// dandelion: long and narrow with backward-pointing teeth ("lion's teeth"), a triangular end lobe
		float w = pow(sin(3.14159 * v), 0.85) * (0.45 + 0.55 * v);
		float lobe = fract(v * (5.0 + sd * 2.0) + sd);
		float teeth = mix(0.42, 1.0, smoothstep(0.0, 0.85, lobe)) * (1.0 - step(0.97, lobe) * 0.5);
		w *= mix(teeth, 1.0, smoothstep(0.72, 0.85, v));
		return max(w, 0.06);
	}
	if (kind == 2) {
		// white clover leaflet: rounded, widest past the middle, a small notch at the tip
		float w = sqrt(max(sin(3.14159 * v), 0.0)) * (0.5 + 0.5 * v);
		return w;
	}
	return 1.0;
}

void fragment() {
	int kind = int(UV2.x + 0.5);
	float sd = UV2.y;
	float u = UV.x;
	float v = UV.y;
	float hw = half_width(kind, v, sd);
	float x = abs(u) / max(hw, 0.001);              // 0 on the midrib, 1 at the edge
	if (kind < 3 && x > 1.0) {
		discard;
	}
	if (kind == 2 && v > 0.86 && abs(u) < (v - 0.86) * 0.9) {
		discard;                                  // the clover leaflet's notch
	}
	vec3 c = COLOR.rgb;
	c = pow(c, vec3(2.2));
	if (kind < 3) {
		float mid = 1.0 - smoothstep(0.015, 0.045 + 0.02 * float(kind == 1), abs(u));
		float vein = mid;
		if (kind == 0) {
			// plantain: three to five ribs running the blade's length side by side, meeting at base and tip
			float side = 0.0;
			for (int k = 1; k <= 2; k++) {
				side = max(side, 1.0 - smoothstep(0.0, 0.07, abs(x - float(k) * 0.36)));
			}
			vein = max(vein, side * 0.85 * smoothstep(0.26, 0.34, v));
			// the stalk is paler
			c = mix(c, c * vec3(1.25, 1.2, 0.85), 1.0 - smoothstep(0.22, 0.32, v));
		} else if (kind == 1) {
			// dandelion: a pale, broad midrib, faint side veins running out toward the teeth
			float pin = fract((v - x * 0.18) * (5.0 + sd * 2.0) + sd);
			vein = max(vein * 1.2, (1.0 - smoothstep(0.0, 0.1, abs(pin - 0.5))) * 0.35 * step(x, 0.85));
			c = mix(c, vec3(0.42, 0.22, 0.2), mid * (1.0 - smoothstep(0.0, 0.35, v)) * 0.5 * step(0.5, sd));  // a reddish rib on some
		} else {
			// white clover: the pale chevron across the leaflet
			float band = (1.0 - smoothstep(0.02, 0.06, abs(v - (0.4 + x * 0.2)))) * smoothstep(0.95, 0.6, x);
			c = mix(c, c * vec3(1.6, 1.55, 1.35) + vec3(0.03), band * (0.15 + 0.35 * step(0.4, sd)));
			vein = mid * 0.6;
		}
		c = mix(c, c * vec3(1.35, 1.38, 1.05) + vec3(0.01, 0.015, 0.0), clamp(vein, 0.0, 1.0) * 0.55);
		// a little darker toward the edges, yellower at the base, mottled
		c *= 1.0 - 0.2 * smoothstep(0.55, 1.0, x);
		c = mix(c, c * vec3(1.15, 1.12, 0.7), (1.0 - smoothstep(0.0, 0.3, v)) * 0.45);
		c *= 0.88 + 0.22 * vnoise(vec2(u * 6.0, v * 18.0) + sd * 37.0);
		// an old leaf now and then: its tip browning
		c = mix(c, vec3(0.2, 0.13, 0.05), smoothstep(0.75, 1.0, v) * step(0.85, fract(sd * 7.3)) * 0.7);
	} else {
		c *= vec3(1.0, 1.05, 0.85);
	}
	float green = clamp((c.g - max(c.r, c.b)) * 6.0, 0.0, 1.0);
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(c, vec3(l * 1.45, l * 1.05, l * 0.55), wither * green);
	c = mix(c, vec3(0.75, 0.8, 0.85), frost * 0.55 * smoothstep(0.0, 0.6, NORMAL.y * 0.5 + 0.5));
	ALBEDO = c;
	ROUGHNESS = 0.5;
	SPECULAR = 0.45;                        // a waxy shine
	BACKLIGHT = backlight * (1.0 - 0.7 * wither);
}
