shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Podłoga w stylu blueprintu: niebieski papier + siatka 25 cm / 1 m / 5 m + osie.
uniform vec3 paper : source_color = vec3(0.05, 0.18, 0.38);
uniform vec3 ink : source_color = vec3(0.62, 0.8, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float grid(vec2 p, float spacing, float width) {
	vec2 d = abs(fract(p / spacing + 0.5) - 0.5) * spacing;
	vec2 fw = max(fwidth(p), vec2(1e-5));
	vec2 l = 1.0 - smoothstep(vec2(width * 0.5), vec2(width * 0.5) + fw * 1.2, d);
	float fade = 1.0 - smoothstep(spacing * 0.06, spacing * 0.3, max(fw.x, fw.y));
	return max(l.x, l.y) * fade;
}

void fragment() {
	vec2 p = wpos.xz;
	float g = grid(p, 0.25, 0.004) * 0.13;
	g = max(g, grid(p, 1.0, 0.009) * 0.3);
	g = max(g, grid(p, 5.0, 0.022) * 0.55);
	vec2 fw = fwidth(p);
	vec2 ad = abs(p);
	float axis = max(1.0 - smoothstep(0.025, 0.025 + fw.x * 1.5, ad.x),
			1.0 - smoothstep(0.025, 0.025 + fw.y * 1.5, ad.y));
	g = max(g, axis * 0.6);
	float n = vnoise(p * 3.0) * 0.5 + vnoise(p * 19.0) * 0.5;
	vec3 base = paper * (0.88 + 0.22 * n);
	ALBEDO = mix(base, ink, g);
	EMISSION = ink * g * 0.12;
	ROUGHNESS = 0.8 - g * 0.2;
	SPECULAR = 0.35;
}
