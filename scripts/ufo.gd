extends "res://scripts/heli.gd"
## Niemiecki latający dysk („Haunebu”, model z paczki „German WW2 UFO”, ~26 m średnicy).
## Lata jak śmigłowiec (ten sam model zawisu: mysz — kierunek, W/S/A/D — ruch, Spacja / Ctrl —
## w górę / w dół), ale jest szybszy w pionie, ciężej opancerzony i nie przechyla się mocno.
## Uzbrojenie: trzy podwójne wieżyczki 23 mm pod krawędzią dysku — LPM strzela ze WSZYSTKICH
## sześciu luf naraz w punkt celowania; PPM — rakiety z wieżyczek. Jak każda maszyna latająca
## jest w grupie "aircraft": namierzają go działka plot., NOMADS i Piorun, ma flary [C].

const DIR := "res://assets/vehicles/ufo/"
# środki trzech wieżyczek (z siatki broni) — po dwie lufy w każdej
const MOUNTS := [Vector3(-2.94, -1.83, -5.19), Vector3(6.18, -1.83, -0.32), Vector3(-2.94, -1.83, 4.54)]

var _glow: OmniLight3D
var gun_label := "6 × działko 23 mm (3 wieżyczki)"
var _hum_t := 0.0


func _init() -> void:
	board_name = "UFO"
	GEAR_H = 4.6
	SEAT = Vector3(0, -1.2, -2.0)
	EYE = Vector3(0, 3.6, -4.2)          # pod kopułą, z widokiem do przodu
	MAX_HP = 650.0
	AMMO = 3000
	MAX_TILT = 0.16
	CLIMB = 22.0
	TURN = 1.3
	CRASH_VY = 16.0
	CRASH_H = 45.0
	BOUND = 1500.0
	GUN_DT = 0.075
	GUN_CONE = PI
	paint = Color(0.45, 0.47, 0.45)
	var guns: Array = []
	var pods: Array = []
	for m: Vector3 in MOUNTS:
		var out := Vector3(m.x, 0, m.z).normalized()
		var side := Vector3(-out.z, 0, out.x)
		for s: float in [-0.45, 0.45]:
			guns.append(m + out * 1.9 + side * s + Vector3.DOWN * 0.25)
		pods.append(m + out * 1.2 + Vector3.DOWN * 0.6)
	GUNS = guns
	PODS = pods


func _ready() -> void:
	super._ready()
	_mg.cal = Weapons.CAL["23x152"]
	_mg.data = {"v0": 980.0, "zero": 300.0, "cal": "23x152"}
	set_meta("size", Vector3(26.0, 9.0, 26.0))
	# kolizja: walec dysku zamiast skrzynek śmigłowca
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 12.8
	cyl.height = 4.6 + 4.9
	cs.shape = cyl
	cs.position = Vector3(0, (4.9 - 4.6) * 0.5, 0)
	add_child(cs)
	_snd.pitch_scale = 0.3


func _part_from(path: String, tex: String, emi: bool) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(DIR + tex + "_alb.png")
	m.normal_enabled = true
	m.normal_texture = load(DIR + tex + "_nrm.png")
	var orm: Texture2D = load(DIR + tex + "_orm.png")
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.metallic = 1.0
	m.metallic_texture = orm
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	if emi:
		m.emission_enabled = true
		m.emission_texture = load(DIR + tex + "_emi.png")
		m.emission_energy_multiplier = 3.0
	var mi := MeshInstance3D.new()
	mi.mesh = load(DIR + path)
	mi.material_override = m
	add_child(mi)
	_parts.append(mi)
	return mi


