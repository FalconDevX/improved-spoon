extends "res://scripts/car.gd"
## Czołg Type 59 (WZ-120) — model z paczki „Type 59 / WZ-120 - Chinese Main Battle Tank”.
## Kierowca jedzie [W/S, A/D] i strzela: mysz obraca wieżę i podnosi lufę za kamerą, LPM —
## pocisk odłamkowo-burzący 100 mm (shell.gd), przeładowanie 6 s. V — widok z trzeciej osoby /
## celownik działonowego (PPM — przybliżenie). Gąsienice jak w NOMADS (sam.gd).

const Shell = preload("res://scripts/shell.gd")
const HULL = preload("res://assets/vehicles/type59/type59_hull.res")
const TURRET = preload("res://assets/vehicles/type59/type59_turret.res")
const GUN = preload("res://assets/vehicles/type59/type59_gun.res")

const TURRET_AT := Vector3(0.044, 1.302, 0.043)   # oś obrotu wieży (od środka kadłuba)
const GUN_AT := Vector3(0.0, 0.664, -1.262)       # czopy lufy (w układzie wieży)
const MUZZLE := Vector3(0.0, -0.1, -4.25)          # wylot lufy (w układzie lufy)
const GUN_MIN := -0.07                            # −4°
const GUN_MAX := 0.3                              # +17°
const TURRET_RATE := 0.6                          # rad/s (napęd elektryczny wieży)
const GUN_RATE := 0.35
const RELOAD := 6.0
const V0 := 700.0
const MASS := 36000.0

var is_tank := true
var reload_t := 0.0                # 0 = gotowe
var zoom := false

var _turret: Node3D
var _gun: Node3D
var _gun_pitch := 0.0
var _flash_t := 0.0
var _flash: MeshInstance3D
var _turret_net_t := 0.0


func _init() -> void:
	board_name = "czołgu"
	MAX_HP = 1600.0
	hp = MAX_HP
	ENGINE = MASS * 1.0
	V_MAX = 14.0              # ~50 km/h
	V_REV = 3.5
	BRAKE = MASS * 0.04
	STEER = 0.3
	SEAT = Vector3(0.6, 0.6, -2.0)
	CAM_DIST = 13.0
	BOARD_AT = Vector3(-2.0, 0.0, -1.0)


func _ready() -> void:
	super()
	mass = MASS
	center_of_mass = Vector3(0, 0.7, 0)
	set_meta("hollow", 0.06)
	set_meta("size", Vector3(3.3, 2.4, 6.3))
	if Player.net_on:
		var gd := _gd()
		for f in [net_turret, net_fire]:
			gd.expose_func(f)


# ---------------------------------------------------------------- model

func _build_model() -> void:
	_burnt = _mat(Color(0.05, 0.045, 0.04), 0.1, 0.95)
	var hull := MeshInstance3D.new()
	hull.mesh = HULL
	add_child(hull)
	_parts.append(hull)
	_turret = Node3D.new()
	_turret.position = TURRET_AT
	add_child(_turret)
	var tm := MeshInstance3D.new()
	tm.mesh = TURRET
	_turret.add_child(tm)
	_parts.append(tm)
	_gun = Node3D.new()
	_gun.position = GUN_AT
	_turret.add_child(_gun)
	var gm := MeshInstance3D.new()
	gm.mesh = GUN
	_gun.add_child(gm)
	_parts.append(gm)
	for mi: MeshInstance3D in _parts:
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m and m.metallic_texture:
				var d := m.duplicate() as StandardMaterial3D
				d.metallic = 1.0     # importer .mtl zostawia 0 (mnożnik tekstury)
				mi.set_surface_override_material(s, d)
	# błysk wystrzału
	_flash = MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.5
	fs.height = 1.6
	_flash.mesh = fs
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.8, 0.45)
	_flash.material_override = fm
	_flash.rotation.x = PI * 0.5
	_flash.position = MUZZLE + Vector3(0, 0, -0.7)
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(_flash)


func _build_body() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.2, 1.25, 6.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(2.4, 0.8, 2.6)
	cs2.shape = bs2
	cs2.position = TURRET_AT + Vector3(0, 0.4, 0)
	add_child(cs2)
	for side: float in [-1.25, 1.25]:
		for k in 5:
			var w := VehicleWheel3D.new()
			w.position = Vector3(side, 0.6, -2.3 + k * 1.15)
			w.wheel_radius = 0.4
			w.wheel_rest_length = 0.22
			w.suspension_travel = 0.18
			w.suspension_stiffness = 70.0
			w.suspension_max_force = MASS * 9.81 * 0.35
			w.damping_compression = 1.3
			w.damping_relaxation = 1.7
			w.wheel_friction_slip = 2.4
			w.wheel_roll_influence = 0.02
			w.use_as_traction = true
			w.use_as_steering = false
			add_child(w)
			_wheels.append(w)


# ---------------------------------------------------------------- sterowanie

func board(p) -> void:
	super(p)
	cockpit_view = false
	_cam_pitch = 0.0
	p._msg("W/S/A/D — jazda, mysz — wieża i lufa, LPM — strzał, PPM — przybliżenie, V — celownik, F — wysiądź")


func _unseat(place: bool) -> void:
	super(place)
	zoom = false


