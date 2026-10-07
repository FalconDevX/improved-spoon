extends CanvasLayer
## Obróbka obrazu (pod HUD-em): wyostrzenie, winieta, ziarno filmowe, lekka aberracja
## chromatyczna przy wstrząsach, czerwone krawędzie ekranu po trafieniu i szarzenie obrazu
## przy dużej utracie krwi.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.32;
uniform float grain = 0.03;
uniform float sharpen = 0.22;
uniform float damage = 0.0;     // świeże trafienie 0..1
uniform float hurt = 0.0;       // utrata krwi 0..1
uniform float shake = 0.0;      // wstrząs (aberracja)
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
	float l = dot(c, vec3(0.299, 0.587, 0.114));
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
