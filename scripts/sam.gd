extends "res://scripts/car.gd"
## Mobilny zestaw przeciwlotniczy NOMADS na podwoziu gąsienicowym (model z paczki „NOMADS SAM system”).
## Kierowca jedzie [W/S, A/D] i jednocześnie obsługuje wyrzutnię: mysz obraca wieżę za kamerą,
## cel w środku obrazu jest namierzany sam (samolot / śmigłowiec), LPM odpala rakietę naprowadzaną
## (missile.gd). 4 rakiety, potem przeładowanie. V — widok z trzeciej osoby / celownik wieży
## (PPM — przybliżenie). Gąsienice: koła po obu stronach, skręt jak przy gąsienicach (przód i tył
## w przeciwne strony, w miejscu — obrót wokół osi).

const Missile = preload("res://scripts/missile.gd")
const HULL = preload("res://assets/vehicles/nomads/nomads_hull.res")
const TURRET = preload("res://assets/vehicles/nomads/nomads_turret.res")
const MISSILES := [preload("res://assets/vehicles/nomads/nomads_missile0.res"), preload("res://assets/vehicles/nomads/nomads_missile1.res"),
	preload("res://assets/vehicles/nomads/nomads_missile2.res"), preload("res://assets/vehicles/nomads/nomads_missile3.res")]

const PIVOT := Vector3(0, 1.21, 1.66)       # oś obrotu wieży (od środka kadłuba, przód -Z)
const LAUNCH_DIR := Vector3(0, 0.53, -0.848) # prowadnice rakiet: 32° w górę, w stronę przodu wieży
const SAM_ROUNDS := 4
const SAM_RELOAD := 20.0
const SAM_DT := 0.9
const LOCK_TIME := 1.5
const LOCK_CONE := 0.08
const LOCK_RANGE := 3000.0
const TURRET_RATE := 1.3                    # rad/s
const MASS := 14000.0

var is_sam := true
var ammo := SAM_ROUNDS
var reload_t := -1.0
var lock_cand: Node3D = null
var lock_t := 0.0
var zoom := false

var _turret: Node3D
var _missiles: Array[MeshInstance3D] = []
var _track_mat: StandardMaterial3D
var _track_uv := 0.0
var _sam_cd := 0.0
var _beep := 0.0
var _lock_net_t := 0.0
var _turret_net_t := 0.0


func _init() -> void:
	board_name = "wyrzutni NOMADS"
	MAX_HP = 900.0
	hp = MAX_HP
	ENGINE = MASS * 1.15     # ~0–40 km/h w ~8 s
	V_MAX = 18.0             # ~65 km/h
	V_REV = 4.0
	BRAKE = MASS * 0.04
	STEER = 0.32
	SEAT = Vector3(-0.6, 0.9, -2.2)
	EYE = Vector3(0, 0, 0)
	CAM_DIST = 14.0
	BOARD_AT = Vector3(-2.1, 0.0, -1.2)


func _ready() -> void:
	super()
	mass = MASS
	center_of_mass = Vector3(0, 0.9, 0)
	set_meta("hollow", 0.012)
	set_meta("size", Vector3(3.1, 2.4, 6.8))
	if Player.net_on:
		var gd := _gd()
		for f in [net_turret, net_launch]:
			gd.expose_func(f)


# ---------------------------------------------------------------- model

func _build_model() -> void:
	_burnt = _mat(Color(0.05, 0.045, 0.04), 0.1, 0.95)
	var hull := MeshInstance3D.new()
	hull.mesh = HULL
	add_child(hull)
	_parts.append(hull)
	_fix_mats(hull)
	_turret = Node3D.new()
	_turret.position = PIVOT
	add_child(_turret)
	var tm := MeshInstance3D.new()
	tm.mesh = TURRET
	_turret.add_child(tm)
	_parts.append(tm)
	for m: Mesh in MISSILES:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		_turret.add_child(mi)
		_missiles.append(mi)
		_parts.append(mi)


## Materiały z .mtl: przezroczystość (gąsienice, szyby, reflektory, ażurowe części karabinu)
## i przesuwanie tekstury gąsienic przy jeździe.
func _fix_mats(mi: MeshInstance3D) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
		if m == null:
			continue
		var n := m.resource_name
		if n in ["track", "headlight", "glass", "browning", "ammo"]:
			var d := m.duplicate() as StandardMaterial3D
			d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			d.alpha_scissor_threshold = 0.5
			d.cull_mode = BaseMaterial3D.CULL_DISABLED
			if n == "track":
				_track_mat = d
			mi.set_surface_override_material(s, d)


