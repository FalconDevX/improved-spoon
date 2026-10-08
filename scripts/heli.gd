extends CharacterBody3D
## Śmigłowiec szturmowy: wirnik nośny (rozkręca się po wejściu pilota), wieżyczka pod nosem
## z podwójnym karabinem 12,7 mm (celuje tam, gdzie patrzysz), dwa zasobniki po 7 rakiet
## niekierowanych na skrzydełkach, flary. Lot zręcznościowy: mysz — kierunek i celowanie
## (śmigłowiec obraca się za wzrokiem), W/S — pochylenie (lot do przodu / do tyłu), A/D — w bok,
## Spacja / Ctrl — w górę / w dół. Twarde przyziemienie albo zderzenie przy prędkości kończy się
## wybuchem; zestrzelony kręci się i spada. Lądowisko dozbraja i naprawia.
## Ten sam interfejs co samolot (plane.gd): grupy "plane" i "aircraft" — wsiadanie, minimapa,
## bomby, namierzanie Piorunem, PvP (symuluje komputer pilota, obrażenia liczy strzelający).

const Player = preload("res://scripts/player.gd")
const Weapons = preload("res://scripts/weapons.gd")
const FX = preload("res://scripts/fx.gd")
const Ballistics = preload("res://scripts/ballistics.gd")
const Flare = preload("res://scripts/flare.gd")
const Rocket = preload("res://scripts/rocket.gd")
const BotPilot = preload("res://scripts/bot_pilot.gd")
const Debris = preload("res://scripts/debris.gd")

const LAYER := 32
const GRAVITY := 9.81
var GEAR_H := 1.2                        # od środka kadłuba do spodu płozy
var SEAT := Vector3(0, -0.75, -1.5)      # stopy pilota (pozycja gracza) w układzie śmigłowca
var EYE := Vector3(0, 0.55, -1.75)       # oczy pilota w kabinie
var MAX_HP := 170.0
var AMMO := 900
const ROCKETS := 14
const ROCKET_RELOAD := 10.0                # rakiety bez limitu: po wystrzelaniu wszystkich przeładowanie [s]
const ROCKET_DT := 0.16
const ROCKET_V0 := 120.0
const ROCKET_CONE := 0.35                  # rakiety lecą najwyżej tyle od osi kadłuba [rad]
var GUN_DT := 0.09             # salwa z obu luf naraz
var GUN_CONE := 1.6                      # zakres obrotu wieżyczki od osi [rad]
const FLARES := 4
const FLARE_RELOAD := 12.0
const FLARE_CD := 0.8
var MAX_TILT := 0.38
var CLIMB := 10.0
var TURN := 1.8                          # obrót za wzrokiem [rad/s]
var THRUST := 1.5                        # ciąg poziomy (× g przy pełnym wychyleniu, przez tg kąta)
const DRAG := 0.12
const SPOOL := 4.0                         # rozkręcanie wirnika [s]
var CRASH_VY := 8.0
var CRASH_H := 16.0
const RESPAWN := 25.0
var BOUND := 1400.0
const MOUSE_SENS := 0.0022
const NET_RATE := 1.0 / 30.0
var GUNS := [Vector3(-0.09, -1.05, -3.05), Vector3(0.09, -1.05, -3.05)]
var PODS := [Vector3(-1.75, -0.45, -0.9), Vector3(1.75, -0.45, -0.9)]


class MG:
	var cal: Dictionary
	var data: Dictionary


var board_name := "śmigłowca"
var is_heli := true
var home: Transform3D
var paint := Color(0.3, 0.34, 0.24)
var pilot = null
var ai = null
var auth := 0
var hp := MAX_HP
var throttle := 0.0          # dla HUD-u / dźwięku: obroty wirnika
var rpm := 0.0
var ammo := AMMO
var rockets := ROCKETS
var rocket_reload := 0.0
var destroyed := false
var on_ground := true
var stall := false
var trigger := false
var rocket_trigger := false
var cockpit_view := false
var warn := ""
var flares := FLARES
var flare_reload := 0.0
var missile_warn := INF
var lock_warn := 0.0

var _aim_yaw := 0.0
var _aim_pitch := -0.1
var _yaw := 0.0
var _tilt := Vector2.ZERO    # x pochylenie (nos w dół +), y przechylenie (w prawo +)
var _spin := 0.0             # zestrzelony: obrót wokół osi
var _gun_t := 0.0
var _gun_k := 0
var _shot_n := 0
var _rocket_t := 0.0
var _pod_k := 0
var _flare_cd := 0.0
var _warn_beep := 0.0
var _wreck_t := 0.0
var _mg := MG.new()
var _parts: Array = []
var _burnt: StandardMaterial3D
var _rotor: Node3D
var _blades: Node3D
var _disc: MeshInstance3D
var _tail_rotor: Node3D
var _turret: Node3D
var _pod_rockets: Array = []
var _flashes: Array = []
var _flash_t := 0.0
var _cam: Camera3D
var _cam_up := Vector3.UP
var _snd: AudioStreamPlayer3D
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _net_t := 0.0
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_vel := Vector3.ZERO
var _net_aim := Vector3.FORWARD
var _alarm_t := 0.0
var _aim_cache := Vector3.ZERO


