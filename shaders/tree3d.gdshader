shader_type spatial;
// Drzewa z generatora Tree3D (JekSun97/gdTree3D): kołysanie na wietrze wg koloru wierzchołka
// (R = wpływ wiatru, 0 przy ziemi), liście docinane alfą (bez sortowania przezroczystości).
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D texture_normal : hint_normal;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float sway_speed = 1.0;
uniform float sway_strength = 0.12;
uniform float sway_phase_len = 2.0;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.5);
uniform float flutter_strength = 0.0;
uniform float backlight = 0.0;      // liście przepuszczają światło (nie czernieją pod słońce)

void vertex() {
	float influence = COLOR.r;
	vec3 wd = normalize(wind_direction);
	// faza od położenia drzewa: sąsiednie drzewa nie kołyszą się równo
	float phase = MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.23;
	float t = TIME * sway_speed + phase;
	float sway = sin(t + VERTEX.y * 0.1 * sway_phase_len) * sway_strength;
	VERTEX += vec3(wd.x * sway, sin(t * 1.3) * sway * 0.05, wd.z * sway) * influence;
	float fl = sin(VERTEX.x * 6.0 + VERTEX.y * 6.0 + TIME * sway_speed * 2.5) * flutter_strength * influence;
	VERTEX += vec3(wd.x * fl * 0.3, fl, wd.z * fl * 0.3);
}

void fragment() {
	vec4 a = texture(texture_albedo, UV);
	ALBEDO = a.rgb * tint_color.rgb;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.3;
	BACKLIGHT = vec3(backlight) * ALBEDO;
	NORMAL_MAP = texture(texture_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = roughness;
}
