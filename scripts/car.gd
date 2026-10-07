extends VehicleBody3D
## Wojskowy samochód terenowy (Humvee): napęd na cztery koła, zawieszenie, skręt przednich kół.
## Wsiadanie [F], W/S — gaz / hamulec i wsteczny, A/D — skręt, Spacja — ręczny, V — widok,
## mysz — rozglądanie się. Kule i odłamki niszczą go (dym, ogień, wybuch), wrak po chwili wraca
## na miejsce. Multiplayer: auto symuluje komputer kierowcy, reszta odtwarza jego ruch.

const Player = preload("res://scripts/player.gd")
const FX = preload("res://scripts/fx.gd")
const MODEL = preload("res://assets/vehicles/hummer.glb")

const MAX_HP := 260.0
const ENGINE := 2600.0          # ciężkie auto (2,4 t): ~0–50 km/h w 6–7 s
const V_MAX := 26.0             # prędkość maksymalna ~95 km/h
const V_REV := 5.5              # wsteczny do ~20 km/h
const BRAKE := 90.0
const STEER := 0.55
const RESPAWN := 30.0
const SEAT := Vector3(-0.45, 0.55, 0.15)    # stopy kierowcy (lewy fotel)
const EYE := Vector3(-0.47, 1.5, 0.1)
const NET_RATE := 1.0 / 20.0

var board_name := "samochodu"
var is_car := true
var home: Transform3D
var pilot = null
var auth := 0
var hp := MAX_HP
var destroyed := false
var on_ground := true
var cockpit_view := false

var _wheels: Array = []
var _parts: Array = []
var _wheel_mesh: Array = []
var _burnt: StandardMaterial3D
var _cam: Camera3D
var _cam_yaw := 0.0
var _cam_pitch := -0.25
var _snd: AudioStreamPlayer3D
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _wreck_t := 0.0
var _net_t := 0.0
var _net_xf := Transform3D()
var _net_vel := Vector3.ZERO
var _steer_s := 0.0
var _flip_t := 0.0


func _ready() -> void:
	add_to_group("car")
	collision_layer = 32
	collision_mask = 1 | 32
	mass = 2400.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.25, 0)
	set_meta("mat", "metal")
	set_meta("hollow", 0.004)
	set_meta("size", Vector3(2.2, 2.4, 4.9))
	_build_model()
	for mi: MeshInstance3D in _parts:
		mi.set_meta("mat0", mi.material_override)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.15, 1.0, 4.8)
	cs.shape = bs
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(2.1, 0.9, 2.7)
	cs2.shape = bs2
	cs2.position = Vector3(0, 1.9, 0.3)
	add_child(cs2)
	for p: Vector3 in [Vector3(-0.9, 0.69, -1.67), Vector3(0.9, 0.69, -1.67), Vector3(-0.9, 0.69, 1.6), Vector3(0.9, 0.69, 1.6)]:
		var w := VehicleWheel3D.new()
		w.position = p
		w.wheel_radius = 0.475
		w.wheel_rest_length = 0.22
		w.suspension_travel = 0.25
		w.suspension_stiffness = 45.0
		w.suspension_max_force = 12000.0
		w.damping_compression = 0.9
		w.damping_relaxation = 1.2
		w.wheel_friction_slip = 2.8
		w.wheel_roll_influence = 0.04
		w.use_as_traction = true
		w.use_as_steering = p.z < 0.0
		add_child(w)
		var tire := MeshInstance3D.new()
		tire.mesh = _wheel_mesh[0 if p.x < 0.0 else 1]
		w.add_child(tire)
		_parts.append(tire)
		_wheels.append(w)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = FX._cache["engine"]
	_snd.unit_size = 8.0
	_snd.max_distance = 250.0
	add_child(_snd)
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.near = 0.05
	_cam.far = 3500.0
	add_child(_cam)
	_smoke = _emitter(Color(0.2, 0.19, 0.18, 0.7), Color(0.35, 0.35, 0.35, 0.0), 2.5, 1.4, false)
	_fire = _emitter(Color(1.0, 0.75, 0.3, 1.0), Color(0.9, 0.2, 0.0, 0.0), 0.5, 0.8, true)
	home = global_transform
	_net_xf = global_transform
	if Player.net_on:
		var gd := _gd()
		for f in [net_car, net_board, net_exit, net_damage, net_explode]:
			gd.expose_func(f)