func _ready() -> void:
	add_to_group("plane")
	add_to_group("aircraft")
	add_to_group("heli")
	collision_layer = LAYER
	collision_mask = 1 | LAYER
	floor_max_angle = 0.6
	set_meta("mat", "metal")
	set_meta("hollow", 0.002)
	set_meta("size", Vector3(2.0, 2.2, 12.0))
	_mg.cal = Weapons.CAL["12.7x99"]
	_mg.data = {"v0": 870.0, "zero": 300.0, "cal": "12.7x99"}
	_build_model()
	for s in [[Vector3(1.5, 2.0, 5.4), Vector3(0, -0.2, -0.6)], [Vector3(0.5, 0.7, 5.0), Vector3(0, 0.25, 4.1)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s[0]
		cs.shape = bs
		cs.position = s[1]
		add_child(cs)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = FX._cache["engine"]
	_snd.unit_size = 16.0
	_snd.max_distance = 900.0
	_snd.attenuation_filter_cutoff_hz = 5000.0
	add_child(_snd)
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.fov = 75.0
	_cam.near = 0.05
	_cam.far = 3500.0
	add_child(_cam)
	_smoke = _emitter(Color(0.2, 0.19, 0.18, 0.7), Color(0.35, 0.35, 0.35, 0.0), 2.5, 1.6, false)
	_fire = _emitter(Color(1.0, 0.75, 0.3, 1.0), Color(0.9, 0.2, 0.0, 0.0), 0.5, 0.9, true)
	home = global_transform
	if Player.net_on:
		var gd := _gd()
		for f in [net_heli, net_board, net_exit, net_damage, net_explode, net_rocket, net_flares, net_locked, net_board_bot, net_eject]:
			gd.expose_func(f)
	_reset()


func _gd() -> Node:
	return get_node("/root/GDSync")


func _my_id() -> int:
	return _gd().get_client_id() if Player.net_on else 0


func _sim_here() -> bool:
	return not Player.net_on or auth == _my_id()


func _local_pilot() -> bool:
	return pilot != null and is_instance_valid(pilot) and not pilot.is_remote and pilot.is_in_group("player")


## Maszyną steruje bot-pilot (liczony na tym komputerze).
func _ai_on() -> bool:
	return ai != null and pilot != null and is_instance_valid(pilot) and not pilot.down 		and pilot.is_in_group("npc") and not pilot.is_remote and _sim_here()


## Bot-pilot wsiada (host / solo); u gościa net_board_bot sadza kukiełkę.
func board_bot(npc) -> void:
	ai = BotPilot.new(self)
	_set_pilot(npc)
	if Player.net_on:
		auth = _my_id()
		_gd().call_func(net_board_bot, String(npc.name))


func net_board_bot(n: String) -> void:
	var p := get_parent().get_node_or_null(n)
	auth = _gd().get_sender_id()
	_net_pos = global_position
	_net_rot = global_basis.get_rotation_quaternion()
	if p and not p.down:
		_set_pilot(p)


func camera() -> Camera3D:
	return _cam


# ---------------------------------------------------------------- model

func _mat(c: Color, metal := 0.3, rough := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _part(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = self, rot := Vector3.ZERO, burn := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if burn:
		_parts.append(mi)
	return mi


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _cyl(r0: float, r1: float, h: float, seg := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _build_model() -> void:
	var body := _mat(paint)
	var dark := _mat(paint.darkened(0.35))
	var black := _mat(Color(0.07, 0.07, 0.07), 0.4, 0.6)
	var glass := _mat(Color(0.1, 0.14, 0.18), 0.7, 0.08)
	_burnt = _mat(Color(0.05, 0.045, 0.04), 0.1, 0.95)
	var along_z := Vector3(PI * 0.5, 0, 0)
	# kadłub: kapsuła wydłużona wzdłuż osi, kabina tandem z przodu
	var hull := CapsuleMesh.new()
	hull.radius = 0.8
	hull.height = 5.2
	_part(hull, Vector3(0, -0.15, -0.6), body, self, along_z).scale = Vector3(0.9, 1.0, 1.15)
	var canopy := SphereMesh.new()
	canopy.radius = 0.62
	canopy.height = 1.24
	_part(canopy, Vector3(0, 0.25, -2.0), glass, self).scale = Vector3(0.95, 0.9, 1.9)
	_part(_box(Vector3(1.1, 0.7, 2.2)), Vector3(0, 0.75, 0.3), dark)                  # osłona silników
	_part(_cyl(0.18, 0.4, 5.2), Vector3(0, 0.2, 4.1), body, self, along_z)           # belka ogonowa
	_part(_box(Vector3(0.12, 1.5, 1.0)), Vector3(0, 0.95, 6.45), body)               # statecznik pionowy
	_part(_box(Vector3(2.2, 0.08, 0.55)), Vector3(0, 0.25, 5.8), body)               # statecznik poziomy
	_part(_box(Vector3(3.8, 0.1, 0.75)), Vector3(0, -0.25, -0.9), dark)              # skrzydełka
	for pod: Vector3 in PODS:
		_part(_cyl(0.22, 0.22, 1.5), pod, black, self, along_z)                     # zasobnik rakiet
		for k in 7:
			var a := TAU * k / 7.0
			var off := Vector3(cos(a) * 0.13, sin(a) * 0.13, -0.76) if k > 0 else Vector3(0, 0, -0.76)
			var tip := _part(_cyl(0.0, 0.035, 0.08, 6), pod + off, _mat(Color(0.75, 0.7, 0.55)), self, Vector3(-PI * 0.5, 0, 0), false)
			_pod_rockets.append(tip)
	# płozy
	for sx: float in [-0.95, 0.95]:
		_part(_cyl(0.06, 0.06, 3.8, 8), Vector3(sx, -GEAR_H + 0.06, -0.5), black, self, along_z)
		for sz: float in [-1.5, 0.6]:
			_part(_box(Vector3(0.07, 0.75, 0.07)), Vector3(sx * 0.85, -GEAR_H + 0.42, sz), black, self, Vector3(0, 0, 0.25 * signf(sx)))
	# wirnik nośny
	_part(_cyl(0.1, 0.12, 0.5), Vector3(0, 1.3, 0.1), black)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 1.58, 0.1)
	add_child(_rotor)
	_blades = Node3D.new()
	_rotor.add_child(_blades)
	_part(_cyl(0.18, 0.18, 0.12), Vector3.ZERO, black, _rotor)
	for k in 4:
		_part(_box(Vector3(5.6, 0.05, 0.32)), Vector3(cos(k * PI * 0.5) * 2.8, 0, -sin(k * PI * 0.5) * 2.8), black, _blades, Vector3(0, k * PI * 0.5, 0))
	_disc = MeshInstance3D.new()
	_disc.mesh = _cyl(5.6, 5.6, 0.02, 32)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.05, 0.05, 0.05, 0.22)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc.material_override = dm
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rotor.add_child(_disc)
	# śmigło ogonowe
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.14, 1.15, 6.6)
	add_child(_tail_rotor)
	for k in 2:
		_part(_box(Vector3(0.03, 1.5, 0.14)), Vector3.ZERO, black, _tail_rotor, Vector3(k * PI * 0.5, 0, 0))
	# wieżyczka pod nosem z dwiema lufami
	_turret = Node3D.new()
	_turret.position = Vector3(0, -1.05, -2.75)
	add_child(_turret)
	var ball := SphereMesh.new()
	ball.radius = 0.24
	ball.height = 0.48
	_part(ball, Vector3.ZERO, black, _turret)
	for g: Vector3 in GUNS:
		_part(_cyl(0.035, 0.035, 0.9, 8), Vector3(g.x, 0, -0.45), black, _turret, along_z)
		var fl := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.12
		fm.height = 0.4
		fl.mesh = fm
		var flm := StandardMaterial3D.new()
		flm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flm.albedo_color = Color(1.0, 0.8, 0.4)
		fl.material_override = flm
		fl.position = Vector3(g.x, 0, -0.95)
		fl.visible = false
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_turret.add_child(fl)
		_flashes.append(fl)


func _emitter(c0: Color, c1: Color, life: float, size: float, add: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.position = Vector3(0, 0.9, 0.6)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 60, 120))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 2.0
	m.gravity = Vector3(0, 1.2 if not add else 2.0, 0)
	m.damping_min = 0.5
	m.damping_max = 1.5
	m.scale_min = 0.6
	m.scale_max = 1.5
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


# ---------------------------------------------------------------- wsiadanie / wysiadanie

func can_board(p) -> bool:
	if destroyed or hp <= 0.0 or pilot != null or not on_ground or velocity.length() > 2.0:
		return false
	return p.global_position.distance_to(global_position - Vector3(0, GEAR_H, 0)) < 5.0


func board(p) -> void:
	_set_pilot(p)
	if Player.net_on:
		auth = _my_id()
		_gd().call_func(net_board, p.net_id)
	_aim_yaw = _yaw
	_aim_pitch = -0.1
	cockpit_view = false
	_cam.current = true
	_place_camera(1.0)
	p._msg("Śmigłowiec: Spacja/Ctrl — góra/dół, W/S/A/D — lot, mysz — kierunek, LPM — działko, PPM — rakiety, C — flary")


func _set_pilot(p) -> void:
	pilot = p
	trigger = false
	rocket_trigger = false
	p.enter_vehicle(self)
	_seat_pilot()


func request_exit() -> void:
	if not on_ground or velocity.length() > 3.0:
		if not on_ground and global_position.y - GEAR_H > 10.0:
			eject()
		elif _local_pilot():
			pilot._msg("Za nisko — wyląduj")
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
	trigger = false
	rocket_trigger = false
	if is_instance_valid(p) and p.vehicle == self:
		p.leave_vehicle(place)
	if _cam.current:
		_cam.current = false


func exit_point() -> Vector3:
	var p := global_transform * Vector3(-2.2, 0, -1.2)
	p.y = global_position.y - GEAR_H
	return p


func pilot_gone(p) -> void:
	if pilot == p:
		pilot = null
		trigger = false
		rocket_trigger = false


func _seat_pilot() -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	var p = pilot
	p.global_position = global_transform * SEAT
	p.velocity = velocity
	p.visual.global_basis = global_basis
	p.rig.crouch = 1.0
	p.rig.sprint = false
	p.rig.air = false
	p.rig.vel = Vector3.ZERO
	p.rig.aim_w = 0.0


# ---------------------------------------------------------------- wejście (pilot lokalny)

func pilot_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_aim_yaw -= e.relative.x * MOUSE_SENS * Settings.sens
		_aim_pitch = clampf(_aim_pitch - e.relative.y * MOUSE_SENS * Settings.sens, -1.3, 0.9)
		return
	if e.is_action_pressed("attack"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		trigger = true
	elif e.is_action_released("attack"):
		trigger = false
	elif e.is_action_pressed("aim"):
		rocket_trigger = true
	elif e.is_action_released("aim"):
		rocket_trigger = false
	elif e.is_action_pressed("use"):
		request_exit()
	elif e.is_action_pressed("flares"):
		release_flares()
	elif e.is_action_pressed("view_toggle"):
		cockpit_view = not cockpit_view
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func aim_dir() -> Vector3:
	return Basis.from_euler(Vector3(_aim_pitch, _aim_yaw, 0.0)) * Vector3.FORWARD


## Punkt, w który celuje pilot (promień z kamery): tam strzela wieżyczka, tam lecą rakiety.
func aim_point() -> Vector3:
	return _aim_cache


func _update_aim_point() -> void:
	var dir := aim_dir() if _sim_here() else _net_aim
	var from := _cam.global_position if _local_pilot() else global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 900.0, 1 | 4 | LAYER, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	_aim_cache = r["position"] if not r.is_empty() else from + dir * 900.0


## Zgodność z plane.gd (HUD rysuje celownik w tym punkcie).
func gun_point() -> Vector3:
	return aim_point()


# ---------------------------------------------------------------- pętla

func _physics_process(dt: float) -> void:
	if destroyed:
		_wreck_t += dt
		if _wreck_t >= RESPAWN:
			_reset()
		return
	if pilot != null and (not is_instance_valid(pilot) or pilot.down):
		pilot = null
	if _sim_here():
		if _ai_on():
			ai.tick(dt)
		_simulate(dt)
		if destroyed:
			return
		if Player.net_on and auth != 0:
			_net_t -= dt
			if _net_t <= 0.0:
				_net_t = NET_RATE
				_gd().call_func_unreliable(net_heli, global_position, global_basis.get_rotation_quaternion(), velocity, rpm, trigger, aim_dir(), hp, rockets)
	else:
		_follow(dt)
	_update_aim_point()
	_aim_turret(dt)
	_guns(dt)
	if _sim_here():
		_rockets(dt)
	_countermeasures(dt)
	_seat_pilot()


func _simulate(dt: float) -> void:
	var fwd := 0.0
	var side := 0.0
	var up := 0.0
	var live: bool = pilot != null and is_instance_valid(pilot) and not pilot.down and hp > 0.0
	if live and _local_pilot() and not Player.chat_open:
		fwd = Input.get_axis("move_back", "move_forward")
		side = Input.get_axis("move_left", "move_right")
		up = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	elif live and _ai_on():
		fwd = ai.fwd
		side = ai.side
		up = ai.up
	rpm = move_toward(rpm, 1.0 if live else (0.55 if hp <= 0.0 and not on_ground else 0.0), dt / SPOOL)
	throttle = rpm
	var lift := rpm * rpm
	if hp <= 0.0:
		# zestrzelony: obraca się (brak śmigła ogonowego) i opada
		_spin = minf(_spin + dt * 1.5, 3.5)
		_yaw += _spin * dt
		up = -0.8
		fwd = 0.0
		side = 0.0
	var yaw_rate := 0.0
	if hp > 0.0 and live and rpm > 0.3:
		var dy := wrapf(_aim_yaw - _yaw, -PI, PI)
		var step := clampf(dy, -TURN * dt, TURN * dt)
		_yaw += step
		yaw_rate = step / maxf(dt, 0.0001)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var spd := hv.length()
	# zakręt skoordynowany: przy prędkości śmigłowiec przechyla się w stronę skrętu
	var bank := clampf(yaw_rate * spd * 0.012, -0.45, 0.45)
	if on_ground:
		_tilt = _tilt.move_toward(Vector2.ZERO, dt * 2.0)
	else:
		_tilt = _tilt.move_toward(Vector2(fwd * MAX_TILT, side * MAX_TILT * 0.8 + bank), dt * 1.3)
	global_basis = Basis.from_euler(Vector3(-_tilt.x, _yaw, -_tilt.y))
	# poziomo: ciąg wirnika pochylonego o kąt (g·tg), w układzie kursu śmigłowca
	var head := Basis(Vector3.UP, _yaw)
	var lv := head.inverse() * hv                         # x — w bok, z — do tyłu (+) / przodu (−)
	var thrust := GRAVITY * lift * THRUST
	lv.z += -tan(_tilt.x) * thrust * dt
	lv.x += tan(_tilt.y - bank) * thrust * dt + bank * GRAVITY * 0.3 * dt
	# opór: do przodu mały (opływowy kadłub), w bok duży i rosnący z prędkością — kadłub i belka
	# ogonowa ustawiają się „z wiatrem”, więc przy obrocie wektor prędkości skręca razem z kursem
	lv.z -= lv.z * (0.07 + 0.0016 * absf(lv.z)) * dt
	lv.x -= lv.x * (0.5 + 0.03 * spd) * dt
	hv = head * lv
	if on_ground:
		hv = hv.lerp(Vector3.ZERO, 1.0 - exp(-5.0 * dt))
	var vy := velocity.y
	# kolektyw: zadana prędkość pionowa; w szybkim locie nośność rośnie (przepływ przez wirnik)
	var trans := 1.0 + clampf((spd - 12.0) / 40.0, 0.0, 0.25)
	var a_y := (up * CLIMB * trans - vy) * 1.6 * lift - GRAVITY * (1.0 - lift)
	if on_ground and up <= 0.0:
		a_y = minf(a_y, 0.0)
	vy += a_y * dt
	var prev := velocity
	velocity = Vector3(hv.x, vy, hv.z)
	move_and_slide()
	on_ground = is_on_floor()
	warn = ""
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if n.y > 0.6:
			if prev.y < -CRASH_VY or Vector2(prev.x, prev.z).length() > CRASH_H or hp <= 0.0 or absf(_tilt.y) > 0.5:
				_crash()
				return
		elif prev.length() > CRASH_H:
			_crash()
			return
	if on_ground:
		velocity.y = maxf(velocity.y, 0.0)
		_rearm(dt)
	elif global_position.y - GEAR_H < 6.0 and velocity.y < -6.0:
		warn = "ZIEMIA — W GÓRĘ (SPACJA)"
	_boundary()


func _boundary() -> void:
	var p := global_position
	if absf(p.x) > BOUND or absf(p.z) > BOUND:
		velocity.x -= signf(p.x) * 4.0 if absf(p.x) > BOUND else 0.0
		velocity.z -= signf(p.z) * 4.0 if absf(p.z) > BOUND else 0.0
		warn = "GRANICA OBSZARU — ZAWRÓĆ"
	if p.y > 400.0:
		velocity.y = minf(velocity.y, 0.0)


## Lądowisko: dozbrajanie i naprawa.
func _rearm(dt: float) -> void:
	if velocity.length() > 1.0 or global_position.distance_to(home.origin) > 30.0:
		return
	ammo = mini(ammo + int(ceil(300.0 * dt)), AMMO)
	hp = minf(hp + 20.0 * dt, MAX_HP)
	if rockets < ROCKETS:
		rockets = ROCKETS
		rocket_reload = 0.0
		_show_pods()


# ---------------------------------------------------------------- uzbrojenie

func _aim_turret(dt: float) -> void:
	var to := aim_point() - _turret.global_position
	if to.length() < 0.5:
		return
	var nose := -global_basis.z
	var dir := to.normalized()
	var ang := nose.angle_to(dir)
	if ang > GUN_CONE:
		dir = nose.slerp(dir, GUN_CONE / ang).normalized()
	var want := Basis.looking_at(dir, global_basis.y if absf(dir.dot(global_basis.y)) < 0.98 else -global_basis.z)
	_turret.global_basis = Basis(_turret.global_basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), 1.0 - exp(-12.0 * dt)))


