shader_type canvas_item;
// Machinery panel for the G-Nome UI (see remake/UI-DESIGN.md): a chamfered SDF shape with
// bevel lighting and a procedural material. Shapes are vector (crisp at any resolution);
// the material comes from noise textures that authored hi-res maps can replace later.
// Coordinates are local design units (set `size` from the Control; see MachinePanel).

uniform vec2 size = vec2(100.0, 100.0);
uniform float chamfer = 8.0;
uniform float bevel = 5.0;
uniform vec4 hi_color : source_color = vec4(0.68, 0.37, 0.36, 1.0);
uniform vec4 base_color : source_color = vec4(0.57, 0.18, 0.17, 1.0);
uniform vec4 lo_color : source_color = vec4(0.43, 0.15, 0.13, 1.0);
uniform int finish = 0; // 0 painted metal, 1 brushed steel, 2 cast iron
uniform float wear = 0.3; // chipped paint showing bare metal (finish 0)
uniform int cylinder = 0; // 0 flat, 1 drum with a horizontal axis, 2 pipe with a vertical axis
uniform vec4 hazard = vec4(0.0); // stripe band as x0, y0, x1, y1 (design units); empty = none
uniform vec4 recess = vec4(0.0); // recessed area x0, y0, x1, y1; empty = none
uniform int vents = 0; // > 0: the recess is a grille of this many horizontal slots
uniform float rivet_inset = 0.0; // > 0: a rivet in each corner, this far from the edges
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float sd_chamfer_box(vec2 p, vec2 b, float c) {
	vec2 q = abs(p) - b;
	float box = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	float ch = (abs(p.x) + abs(p.y) - (b.x + b.y - c)) * 0.70710678;
	return max(box, ch);
}

float in_rect(vec2 p, vec4 r, float aa) {
	vec2 lo = smoothstep(r.xy - aa, r.xy + aa, p);
	vec2 hi = 1.0 - smoothstep(r.zw - aa, r.zw + aa, p);
	return lo.x * lo.y * hi.x * hi.y;
}

vec3 material(vec2 p) {
	float n = texture(noise, p / 320.0).r;
	float f = texture(noise, p / 41.0 + 0.37).r;
	vec3 col;
	if (finish == 1) {
		float brush = texture(noise, vec2(p.x / 900.0, p.y / 2.2)).r;
		col = mix(lo_color.rgb, hi_color.rgb, clamp(0.2 + brush * 0.9 + (n - 0.5) * 0.3, 0.0, 1.0));
	} else if (finish == 2) {
		col = base_color.rgb * (0.75 + 0.5 * n) * (0.9 + 0.2 * f);
	} else {
		col = mix(lo_color.rgb, hi_color.rgb, clamp(0.5 + (n - 0.5) * 1.1, 0.0, 1.0));
		col = mix(col, base_color.rgb, 0.4);
		// chips: bare grey metal where fine noise peaks
		float chip = smoothstep(1.0 - wear * 0.35, 1.02 - wear * 0.35, f * (0.6 + 0.6 * n));
		col = mix(col, vec3(0.42, 0.41, 0.40) * (0.8 + 0.4 * n), chip);
	}
	return col;
}

void fragment() {
	vec2 p = local;
	vec2 c = size * 0.5;
	float d = sd_chamfer_box(p - c, c, chamfer);
	float aa = max(abs(dFdx(p.x)), abs(dFdy(p.y))) + 1e-4; // design units per screen pixel
	float alpha = clamp(0.5 - d / aa, 0.0, 1.0);

	vec3 col = material(p);

	// cylinder shading for pipes and push-button drums
	if (cylinder == 1 || cylinder == 2) {
		float t = cylinder == 1 ? p.y / size.y : p.x / size.x;
		float body = pow(max(sin(t * 3.14159), 0.0), 0.6);
		float spec = exp(-pow((t - 0.3) / 0.07, 2.0));
		col = col * (0.35 + 0.75 * body) + vec3(spec * 0.35);
	}

	// hazard stripes
	if (hazard.z > hazard.x) {
		float h = in_rect(p, hazard, aa);
		float s = step(0.5, fract((p.x + p.y) / 28.0));
		vec3 stripe = mix(vec3(0.07, 0.065, 0.05), vec3(0.79, 0.63, 0.15), s);
		stripe *= 0.8 + 0.4 * texture(noise, p / 60.0).r;
		col = mix(col, stripe, h);
	}

	// recess (inner shadow) or vent grille
	if (recess.z > recess.x) {
		float r = in_rect(p, recess, aa);
		vec3 deep = vec3(0.05, 0.05, 0.045);
		if (vents > 0) {
			float pitch = (recess.w - recess.y) / float(vents);
			float y = fract((p.y - recess.y) / pitch);
			float slot = smoothstep(0.18, 0.22, y) * (1.0 - smoothstep(0.62, 0.66, y));
			vec3 lip = col * mix(1.25, 0.6, y);
			col = mix(col, mix(lip, deep, slot), r);
		} else {
			vec2 e = clamp((p - recess.xy) / 6.0, 0.0, 1.0);
			col = mix(col, deep * (0.6 + 0.4 * min(e.x, e.y)) + col * 0.15, r);
		}
	}

	// rivets
	if (rivet_inset > 0.0) {
		vec2 rp = vec2(rivet_inset);
		vec2 q = abs(p - c) - (c - rp);
		float rd = length(q) - 3.6;
		float dome = clamp(-rd / 3.6, 0.0, 1.0);
		vec2 g = normalize(q + 1e-4);
		float lit = 0.6 + 0.5 * dot(-g, normalize(vec2(1.0, 1.0)));
		vec3 rivet = vec3(0.55, 0.53, 0.5) * lit * (0.5 + 0.5 * dome);
		col = mix(col, rivet, clamp(0.5 - rd / aa, 0.0, 1.0));
	}

	// bevel lighting from the top left, a dark outline at the very edge
	float inner = clamp(-d / bevel, 0.0, 1.0);
	vec2 grad = vec2(dFdx(d), dFdy(d));
	vec2 nrm = length(grad) > 0.0 ? normalize(grad) : vec2(0.0);
	float light = dot(nrm, normalize(vec2(-1.0, -1.0)));
	col *= 1.0 + 0.55 * light * (1.0 - inner);
	col *= mix(0.35, 1.0, smoothstep(0.0, 1.5, -d));

	COLOR = vec4(col, alpha * COLOR.a);
}
