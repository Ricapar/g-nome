shader_type canvas_item;
// Overlay for the centre "screen": a faint phosphor vignette, fine scanlines and a power-on sweep.
// Drawn above the screen content (3D view or 2D page); keep it subtle.

uniform vec2 size = vec2(800.0, 600.0);
uniform float scanline_pitch = 3.0; // design units
uniform float scanline_strength = 0.10;
uniform float power = 1.0; // 0 = off (black), 1 = on; animate for the power-on sweep

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 uv = local / size;
	vec2 v = uv * (1.0 - uv);
	float vignette = pow(clamp(v.x * v.y * 18.0, 0.0, 1.0), 0.35);
	float line = 0.5 + 0.5 * sin(local.y / scanline_pitch * 6.28318);
	float aa = abs(dFdy(local.y)) / scanline_pitch; // fade scanlines out when they get too fine to draw
	float scan = scanline_strength * line * (1.0 - smoothstep(0.25, 0.5, aa));
	float dark = clamp(1.0 - vignette + scan, 0.0, 1.0);
	// power-on: a bright line sweeps down, the screen is dark below it
	float edge = power * 1.1;
	float off = smoothstep(edge - 0.02, edge, uv.y);
	float sweep = exp(-pow((uv.y - edge) / 0.008, 2.0)) * (1.0 - step(1.0, power));
	COLOR = vec4(vec3(0.2, 1.0, 0.45) * sweep * 2.0, max(dark * 0.85, off) + sweep);
}
