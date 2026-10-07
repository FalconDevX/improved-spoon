extends CanvasLayer
## Obróbka obrazu (pod HUD-em): wyostrzenie, winieta, ziarno filmowe, lekka aberracja
## chromatyczna przy wstrząsach, czerwone krawędzie ekranu po trafieniu i szarzenie obrazu
## przy dużej utracie krwi. Filtry kolorów (Settings.grade): balans bieli, tonowanie cieni
## i świateł, kontrast, nasycenie, podniesiona czerń, czerń-biel.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.32;
uniform float grain = 0.03;
uniform float sharpen = 0.22;
uniform float damage = 0.0;     // świeże trafienie 0..1
uniform float hurt = 0.0;       // utrata krwi 0..1
uniform float shake = 0.0;      // wstrząs (aberracja)
uniform vec3 gain = vec3(1.0);          // balans bieli
uniform vec3 tone_shadow = vec3(0.0);   // zabarwienie cieni
uniform vec3 tone_high = vec3(0.0);     // zabarwienie świateł
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float fade = 0.0;               // podniesiona czerń (wyblakły film)
uniform float mono = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r = length(d * vec2(1.0, 0.8));
	float ca = (0.0015 + shake * 0.01 + damage * 0.006) * r;
	vec3 c;
	c.r = texture(screen, uv + d * ca * 2.0).r;
	c.g = texture(screen, uv).g;
	c.b = texture(screen, uv - d * ca * 2.0).b;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 blur = (texture(screen, uv + vec2(px.x, 0.0)).rgb + texture(screen, uv - vec2(px.x, 0.0)).rgb
		+ texture(screen, uv + vec2(0.0, px.y)).rgb + texture(screen, uv - vec2(0.0, px.y)).rgb) * 0.25;
	c += (c - blur) * sharpen;
	// filtr kolorów
	c *= gain;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c += mix(tone_shadow, tone_high, smoothstep(0.1, 0.8, l));
	c = (c - 0.45) * contrast + 0.45;
	l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = mix(c, vec3(l), mono);
	c = c * (1.0 - fade) + fade * 0.35;
	c = max(c, vec3(0.0));
	l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), hurt * 0.65);
	c *= 1.0 - (vignette + hurt * 0.35) * smoothstep(0.3, 0.85, r);
	// krew na krawędziach ekranu: poszarpany brzeg z szumu
	float edge = smoothstep(0.32, 0.75, r + (n2(uv * 9.0) - 0.5) * 0.18);
	float red = clamp(damage + hurt * 0.55, 0.0, 1.0);
	c = mix(c, vec3(0.35, 0.0, 0.01), edge * red * 0.8);
	c += (h(uv * 1000.0 + fract(TIME) * 37.0) - 0.5) * grain;
	COLOR = vec4(c, 1.0);
}
"""

# filtry: [gain, cienie, światła, kontrast, nasycenie, wyblaknięcie, cz-b]
const GRADES := [
	[Vector3(1.0, 0.99, 0.96), Vector3(-0.01, 0.01, 0.03), Vector3(0.03, 0.015, -0.015), 1.08, 1.04, 0.0, 0.0],   # filmowy
	[Vector3(1.0, 0.98, 0.86), Vector3(0.0, 0.012, 0.0), Vector3(0.02, 0.01, -0.03), 1.16, 0.68, 0.03, 0.0],      # wojenny
	[Vector3(1.08, 0.97, 0.84), Vector3(0.03, 0.0, 0.025), Vector3(0.04, 0.015, -0.02), 1.06, 1.1, 0.0, 0.0],     # ciepły zachód
	[Vector3(0.9, 0.97, 1.08), Vector3(0.0, 0.015, 0.045), Vector3(0.0, 0.01, 0.02), 1.05, 0.84, 0.02, 0.0],      # chłodny poranek
	[Vector3(1.0, 1.0, 1.0), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), 1.3, 1.0, 0.02, 1.0],                # noir
	[Vector3(1.0, 1.0, 1.0), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), 1.0, 1.0, 0.0, 0.0],                 # bez filtra
]

var main
var _rect: ColorRect
var _mat: ShaderMaterial
var _dmg := 0.0
var _last_hit := -100.0


func _ready() -> void:
	layer = 0
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	Settings.changed.connect(_apply_grade)
	_apply_grade()


func _apply_grade() -> void:
	var g: Array = GRADES[clampi(Settings.grade, 0, GRADES.size() - 1)]
	_mat.set_shader_parameter("gain", g[0])
	_mat.set_shader_parameter("tone_shadow", g[1])
	_mat.set_shader_parameter("tone_high", g[2])
	_mat.set_shader_parameter("contrast", g[3])
	_mat.set_shader_parameter("saturation", g[4])
	_mat.set_shader_parameter("fade", g[5])
	_mat.set_shader_parameter("mono", g[6])


func _process(dt: float) -> void:
	var p = main._player if main else null
	if p == null or not is_instance_valid(p):
		_mat.set_shader_parameter("damage", 0.0)
		_mat.set_shader_parameter("hurt", 0.0)
		_mat.set_shader_parameter("shake", 0.0)
		return
	if p.last_hit_time > _last_hit:
		_last_hit = p.last_hit_time
		_dmg = 1.0
	_dmg = maxf(_dmg - dt * 1.2, 0.0)
	var hurt := clampf(p.vitals.lost() * 2.2, 0.0, 1.0)
	if p.down:
		hurt = 1.0
	_mat.set_shader_parameter("damage", _dmg)
	_mat.set_shader_parameter("hurt", hurt)
	_mat.set_shader_parameter("shake", clampf(p._trauma, 0.0, 1.0))
