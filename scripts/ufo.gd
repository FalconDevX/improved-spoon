extends "res://scripts/heli.gd"
## Niemiecki latający dysk („Haunebu”, model z paczki „German WW2 UFO”, ~26 m średnicy).
## Lata jak śmigłowiec (ten sam model zawisu: mysz — kierunek, W/S/A/D — ruch, Spacja / Ctrl —
## w górę / w dół), ale jest dużo szybszy, ciężej opancerzony i nie przechyla się mocno.
## Dysk wokół kopuły obraca się z prędkością napędu.
## Uzbrojenie: trzy podwójne wieżyczki 23 mm na górze dysku i trzy pod spodem — [B] przełącza
## zestaw; LPM strzela ze WSZYSTKICH sześciu luf wybranego zestawu naraz w punkt celowania
## (wieżyczki obracają się za celownikiem). PPM — bomby burzące zrzucane spod dysku.
## Jak każda maszyna latająca jest w grupie "aircraft": namierzają go działka plot., NOMADS
## i Piorun, ma flary [C].

const DIR := "res://assets/vehicles/ufo/"
const Bomb = preload("res://scripts/bomb.gd")
# środki trzech wieżyczek w siatce broni (po dwie lufy w każdej); w modelu są schowane w dysku,
# więc wycina się je z siatki i stawia na górze i pod spodem dysku
const MOUNTS := [Vector3(-2.94, -1.83, -5.19), Vector3(6.18, -1.83, -0.32), Vector3(-2.94, -1.83, 4.54)]
const MOUNT_BASE := -2.48       # spód wieżyczek w siatce broni
const TOP_R := 9.3              # wieżyczki górne: odległość od osi i wysokość podstawy
const TOP_Y := -1.75
const BOT_R := 6.2              # dolne: zwisają spod dysku
const BOT_Y := -4.35
const BOT_STOW := 1.4           # na ziemi dolne wieżyczki chowają się w kadłub
const BOMB_KIND := "he"
const BOMB_DT := 0.22

var _glow: OmniLight3D
var gun_label := ""
var rocket_label := "BOMBY"
var guns_top := false           # false — strzelają dolne wieżyczki, true — górne
var _hum_t := 0.0
var _axis := Vector3.ZERO       # oś obrotu dysku (środek siatki kadłuba)
var _spinner: Node3D            # obracająca się część dysku
var _tur_top: Array = []        # obrotnice wieżyczek (Node3D)
var _tur_bot: Array = []
var _stow := 1.0                # 1 — dolne schowane (na ziemi), 0 — wysunięte


func _init() -> void:
	board_name = "UFO"
	GEAR_H = 4.6
	SEAT = Vector3(0, -1.2, -2.0)
	EYE = Vector3(0, 3.6, -4.2)          # pod kopułą, z widokiem do przodu
	MAX_HP = 650.0
	AMMO = 3000
	MAX_TILT = 0.16
	THRUST = 13.0                        # ok. 330 km/h w poziomie
	CLIMB = 32.0
	TURN = 1.7
	CRASH_VY = 16.0
	CRASH_H = 45.0
	BOUND = 1500.0
	GUN_DT = 0.075
	GUN_CONE = PI
	paint = Color(0.45, 0.47, 0.45)
	# lufy 0–5: wieżyczki górne, 6–11: dolne (pozycje ustawia _build_model)
	var guns: Array = []
	for k in 12:
		guns.append(Vector3.ZERO)
	GUNS = guns
	PODS = [Vector3(0, -6.5, 0)]        # zrzut bomb spod środka dysku
	_update_label()


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
	if Player.net_on:
		_gd().expose_func(net_gunset)


func _mat_from(tex: String, emi: bool) -> StandardMaterial3D:
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
	return m


