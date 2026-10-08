extends StaticBody3D
## Stanowisko obrony przeciwlotniczej, które obsługuje gracz [F]:
##  - "gun": podwójne działko 23 mm (ZU-23-2) — bardzo szybki ogień, taśma 120 naboi, przeładowanie,
##  - "sam": wyrzutnia 4 rakiet przeciwlotniczych — sama namierza samolot / śmigłowiec w celowniku,
##    LPM odpala rakietę naprowadzaną (missile.gd); po wystrzelaniu wszystkich przeładowanie.
## Mysz obraca wieżę i podnosi lufy, PPM — przybliżenie (działko). Obsługujący siedzi odkryty.
## Multiplayer: obsadzenie, obrót i ogień widać u drugiego gracza; obrażenia liczy strzelający.

const Player = preload("res://scripts/player.gd")
const Weapons = preload("res://scripts/weapons.gd")
const FX = preload("res://scripts/fx.gd")
const Ballistics = preload("res://scripts/ballistics.gd")
const Missile = preload("res://scripts/missile.gd")

const GUN_DT := 0.06             # salwa z obu luf naraz (2 × 1000 strzałów/min)
const BELT := 120
const BELT_RELOAD := 4.0
const SAM_ROUNDS := 4
const SAM_RELOAD := 15.0
const SAM_DT := 0.8
const LOCK_TIME := 1.5
const LOCK_CONE := 0.08
const LOCK_RANGE := 2600.0
const MOUSE_SENS := 0.0022
const NET_RATE := 1.0 / 20.0
const PITCH_MIN := -0.1
const PITCH_MAX := 1.45


class Ammo:
	var cal: Dictionary
	var data: Dictionary


var kind := "gun"
var is_emplacement := true
var board_name := "działka przeciwlotniczego"
var pilot = null
var destroyed := false            # zgodność z interfejsem maszyn (stanowisko się nie niszczy)
var on_ground := true
var velocity := Vector3.ZERO
var trigger := false
var zoom := false
var third_person := false         # V: widok zza stanowiska
var ammo := BELT
var reload_t := -1.0              # >= 0: trwa przeładowanie
var lock_cand: Node3D = null
var lock_t := 0.0

var _yaw := 0.0
var _pitch := 0.3
var _turret: Node3D
var _cradle: Node3D
var _muzzles: Array = []
var _flashes: Array = []
var _tubes: Array = []
var _flash_t := 0.0
var _gun_t := 0.0
var _gun_k := 0
var _shot_n := 0
var _sam_cd := 0.0
var _beep := 0.0
var _lock_net_t := 0.0
var _cam: Camera3D
var _net_t := 0.0
var _ammo := Ammo.new()
var _home_yaw := 0.0


func _ready() -> void:
	add_to_group("emplacement")
	collision_layer = 1
	collision_mask = 0
	set_meta("mat", "metal")
	set_meta("hollow", 0.0)
	set_meta("size", Vector3(2.5, 1.2, 2.5))
	board_name = "działka przeciwlotniczego" if kind == "gun" else "wyrzutni rakiet przeciwlotniczych"
	ammo = BELT if kind == "gun" else SAM_ROUNDS
	_ammo.cal = Weapons.CAL["23x152"]
	_ammo.data = {"v0": 970.0, "zero": 600.0, "cal": "23x152"}
	_home_yaw = rotation.y
	_yaw = rotation.y
	_build_model()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 0.9, 2.4)
	cs.shape = bs
	cs.position = Vector3(0, 0.45, 0)
	add_child(cs)
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.near = 0.05
	_cam.far = 3500.0
	_cam.fov = 70.0
	add_child(_cam)
	if Player.net_on:
		var gd := _gd()
		for f in [net_mount, net_unmount, net_aim, net_launch]:
			gd.expose_func(f)


func _gd() -> Node:
	return get_node("/root/GDSync")


func _local() -> bool:
	return pilot != null and is_instance_valid(pilot) and not pilot.is_remote


func camera() -> Camera3D:
	return _cam


# ---------------------------------------------------------------- model