func _guns(dt: float) -> void:
	_flash_t -= dt
	if _flash_t <= 0.0:
		for f: Node3D in _flashes:
			f.visible = false
	var can: bool = trigger and pilot != null and is_instance_valid(pilot) and not pilot.down and hp > 0.0
	if _local_pilot() or not Player.net_on:
		can = can and ammo > 0
	if not can:
		_gun_t = maxf(_gun_t - dt, 0.0)
		return
	_gun_t -= dt
	var guard := 0
	while _gun_t <= 0.0 and guard < 3:
		guard += 1
		_gun_t += GUN_DT
		for k in GUNS.size():
			_fire_gun(k)


func _fire_gun(i: int) -> void:
	var fl: MeshInstance3D = _flashes[i]
	var m := fl.global_position
	var d := -_turret.global_basis.z
	d = _jitter(d, 0.0025)
	_shot_n += 1
	if _local_pilot() or not Player.net_on:
		ammo -= 1
	Ballistics.I.fire(pilot, _mg, m, d, _shot_n % 3 == 0, velocity, [get_rid()])
	fl.visible = true
	fl.scale = Vector3.ONE * randf_range(0.7, 1.3)
	_flash_t = 0.035
	FX.I.play("shot_50", m, 3.0, 0.06, 1.05, 30.0)
	if _shot_n % 6 == 0:
		FX.I.muzzle_smoke(m, d, 0.5)
		for s in get_tree().get_nodes_in_group("soldier"):
			if s != pilot and s.has_method("heard_shot"):
				s.heard_shot(global_position, pilot)