func _add_mesh(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	_parts.append(mi)
	return mi


## Część siatki: trójkąty, których środek spełnia warunek `keep` (wierzchołki bez zmian).
func _sub_mesh(mesh: Mesh, keep: Callable) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		var sel := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			if keep.call((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0):
				sel.append(idx[t])
				sel.append(idx[t + 1])
				sel.append(idx[t + 2])
		if sel.is_empty():
			continue
		arr[Mesh.ARRAY_INDEX] = sel
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


func _nearest_mount(c: Vector3) -> int:
	var best := 0
	for k in MOUNTS.size():
		var m: Vector3 = MOUNTS[k]
		var b: Vector3 = MOUNTS[best]
		if Vector2(c.x - m.x, c.z - m.z).length() < Vector2(c.x - b.x, c.z - b.z).length():
			best = k
	return best


func _build_model() -> void:
	_burnt = _mat(Color(0.05, 0.045, 0.04), 0.1, 0.95)
	var flm := StandardMaterial3D.new()
	flm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flm.albedo_color = Color(1.0, 0.8, 0.4)
	_spinner = Node3D.new()
	add_child(_spinner)
	if ResourceLoader.exists(DIR + "body.obj"):
		var body: Mesh = load(DIR + "body.obj")
		var bb := body.get_aabb()
		_axis = Vector3(bb.get_center().x, 0, bb.get_center().z)
		var body_mat := _mat_from("body", true)
		# kopuła (blisko osi, nad dyskiem) stoi, dysk wokół niej się obraca
		var dome := func(c: Vector3) -> bool:
			return Vector2(c.x - _axis.x, c.z - _axis.z).length() < 6.55 and c.y > -0.9
		_add_mesh(_sub_mesh(body, dome), body_mat, self)
		_spinner.position = _axis
		_add_mesh(_sub_mesh(body, func(c: Vector3) -> bool: return not dome.call(c)), body_mat, _spinner).position = -_axis
		_add_mesh(load(DIR + "gear.obj"), _mat_from("gear", false), self)
		_add_mesh(load(DIR + "walkway.obj"), _mat_from("walkway", true), self)
		var weapons: Mesh = load(DIR + "weapons.obj")
		var wmat := _mat_from("weapons", false)
		for k in MOUNTS.size():
			var tm := _sub_mesh(weapons, func(c: Vector3) -> bool: return _nearest_mount(c) == k)
			for top: bool in [true, false]:
				_turret_node(k, tm, wmat, top, flm)
	else:
		var c := CylinderMesh.new()     # zastępczy dysk (bez zaimportowanego modelu)
		c.top_radius = 6.0
		c.bottom_radius = 13.0
		c.height = 3.0
		_part(c, Vector3.ZERO, _mat(paint, 0.7, 0.4))
		for k in MOUNTS.size():
			for top: bool in [true, false]:
				_turret_node(k, null, null, top, flm)
	# kolejność luf jak w GUNS: najpierw górne, potem dolne
	var fl_top: Array = []
	var fl_bot: Array = []
	for t: Node3D in _tur_top:
		fl_top.append_array(t.get_meta("flashes"))
	for t: Node3D in _tur_bot:
		fl_bot.append_array(t.get_meta("flashes"))
	_flashes.clear()
	_flashes.append_array(fl_top + fl_bot)
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
	# poświata napędu pod dyskiem
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.55, 0.75, 1.0)
	_glow.omni_range = 18.0
	_glow.light_energy = 0.0
	_glow.position = Vector3(0, -4.0, 0)
	add_child(_glow)


## Wieżyczka k (część siatki broni) na obrotnicy: górna stoi na dysku, dolna wisi do góry nogami.
## W układzie obrotnicy lufy patrzą w −Z, obrót wokół Y kieruje je na cel.
func _turret_node(k: int, tm: Mesh, wmat: Material, top: bool, flm: Material) -> void:
	var m: Vector3 = MOUNTS[k]
	var out := Vector3(m.x - _axis.x, 0, m.z - _axis.z).normalized()
	var base := Vector3(m.x, MOUNT_BASE, m.z)
	var face := Basis.looking_at(out, Vector3.UP)     # −Z → na zewnątrz dysku
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = _axis + out * (TOP_R if top else BOT_R) + Vector3.UP * (TOP_Y if top else BOT_Y)
	var mount := Node3D.new()            # przy dolnej: odwrócenie (podstawa do góry)
	pivot.add_child(mount)
	if not top:
		mount.basis = Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, PI)
	if tm != null:
		var mi := _add_mesh(tm, wmat, mount)
		mi.transform = Transform3D(face.inverse(), face.inverse() * -base)
	var side := Vector3(-out.z, 0, out.x)
	var fls: Array = []
	for s: float in [-0.45, 0.45]:
		var g := m + out * 1.9 + side * s + Vector3.DOWN * 0.25
		var fl := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.3
		fm.height = 0.9
		fl.mesh = fm
		fl.material_override = flm
		fl.position = face.inverse() * (g - base)
		fl.visible = false
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mount.add_child(fl)
		fls.append(fl)
	pivot.set_meta("flashes", fls)
	pivot.rotation.y = atan2(-out.x, -out.z)
	(_tur_top if top else _tur_bot).append(pivot)


