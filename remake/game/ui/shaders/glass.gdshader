shader_type canvas_item;
// Glass face of a slot button (target look: remake/art/ui/reference/target_briefing.png).
// The 3D frame supplies the steel collar; this draws the pane: smoky dark glass, glossy blue
// when the slot is empty, and a neon green frame with green glass when selected.

uniform vec2 size = vec2(150.0, 62.0);
uniform float radius = 7.0;
uniform int state = 0; // 0 empty (blue), 1 idle, 2 hover/focus, 3 selected, 4 selected + hover
uniform float flash = 0.0;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = local;
	vec2 c = size * 0.5;
	float aa = max(abs(dFdx(p.x)), abs(dFdy(p.y))) + 1e-4;
	float d = sd_round_box(p - c, c - 1.0, radius);
	float t = p.y / size.y;
	float inside = clamp(0.5 - d / aa, 0.0, 1.0);
	float grain = texture(noise, p / 60.0).r;

	vec3 col;
	if (state == 0) {
		// deep blue glass, darker and less saturated than the original's flat blue
		float streak = texture(noise, vec2(p.x / 800.0, p.y / 4.0)).r;
		col = mix(vec3(0.05, 0.07, 0.3), vec3(0.17, 0.22, 0.58), clamp(1.0 - t + streak * 0.25, 0.0, 1.0));
		col *= 0.92 + 0.16 * grain;
	} else if (state >= 3) {
		col = mix(vec3(0.015, 0.05, 0.035), vec3(0.03, 0.12, 0.07), clamp(1.0 - t * 1.1, 0.0, 1.0));
	} else {
		col = mix(vec3(0.025, 0.045, 0.05), vec3(0.07, 0.105, 0.11), clamp(1.0 - t, 0.0, 1.0));
		col *= 0.9 + 0.2 * grain;
	}
	// inner edge light: teal when idle/hover, neon green frame when selected
	float edge = exp(-max(-d, 0.0) / 3.0);
	if (state == 1) col += vec3(0.05, 0.16, 0.16) * edge;
	if (state == 2) col += vec3(0.10, 0.45, 0.40) * edge;
	if (state >= 3) {
		float band = smoothstep(-4.0, -2.6, d) * (1.0 - smoothstep(-1.2, 0.0, d));
		col += vec3(0.18, 0.62, 0.3) * band * (state == 4 ? 1.15 : 1.0);
		col += vec3(0.05, 0.6, 0.2) * exp(-max(-d - 3.0, 0.0) / 9.0);
	}
	// gloss: a soft upper band and a thin highlight line
	col += vec3(smoothstep(0.5, 0.05, t) * 0.07 + exp(-pow((t - 0.12) / 0.025, 2.0)) * 0.10);
	col += vec3(0.3, 1.2, 0.5) * flash * 0.5;
	// darken where the pane meets the collar
	col *= mix(0.5, 1.0, smoothstep(0.0, 2.0, -d));
	// colours above are authored in sRGB; UI screens render with HDR 2D (linear), so convert
	COLOR = vec4(pow(max(col, vec3(0.0)), vec3(2.2)), inside * COLOR.a);
}