func _build_model() -> void:
	_burnt = _mat(Color(0.05, 0.045, 0.04), 0.1, 0.95)
	if ResourceLoader.exists(DIR + "body.obj"):
		_part_from("body.obj", "body", true)
		_part_from("gear.obj", "gear", false)
		_part_from("weapons.obj", "weapons", false)
		_part_from("walkway.obj", "walkway", true)
	else:
		var c := CylinderMesh.new()     # zastępczy dysk (bez zaimportowanego modelu)
		c.top_radius = 6.0
		c.bottom_radius = 13.0
		c.height = 3.0
		_part(c, Vector3.ZERO, _mat(paint, 0.7, 0.4))
	# węzły wspólnego kodu śmigłowca (wirnik, śmigło ogonowe, wieżyczka) — bez geometrii
	_rotor = Node3D.new()
	add_child(_rotor)
	_blades = Node3D.new()
	_rotor.add_child(_blades)
	_disc = MeshInstance3D.new()
	_rotor.add_child(_disc)
	_tail_rotor = Node3D.new()
	add_child(_tail_rotor)
	_turret = Node3D.new()
	_turret.position = Vector3(0, -1.9, 0)
	add_child(_turret)
	var flm := StandardMaterial3D.new()
	flm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flm.albedo_color = Color(1.0, 0.8, 0.4)
	for g: Vector3 in GUNS:
		var fl := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.3
		fm.height = 0.9
		fl.mesh = fm
		fl.material_override = flm
		fl.position = g
		fl.visible = false
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fl)
		_flashes.append(fl)
	# poświata napędu pod dyskiem
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.55, 0.75, 1.0)
	_glow.omni_range = 18.0
	_glow.light_energy = 0.0
	_glow.position = Vector3(0, -4.0, 0)
	add_child(_glow)


func _aim_turret(_dt: float) -> void:
	pass   # wieżyczki są częścią siatki; każda lufa celuje osobno w _fire_gun


## Każda lufa strzela prosto w punkt celowania (o ile nie celuje w głąb dysku).
func _fire_gun(i: int) -> void:
	var fl: MeshInstance3D = _flashes[i]
	var m := fl.global_position
	var d := (aim_point() - m).normalized()
	var out := (m - global_position)
	out.y = 0.0
	if d.dot(out.normalized()) < -0.35 and d.y > -0.6:
		return   # cel za dyskiem: ta lufa go nie widzi
	d = _jitter(d, 0.003)
	_shot_n += 1
	if _local_pilot() or not Player.net_on:
		ammo -= 1
	Ballistics.I.fire(pilot, _mg, m, d, _shot_n % 2 == 0, velocity, [get_rid()])
	fl.visible = true
	fl.scale = Vector3.ONE * randf_range(0.7, 1.3)
	_flash_t = 0.04
	if i % 2 == 0:
		FX.I.play("shot_50", m, 5.0, 0.06, 0.75, 40.0)
	if _shot_n % 8 == 0:
		FX.I.muzzle_smoke(m, d, 0.8)
		for s in get_tree().get_nodes_in_group("soldier"):
			if s != pilot and s.has_method("heard_shot"):
				s.heard_shot(global_position, pilot)


func _process(dt: float) -> void:
	super._process(dt)
	if destroyed:
		_glow.light_energy = 0.0
		return
	_hum_t += dt
	_glow.light_energy = rpm * (2.5 + 0.6 * sin(_hum_t * 9.0))
	if _snd.playing:
		_snd.pitch_scale = 0.22 + rpm * 0.18


func _place_camera(rd: float) -> void:
	if cockpit_view:
		super._place_camera(rd)
		return
	# widok z zewnątrz: dalej i wyżej niż za śmigłowcem (dysk ma 26 m)
	var aim := aim_dir()
	var tgt := global_position - aim * 42.0 + Vector3.UP * 12.0
	var k := 1.0 - exp(-8.0 * rd)
	if _cam.global_position.distance_to(tgt) > 80.0:
		_cam.global_position = tgt
	else:
		_cam.global_position = _cam.global_position.lerp(tgt, k)
	_cam.global_position.y = maxf(_cam.global_position.y, 1.0)
	_cam.global_basis = Basis.looking_at(global_position + aim * 120.0 - _cam.global_position, Vector3.UP)
	_cam.cull_mask = 0xFFFFF
	_cam.fov = lerpf(_cam.fov, Settings.fov + 2.0, 1.0 - exp(-2.0 * rd))


## Wsiada się przy krawędzi dysku (pod środek nie da się podejść).
func can_board(p) -> bool:
	if destroyed or hp <= 0.0 or pilot != null or not on_ground or velocity.length() > 2.0:
		return false
	var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
	return d < 17.0 and absf(p.global_position.y - (global_position.y - GEAR_H)) < 3.0


## Wysiadanie przy końcu kładki (z tyłu dysku).
func exit_point() -> Vector3:
	var p := global_transform * Vector3(0, 0, 15.5)
	p.y = global_position.y - GEAR_H
	return p