func _gd() -> Node:
	return get_node("/root/GDSync")


func _my_id() -> int:
	return _gd().get_client_id() if Player.net_on else 0


func _sim_here() -> bool:
	return not Player.net_on or auth == 0 or auth == _my_id()


func _local_pilot() -> bool:
	return pilot != null and is_instance_valid(pilot) and not pilot.is_remote and pilot.is_in_group("player")


func camera() -> Camera3D:
	return _cam


# ---------------------------------------------------------------- model

func _mat(c: Color, metal := 0.25, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _build_model() -> void:
	_burnt = _mat(Color(0.05, 0.045, 0.04), 0.1, 0.95)
	# model Hummera (assets/vehicles/hummer.glb): nadwozie + osobne koło lewe i prawe
	var m: Node3D = MODEL.instantiate()
	var body: MeshInstance3D = m.get_node("Body")
	m.remove_child(body)
	body.owner = null
	add_child(body)
	_parts.append(body)
	_wheel_mesh = [(m.get_node("WheelL") as MeshInstance3D).mesh, (m.get_node("WheelR") as MeshInstance3D).mesh]
	m.free()


func _emitter(c0: Color, c1: Color, life: float, size: float, add: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.position = Vector3(0, 1.5, -1.5)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 40, 80))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.8
	m.gravity = Vector3(0, 1.2 if not add else 2.0, 0)
	m.scale_min = 0.6
	m.scale_max = 1.4
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = FX._cache["dot"]
	if add:
		mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = mm
	p.draw_pass_1 = q
	add_child(p)
	return p


# ---------------------------------------------------------------- wsiadanie

func can_board(p) -> bool:
	if destroyed or pilot != null:
		return false
	return p.global_position.distance_to(global_transform * Vector3(-1.6, 0.0, 0.2)) < 2.6


func board(p) -> void:
	_set_pilot(p)
	if Player.net_on:
		auth = _my_id()
		_gd().call_func(net_board, p.net_id)
	_cam_yaw = global_rotation.y
	_cam.current = true
	cockpit_view = false
	p._msg("W/S — gaz / hamulec, A/D — skręt, Spacja — ręczny, V — widok, F — wysiądź")


func _set_pilot(p) -> void:
	pilot = p
	p.enter_vehicle(self)
	_seat_pilot()


func request_exit() -> void:
	if linear_velocity.length() > 4.0:
		if _local_pilot():
			pilot._msg("Zatrzymaj się, żeby wysiąść")
		return
	var p = pilot
	_unseat(true)
	if Player.net_on:
		_gd().call_func(net_exit)
	if p and is_instance_valid(p):
		p.camera().current = true


func _unseat(place: bool) -> void:
	if pilot == null:
		return
	var p = pilot
	pilot = null
	engine_force = 0.0
	brake = BRAKE * 0.5
	if is_instance_valid(p) and p.vehicle == self:
		p.leave_vehicle(place)
	if _cam.current:
		_cam.current = false


func exit_point() -> Vector3:
	var p := global_transform * Vector3(-1.9, 0, 0.2)
	p.y = global_position.y + 0.2
	return p


func pilot_gone(p) -> void:
	if pilot == p:
		pilot = null
		engine_force = 0.0


func _seat_pilot() -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	var p = pilot
	p.global_position = global_transform * SEAT
	p.velocity = linear_velocity
	p.visual.global_basis = global_basis
	p.rig.crouch = 1.0
	p.rig.sprint = false
	p.rig.air = false
	p.rig.vel = Vector3.ZERO
	p.rig.aim_w = 0.0


