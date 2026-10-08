extends Node3D
## Wybuch jądrowy w powietrzu (~200 m nad ziemią, jak Hiroszima — tu w skali mapy):
## 1) błysk: oślepiające światło na całą mapę i biały ekran dla graczy, którzy go widzą,
## 2) kula ognia: rośnie w sekundę do ~90 m, stygnie z bieli przez żółć do ciemnej czerwieni i unosi się,
## 3) fala uderzeniowa: rozchodzi się z prędkością dźwięku (343 m/s) — pierścień kurzu po ziemi,
##    na chwilę mgiełka kondensacyjna (chmura Wilsona); obrażenia i huk docierają razem z nią,
## 4) grzyb: kula ognia przechodzi w toroidalną czapę, która toczy się (w środku w górę, na zewnątrz w dół)
##    i wznosi na ~1,2 km; trzon z kurzu i dymu zassany z ziemi; u podstawy pierścień kurzu.
## Obrażenia: żołnierze bliżej niż LETHAL giną od błysku i fali, dalej do HURT — ogłuszenie i rany;
## pojazdy i samoloty dostają obrażenia malejące z odległością, gdy dotrze do nich fala.

const FX = preload("res://scripts/fx.gd")
const Player = preload("res://scripts/player.gd")
const Bunker = preload("res://scripts/bunker.gd")

const SOUND := 343.0          # prędkość fali / dźwięku [m/s]
const LETHAL := 480.0         # promień pewnej śmierci (od punktu zero na ziemi) [m]
const HURT := 900.0           # promień ogłuszenia i ran
const WRECK := 650.0          # pojazdy: zniszczone bliżej, uszkodzone dalej (do 2 × WRECK)
const LIFE := 150.0           # po tylu sekundach chmura znika

const N_CAP := 240
const N_DOME := 90
const N_STEM := 150
const N_SKIRT := 60
const N_DUST := 70

var shooter = null
var _t := 0.0
var _gz := Vector3.ZERO       # punkt zero na ziemi
var _burst_h := 200.0
var _seed: PackedFloat32Array
var _mm: MultiMesh
var _fireball: MeshInstance3D
var _fb_mat: ShaderMaterial
var _shock: MeshInstance3D
var _shock_mat: StandardMaterial3D
var _wilson: MeshInstance3D
var _wilson_mat: StandardMaterial3D
var _light: OmniLight3D
var _flash: ColorRect
var _hit := {}                # kogo fala już dosięgła
var _sounds := 0


func _ready() -> void:
	var r := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 2000.0, 1))
	_gz = r["position"] if not r.is_empty() else Vector3(global_position.x, 0.0, global_position.z)
	_burst_h = global_position.y - _gz.y
	_seed = PackedFloat32Array()
	for i in N_CAP + N_DOME + N_STEM + N_SKIRT + N_DUST:
		_seed.append(randf())
	_build_cloud()
	_build_fireball()
	_build_shock()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.95, 0.85)
	_light.omni_range = 4096.0
	_light.omni_attenuation = 0.6
	_light.light_energy = 60.0
	_light.shadow_enabled = false
	add_child(_light)
	_flash_screen()
	_scorch()


# ---------------------------------------------------------------- alarm

const Sfx = preload("res://scripts/sfx.gd")
const SIRENS := [Vector3(0, 12, 0), Vector3(600, 12, 30), Vector3(40, 14, 215), Vector3(-300, 12, -60)]
static var _siren_wav: AudioStreamWAV


## Zrzut bomby atomowej: syreny w bazie, na lotnisku i w wiosce wyją przez `dur` sekund, gracze
## dostają ostrzeżenie (do schronu!).
static func alarm(parent: Node, dur: float) -> void:
	if _siren_wav == null:
		_siren_wav = Sfx.siren()
	for i in SIRENS.size():
		var a := AudioStreamPlayer3D.new()
		a.stream = _siren_wav
		a.unit_size = 90.0
		a.max_distance = 3500.0
		a.volume_db = 8.0
		a.attenuation_filter_cutoff_hz = 9000.0
		a.pitch_scale = 1.0 + 0.03 * i
		parent.add_child(a)
		a.global_position = SIRENS[i]
		a.play(0.7 * i)
		var tw := a.create_tween()
		tw.tween_interval(dur)
		tw.tween_property(a, "volume_db", -60.0, 4.0)
		tw.tween_callback(a.queue_free)
	for p in parent.get_tree().get_nodes_in_group("player"):
		if p.has_method("_msg") and not p.is_remote:
			p._msg("ALARM ATOMOWY! Bomba spada — natychmiast do bunkra!")