func _jitter(d: Vector3, sigma: float) -> Vector3:
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var x := d.cross(up).normalized()
	var y := x.cross(d).normalized()
	return (d + x * randfn(0.0, sigma) + y * randfn(0.0, sigma)).normalized()


func _rockets(dt: float) -> void:
	_rocket_t = maxf(_rocket_t - dt, 0.0)
	if rockets < ROCKETS and not rocket_trigger and not destroyed:
		rocket_reload += dt
		if rocket_reload >= ROCKET_RELOAD:
			rocket_reload = 0.0
			rockets = ROCKETS
			_show_pods()
	elif rocket_trigger:
		rocket_reload = 0.0
	var live: bool = pilot != null and is_instance_valid(pilot) and not pilot.down and hp > 0.0
	if not rocket_trigger or not live or rockets <= 0 or _rocket_t > 0.0:
		return
	_rocket_t = ROCKET_DT
	var pod: Vector3 = global_transform * (PODS[_pod_k] as Vector3) - global_basis.z * 0.9
	_pod_k = (_pod_k + 1) % PODS.size()
	var nose := -global_basis.z
	var dir := (aim_point() - pod).normalized()
	var ang := nose.angle_to(dir)
	if ang > ROCKET_CONE:
		dir = nose.slerp(dir, ROCKET_CONE / ang).normalized()
	dir = _jitter(dir, 0.006)
	var v := dir * ROCKET_V0 + velocity
	rockets -= 1
	_show_pods()
	_launch(pod, v)
	if Player.net_on:
		_gd().call_func(net_rocket, pod, v)


