shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float curvature : hint_range(0.0, 0.2) = 0.042;
uniform float scanline_opacity : hint_range(0.0, 0.5) = 0.14;
uniform float scanline_density : hint_range(120.0, 720.0) = 320.0;
uniform float chromatic_aberration : hint_range(0.0, 0.01) = 0.0022;
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.42;
uniform float grain_amount : hint_range(0.0, 0.12) = 0.025;
uniform float contrast : hint_range(0.8, 1.4) = 1.06;
uniform float saturation : hint_range(0.5, 1.5) = 1.04;

vec2 warp_uv(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	vec2 offset = centered.yx * centered.yx * curvature;
	centered += centered * offset;
	return centered * 0.5 + 0.5;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = warp_uv(SCREEN_UV);

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.015, 0.018, 0.025, 1.0);
	} else {
		// Discreet radial RGB chromatic aberration
		vec2 from_center = uv - vec2(0.5);
		float dist = length(from_center);
		vec2 ca_offset = from_center * chromatic_aberration * (0.4 + dist * 1.4);

		float r = texture(screen_texture, clamp(uv + ca_offset, vec2(0.001), vec2(0.999))).r;
		float g = texture(screen_texture, uv).g;
		float b = texture(screen_texture, clamp(uv - ca_offset, vec2(0.001), vec2(0.999))).b;
		vec3 col = vec3(r, g, b);

		// Subtle horizontal CRT scanlines
		float scan = sin(uv.y * scanline_density * 3.14159265) * 0.5 + 0.5;
		col *= 1.0 - (1.0 - scan) * scanline_opacity;

		// Faint phosphor vertical triad modulation
		float grille = sin(FRAGCOORD.x * 3.14159265) * 0.5 + 0.5;
		col *= 1.0 - (1.0 - grille) * 0.03;

		// Subtle analog film grain
		float grain = (hash12(FRAGCOORD.xy + vec2(fract(TIME * 17.3) * 100.0, fract(TIME * 11.7) * 100.0)) - 0.5) * grain_amount;
		col += vec3(grain);

		// Slight contrast & saturation polish
		col = (col - 0.5) * contrast + 0.5;
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(luma), col, saturation);

		// Cold gothic edge vignette
		float vig = smoothstep(0.95, 0.25, dist * (1.0 + vignette_strength));
		col *= mix(1.0 - vignette_strength, 1.0, vig);

		// Subtle CRT bezel edge fade
		vec2 edge = smoothstep(vec2(0.0), vec2(0.015), uv) * smoothstep(vec2(0.0), vec2(0.015), vec2(1.0) - uv);
		col *= edge.x * edge.y;

		COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
	}
}