# ---------------------------------------------------------------- budowa

const PUFF := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform sampler2D tex : source_color, filter_linear_mipmap;
varying vec4 cust;
varying vec3 col;
void vertex() {
	// billboard z rozmiarem z transformacji instancji
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	cust = INSTANCE_CUSTOM;
	col = COLOR.rgb;
}
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	vec2 q = UV * 3.0 + cust.b * 37.0 + TIME * 0.02;
	float n = n2(q) * 0.55 + n2(q * 2.3) * 0.3 + n2(q * 5.1) * 0.15;
	float a = smoothstep(1.0, 0.35, r + (n - 0.5) * 0.7) * smoothstep(1.0, 0.75, r) * texture(tex, UV).a;
	// cieniowanie: góra kłębu jaśniejsza (słońce z góry), dół ciemniejszy, krawędź z prześwitem
	float lit = clamp(0.55 + (0.5 - UV.y) * 0.9 + (n - 0.5) * 0.5, 0.15, 1.2);
	vec3 smoke = col * lit;
	// żar: od bieli przez żółć do czerwieni, wygasa z cust.r
	float heat = cust.r;
	vec3 fire = mix(vec3(1.0, 0.25, 0.04), mix(vec3(1.0, 0.7, 0.25), vec3(1.0, 0.97, 0.85), clamp(heat * 2.0 - 1.0, 0.0, 1.0)), clamp(heat * 2.0, 0.0, 1.0));
	float core = clamp(heat * 1.4 * (1.0 - r * 0.6) + (n - 0.5) * heat, 0.0, 1.0);
	ALBEDO = mix(smoke, fire * (1.0 + heat * 2.5), core);
	ALPHA = a * cust.g;
}
"""


func _build_cloud() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.instance_count = N_CAP + N_DOME + N_STEM + N_SKIRT + N_DUST
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PUFF
	mat.shader = sh
	mat.set_shader_parameter("tex", FX._cache["dot"])
	q.material = mat
	_mm.mesh = q
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-3000, -400, -3000), Vector3(6000, 3000, 6000))
	add_child(mi)
	mi.top_level = true
	mi.global_transform = Transform3D.IDENTITY
	for i in _mm.instance_count:
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), _gz))


const FIREBALL := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform float heat = 1.0;
uniform float fade = 1.0;
float h(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float n3(vec3 p) { vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z); }
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 p = lp * 3.0 + vec3(0.0, -TIME * 0.4, 0.0);
	float n = n3(p) * 0.5 + n3(p * 2.1) * 0.3 + n3(p * 4.3) * 0.2;
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float t = clamp(heat - n * 0.35 - rim * 0.3, 0.0, 1.0);
	vec3 c = mix(vec3(0.25, 0.04, 0.0), vec3(1.0, 0.35, 0.05), smoothstep(0.0, 0.35, t));
	c = mix(c, vec3(1.0, 0.8, 0.35), smoothstep(0.35, 0.7, t));
	c = mix(c, vec3(1.0, 1.0, 0.95), smoothstep(0.7, 1.0, t));
	ALBEDO = c * (1.0 + heat * 4.0);
	ALPHA = fade;
}
"""


func _build_fireball() -> void:
	_fireball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 48
	s.rings = 24
	_fireball.mesh = s
	_fb_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FIREBALL
	_fb_mat.shader = sh
	_fireball.material_override = _fb_mat
	_fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fireball)
	_fireball.top_level = true
	_fireball.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 2.0), global_position)


func _build_shock() -> void:
	# pierścień kurzu przy ziemi (spłaszczony torus) — czoło fali uderzeniowej
	_shock = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 96
	t.ring_segments = 8
	_shock.mesh = t
	_shock_mat = StandardMaterial3D.new()
	_shock_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shock_mat.albedo_color = Color(0.62, 0.56, 0.47, 0.0)
	_shock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shock.material_override = _shock_mat
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shock)
	_shock.top_level = true
	_shock.visible = false
	# chmura Wilsona: półprzezroczysta biała powłoka za czołem fali w wilgotnym powietrzu
	_wilson = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	_wilson.mesh = sp
	_wilson_mat = StandardMaterial3D.new()
	_wilson_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wilson_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wilson_mat.albedo_color = Color(1, 1, 1, 0.0)
	_wilson_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wilson.material_override = _wilson_mat
	_wilson.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wilson)
	_wilson.top_level = true