func _launch(pos: Vector3, v: Vector3) -> void:
	var r := Rocket.new()
	r.vel = v
	r.shooter = pilot
	r.plane = self
	get_parent().add_child(r)
	r.global_position = pos
	r.global_basis = Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.FORWARD)
	FX.I.muzzle_smoke(pos, -v.normalized(), 1.2)
	FX.I.play("shot_50", pos, 2.0, 0.08, 0.7, 40.0)


func _show_pods() -> void:
	for k in _pod_rockets.size():
		# po 7 rakiet w zasobniku, wystrzeliwane na zmianę z lewego i prawego
		var fired := ROCKETS - rockets
		var order := (k % 7) * 2 + int(k / 7.0)
		(_pod_rockets[k] as Node3D).visible = order >= fired


# ---------------------------------------------------------------- flary, ostrzeżenia

func release_flares() -> void:
	if flares <= 0 or _flare_cd > 0.0 or destroyed:
		if flares <= 0 and _local_pilot():
			pilot._msg("Flary: przeładowanie %d s" % ceili(FLARE_RELOAD - flare_reload))
		return
	flares -= 1
	_flare_cd = FLARE_CD
	Flare.salvo(self)
	if Player.net_on:
		_gd().call_func(net_flares)


func _countermeasures(dt: float) -> void:
	_flare_cd = maxf(_flare_cd - dt, 0.0)
	if flares < FLARES:
		flare_reload += dt
		if flare_reload >= FLARE_RELOAD:
			flare_reload = 0.0
			flares = FLARES
	lock_warn = maxf(lock_warn - dt, 0.0)
	if not _missile_near():
		missile_warn = INF
	if _local_pilot():
		_warn_beep -= dt
		var incoming := _missile_near()
		if _warn_beep <= 0.0 and (incoming or lock_warn > 0.0):
			_warn_beep = 0.12 if incoming else 0.45
			FX.I.play("click", _cam.global_position, 0.0 if incoming else -4.0, 0.0, 3.0 if incoming else 1.8, 4.0)


