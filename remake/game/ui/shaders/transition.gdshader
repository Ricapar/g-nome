shader_type canvas_item;
// Screen change cover (TransitionOverlay): two black shutters close from the top and bottom to
// a bright phosphor line, like a CRT switching off, then open again. amount 0 = open, 1 = closed.
// Colours are authored in sRGB and converted (UI screens render with HDR 2D, linear).

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 line_color = vec3(0.35, 1.0, 0.55);

void fragment() {
	float half_open = (1.0 - amount) * 0.5;
	float d = abs(UV.y - 0.5);
	float aa = fwidth(UV.y) + 1e-5;
	float shut = smoothstep(half_open - aa, half_open + aa, d);
	// the shutters' edges glow; fully closed they meet in one bright line that fades out
	float w = max(0.0025, aa * 1.5);
	float edge = exp(-pow((d - half_open) / w, 2.0)) * smoothstep(0.0, 0.08, amount);
	float closed_line = exp(-pow(d / w, 2.0)) * smoothstep(0.85, 1.0, amount) * (1.0 - smoothstep(0.98, 1.0, amount) * 0.6);
	float glow = max(edge, closed_line);
	vec3 col = pow(line_color, vec3(2.2)) * glow * 1.6;
	float a = max(shut, glow);
	COLOR = vec4(col / max(a, 1e-3), a);
}