func _flash_screen() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if Bunker.underground(cam.global_position):
		return
	var d := cam.global_position.distance_to(global_position)
	var facing := (-cam.global_basis.z).dot((global_position - cam.global_position).normalized())
	var a := clampf(1.3 - d / 4000.0, 0.25, 1.0) * clampf(0.55 + facing * 0.6, 0.35, 1.0)
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 0.97, a)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_flash)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_flash, "color:a", 0.0, 3.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


## Spalona ziemia wokół punktu zero.
func _scorch() -> void:
	for k in 2:
		var d := Decal.new()
		d.texture_albedo = FX._cache["dot"]
		d.modulate = Color(0.04, 0.03, 0.025, 0.85 if k == 0 else 0.45)
		var s := 380.0 if k == 0 else 900.0
		d.size = Vector3(s, 600.0, s)
		d.cull_mask = FX.FLOOR_LAYER
		add_child(d)
		d.top_level = true
		d.global_position = _gz


# ---------------------------------------------------------------- przebieg

func _process(dt: float) -> void:
	_t += dt
	var t := _t
	# światło: oślepiający błysk, potem żar kuli ognia
	_light.light_energy = 60.0 * exp(-t * 3.0) + 8.0 * clampf(1.0 - t / 12.0, 0.0, 1.0)
	_light.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.45, 0.15), clampf(t / 3.0, 0.0, 1.0))
	_light.omni_range = 4096.0 if t < 2.0 else 1500.0
	if t > 12.0 and _light.visible:
		_light.visible = false
	# kula ognia: rośnie, stygnie, unosi się i wtapia w czapę grzyba
	var rise := _cap_height(t)
	var fb_r := 90.0 * (1.0 - exp(-t * 3.5)) + 10.0
	var heat := clampf(1.0 - t / 9.0, 0.0, 1.0)
	_fb_mat.set_shader_parameter("heat", heat)
	_fb_mat.set_shader_parameter("fade", clampf(1.0 - (t - 6.0) / 6.0, 0.0, 1.0))
	_fireball.global_transform = Transform3D(Basis.from_scale(Vector3(fb_r, fb_r * 0.92, fb_r)), Vector3(_gz.x, _gz.y + rise, _gz.z))
	_fireball.visible = t < 12.0
	# fala uderzeniowa
	var dist_ground := sqrt(maxf(pow(SOUND * t, 2.0) - _burst_h * _burst_h, 0.0))  # gdzie czoło dotyka ziemi
	_shock.visible = dist_ground > 1.0 and dist_ground < 2600.0
	if _shock.visible:
		var hgt := 18.0 + dist_ground * 0.03
		_shock.global_transform = Transform3D(Basis.from_scale(Vector3(dist_ground, hgt * 4.0, dist_ground)), _gz + Vector3.UP * hgt * 0.5)
		_shock_mat.albedo_color.a = clampf(0.75 * (1.0 - dist_ground / 2600.0), 0.0, 0.75)
	var wr := SOUND * t
	_wilson.visible = t > 0.15 and t < 2.4
	if _wilson.visible:
		_wilson.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * wr), global_position)
		_wilson_mat.albedo_color.a = 0.22 * sin(clampf((t - 0.15) / 2.25, 0.0, 1.0) * PI)
	_shockwave(t)
	_update_cloud(t)
	if t > LIFE:
		queue_free()


## Wysokość środka czapy nad punktem zero.
func _cap_height(t: float) -> float:
	return _burst_h + 1050.0 * (1.0 - exp(-t / 22.0))