func _build_body() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.0, 1.9, 6.7)
	cs.shape = bs
	cs.position = Vector3(0, 1.4, 0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(2.4, 1.4, 3.2)
	cs2.shape = bs2
	cs2.position = Vector3(0, 3.0, PIVOT.z)
	add_child(cs2)
	# gąsienice: po 5 kół z każdej strony
	for side: float in [-1.25, 1.25]:
		for k in 5:
			var w := VehicleWheel3D.new()
			w.position = Vector3(side, 0.62, -2.5 + k * 1.25)
			w.wheel_radius = 0.42
			w.wheel_rest_length = 0.22
			w.suspension_travel = 0.2
			w.suspension_stiffness = 60.0
			w.suspension_max_force = MASS * 9.81 * 0.35
			w.damping_compression = 1.2
			w.damping_relaxation = 1.6
			w.wheel_friction_slip = 2.2
			w.wheel_roll_influence = 0.02
			w.use_as_traction = true
			w.use_as_steering = false
			add_child(w)
			_wheels.append(w)


# ---------------------------------------------------------------- sterowanie

func board(p) -> void:
	super(p)
	cockpit_view = false
	_cam_pitch = 0.15
	p._msg("W/S/A/D — jazda, mysz — wieża, LPM — rakieta (po namierzeniu), V — celownik, F — wysiądź")


func _unseat(place: bool) -> void:
	super(place)
	zoom = false
	lock_cand = null
	lock_t = 0.0


func pilot_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := 0.0022 * Settings.sens * (0.35 if zoom else 1.0)
		_cam_yaw -= e.relative.x * k
		_cam_pitch = clampf(_cam_pitch - e.relative.y * k, -0.5, 1.45)
		return
	if e.is_action_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_launch_request()
		return
	if e.is_action_pressed("aim"):
		zoom = true
	elif e.is_action_released("aim"):
		zoom = false
	super(e)


func aim_dir() -> Vector3:
	return Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0.0)) * Vector3.FORWARD


func _physics_process(dt: float) -> void:
	super(dt)
	if destroyed:
		return
	# skręt jak gąsienice: przednie koła w jedną, tylne w drugą stronę, środkowe prosto
	for i in _wheels.size():
		var k := i % 5
		(_wheels[i] as VehicleWheel3D).steering = _steer_s * (1.0 if k == 0 else (-1.0 if k == 4 else 0.0))
	if _local_pilot() and not Player.chat_open:
		var turn := Input.get_axis("move_right", "move_left")
		var fwd_speed := -(global_basis.inverse() * linear_velocity).z
		if absf(turn) > 0.01 and absf(fwd_speed) < 3.0:
			# obrót w miejscu (gąsienice w przeciwne strony)
			apply_torque(global_basis.y * turn * MASS * 3.2)
	# wieża za kamerą (kierowca celuje myszą)
	if _local_pilot():
		var want := wrapf(_cam_yaw - global_rotation.y, -PI, PI)
		var cur := _turret.rotation.y
		_turret.rotation.y = cur + clampf(wrapf(want - cur, -PI, PI), -TURRET_RATE * dt, TURRET_RATE * dt)
		_tick_lock(dt)
		if Player.net_on:
			_turret_net_t -= dt
			if _turret_net_t <= 0.0:
				_turret_net_t = 0.1
				_gd().call_func_unreliable(net_turret, _turret.rotation.y)
	_sam_cd = maxf(_sam_cd - dt, 0.0)
	if reload_t >= 0.0:
		reload_t += dt
		if reload_t >= SAM_RELOAD:
			reload_t = -1.0
			ammo = SAM_ROUNDS
			_show_missiles()
			if _local_pilot():
				FX.I.play("mag_in", global_position, -2.0)
				pilot._msg("Wyrzutnia przeładowana")


func _process(dt: float) -> void:
	super(dt)
	if _track_mat and not destroyed:
		# tekstura gąsienic przesuwa się z prędkością jazdy
		var fwd_speed := -(global_basis.inverse() * linear_velocity).z
		_track_uv = fmod(_track_uv + fwd_speed * dt * 0.25, 1.0)
		_track_mat.uv1_offset = Vector3(_track_uv, 0, 0)


