shader_type spatial;
render_mode cull_back;

// Grass field with trampled mud near the wall. World-space XZ UVs, so tiling is
// independent of the mesh; the two sets are blended by a noise mask and distance.
uniform sampler2D grass_diffuse : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_diffuse : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 mud_tint : source_color = vec3(1.0);
uniform bool textured = true;
uniform float tile_size = 4.0;      // metres per texture repeat
uniform vec3 mud_center = vec3(0.0, 0.0, -14.0);
uniform vec2 mud_extent = vec2(60.0, 40.0);  // half-size of the trampled ellipse (x, z)

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz / tile_size;
	// break up tiling: second sample rotated and scaled, mixed by low frequency noise
	vec2 uv2 = vec2(uv.x * 0.62 - uv.y * 0.31, uv.x * 0.31 + uv.y * 0.62) * 1.7;
	float n_big = texture(noise_tex, world_pos.xz * 0.004).r;
	float n_mid = texture(noise_tex, world_pos.xz * 0.02).r;
	float variation = smoothstep(0.35, 0.65, n_big);

	vec2 d = (world_pos.xz - mud_center.xz) / mud_extent;
	float trample = 1.0 - smoothstep(0.55, 1.0, length(d));
	float mud = clamp(trample * 0.9 + (n_mid - 0.5) * 0.9 + trample * (n_mid - 0.5), 0.0, 1.0);
	mud = smoothstep(0.25, 0.75, mud);

	vec3 g_col = mix(texture(grass_diffuse, uv).rgb, texture(grass_diffuse, uv2).rgb, variation) * grass_tint;
	vec3 m_col = mix(texture(mud_diffuse, uv).rgb, texture(mud_diffuse, uv2).rgb, variation) * mud_tint;
	vec3 g_arm = texture(grass_arm, uv).rgb;
	vec3 m_arm = texture(mud_arm, uv).rgb;
	vec3 g_n = texture(grass_normal, uv).rgb;
	vec3 m_n = texture(mud_normal, uv).rgb;

	vec3 albedo = mix(g_col, m_col, mud);
	// subtle large scale colour variation so the field does not read as one flat tile
	albedo *= mix(0.85, 1.1, n_big);
	ALBEDO = albedo;
	if (textured) {
		vec3 arm = mix(g_arm, m_arm, mud);
		AO = arm.r;
		AO_LIGHT_AFFECT = 0.6;
		ROUGHNESS = arm.g;
		NORMAL_MAP = mix(g_n, m_n, mud);
		NORMAL_MAP_DEPTH = 1.0;
	} else {
		ROUGHNESS = 0.95;
	}
	SPECULAR = 0.2;
}