func pilot_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := 0.0022 * Settings.sens * (0.3 if zoom else 1.0)
		_cam_yaw -= e.relative.x * k
		_cam_pitch = clampf(_cam_pitch - e.relative.y * k, -0.6, 0.8)
		return
	if e.is_action_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_fire_request()
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
	for i in _wheels.size():
		var k := i % 5
		(_wheels[i] as VehicleWheel3D).steering = _steer_s * (1.0 if k == 0 else (-1.0 if k == 4 else 0.0))
	if _local_pilot() and not Player.chat_open:
		var turn := Input.get_axis("move_right", "move_left")
		var fwd_speed := -(global_basis.inverse() * linear_velocity).z
		if absf(turn) > 0.01 and absf(fwd_speed) < 3.0:
			apply_torque(global_basis.y * turn * MASS * 3.0)
	if _local_pilot():
		# wieża i lufa gonią kierunek kamery z ograniczoną prędkością
		var aim := aim_dir()
		var local := global_basis.inverse() * aim
		var want_y := atan2(-local.x, -local.z)
		var cur := _turret.rotation.y
		_turret.rotation.y = cur + clampf(wrapf(want_y - cur, -PI, PI), -TURRET_RATE * dt, TURRET_RATE * dt)
		var want_p := clampf(asin(clampf(local.y, -1.0, 1.0)), GUN_MIN, GUN_MAX)
		_gun_pitch = move_toward(_gun_pitch, want_p, GUN_RATE * dt)
		_gun.rotation.x = _gun_pitch
		if Player.net_on:
			_turret_net_t -= dt
			if _turret_net_t <= 0.0:
				_turret_net_t = 0.1
				_gd().call_func_unreliable(net_turret, _turret.rotation.y, _gun_pitch)
	if reload_t > 0.0:
		reload_t = maxf(reload_t - dt, 0.0)
		if reload_t <= 0.0 and _local_pilot():
			FX.I.play("mag_in", global_position, 0.0)
	_flash_t -= dt
	if _flash_t <= 0.0:
		_flash.visible = false


func _place_camera(rd: float) -> void:
	var aim := aim_dir()
	if cockpit_view:
		# celownik działonowego: przy lufie, wzdłuż osi lufy (widać, gdzie faktycznie mierzy)
		var gb := _gun.global_basis
		_cam.global_transform = Transform3D(gb.orthonormalized(), _turret.global_transform * Vector3(0.55, 0.85, -1.0))
		_cam.cull_mask = 0xFFFFF & ~Player.OWN_LAYER
		_cam.fov = lerpf(_cam.fov, Settings.fov * (0.2 if zoom else 0.6), 0.2)
		return
	var pivot := global_position + Vector3.UP * 3.0
	var tgt := pivot - aim * CAM_DIST
	tgt.y = maxf(tgt.y, global_position.y + 1.2)
	var q := PhysicsRayQueryParameters3D.create(pivot, tgt, 1, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		tgt = (r["position"] as Vector3) + (pivot - tgt).normalized() * 0.3
	_cam.global_position = _cam.global_position.lerp(tgt, 1.0 - exp(-12.0 * rd)) if _cam.global_position.distance_to(tgt) < 20.0 else tgt
	_cam.global_basis = Basis.looking_at(aim, Vector3.UP)
	_cam.cull_mask = 0xFFFFF
	_cam.fov = lerpf(_cam.fov, Settings.fov * (0.5 if zoom else 1.0), 0.2)


## Punkt, w który mierzy lufa (do znacznika w HUD): promień wzdłuż lufy.
func gun_point() -> Vector3:
	var mz := _gun.global_transform * MUZZLE
	var d := -_gun.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(mz, mz + d * 1500.0, 1 | 32, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r["position"] if not r.is_empty() else mz + d * 1500.0


# ---------------------------------------------------------------- strzał

func _fire_request() -> void:
	if reload_t > 0.0 or destroyed:
		return
	reload_t = RELOAD
	var mz := _gun.global_transform * MUZZLE
	var v := -_gun.global_basis.z * V0 + linear_velocity
	_shoot(mz, v)
	if Player.net_on:
		_gd().call_func(net_fire, mz, v)
	# odrzut: pchnięcie kadłuba do tyłu
	apply_impulse(_gun.global_basis.z * MASS * 0.35, _turret.global_position - global_position)


func _shoot(pos: Vector3, v: Vector3) -> void:
	var s := Shell.new()
	s.vel = v
	s.shooter = pilot
	s.plane = self
	get_parent().add_child(s)
	s.global_position = pos
	_flash.visible = true
	_flash_t = 0.06
	FX.I.play("shot_50", pos, 10.0, 0.04, 0.45, 120.0)
	var d := v.normalized()
	for k in 4:
		FX.I.muzzle_smoke(pos + d * 0.5, d * (2.0 + k) + Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)), 3.0)
	for p in get_tree().get_nodes_in_group("player"):
		var dp: float = p.global_position.distance_to(pos)
		if dp < 60.0:
			p._trauma = minf(p._trauma + 0.35 * (1.0 - dp / 60.0), 1.0)
	for s2 in get_tree().get_nodes_in_group("soldier"):
		if s2.has_method("heard_shot"):
			s2.heard_shot(pos, pilot)


func _reset() -> void:
	super()
	reload_t = 0.0
	_turret.rotation.y = 0.0
	_gun_pitch = 0.0
	_gun.rotation.x = 0.0


# ---------------------------------------------------------------- sieć

func net_turret(y: float, p: float) -> void:
	_turret.rotation.y = y
	_gun_pitch = p
	_gun.rotation.x = p


func net_fire(pos: Vector3, v: Vector3) -> void:
	_shoot(pos, v)
