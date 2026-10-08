extends Node3D
## Rakieta V-2 (A4): stoi pionowo na stole startowym (v2_site.gd). Po wybraniu celu na mapie:
## odliczanie, zapłon, powolny pionowy start, przechylenie i lot balistyczny wysokim łukiem
## (apogeum 1,5–3 km), spadek prawie pionowo z ogromną prędkością. Głowica 1000 kg (bomb.gd,
## rodzaj "v2") i pożar wokół krateru (napalm.gd). Uderza szybciej niż dźwięk — bez ostrzeżenia
## dźwiękowego; HUD innych graczy pokazuje znacznik lecącej rakiety.
## Lot jest deterministyczny (ten sam cel → ten sam tor), więc w sieci wystarczy przesłać cel.

const FX = preload("res://scripts/fx.gd")
const Bomb = preload("res://scripts/bomb.gd")
const Napalm = preload("res://scripts/napalm.gd")
const Player = preload("res://scripts/player.gd")

const MODEL := "res://assets/vehicles/v2/v2.obj"
const SCALE := 0.54                 # siatka ma 25,9 m — prawdziwa V-2 ma 14 m
const BASE_Y := 11.89               # spód stateczników w siatce
const G := 9.81
const BOOST := 7.0                  # pionowy start [s]
const TURN := 3.0                   # przechylanie na tor balistyczny [s]
const BURN := 22.0                  # silnik pracuje tyle sekund (płomień, ryk)
const COUNTDOWN := 5.0

var board_name := "V-2"
var marker_name := "V-2"
var phase := 0                      # 0 na stole, 1 odliczanie, 2 start, 3 przechył, 4 balistyczny, 5 po wybuchu
var target := Vector3.ZERO
var vel := Vector3.ZERO
var shooter = null
var site = null
var _t := 0.0
var _flame: MeshInstance3D
var _light: OmniLight3D
var _snd: AudioStreamPlayer3D
var _trail: GPUParticles3D
var _body: Node3D

const MODEL_DARK := "res://assets/vehicles/v2/v2_dark.obj"   # druga połowa malowania (czarne pola)
static var _white: StandardMaterial3D
static var _black: StandardMaterial3D


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	if _white == null:
		# siatka jest podzielona na pola malowania z prób (czarno-białe); część ścian ma odwrotny
		# obieg, więc bez odrzucania tylnych ścian
		_white = StandardMaterial3D.new()
		_white.albedo_color = Color(0.9, 0.89, 0.84)
		_white.roughness = 0.6
		_white.cull_mode = BaseMaterial3D.CULL_DISABLED
		_black = _white.duplicate()
		_black.albedo_color = Color(0.07, 0.07, 0.07)
	if ResourceLoader.exists(MODEL):
		for part: Array in [[MODEL, _white], [MODEL_DARK, _black]]:
			var mi := MeshInstance3D.new()
			mi.mesh = load(part[0])
			mi.material_override = part[1]
			mi.scale = Vector3.ONE * SCALE
			mi.position = Vector3.UP * BASE_Y * SCALE        # początek węzła = spód stateczników
			_body.add_child(mi)
	else:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.3
		c.bottom_radius = 0.85
		c.height = 14.0
		mi.mesh = c
		mi.position = Vector3.UP * 7.0
		_body.add_child(mi)
	# płomień z dyszy (w dół, czyli w −Y rakiety)
	_flame = MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.55
	fm.bottom_radius = 0.1
	fm.height = 6.0
	_flame.mesh = fm
	var flm := StandardMaterial3D.new()
	flm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flm.albedo_color = Color(1.0, 0.75, 0.35, 0.85)
	flm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame.material_override = flm
	_flame.position = Vector3(0, -3.0, 0)
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	_body.add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.4)
	_light.omni_range = 40.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, -4.0, 0)
	_body.add_child(_light)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = FX._cache["rocket"]
	_snd.unit_size = 70.0
	_snd.max_distance = 5000.0
	_snd.volume_db = 10.0
	add_child(_snd)
	_trail = _make_trail()
	add_child(_trail)
	_trail.position = Vector3(0, -2.0, 0)


func _make_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 9.0
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3000, -3000, -3000), Vector3(6000, 6000, 6000))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.DOWN
	m.spread = 12.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 10.0
	m.gravity = Vector3(0, 0.4, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 2.5
	m.scale_max = 4.5
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 2.5))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.93, 0.9, 0.75))
	g.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_texture = FX._cache.get("dot")
	q.material = qm
	p.draw_pass_1 = q
	return p


## Cel wybrany: odliczanie, potem start.
func launch(at: Vector3, who) -> void:
	target = at
	shooter = who
	phase = 1
	_t = 0.0


