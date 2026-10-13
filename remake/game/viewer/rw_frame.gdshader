shader_type spatial;
// Original RenderWare 2.0 model textures (placeholders). Textures taller than 128 px are stacks
// of 128x128 frames: display states (normal paint, damage tints, the green cockpit hologram).
// Model UVs address one frame and wrap inside it: V is wrapped, then moved into the frame.

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform float frames = 1.0; // texture height / 128
uniform float frame = 0.0; // 0 = normal paint
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness = 0.9;

void fragment() {
	vec2 uv = vec2(UV.x, (fract(UV.y) + frame) / frames);
	// fract() jumps where a triangle crosses a frame edge; take mip derivatives from the
	// unwrapped coordinates so that seam doesn't select a tiny mip
	vec2 d = vec2(1.0, 1.0 / frames);
	vec4 c = textureGrad(albedo_tex, uv, dFdx(UV) * d, dFdy(UV) * d) * tint;
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
}
