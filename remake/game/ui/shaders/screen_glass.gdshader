shader_type canvas_item;
// The centre screen's glass (target look: remake/art/ui/reference/target_briefing.png): dark teal
// with a faint circuit grid, a thin chamfered inner border and a little green spill at the edges.
// The corners are cut like the 3D bezel (build_frame.py SCREEN_CUT) so the bezel shows through.
// Colours are authored in sRGB and converted (UI screens render with HDR 2D, linear).

uniform vec2 size = vec2(1320.0, 690.0);
uniform vec2 cut = vec2(0.087, 0.0435); // corner chamfers (top, bottom) as fractions of the height
uniform vec3 glass = vec3(0.022, 0.075, 0.07);
uniform vec3 line = vec3(0.1, 0.55, 0.38);
uniform float grid_pitch = 46.0;
uniform float inset = 14.0; // inner border line distance from the edge
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

// chamfered rectangle: half size b, chamfer ct at the top corners, cb at the bottom (inside < 0)
float sd_oct(vec2 p, vec2 b, float ct, float cb) {
	float c = p.y < 0.0 ? ct : cb;
	float d_rect = max(abs(p.x) - b.x, abs(p.y) - b.y);
	float d_diag = (abs(p.x) + abs(p.y) - (b.x + b.y - c)) * 0.70710678;
	return max(d_rect, d_diag);
}

void fragment() {
	vec2 p = local - size * 0.5;
	float ct = cut.x * size.y;
	float cb = cut.y * size.y;
	float d = sd_oct(p, size * 0.5, ct, cb);
	float aa = max(abs(dFdx(p.x)), abs(dFdy(p.y))) + 1e-4;
	float inside = clamp(0.5 - d / aa, 0.0, 1.0);

	vec3 col = glass;
	// faint circuit grid with brighter nodes every fourth line
	vec2 g = abs(fract(local / grid_pitch) - 0.5) * grid_pitch;
	float grid = 1.0 - smoothstep(0.6, 1.4, min(g.x, g.y));
	vec2 big = abs(fract(local / (grid_pitch * 4.0)) - 0.5) * grid_pitch * 4.0;
	float grid_big = 1.0 - smoothstep(0.6, 1.6, min(big.x, big.y));
	col += line * (grid * 0.045 + grid_big * 0.05);
	// inner chamfered border
	float di = sd_oct(p, size * 0.5 - inset, max(ct - inset * 0.6, 4.0), max(cb - inset * 0.4, 3.0));
	float border = 1.0 - smoothstep(0.4, 1.6, abs(di));
	col += line * border * 0.5;
	// green spill from the bezel's edge lamps
	col += line * 0.09 * exp(d / 40.0);
	// a touch lighter at the top, faint grain
	col *= 1.0 + 0.12 * (1.0 - local.y / size.y);
	col *= 0.94 + 0.12 * texture(noise, local / 260.0).r;
	COLOR = vec4(pow(max(col, vec3(0.0)), vec3(2.2)), inside * COLOR.a);
}