func _place_camera(rd: float) -> void:
	var aim := aim_dir()
	if cockpit_view:
		# celownik wieży: nad wyrzutnią, wzdłuż kierunku celowania
		_cam.global_transform = Transform3D(Basis.looking_at(aim, Vector3.UP), _turret.global_transform * Vector3(0, 3.3, 0.2))
		_cam.cull_mask = 0xFFFFF & ~Player.OWN_LAYER
		_cam.fov = lerpf(_cam.fov, Settings.fov * (0.3 if zoom else 1.0), 0.2)
		return
	var pivot := global_position + Vector3.UP * 3.2
	var tgt := pivot - aim * CAM_DIST
	tgt.y = maxf(tgt.y, global_position.y + 1.2)
	var q := PhysicsRayQueryParameters3D.create(pivot, tgt, 1, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		tgt = (r["position"] as Vector3) + (pivot - tgt).normalized() * 0.3
	_cam.global_position = _cam.global_position.lerp(tgt, 1.0 - exp(-12.0 * rd)) if _cam.global_position.distance_to(tgt) < 20.0 else tgt
	# środek obrazu = kierunek celowania (namierzanie bierze cel ze środka)
	_cam.global_basis = Basis.looking_at(aim, Vector3.UP)
	_cam.cull_mask = 0xFFFFF
	_cam.fov = lerpf(_cam.fov, Settings.fov * (0.5 if zoom else 1.0), 0.2)


# ---------------------------------------------------------------- namierzanie i rakiety

func locked() -> bool:
	return lock_cand != null and is_instance_valid(lock_cand) and lock_t >= LOCK_TIME


func _lockable(a: Node3D, eye: Vector3, fwd: Vector3, cone: float) -> bool:
	if not is_instance_valid(a) or a.destroyed:
		return false
	var to := a.global_position - eye
	var d := to.length()
	if d > LOCK_RANGE or d < 30.0 or fwd.angle_to(to) > cone:
		return false
	# widoczność z głowicy radaru na maszcie
	var head := _turret.global_transform * Vector3(0, 4.0, 1.0)
	var q := PhysicsRayQueryParameters3D.create(head, a.global_position, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _tick_lock(dt: float) -> void:
	if ammo <= 0 or reload_t >= 0.0:
		lock_cand = null
		lock_t = 0.0
		return
	var eye := _cam.global_position
	var fwd := -_cam.global_basis.z
	if lock_cand != null and not _lockable(lock_cand, eye, fwd, LOCK_CONE * 2.5):
		lock_cand = null
		lock_t = 0.0
	if lock_cand == null:
		var best := LOCK_CONE
		for a in get_tree().get_nodes_in_group("aircraft"):
			if a.get("pilot") == null and a.on_ground:
				continue   # stojące puste maszyny (zimny silnik)
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
	if ammo <= 0 or reload_t >= 0.0 or _sam_cd > 0.0 or destroyed:
		return
	if not locked():
		if _local_pilot():
			pilot._msg("Brak namierzenia — trzymaj samolot / śmigłowiec w środku obrazu")
		return
	_sam_cd = SAM_DT
	var i := SAM_ROUNDS - ammo
	var mi: MeshInstance3D = _missiles[i]
	var dir := (_turret.global_basis * LAUNCH_DIR).normalized()
	var pos: Vector3 = mi.global_transform * mi.mesh.get_aabb().get_center() + dir * 1.6
	var v := dir * 45.0 + linear_velocity
	ammo -= 1
	_show_missiles()
	_launch(pos, v, lock_cand)
	if Player.net_on:
		_gd().call_func(net_launch, pos, v, String(lock_cand.name))
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


func _show_missiles() -> void:
	for i in _missiles.size():
		_missiles[i].visible = i >= SAM_ROUNDS - ammo


func _reset() -> void:
	super()
	ammo = SAM_ROUNDS
	reload_t = -1.0
	_show_missiles()
	_turret.rotation.y = 0.0


# ---------------------------------------------------------------- sieć

func net_turret(y: float) -> void:
	_turret.rotation.y = y


func net_launch(pos: Vector3, v: Vector3, tgt: String) -> void:
	ammo = maxi(ammo - 1, 0)
	_show_missiles()
	if ammo <= 0:
		reload_t = 0.0
	_launch(pos, v, get_parent().get_node_or_null(tgt))