func _missile_near() -> bool:
	for m in get_tree().get_nodes_in_group("missile"):
		if m.target == self:
			return true
	return false


# ---------------------------------------------------------------- uszkodzenia

func bullet_struck(shooter, energy: float, _at: Vector3) -> void:
	if destroyed:
		return
	if shooter != null and is_instance_valid(shooter) and shooter.get("is_remote") == true:
		return
	var was := hp
	_damage(clampf(sqrt(energy) / 6.0, 0.5, 30.0))
	if shooter != null and is_instance_valid(shooter) and shooter.has_method("confirm_hit") and shooter != pilot:
		shooter.confirm_hit(self, was > 0.0 and hp <= 0.0)


func _damage(d: float) -> void:
	_apply_damage(d)
	if Player.net_on:
		_gd().call_func(net_damage, d)


func _apply_damage(d: float) -> void:
	if destroyed:
		return
	var was := hp
	hp = minf(hp - d, MAX_HP)   # ujemne d = naprawa (gracz z kluczem, [R])
	if not on_ground and d > 0.0 and (hp <= -MAX_HP * 0.8 or d >= MAX_HP * 1.3):   # rozpad tylko przy trafieniu niemal bezpośrednim; zwykle pożar i czas na skok
		_break_apart()
		return
	if hp <= 0.0 and was > 0.0:
		if _local_pilot():
			pilot._msg("ŚMIGŁOWIEC TRAFIONY — SPADASZ!")
		if on_ground and velocity.length() < 3.0:
			_explode(global_position)


