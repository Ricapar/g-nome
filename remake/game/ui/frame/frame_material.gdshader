shader_type spatial;
// Material for the menu machinery (ui/frame/menu_frame.glb): world-space triplanar PBR (the
// model has no UVs) with two layers. Vertex colour masks baked by build_frame.py drive them:
// R = convex edges -> worn to the wear layer (bare/polished metal), G = concave corners -> grime.

uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_rough : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D base_metal : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_black;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform bool use_base_albedo = true;
uniform float base_roughness = 1.0;
uniform float base_metallic = 1.0;
uniform float normal_strength = 1.0;
uniform float scale = 0.6; // texture repeats per model unit

uniform sampler2D wear_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D wear_rough : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec4 wear_tint : source_color = vec4(1.0);
uniform float wear_amount = 1.0;
uniform float wear_roughness = 0.45;
uniform float grime_amount = 0.55;
// paint chips: where the base albedo loses its saturation (the grey flecks in a painted-metal
// map) the wear layer shows through, so chipped paint reads as bare steel, not dark paint
uniform float chip_amount = 0.0;
// painterly variety on top of the tiled set, from a seamless fbm noise sampled at three scales
// with different offsets (so no two plates repeat): blotches of paint worn to bare metal,
// fine chips and dirt specks, and rust staining where the wear is about to break through
// (same sampler settings as the maps above: tri() takes them all through one parameter)
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float patch_amount = 0.0;
uniform float speckle_amount = 0.0;
uniform float rust_amount = 0.0;
uniform vec4 rust_tint : source_color = vec4(0.36, 0.17, 0.06, 1.0);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_weights(vec3 n) {
	vec3 b = pow(abs(n), vec3(5.0));
	return b / (b.x + b.y + b.z);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	vec3 w = tri_weights(wnrm);
	vec3 p = wpos * scale;

	vec3 tex = tri(base_albedo, p, w).rgb;
	vec3 albedo = (use_base_albedo ? tex : vec3(1.0)) * base_tint.rgb;
	float rough = tri(base_rough, p, w).r * base_roughness;
	float sat = (max(tex.r, max(tex.g, tex.b)) - min(tex.r, min(tex.g, tex.b))) / max(max(tex.r, max(tex.g, tex.b)), 1e-3);
	float chip = (1.0 - smoothstep(0.22, 0.55, sat)) * chip_amount;
	float metal = tri(base_metal, p, w).r * base_metallic;

	// triplanar normal mapping (whiteout-style swizzle onto the world axes)
	vec3 sn = sign(wnrm);
	vec3 nx = texture(base_normal, p.zy).xyz * 2.0 - 1.0;
	vec3 ny = texture(base_normal, p.xz).xyz * 2.0 - 1.0;
	vec3 nz = texture(base_normal, p.xy).xyz * 2.0 - 1.0;
	nx.xy *= normal_strength; ny.xy *= normal_strength; nz.xy *= normal_strength;
	vec3 wn = vec3(0.0, nx.y, nx.x * sn.x) * w.x + vec3(ny.x * sn.y, 0.0, ny.y) * w.y + vec3(nz.x * sn.z, nz.y, 0.0) * w.z;
	wn = normalize(wnrm + wn);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// edge wear with a noisy boundary, and grime in the seams
	float breakup = tri(base_rough, p * 2.7 + 0.31, w).r;
	float edge = COLOR.r * wear_amount;
	float wear = smoothstep(0.45, 0.6, edge + (breakup - 0.5) * 0.7) * step(0.02, edge);
	wear = max(wear, chip);
	// painterly wear: big blotches (more likely near edges), fine specks, rust around both
	float fbm_big = tri(noise, p * 0.2 + 1.7, w).r;
	float fbm_mid = tri(noise, p * 1.1 + 0.4, w).r;
	float fbm_fine = tri(noise, p * 4.6 + 2.9, w).r;
	// blotches: large, soft, ragged at the rim (the mid noise eats into them), more near edges
	float blot = fbm_big * 0.55 + fbm_mid * 0.3 + COLOR.r * 0.3;
	float patch = smoothstep(0.58, 0.66, blot) * smoothstep(0.3, 0.42, fbm_fine) * patch_amount;
	float speck = smoothstep(0.65, 0.7, fbm_fine) * smoothstep(0.35, 0.5, fbm_mid) * speckle_amount;
	wear = max(wear, max(patch, speck));
	float rust = smoothstep(0.52, 0.6, blot) * (1.0 - wear) * rust_amount
		+ smoothstep(0.6, 0.65, fbm_fine) * smoothstep(0.5, 0.6, fbm_mid) * rust_amount * 0.5;
	vec3 bare = tri(wear_albedo, p * 1.6, w).rgb * wear_tint.rgb;
	albedo = mix(albedo, rust_tint.rgb, clamp(rust, 0.0, 1.0) * 0.7);
	albedo = mix(albedo, bare, wear);
	rough = mix(rough, tri(wear_rough, p * 1.6, w).r * wear_roughness, wear);
	rough = mix(rough, 1.0, clamp(rust, 0.0, 1.0) * 0.5);
	metal = mix(metal, 1.0, wear);
	float grime = COLOR.g * grime_amount * (0.6 + 0.8 * breakup);
	// dirt also gathers in the noise's dark hollows, so the grime is not only in the seams
	grime += (1.0 - smoothstep(0.3, 0.45, fbm_mid)) * grime_amount * 0.35;
	albedo *= 1.0 - clamp(grime, 0.0, 0.85);
	rough = mix(rough, 1.0, grime * 0.5);

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
}
