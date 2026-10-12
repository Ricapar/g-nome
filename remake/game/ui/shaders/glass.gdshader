shader_type canvas_item;
// Glass slot / button face (remake/UI-DESIGN.md): a steel rim around a pane of glass that is
// blue when the slot is empty and dark green phosphor glass when it holds a menu entry.

uniform vec2 size = vec2(160.0, 48.0);
uniform float radius = 6.0;
uniform float rim = 5.0;
uniform int state = 0; // 0 empty (blue), 1 idle, 2 hover/focus, 3 selected, 4 selected + hover
uniform float flash = 0.0; // 0..1 press flash
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
	float d = sd_round_box(p - c, c, radius);
	float dg = sd_round_box(p - c, c - rim, max(radius - rim * 0.5, 1.0));
	float t = p.y / size.y;

	// rim: dark steel with a bevel lit from the top left
	vec2 grad = vec2(dFdx(d), dFdy(d));
	float light = length(grad) > 0.0 ? dot(normalize(grad), normalize(vec2(-1.0, -1.0))) : 0.0;
	vec3 rimc = vec3(0.30, 0.31, 0.30) * (0.8 + 0.4 * texture(noise, p / 90.0).r);
	rimc *= 1.0 + 0.6 * light;

	// glass
	vec3 glass;
	float edge = clamp(-dg / 10.0, 0.0, 1.0); // 0 at the pane edge, 1 inside
	if (state == 0) {
		float streak = texture(noise, vec2(p.x / 700.0, p.y / 3.0)).r;
		glass = mix(vec3(0.07, 0.14, 0.56), vec3(0.29, 0.32, 0.66), clamp(1.0 - t * 1.2 + streak * 0.35, 0.0, 1.0));
	} else if (state >= 3) {
		glass = mix(vec3(0.06, 0.30, 0.24), vec3(0.11, 0.48, 0.38), 1.0 - t);
		glass += vec3(0.0, 0.12, 0.06) * (1.0 - edge) * (state == 4 ? 1.8 : 1.0);
	} else {
		glass = mix(vec3(0.010, 0.030, 0.018), vec3(0.025, 0.07, 0.04), 1.0 - t);
		float glow = state == 2 ? 0.55 : 0.18;
		glass += vec3(0.05, 0.55, 0.18) * glow * pow(1.0 - edge, 2.0);
	}
	// sheen: a soft band in the upper third and a thin highlight line
	float sheen = smoothstep(0.42, 0.08, t) * 0.10 + exp(-pow((t - 0.16) / 0.03, 2.0)) * 0.08;
	glass += vec3(sheen);
	glass += vec3(0.2, 1.0, 0.45) * flash * 0.6;

	float g = clamp(0.5 - dg / aa, 0.0, 1.0);
	vec3 col = mix(rimc, glass, g);
	// inner shadow where the pane meets the rim
	col *= mix(0.55, 1.0, smoothstep(0.0, 3.0, -dg) * g + (1.0 - g));

	COLOR = vec4(col, clamp(0.5 - d / aa, 0.0, 1.0) * COLOR.a);
}