func _update_cloud(t: float) -> void:
	var fade := clampf((LIFE - t) / 30.0, 0.0, 1.0)
	var grow := clampf(t / 1.5, 0.0, 1.0)
	var H := _cap_height(t)
	var R := 40.0 + 300.0 * (1.0 - exp(-t / 20.0))         # promień torusa czapy
	var r := 35.0 + 140.0 * (1.0 - exp(-t / 16.0))         # grubość czapy
	var heat_cap := clampf(1.0 - t / 10.0, 0.0, 1.0)
	var smoke_col := Color(0.62, 0.55, 0.5).lerp(Color(0.72, 0.68, 0.64), clampf(t / 40.0, 0.0, 1.0))
	var k := 0
	# czapa: kłęby na torusie, toczące się (kąt wokół przekroju rośnie z czasem)
	for i in N_CAP:
		var s := _seed[k]
		var th := TAU * (float(i) / N_CAP) * 7.0 + s * 0.6
		var ph := s * TAU + t * 0.18 * (1.0 + s * 0.3)
		var rr := r * (0.65 + 0.35 * fmod(s * 7.13, 1.0))
		var ring := R + cos(ph) * rr
		var p := _gz + Vector3(cos(th) * ring, H + sin(ph) * rr * 0.8, sin(th) * ring)
		var size := (r * 1.05 + 25.0) * (0.7 + 0.5 * fmod(s * 3.7, 1.0)) * grow
		# wnętrze i spód czapy dłużej żarzą się na czerwono
		var inner := clampf(0.5 - sin(ph) * 0.5, 0.0, 1.0)
		var shade := 0.75 + 0.3 * sin(ph)        # spód czapy w cieniu, wierzch jasny
		_put(k, p, size, Color(smoke_col.r * shade, smoke_col.g * shade * 0.95, smoke_col.b * shade * 0.9), heat_cap * (0.5 + inner * 0.5), fade)
		k += 1
	# kopuła: wierzch czapy domyka środek torusa (grzyb z daleka jest pełny, nie pierścień)
	for i in N_DOME:
		var s := _seed[k]
		var a := s * TAU * 17.0
		var u := fmod(s * 9.31, 1.0)
		var rad := sqrt(u) * R * 0.95
		var p := _gz + Vector3(cos(a) * rad, H + r * (0.55 + 0.35 * (1.0 - u)), sin(a) * rad)
		var size := (r * 1.1 + 25.0) * (0.75 + 0.4 * fmod(s * 2.3, 1.0)) * grow
		_put(k, p, size, smoke_col * 1.05, heat_cap * 0.6, fade)
		k += 1
	# trzon: kurz i dym zasysany w górę (kłęby wędrują od ziemi do czapy)
	var stem_top := maxf(H - r * 0.6, 0.0)
	var stem_r := 18.0 + 42.0 * (1.0 - exp(-t / 25.0))
	var stem_on := clampf((t - 1.5) / 4.0, 0.0, 1.0)
	for i in N_STEM:
		var s := _seed[k]
		var f := fmod(s + t * 0.035, 1.0)
		var a := s * TAU * 13.0 + t * 0.3
		var rad := stem_r * (0.4 + 0.6 * fmod(s * 5.3, 1.0)) * (1.0 + (1.0 - f) * 0.6)
		var p := _gz + Vector3(cos(a) * rad, f * stem_top, sin(a) * rad)
		var size := (stem_r * 1.4 + 18.0) * (0.7 + 0.5 * fmod(s * 2.9, 1.0)) * stem_on * clampf(f * 6.0, 0.3, 1.0)
		var dust := Color(0.5, 0.43, 0.35).lerp(smoke_col * 0.9, f)
		_put(k, p, size, dust, heat_cap * f * 0.4, 0.95 * fade * stem_on)
		k += 1
	# kołnierz pod czapą (pierścień kondensacji / spódnica) — tylko na początku wznoszenia
	var sk := clampf((t - 4.0) / 5.0, 0.0, 1.0) * clampf((40.0 - t) / 15.0, 0.0, 1.0)
	for i in N_SKIRT:
		var s := _seed[k]
		var a := TAU * float(i) / N_SKIRT + s * 0.2
		var rad := R * 0.9 + r * 0.6
		var p := _gz + Vector3(cos(a) * rad, H - r * 1.1 - 40.0 * s, sin(a) * rad)
		_put(k, p, (r * 0.9 + 20.0) * sk, Color(0.85, 0.85, 0.85), 0.0, 0.55 * sk * fade)
		k += 1
	# kurz przy ziemi: pierścień niesiony falą, potem rozlewa się i opada
	var base_r := minf(SOUND * maxf(t - 0.6, 0.0) * 0.45, 260.0 + t * 6.0)
	var dust_on := clampf((t - 0.6) / 2.0, 0.0, 1.0)
	for i in N_DUST:
		var s := _seed[k]
		var a := TAU * float(i) / N_DUST + s * 0.4
		var rad := base_r * (0.55 + 0.45 * fmod(s * 4.1, 1.0))
		var p := _gz + Vector3(cos(a) * rad, 15.0 + 35.0 * fmod(s * 6.7, 1.0) * dust_on, sin(a) * rad)
		_put(k, p, (55.0 + 45.0 * s) * dust_on, Color(0.6, 0.52, 0.42), 0.0, 0.8 * dust_on * fade)
		k += 1