## Obrotnice wieżyczek wybranego zestawu idą za celownikiem; dolne chowają się na ziemi.
func _aim_turret(dt: float) -> void:
	_stow = move_toward(_stow, 1.0 if on_ground else 0.0, dt * 0.8)
	for i in _tur_bot.size():
		var t: Node3D = _tur_bot[i]
		var out := Vector3(t.position.x - _axis.x, 0, t.position.z - _axis.z).normalized()
		t.position = _axis + out * BOT_R + Vector3.UP * (BOT_Y + BOT_STOW * _stow)
	var aim := aim_point()
	for t: Node3D in (_tur_top if guns_top else _tur_bot):
		var d := global_basis.inverse() * (aim - t.global_position)
		var want := atan2(-d.x, -d.z)
		t.rotation.y = rotate_toward(t.rotation.y, want, dt * 2.5)


## Każda lufa wybranego zestawu strzela prosto w punkt celowania.
func _fire_gun(i: int) -> void:
	if (i < 6) != guns_top:
		return
	if not guns_top and _stow > 0.5:
		return   # dolne wieżyczki schowane (na ziemi)
	var fl: MeshInstance3D = _flashes[i]
	var m := fl.global_position
	var d := (aim_point() - m).normalized()
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


func pilot_input(e: InputEvent) -> void:
	if e.is_action_pressed("fire_mode"):
		set_guns(not guns_top)
		if Player.net_on:
			_gd().call_func(net_gunset, guns_top)
		if _local_pilot():
			pilot._msg("Działka: %s" % ("GÓRNE" if guns_top else "DOLNE"))
		return
	super.pilot_input(e)


func set_guns(top: bool) -> void:
	guns_top = top
	_update_label()


func _update_label() -> void:
	gun_label = "6 × 23 mm — %s  [B]" % ("góra" if guns_top else "dół")


## (zdalnie) pilot przełączył zestaw działek.
func net_gunset(top: bool) -> void:
	set_guns(top)


## PPM: seria bomb burzących spod dysku (zamiast rakiet), po wyczerpaniu przeładowanie.
func _rockets(dt: float) -> void:
	_rocket_t = maxf(_rocket_t - dt, 0.0)
	if rockets < ROCKETS and not rocket_trigger and not destroyed:
		rocket_reload += dt
		if rocket_reload >= ROCKET_RELOAD:
			rocket_reload = 0.0
			rockets = ROCKETS
	elif rocket_trigger:
		rocket_reload = 0.0
	var live: bool = pilot != null and is_instance_valid(pilot) and not pilot.down and hp > 0.0
	if not rocket_trigger or not live or rockets <= 0 or _rocket_t > 0.0 or on_ground:
		return
	_rocket_t = BOMB_DT
	var pos: Vector3 = global_transform * (PODS[0] as Vector3)
	var v := velocity + Vector3.DOWN * 2.0
	rockets -= 1
	_launch(pos, v)
	if Player.net_on:
		_gd().call_func(net_rocket, pos, v)


func _launch(pos: Vector3, v: Vector3) -> void:
	var b := Bomb.new()
	b.kind = BOMB_KIND
	b.vel = v
	b.shooter = pilot
	b.plane = self
	get_parent().add_child(b)
	b.global_position = pos
	b.global_basis = global_basis
	FX.I.play("click", pos, -2.0, 0.1, 0.5, 10.0)


func _process(dt: float) -> void:
	super._process(dt)
	if destroyed:
		_glow.light_energy = 0.0
		return
	_hum_t += dt
	_spinner.rotate_y(minf(dt, 0.1) * rpm * 2.2)
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