func _m(c: Color, metal := 0.4, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _add(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _cyl(r: float, h: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _build_model() -> void:
	var olive := _m(Color(0.3, 0.34, 0.24))
	var dark := _m(Color(0.1, 0.1, 0.09), 0.6, 0.45)
	var sand := _m(Color(0.55, 0.5, 0.38), 0.0, 0.95)
	# krąg z worków z piaskiem
	for k in 10:
		var a := TAU * k / 10.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.4:
			continue   # wejście od tyłu
		_add(_box(Vector3(1.0, 0.5, 0.45)), Vector3(sin(a) * 2.6, 0.25, cos(a) * 2.6), sand, self, Vector3(0, a, 0))
	_add(_cyl(1.0, 0.25), Vector3(0, 0.125, 0), dark, self)          # podstawa
	_turret = Node3D.new()
	_turret.position = Vector3(0, 0.3, 0)
	add_child(_turret)
	_add(_box(Vector3(1.4, 0.35, 1.6)), Vector3(0, 0.2, 0), olive, _turret)       # platforma obrotowa
	_add(_box(Vector3(0.5, 0.1, 0.5)), Vector3(0, 0.65, 0.75), dark, _turret)     # siedzisko
	_cradle = Node3D.new()
	_cradle.position = Vector3(0, 1.0, -0.1)
	_turret.add_child(_cradle)
	var along := Vector3(PI * 0.5, 0, 0)
	if kind == "gun":
		_add(_box(Vector3(0.9, 0.4, 0.9)), Vector3.ZERO, olive, _cradle)          # łoże z magazynkami
		for sx: float in [-0.25, 0.25]:
			_add(_cyl(0.05, 2.0, 8), Vector3(sx, 0.05, -1.3), dark, _cradle, along)
			_add(_cyl(0.075, 0.25, 8), Vector3(sx, 0.05, -2.3), dark, _cradle, along)   # hamulec wylotowy
			var mz := Node3D.new()
			mz.position = Vector3(sx, 0.05, -2.45)
			_cradle.add_child(mz)
			_muzzles.append(mz)
			var fl := MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.15
			fm.height = 0.5
			fl.mesh = fm
			var flm := StandardMaterial3D.new()
			flm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flm.albedo_color = Color(1.0, 0.8, 0.4)
			fl.material_override = flm
			fl.visible = false
			fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mz.add_child(fl)
			_flashes.append(fl)
		_add(_box(Vector3(0.05, 0.3, 0.3)), Vector3(0.6, 0.3, 0.2), dark, _cradle)   # celownik (z boku)
	else:
		# cztery tuby w kwadracie na wspólnej ramie
		_add(_box(Vector3(1.3, 1.1, 0.3)), Vector3(0, 0, 0.2), olive, _cradle)
		for i in 4:
			var p := Vector3(-0.32 if i % 2 == 0 else 0.32, -0.25 if i < 2 else 0.25, -0.8)
			_add(_cyl(0.16, 2.2, 12), p, olive, _cradle, along)
			var cap := _add(_cyl(0.13, 0.02, 12), p + Vector3(0, 0, -1.11), _m(Color(0.6, 0.6, 0.55)), _cradle, along)
			var mz := Node3D.new()
			mz.position = p + Vector3(0, 0, -1.3)
			_cradle.add_child(mz)
			_muzzles.append(mz)
			_tubes.append(cap)
		_add(_box(Vector3(0.25, 0.25, 0.4)), Vector3(0.8, 0.2, 0.0), dark, _cradle)  # głowica celownicza


# ---------------------------------------------------------------- obsadzanie

func _seat() -> Vector3:
	return _turret.global_transform * Vector3(0, 0.0, 0.85)


func can_board(p) -> bool:
	if pilot != null or p.vehicle != null:
		return false
	return p.global_position.distance_to(global_position) < 3.2


func board(p) -> void:
	_set_pilot(p)
	_yaw = _turret.global_rotation.y
	if Player.net_on:
		_gd().call_func(net_mount, p.net_id)
	_cam.current = true
	_place_camera()
	p._msg("Mysz — obrót i lufy, LPM — ogień, PPM — przybliżenie, F — zejdź" if kind == "gun" \
		else "Celuj w samolot / śmigłowiec — namierzanie samo, LPM — rakieta, F — zejdź")


func _set_pilot(p) -> void:
	pilot = p
	trigger = false
	p.enter_vehicle(self)
	_place_pilot()


func request_exit() -> void:
	var p = pilot
	_unseat(true)
	if Player.net_on:
		_gd().call_func(net_unmount)
	if p and is_instance_valid(p):
		p.camera().current = true


func _unseat(place: bool) -> void:
	if pilot == null:
		return
	var p = pilot
	pilot = null
	trigger = false
	zoom = false
	lock_cand = null
	lock_t = 0.0
	if is_instance_valid(p) and p.vehicle == self:
		p.leave_vehicle(place)
	if _cam.current:
		_cam.current = false


func exit_point() -> Vector3:
	return global_transform * Vector3(0, 0, 3.4)


func pilot_gone(p) -> void:
	if pilot == p:
		pilot = null
		trigger = false
		lock_cand = null


func _place_pilot() -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	var p = pilot
	p.global_position = _seat() - Vector3(0, 0.3, 0)
	p.velocity = Vector3.ZERO
	p.visual.global_basis = Basis(Vector3.UP, _turret.global_rotation.y)
	p.rig.crouch = 0.7
	p.rig.sprint = false
	p.rig.air = false
	p.rig.vel = Vector3.ZERO
	p.rig.aim_w = 0.0


func pilot_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := MOUSE_SENS * Settings.sens * (0.4 if zoom else 1.0)
		_yaw -= e.relative.x * k
		_pitch = clampf(_pitch - e.relative.y * k, PITCH_MIN, PITCH_MAX)
		return
	if e.is_action_pressed("attack"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		trigger = true
		if kind == "sam":
			_launch_request()
	elif e.is_action_released("attack"):
		trigger = false
	elif e.is_action_pressed("aim"):
		zoom = true
	elif e.is_action_released("aim"):
		zoom = false
	elif e.is_action_pressed("view_toggle"):
		third_person = not third_person
	elif e.is_action_pressed("use"):
		request_exit()
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func aim_dir() -> Vector3:
	return Basis.from_euler(Vector3(_pitch, _yaw, 0.0)) * Vector3.FORWARD


# ---------------------------------------------------------------- pętla

func _physics_process(dt: float) -> void:
	if pilot != null and (not is_instance_valid(pilot) or pilot.down):
		pilot = null
		trigger = false
		lock_cand = null
	if pilot != null:
		_turret.global_rotation.y = _yaw
	_cradle.rotation.x = _pitch
	_place_pilot()
	_flash_t -= dt
	if _flash_t <= 0.0:
		for f: Node3D in _flashes:
			f.visible = false
	# przeładowanie (taśma / tuby)
	if reload_t >= 0.0:
		reload_t += dt
		if reload_t >= (BELT_RELOAD if kind == "gun" else SAM_RELOAD):
			reload_t = -1.0
			ammo = BELT if kind == "gun" else SAM_ROUNDS
			_show_tubes()
			if _local():
				FX.I.play("mag_in", global_position, -2.0)
	if kind == "gun":
		_guns(dt)
	else:
		_sam_cd = maxf(_sam_cd - dt, 0.0)
		if _local():
			_tick_lock(dt)
	if _local() and Player.net_on:
		_net_t -= dt
		if _net_t <= 0.0:
			_net_t = NET_RATE
			_gd().call_func_unreliable(net_aim, _yaw, _pitch, trigger)


func _process(_dt: float) -> void:
	if _local():
		_place_camera()


func _place_camera() -> void:
	var eye := _seat() + Vector3(0, 1.6, 0)
	if kind == "sam":
		eye += Basis(Vector3.UP, _yaw) * Vector3(0.75, 0.0, 0.0)   # z boku tub (głowica celownicza)
	if third_person:
		# zza stanowiska: kamera za obsługą, środek obrazu dalej w kierunku celowania
		var pivot := global_position + Vector3.UP * 2.4
		var tgt := pivot - aim_dir() * 7.0
		tgt.y = maxf(tgt.y, global_position.y + 1.0)
		var q := PhysicsRayQueryParameters3D.create(pivot, tgt, 1, [get_rid()])
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			tgt = (r["position"] as Vector3) + (pivot - tgt).normalized() * 0.3
		_cam.global_transform = Transform3D(Basis.looking_at(aim_dir(), Vector3.UP), tgt)
		_cam.cull_mask = 0xFFFFF
		_cam.fov = lerpf(_cam.fov, (Settings.fov * 0.4) if zoom else Settings.fov, 0.2)
		return
	_cam.global_transform = Transform3D(Basis.looking_at(aim_dir(), Vector3.UP), eye)
	_cam.cull_mask = 0xFFFFF & ~Player.OWN_LAYER
	_cam.fov = lerpf(_cam.fov, (Settings.fov * 0.4) if zoom else Settings.fov, 0.2)


func _guns(dt: float) -> void:
	var live: bool = pilot != null and is_instance_valid(pilot) and not pilot.down
	if not (trigger and live) or reload_t >= 0.0:
		_gun_t = maxf(_gun_t - dt, 0.0)
		return
	if _local() or not Player.net_on:
		if ammo <= 0:
			reload_t = 0.0
			FX.I.play("mag_out", global_position, -2.0)
			return
	_gun_t -= dt
	var guard := 0
	while _gun_t <= 0.0 and guard < 3:
		guard += 1
		_gun_t += GUN_DT
		for k in _muzzles.size():
			_fire(k)


func _fire(i: int) -> void:
	var mz: Node3D = _muzzles[i]
	var m := mz.global_position
	var d := _jitter(-_cradle.global_basis.z, 0.0022)
	_shot_n += 1
	if _local() or not Player.net_on:
		ammo -= 1
	Ballistics.I.fire(pilot, _ammo, m, d, true, Vector3.ZERO, [get_rid()])
	var fl: MeshInstance3D = _flashes[i]
	fl.visible = true
	fl.scale = Vector3.ONE * randf_range(0.8, 1.4)
	_flash_t = 0.03
	FX.I.play("shot_50", m, 5.0, 0.06, 0.8, 50.0)
	if _shot_n % 5 == 0:
		FX.I.muzzle_smoke(m, d, 0.8)
		for s in get_tree().get_nodes_in_group("soldier"):
			if s != pilot and s.has_method("heard_shot"):
				s.heard_shot(global_position, pilot)


func _jitter(d: Vector3, sigma: float) -> Vector3:
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var x := d.cross(up).normalized()
	var y := x.cross(d).normalized()
	return (d + x * randfn(0.0, sigma) + y * randfn(0.0, sigma)).normalized()


# ---------------------------------------------------------------- wyrzutnia rakiet

func locked() -> bool:
	return lock_cand != null and is_instance_valid(lock_cand) and lock_t >= LOCK_TIME


func _lockable(a: Node3D, eye: Vector3, fwd: Vector3, cone: float) -> bool:
	if not is_instance_valid(a) or a.destroyed:
		return false
	var to := a.global_position - eye
	var d := to.length()
	if d > LOCK_RANGE or d < 25.0 or fwd.angle_to(to) > cone:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, a.global_position, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _tick_lock(dt: float) -> void:
	if ammo <= 0 or reload_t >= 0.0:
		lock_cand = null
		lock_t = 0.0
		return
	var eye := _cam.global_position
	var fwd := aim_dir()
	if lock_cand != null and not _lockable(lock_cand, eye, fwd, LOCK_CONE * 2.5):
		lock_cand = null
		lock_t = 0.0
	if lock_cand == null:
		var best := LOCK_CONE
		for a in get_tree().get_nodes_in_group("aircraft"):
			if a.get("pilot") == null and a.on_ground:
				continue   # stojące puste maszyny pomijamy (zimny silnik)
			if _lockable(a, eye, fwd, LOCK_CONE):
				var ang := fwd.angle_to(a.global_position - eye)
				if ang <= best:
					best = ang
					lock_cand = a
		lock_t = 0.0
	if lock_cand == null:
		return
	lock_t += dt
	lock_cand.lock_warn = 0.4
	_beep -= dt
	if _beep <= 0.0:
		_beep = 0.07 if locked() else 0.28
		FX.I.play("click", eye, -6.0, 0.0, 3.6 if locked() else 2.4, 4.0)
	_lock_net_t -= dt
	if Player.net_on and _lock_net_t <= 0.0:
		_lock_net_t = 0.3
		_gd().call_func(lock_cand.net_locked)


func _launch_request() -> void:
	if ammo <= 0 or reload_t >= 0.0 or _sam_cd > 0.0:
		return
	if not locked():
		if _local():
			pilot._msg("Brak namierzenia — trzymaj cel w celowniku")
		return
	_sam_cd = SAM_DT
	var i := SAM_ROUNDS - ammo
	var mz: Node3D = _muzzles[i % _muzzles.size()]
	var v := -_cradle.global_basis.z * 45.0
	ammo -= 1
	_show_tubes()
	_launch(mz.global_position, v, lock_cand)
	if Player.net_on:
		_gd().call_func(net_launch, mz.global_position, v, String(lock_cand.name))
	lock_t = 0.0
	if ammo <= 0:
		reload_t = 0.0


func _launch(pos: Vector3, v: Vector3, tgt: Node3D) -> void:
	var m := Missile.new()
	m.vel = v
	m.shooter = pilot
	m.target = tgt
	get_parent().add_child(m)
	m.global_position = pos
	m.global_basis = Basis.looking_at(v.normalized(), Vector3.UP)
	FX.I.play("shot_50", pos, 6.0, 0.05, 0.6, 60.0)
	for k in 3:
		FX.I.muzzle_smoke(pos - v.normalized() * 2.0, -v.normalized() * (1.0 + k * 0.5), 2.0)


func _show_tubes() -> void:
	for i in _tubes.size():
		(_tubes[i] as Node3D).visible = i >= SAM_ROUNDS - ammo


# ---------------------------------------------------------------- sieć

func net_mount(id: int) -> void:
	var p := get_parent().get_node_or_null("P%d" % id)
	if p and not p.down and pilot == null:
		_set_pilot(p)


func net_unmount() -> void:
	_unseat(true)


func net_aim(y: float, p: float, trig: bool) -> void:
	_yaw = y
	_pitch = p
	trigger = trig and pilot != null


func net_launch(pos: Vector3, v: Vector3, tgt: String) -> void:
	ammo = maxi(ammo - 1, 0)
	_show_tubes()
	if ammo <= 0:
		reload_t = 0.0
	_launch(pos, v, get_parent().get_node_or_null(tgt))