func pilot_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= e.relative.x * 0.0022 * Settings.sens
		_cam_pitch = clampf(_cam_pitch - e.relative.y * 0.0022 * Settings.sens, -1.2, 0.6)
		return
	if e.is_action_pressed("use"):
		request_exit()
	elif e.is_action_pressed("view_toggle"):
		cockpit_view = not cockpit_view
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e.is_action_pressed("attack") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- jazda

func _physics_process(dt: float) -> void:
	if destroyed:
		_wreck_t += dt
		if _wreck_t >= RESPAWN:
			_reset()
		return
	if pilot != null and (not is_instance_valid(pilot) or pilot.down):
		pilot = null
	if not _sim_here():
		_follow(dt)
		_seat_pilot()
		return
	freeze = false
	var gas := 0.0
	var turn := 0.0
	var hand := false
	if _local_pilot() and not Player.chat_open:
		gas = Input.get_axis("move_back", "move_forward")
		turn = Input.get_axis("move_right", "move_left")
		hand = Input.is_action_pressed("jump")
	var fwd_speed := -(global_basis.inverse() * linear_velocity).z
	var eng := 0.5 if hp < MAX_HP * 0.3 else 1.0
	if gas > 0.0:
		# siła maleje z prędkością (biegi, opór) — do zera przy V_MAX
		engine_force = -ENGINE * gas * eng * clampf(1.0 - pow(maxf(fwd_speed, 0.0) / V_MAX, 2.0), 0.0, 1.0) if fwd_speed > -1.0 else 0.0
		brake = 0.0 if fwd_speed > -1.0 else BRAKE
	elif gas < 0.0:
		# hamowanie, po zatrzymaniu wsteczny
		if fwd_speed > 1.0:
			engine_force = 0.0
			brake = BRAKE
		else:
			engine_force = ENGINE * 0.7 * -gas * eng * clampf(1.0 + fwd_speed / V_REV, 0.0, 1.0)
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 3.0 if pilot != null else BRAKE * 0.3
	if hand:
		brake = BRAKE * 1.5
	# skręt łagodniejszy przy dużej prędkości
	var lim := STEER * clampf(1.0 - absf(fwd_speed) / 40.0, 0.35, 1.0)
	_steer_s = move_toward(_steer_s, turn * lim, dt * 2.2)
	steering = _steer_s
	on_ground = true
	for w: VehicleWheel3D in _wheels:
		on_ground = on_ground and w.is_in_contact()
	# przewrócony (na boku / dachu) i prawie stoi: po 2 s staje z powrotem na koła
	if global_basis.y.y < 0.35 and linear_velocity.length() < 3.0:
		_flip_t += dt
		if _flip_t > 2.0:
			_flip_t = 0.0
			var f := -global_basis.z
			global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), global_position + Vector3.UP * 1.2)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_t = 0.0
	_seat_pilot()
	if Player.net_on and auth != 0 and _local_pilot():
		_net_t -= dt
		if _net_t <= 0.0:
			_net_t = NET_RATE
			_gd().call_func_unreliable(net_car, global_transform, linear_velocity, steering)


func _process(dt: float) -> void:
	if destroyed:
		return
	var spd := linear_velocity.length()
	var rev := 0.0 if pilot == null else clampf(0.25 + absf(engine_force) / ENGINE * 0.5 + spd / 30.0, 0.0, 1.2)
	if rev > 0.01:
		if not _snd.playing:
			_snd.play()
		_snd.pitch_scale = 0.35 + rev * 0.5
		_snd.volume_db = linear_to_db(clampf(0.2 + rev * 0.6, 0.0, 1.0)) - 2.0
	elif _snd.playing:
		_snd.stop()
	_smoke.emitting = hp < MAX_HP * 0.5
	_fire.emitting = hp < MAX_HP * 0.25
	if _local_pilot():
		_place_camera(minf(dt, 0.1))


