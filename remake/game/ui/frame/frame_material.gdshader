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

	vec3 albedo = (use_base_albedo ? tri(base_albedo, p, w).rgb : vec3(1.0)) * base_tint.rgb;
	float rough = tri(base_rough, p, w).r * base_roughness;
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
	vec3 bare = tri(wear_albedo, p * 1.6, w).rgb * wear_tint.rgb;
	albedo = mix(albedo, bare, wear);
	rough = mix(rough, tri(wear_rough, p * 1.6, w).r * wear_roughness, wear);
	metal = mix(metal, 1.0, wear);
	float grime = COLOR.g * grime_amount * (0.6 + 0.8 * breakup);
	albedo *= 1.0 - clamp(grime, 0.0, 0.85);
	rough = mix(rough, 1.0, grime * 0.5);

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
}