func _crash() -> void:
	var p := global_position
	_explode(p)
	if Player.net_on:
		_gd().call_func(net_explode, p)


func _explode(pos: Vector3) -> void:
	if destroyed:
		return
	destroyed = true
	hp = 0.0
	trigger = false
	rocket_trigger = false
	FX.I.explosion(pos + Vector3(0, 0.5, 0), 1.6)
	var p = pilot
	_unseat(false)
	if p != null and is_instance_valid(p) and not p.is_remote and not p.down:
		p.vehicle_death()
	for s in get_tree().get_nodes_in_group("soldier"):
		if s.down or s.get("is_remote") == true:
			continue
		var d: float = s.global_position.distance_to(pos)
		if d < 7.0:
			s.vitals._die()
			s._collapse((s.global_position - pos).normalized(), s.chest_pos(), "torso", 4000.0, true)
	var f := -global_basis.z
	global_basis = Basis.from_euler(Vector3(randf_range(-0.1, 0.1), atan2(-f.x, -f.z), randf_range(-0.5, 0.5)))
	var gy := _ground_y()
	global_position.y = (gy if gy > -999.0 else 0.0) + 0.8
	velocity = Vector3.ZERO
	rpm = 0.0
	for mi: MeshInstance3D in _parts:
		mi.material_override = _burnt
	for r: Node3D in _pod_rockets:
		r.visible = false
	_disc.visible = false
	_fire.emitting = true
	_smoke.emitting = true
	_snd.stop()
	_wreck_t = 0.0
	if _cam.current:
		_cam.current = false


func _ground_y() -> float:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 2.0, 0), global_position - Vector3(0, 60.0, 0), 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return (r["position"] as Vector3).y if not r.is_empty() else -1000.0


func _reset() -> void:
	destroyed = false
	visible = true
	collision_layer = LAYER
	global_transform = home
	_yaw = home.basis.get_euler().y
	_aim_yaw = _yaw
	_tilt = Vector2.ZERO
	_spin = 0.0
	velocity = Vector3.ZERO
	hp = MAX_HP
	ammo = AMMO
	rockets = ROCKETS
	rocket_reload = 0.0
	flares = FLARES
	flare_reload = 0.0
	rpm = 0.0
	on_ground = true
	auth = 0
	trigger = false
	rocket_trigger = false
	for mi: MeshInstance3D in _parts:
		mi.material_override = _part_mat(mi)
	_show_pods()
	_disc.visible = false
	_fire.emitting = false
	_smoke.emitting = false
	_net_pos = global_position
	_net_rot = global_basis.get_rotation_quaternion()
	_net_vel = Vector3.ZERO


func _part_mat(mi: MeshInstance3D) -> Material:
	if not mi.has_meta("mat0"):
		mi.set_meta("mat0", mi.material_override)
	return mi.get_meta("mat0")


# ---------------------------------------------------------------- obraz, dźwięk

func _process(dt: float) -> void:
	var rd := minf(dt, 0.1)
	if destroyed:
		return
	_rotor.rotate_y(rd * rpm * 28.0)
	_tail_rotor.rotate_x(rd * rpm * 60.0)
	_blades.visible = rpm < 0.6
	_disc.visible = rpm > 0.35
	if rpm > 0.02:
		if not _snd.playing:
			_snd.play()
		_snd.pitch_scale = 0.35 + rpm * 0.45
		_snd.volume_db = linear_to_db(clampf(0.2 + rpm, 0.0, 1.0)) + 6.0
	elif _snd.playing:
		_snd.stop()
	_smoke.emitting = hp < MAX_HP * 0.5
	_fire.emitting = hp < MAX_HP * 0.25
	if _local_pilot():
		_place_camera(rd)
		if hp <= 0.0:
			_alarm_t -= rd
			if _alarm_t <= 0.0:
				_alarm_t = 0.3
				FX.I.play("click", _cam.global_position, -2.0, 0.0, 0.5, 4.0)