func _place_camera(rd: float) -> void:
	var aim := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0.0)) * Vector3.FORWARD
	if cockpit_view:
		_cam.global_transform = Transform3D(Basis.looking_at(aim, Vector3.UP), global_transform * EYE)
		_cam.cull_mask = 0xFFFFF & ~Player.OWN_LAYER
	else:
		var tgt := global_position + Vector3.UP * 1.6 - aim * 8.5
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.8, tgt, 1, [get_rid()])
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			tgt = (r["position"] as Vector3) + (global_position - tgt).normalized() * 0.3
		_cam.global_position = _cam.global_position.lerp(tgt, 1.0 - exp(-12.0 * rd)) if _cam.global_position.distance_to(tgt) < 15.0 else tgt
		_cam.global_basis = Basis.looking_at(global_position + Vector3.UP * 1.4 + aim * 6.0 - _cam.global_position, Vector3.UP)
		_cam.cull_mask = 0xFFFFF
	_cam.fov = Settings.fov


# ---------------------------------------------------------------- uszkodzenia

func bullet_struck(shooter, energy: float, _at: Vector3) -> void:
	if destroyed:
		return
	if shooter != null and is_instance_valid(shooter) and shooter.get("is_remote") == true:
		return
	var was := hp
	_damage(clampf(sqrt(energy) / 8.0, 0.3, 25.0))
	if shooter != null and is_instance_valid(shooter) and shooter.has_method("confirm_hit") and shooter != pilot:
		shooter.confirm_hit(self, was > 0.0 and hp <= 0.0)


func _damage(d: float) -> void:
	_apply_damage(d)
	if Player.net_on:
		_gd().call_func(net_damage, d)


func _apply_damage(d: float) -> void:
	if destroyed:
		return
	hp = minf(hp - d, MAX_HP)
	if hp <= 0.0:
		_explode()


func _explode() -> void:
	if destroyed:
		return
	destroyed = true
	hp = 0.0
	FX.I.explosion(global_position + Vector3(0, 1.0, 0), 1.3)
	var p = pilot
	_unseat(false)
	if p != null and is_instance_valid(p) and not p.is_remote and not p.down:
		p.vehicle_death()
	for s in get_tree().get_nodes_in_group("soldier"):
		if s.down or s.get("is_remote") == true:
			continue
		if s.global_position.distance_to(global_position) < 5.0:
			s.vitals._die()
			s._collapse((s.global_position - global_position).normalized(), s.chest_pos(), "torso", 3000.0, true)
	for mi: MeshInstance3D in _parts:
		mi.material_override = _burnt
	engine_force = 0.0
	brake = BRAKE
	_fire.emitting = true
	_smoke.emitting = true
	_snd.stop()
	_wreck_t = 0.0
	apply_central_impulse(Vector3.UP * mass * 4.0)
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 2.0)


func _reset() -> void:
	destroyed = false
	freeze = false
	global_transform = home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	hp = MAX_HP
	auth = 0
	for mi: MeshInstance3D in _parts:
		if mi.has_meta("mat0"):
			mi.material_override = mi.get_meta("mat0")
	_fire.emitting = false
	_smoke.emitting = false


# ---------------------------------------------------------------- sieć

func _follow(dt: float) -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_net_xf.origin += _net_vel * dt
	var k := 1.0 - exp(-12.0 * dt)
	global_transform = Transform3D(Basis(global_basis.get_rotation_quaternion().slerp(_net_xf.basis.get_rotation_quaternion(), k)),
		global_position.lerp(_net_xf.origin, k) if global_position.distance_to(_net_xf.origin) < 10.0 else _net_xf.origin)


func net_car(xf: Transform3D, v: Vector3, st: float) -> void:
	auth = _gd().get_sender_id()
	_net_xf = xf
	_net_vel = v
	steering = st


func net_board(id: int) -> void:
	var p := get_parent().get_node_or_null("P%d" % id)
	auth = _gd().get_sender_id()
	if p and not p.down:
		_set_pilot(p)


func net_exit() -> void:
	_unseat(true)
	auth = 0


func net_damage(d: float) -> void:
	_apply_damage(d)


func net_explode() -> void:
	_explode()