func _put(i: int, p: Vector3, size: float, c: Color, heat: float, alpha: float) -> void:
	_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * maxf(size, 0.001)), p))
	_mm.set_instance_color(i, c)
	_mm.set_instance_custom_data(i, Color(heat, alpha, _seed[i], 0.0))


# ---------------------------------------------------------------- skutki

## Fala dociera do kolejnych celów (odległość / prędkość dźwięku): obrażenia, wstrząs, huk.
func _shockwave(t: float) -> void:
	var front := SOUND * t
	var sh = shooter if (shooter != null and is_instance_valid(shooter)) else null
	var mine: bool = not Player.net_on or (sh != null and sh.get("is_remote") == false)
	# błysk: w promieniu śmierci ginie się od razu (promieniowanie cieplne), reszta czeka na falę
	for s in get_tree().get_nodes_in_group("soldier"):
		if _hit.has(s) or s.down or s.get("is_remote") == true:
			continue
		if Bunker.underground(s.global_position):
			continue   # w schronie: 10 m skały i betonu nad głową
		var d: float = s.global_position.distance_to(global_position)
		var dg := Vector2(s.global_position.x - _gz.x, s.global_position.z - _gz.z).length()
		if dg < LETHAL * 0.6 or d < front:
			_hit[s] = true
			if dg < LETHAL:
				if sh != null and sh != s:
					s.last_shooter = sh
					s.last_hit_seg = "torso"
				s.vitals._die()
				var away: Vector3 = (s.global_position - _gz).normalized() + Vector3.UP * 0.4
				s._collapse(away.normalized(), s.chest_pos(), "torso", 12000.0, true)
			elif dg < HURT:
				s.vitals.blunt(clampf((HURT - dg) / (HURT - LETHAL), 0.3, 1.0) * 2.0)
	for p in get_tree().get_nodes_in_group("player"):
		var key := "shake_%d" % p.get_instance_id()
		if _hit.has(key):
			continue
		var d: float = p.global_position.distance_to(global_position)
		if d < front:
			_hit[key] = true
			var k := 0.35 if Bunker.underground(p.global_position) else 1.0
			p._trauma = minf(p._trauma + clampf(1.6 - d / 2500.0, 0.3, 1.0) * k, 1.0)
			_boom(p.global_position, d)
	if mine:
		for v in get_tree().get_nodes_in_group("car") + get_tree().get_nodes_in_group("plane"):
			if _hit.has(v) or v.destroyed:
				continue
			var d: float = v.global_position.distance_to(global_position)
			if d < front:
				_hit[v] = true
				if d < WRECK * 2.0:
					var dmg: float = v.MAX_HP * 1.6 * clampf((WRECK * 2.0 - d) / WRECK, 0.0, 1.0)
					if dmg > 1.0:
						v._damage(dmg)
				if v is CharacterBody3D and v.has_method("_ground_y") and d < 1600.0:
					v.velocity += (v.global_position - global_position).normalized() * clampf((1600.0 - d) / 30.0, 0.0, 40.0)


## Huk: niski grzmot, a z bliska podwójny trzask; wolny „pomruk” ciągnie się jeszcze kilka sekund.
func _boom(at: Vector3, d: float) -> void:
	if _sounds > 0:
		return
	_sounds += 1
	var v := clampf(24.0 - d / 120.0, 6.0, 24.0)
	FX.I.play("boom", at + Vector3.UP * 3.0, v, 0.0, 0.42, 400.0)
	FX.I.play("boom", at + Vector3.UP * 3.0, v - 4.0, 0.0, 0.3, 400.0)
	get_tree().create_timer(0.35).timeout.connect(func(): FX.I.play("boom", at + Vector3.UP * 3.0, v - 2.0, 0.0, 0.55, 400.0))
	get_tree().create_timer(1.2).timeout.connect(func(): FX.I.play("boom", at + Vector3.UP * 3.0, v - 8.0, 0.0, 0.25, 400.0))
