shader_type canvas_item;
// Briefing map terrain (TacticalMap), painted like a satellite survey: rolling olive lowlands,
// sandstone ridges where the mission's rock formations are, hillshade from the top left,
// faint contour lines, dry river beds and slow drifting cloud with shadows.
// The terrain away from the rocks is invented (placeholder until R13 decodes the real map).
// Colours are authored in sRGB and converted (UI screens render with HDR 2D, linear).

uniform sampler2D height : filter_linear, repeat_disable; // mission rock mask
uniform sampler2D noise : repeat_enable, filter_linear_mipmap; // seamless fractal noise
uniform float contours = 14.0;
uniform float seed = 0.37;

float n(vec2 p) {
	return texture(noise, p + seed).r;
}

// ridged noise: sharp crests where the noise crosses its middle value
float ridge(vec2 p) {
	return 1.0 - abs(n(p) * 2.0 - 1.0);
}

float h_at(vec2 uv) {
	float rocks = texture(height, uv).r;
	float base = n(uv * 0.22) * 0.55 + n(uv * 0.55 + 0.2) * 0.25;
	float r = pow(ridge(uv * 0.38 + 0.5), 3.0) * 0.35 + pow(ridge(uv * 0.9 + 0.1), 2.0) * 0.14;
	// ridges grow where the mission has rock formations, and a little everywhere
	float hills = base * 0.6 + r * (0.6 + 1.1 * rocks);
	return hills + rocks * 0.45 + (n(uv * 2.6) - 0.5) * 0.03;
}

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

void fragment() {
	vec2 uv = UV;
	float h = h_at(uv);
	vec2 e = vec2(1.5 / 512.0, 0.0);
	vec2 g = vec2(h_at(uv + e.xy) - h_at(uv - e.xy), h_at(uv + e.yx) - h_at(uv - e.yx)) / (2.0 * e.x);
	// hillshade: light from the top left, a little from above
	vec3 nrm = normalize(vec3(-g * 0.12, 1.0));
	float shade = clamp(dot(nrm, normalize(vec3(-0.6, -0.6, 0.55))) * 1.2 + 0.15, 0.4, 1.45);

	// colour by height: olive valleys, khaki slopes, sandstone ridges, pale crests
	float t = smoothstep(0.25, 0.95, h);
	vec3 col = mix(vec3(0.24, 0.26, 0.13), vec3(0.40, 0.38, 0.19), smoothstep(0.0, 0.3, t));
	col = mix(col, vec3(0.58, 0.47, 0.26), smoothstep(0.25, 0.55, t));
	col = mix(col, vec3(0.86, 0.74, 0.50), smoothstep(0.5, 0.8, t));
	col = mix(col, vec3(0.97, 0.92, 0.80), smoothstep(0.82, 1.0, t));
	// ground variation: patches of scrub and bare earth
	float scrub = n(uv * 1.8 + 0.7);
	col *= mix(vec3(0.85, 0.95, 0.8), vec3(1.1, 1.0, 0.92), scrub);
	col *= shade;

	// dry river beds wind through the low ground
	float riv = abs(n(uv * 0.3 + vec2(0.3, 0.8)) - 0.5);
	float bed = (1.0 - smoothstep(0.004, 0.012, riv)) * (1.0 - smoothstep(0.35, 0.6, t));
	col = mix(col, vec3(0.26, 0.30, 0.30) * 0.9, bed * 0.8);
	col = mix(col, vec3(0.55, 0.55, 0.45), (1.0 - smoothstep(0.0, 0.003, riv)) * (1.0 - smoothstep(0.35, 0.6, t)) * 0.5);

	// contour lines, fainter in the valleys
	float c = fract(h * contours);
	float w = fwidth(h * contours) * 1.2;
	float line = 1.0 - smoothstep(0.0, w, min(c, 1.0 - c));
	col = mix(col, mix(col * 0.6, vec3(0.85, 0.72, 0.4), 0.35), line * mix(0.45, 0.75, t));

	// clouds and their shadows, drifting slowly
	vec2 wind = vec2(TIME * 0.004, TIME * 0.0015);
	float cl = n(uv * 0.28 + wind + 0.13) * 0.7 + n(uv * 0.8 + wind * 1.6) * 0.3;
	float cloud = smoothstep(0.6, 0.78, cl);
	float cs = n((uv + vec2(0.025, 0.035)) * 0.28 + wind + 0.13) * 0.7 + n((uv + vec2(0.025, 0.035)) * 0.8 + wind * 1.6) * 0.3;
	col *= 1.0 - smoothstep(0.6, 0.78, cs) * 0.45;
	col = mix(col, vec3(0.93, 0.95, 0.97) * (0.75 + 0.25 * smoothstep(0.6, 0.9, cl)), cloud * 0.85);

	// faint survey grid and a vignette
	vec2 gr = abs(fract(uv * 8.0) - 0.5);
	float grid = 1.0 - smoothstep(0.494, 0.5, max(gr.x, gr.y));
	col = mix(col, vec3(0.2, 0.75, 0.35), (1.0 - grid) * 0.2);
	vec2 v = uv * (1.0 - uv);
	col *= 0.6 + 0.4 * pow(clamp(v.x * v.y * 16.0, 0.0, 1.0), 0.35);
	COLOR = vec4(srgb(col), 1.0);
}