func _physics_process(dt: float) -> void:
	if phase == 0 or phase == 5:
		return
	_t += dt
	if phase == 1:
		if _t >= COUNTDOWN:
			phase = 2
			_t = 0.0
			add_to_group("v1_flying")       # ten sam znacznik HUD / minimapy co V-1
			_flame.visible = true
			_trail.emitting = true
			_snd.play()
			FX.I.play("boom", global_position, 4.0, 0.05, 0.6, 60.0)
			if site != null and is_instance_valid(site):
				site.on_launched()
		return
	var p0 := global_position
	if phase == 2:
		# pionowo w górę, ciąg rośnie w miarę wypalania paliwa
		vel.y += lerpf(6.0, 26.0, clampf(_t / BOOST, 0.0, 1.0)) * dt
		if _t >= BOOST:
			phase = 3
			_t = 0.0
	elif phase == 3:
		var want := _ballistic_v(p0)
		vel = vel.lerp(want, minf(dt * 1.6, 1.0))
		if _t >= TURN:
			phase = 4
			_t = 0.0
			vel = _ballistic_v(p0)
	else:
		vel.y -= G * dt
	var p1 := p0 + vel * dt
	if _hit_aircraft(p1):
		return
	if phase >= 3:
		var excl: Array[RID] = []
		if site != null and is_instance_valid(site):
			excl.append_array(site.body_rids())
		var r := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p0, p1, 1 | 4 | 32, excl))
		if not r.is_empty():
			_explode(r["position"])
			return
	global_position = p1
	if vel.length() > 1.0:
		# oś rakiety (+Y) wzdłuż prędkości
		var up := vel.normalized()
		var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
		var x := up.cross(ref).normalized()
		global_basis = Basis(x, up, x.cross(up))
	_engine(dt)
	if p1.y < -100.0 or _ft > 200.0:
		_explode(p1)

var _ft := 0.0                      # czas od zapłonu


## Zderzenie w locie z samolotem, śmigłowcem albo UFO (promień kolizji jest cienki — sprawdzane
## zbliżenie do bryły maszyny): wybuch na miejscu.
func _hit_aircraft(p: Vector3) -> bool:
	for a in get_tree().get_nodes_in_group("aircraft"):
		if a.get("destroyed") == true:
			continue
		var sz: Vector3 = a.get_meta("size", Vector3(12, 4, 12))
		var r := maxf(sz.x, sz.z) * 0.45 + 1.0
		var lp: Vector3 = a.global_transform.affine_inverse() * p
		if absf(lp.y) < sz.y * 0.6 + 1.0 and Vector2(lp.x, lp.z).length() < r:
			_explode(p)
			return true
	return false


## Prędkość, z którą lot balistyczny z punktu p trafi w cel (apogeum zależne od odległości).
func _ballistic_v(p: Vector3) -> Vector3:
	var flat := Vector2(target.x - p.x, target.z - p.z)
	var dist := flat.length()
	var apex := maxf(p.y + 300.0, target.y + clampf(dist * 1.0, 1500.0, 3000.0))
	var vy := sqrt(2.0 * G * (apex - p.y))
	var tu := vy / G
	var td := sqrt(2.0 * maxf(apex - target.y, 1.0) / G)
	var hv := flat / (tu + td)
	return Vector3(hv.x, vy, hv.y)


func _engine(dt: float) -> void:
	_ft += dt
	var burning := phase >= 2 and _ft < BURN
	if _flame.visible != burning:
		_flame.visible = burning
		_trail.emitting = burning
		if not burning:
			_snd.stop()
			_light.light_energy = 0.0
	if burning:
		var fl := 0.85 + 0.15 * sin(_ft * 60.0) + randf_range(-0.05, 0.05)
		_flame.scale = Vector3(1.0, fl * (1.0 + minf(_ft / 4.0, 1.0)), 1.0)
		_light.light_energy = 6.0 * fl


## Uderzenie: głowica i pożar dookoła.
func _explode(pos: Vector3) -> void:
	if phase == 5:
		return
	phase = 5
	var world: Node = site.get_parent() if (site != null and is_instance_valid(site)) else get_parent()
	var b := Bomb.new()
	b.kind = "v2"
	b.shooter = shooter if (shooter != null and is_instance_valid(shooter)) else null
	world.add_child(b)
	b.global_position = pos
	b._explode(pos)
	FX.I.explosion(pos + Vector3.UP * 6.0, 9.0)
	# kula ognia, pierścień pyłu po ziemi i wysoki słup dymu
	FX.I._burst(pos + Vector3.UP * 5.0, 90, 2.2, 10.0, 45.0, Vector3(0, 6.0, 0),
		[Color(1.0, 0.9, 0.55, 1.0), Color(1.0, 0.45, 0.08, 0.9), Color(0.2, 0.12, 0.08, 0.0)], 9.0, true)
	FX.I._burst(pos + Vector3.UP * 1.5, 70, 5.0, 25.0, 60.0, Vector3(0, -1.0, 0),
		[Color(0.55, 0.47, 0.36, 0.85), Color(0.5, 0.45, 0.38, 0.5), Color(0.5, 0.45, 0.4, 0.0)], 7.0, false)
	FX.I._burst(pos + Vector3.UP * 10.0, 60, 14.0, 3.0, 12.0, Vector3(0, 5.0, 0),
		[Color(0.1, 0.09, 0.08, 0.9), Color(0.2, 0.19, 0.18, 0.6), Color(0.3, 0.3, 0.3, 0.0)], 12.0, false)
	for k in 8:
		var a := TAU * k / 8.0
		FX.I.crater(pos + Vector3(cos(a), 0, sin(a)) * 7.0)
	# pożar: sześć pasów płonącego paliwa rozchodzących się od krateru
	for k in 6:
		var d := Vector3(cos(TAU * k / 6.0 + 0.4), 0, sin(TAU * k / 6.0 + 0.4))
		var f := Napalm.new()
		f.shooter = b.shooter
		f.dir = d
		f.position = pos - d * 6.0       # przed add_child: _ready rozkłada płomienie od tej pozycji
		world.add_child(f)
	queue_free()