func _place_camera(rd: float) -> void:
	var aim := aim_dir()
	if cockpit_view:
		var eye := global_transform * EYE
		_cam_up = _cam_up.lerp(global_basis.y.lerp(Vector3.UP, 0.5), 1.0 - exp(-4.0 * rd)).normalized()
		var up := _cam_up
		if absf(aim.dot(up)) > 0.97:
			up = -global_basis.z
		_cam.global_transform = Transform3D(Basis.looking_at(aim, up), eye)
		_cam.cull_mask = 0xFFFFF & ~Player.OWN_LAYER
	else:
		var tgt := global_position - aim * 14.0 + Vector3.UP * 3.5
		var k := 1.0 - exp(-8.0 * rd)
		if _cam.global_position.distance_to(tgt) > 40.0:
			_cam.global_position = tgt
		else:
			_cam.global_position = _cam.global_position.lerp(tgt, k)
		# kamera nie wchodzi pod ziemię
		var gy := _cam.global_position.y
		if gy < 0.8:
			_cam.global_position.y = 0.8
		_cam.global_basis = Basis.looking_at(global_position + aim * 80.0 - _cam.global_position, Vector3.UP)
		_cam.cull_mask = 0xFFFFF
	_cam.fov = lerpf(_cam.fov, Settings.fov + 2.0, 1.0 - exp(-2.0 * rd))


# ---------------------------------------------------------------- sieć (PvP, GD-Sync)

func _follow(dt: float) -> void:
	if auth == 0:
		return
	_net_pos += _net_vel * dt
	if global_position.distance_to(_net_pos) > 20.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-12.0 * dt))
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(_net_rot, 1.0 - exp(-14.0 * dt)))
	velocity = _net_vel
	on_ground = global_position.y - GEAR_H <= _ground_y() + 0.15


func net_heli(p: Vector3, rot: Quaternion, v: Vector3, r: float, trig: bool, aim: Vector3, h: float, nr: int) -> void:
	if destroyed:
		return
	auth = _gd().get_sender_id()
	_net_pos = p
	_net_rot = rot
	_net_vel = v
	rpm = r
	throttle = r
	_net_aim = aim
	trigger = trig and pilot != null
	if h > 0.0:
		hp = h
	if nr != rockets:
		rockets = nr
		_show_pods()


func net_board(id: int) -> void:
	var p := get_parent().get_node_or_null("P%d" % id)
	auth = _gd().get_sender_id()
	_net_pos = global_position
	_net_rot = global_basis.get_rotation_quaternion()
	if p and not p.down:
		_set_pilot(p)


func net_exit() -> void:
	_unseat(true)


func net_damage(d: float) -> void:
	_apply_damage(d)


func net_explode(pos: Vector3) -> void:
	global_position = pos
	_explode(pos)


## (zdalnie) przeciwnik odpalił rakietę — ta sama leci u mnie.
func net_rocket(pos: Vector3, v: Vector3) -> void:
	rockets = maxi(rockets - 1, 0)
	_show_pods()
	_launch(pos, v)


func net_flares() -> void:
	flares = maxi(flares - 1, 0)
	Flare.salvo(self)


func net_locked() -> void:
	lock_warn = 0.5


# ---------------------------------------------------------------- katapulta, rozpad w powietrzu

## Pilot opuszcza maszynę w locie (F albo bot przy pożarze): leci dalej sam, z prędkością maszyny.
func eject() -> void:
	var p = pilot
	if p == null or not is_instance_valid(p):
		return
	_unseat(false)
	if Player.net_on and (_local_pilot() or (p.is_in_group("npc") and not p.is_remote)):
		_gd().call_func(net_eject)
	p.start_freefall(global_position + global_basis.y * 2.5 + Vector3.UP, velocity + global_basis.y * 9.0)


func net_eject() -> void:
	var p = pilot
	_unseat(false)
	if p != null and is_instance_valid(p) and p.has_method("start_freefall") and p.is_in_group("npc"):
		p.para = 2      # kukiełka bota: czasza (ruch przychodzi z paczek hosta)


## Bardzo duże obrażenia w locie: maszyna rozpada się na płonące części, pilot ginie.
func _break_apart() -> void:
	var pos := global_position
	var vel := velocity
	FX.I.explosion(pos, 2.2)
	var parts: Array = _parts.duplicate()
	parts.shuffle()
	var n := 0
	for mi: MeshInstance3D in parts:
		if n >= 7 or mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		if aabb.size.length() < 0.8:
			continue
		n += 1
		var d := Debris.new()
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = _burnt
		copy.scale = mi.global_basis.get_scale()
		d.add_child(copy)
		get_parent().add_child(d)
		d.global_transform = Transform3D(mi.global_basis.orthonormalized(), mi.global_position)
		d.setup(copy)
		d.linear_velocity = vel * 0.8 + Vector3(randf_range(-1, 1), randf_range(0, 1.2), randf_range(-1, 1)) * 14.0
		d.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 4.0
	_explode(pos)
	visible = false
	collision_layer = 0
