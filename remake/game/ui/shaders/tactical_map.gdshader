shader_type canvas_item;
// Briefing map terrain (TacticalMap): a height mask from the mission's rock formations shaded
// as sandstone ridges with contour lines over dark ground, a faint grid and a vignette.
// Colours are authored in sRGB and converted (UI screens render with HDR 2D, linear).

uniform sampler2D height : filter_linear, repeat_disable;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform float contours = 9.0;

float h_at(vec2 uv) {
	float n = texture(noise, uv * 2.0).r;
	float n2 = texture(noise, uv * 6.0 + 0.4).r;
	return texture(height, uv).r * (0.8 + 0.4 * n) + (n2 - 0.5) * 0.03;
}

void fragment() {
	vec2 uv = UV;
	float h = h_at(uv);
	vec2 e = vec2(2.0 / 384.0, 0.0);
	vec2 g = vec2(h_at(uv + e.xy) - h_at(uv - e.xy), h_at(uv + e.yx) - h_at(uv - e.yx));
	float shade = clamp(0.85 - dot(g, vec2(1.0, 1.0)) * 6.0, 0.35, 1.25); // light from the top left

	vec3 ground = mix(vec3(0.10, 0.11, 0.07), vec3(0.20, 0.19, 0.11), texture(noise, uv * 6.0).r);
	vec3 rock = mix(vec3(0.45, 0.36, 0.20), vec3(0.95, 0.85, 0.62), smoothstep(0.35, 1.0, h));
	float r = smoothstep(0.12, 0.32, h);
	vec3 col = mix(ground, rock * shade, r);
	// contour lines
	float c = fract(h * contours);
	float line = 1.0 - smoothstep(0.0, 0.08, min(c, 1.0 - c));
	col = mix(col, col * 0.55 + vec3(0.25, 0.2, 0.08), line * 0.7 * smoothstep(0.05, 0.2, h));
	// faint grid and vignette
	vec2 gr = abs(fract(uv * 8.0) - 0.5);
	float grid = 1.0 - smoothstep(0.485, 0.5, max(gr.x, gr.y));
	col = mix(col, vec3(0.1, 0.6, 0.25), (1.0 - grid) * 0.18);
	vec2 v = uv * (1.0 - uv);
	col *= 0.55 + 0.45 * pow(clamp(v.x * v.y * 16.0, 0.0, 1.0), 0.3);
	COLOR = vec4(pow(col, vec3(2.2)), 1.0);
}
