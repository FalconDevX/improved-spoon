extends Node3D
## Pocisk V-1 (Fieseler Fi 103, „buzz bomb”): skrzydlaty pocisk z silnikiem pulsacyjnym Argus
## As 014 na grzbiecie. Stoi na rampie wyrzutni (v1_site.gd); katapulta parowa rozpędza go po
## szynach do ~360 km/h, dalej leci sam (~630 km/h). Gracz przy pulpicie steruje nim jak dronem:
## mysz — kierunek, W/S — szybciej/wolniej, Spacja lub LPM — wyłączenie silnika i nurkowanie
## (cisza przed uderzeniem, jak w 1944), F — natychmiastowe zdetonowanie. Wybucha przy uderzeniu
## (głowica 850 kg); po wybuchu sterowanie wraca do żołnierza przy pulpicie.

const Player = preload("res://scripts/player.gd")
const FX = preload("res://scripts/fx.gd")
const Bomb = preload("res://scripts/bomb.gd")

const MODEL := "res://assets/vehicles/v1/v1.obj"
const TEX := "res://assets/vehicles/v1/v1_alb.png"
const SCALE := 0.56                 # siatka ma 15,2 m długości, prawdziwy V-1 — 8,3 m
const RAIL_V := 100.0               # prędkość na końcu rampy [m/s] (~360 km/h)
const CRUISE := 175.0               # prędkość przelotowa [m/s] (~630 km/h)
const V_MIN := 120.0
const V_MAX := 200.0
const TURN := 0.9                   # [rad/s]
const FUEL := 150.0                 # [s] lotu z pracującym silnikiem
const MOUSE_SENS := 0.0022
const BOUND := 1580.0               # świat ma ±1600 m — dalej pocisk wybucha
const TURN_BACK := 1400.0           # od tej odległości od środka sam zawraca nad mapę

const NET_RATE := 1.0 / 20.0

var board_name := "V-1"
var is_v1 := true
var pilot = null
var site = null                     # wyrzutnia (pomijana przez promienie kolizji na starcie)
var phase := 0                      # 0 — na rampie, 1 — katapulta, 2 — lot, 3 — nurkowanie, 4 — po wybuchu
var speed := 0.0
var fuel := FUEL
var throttle := 0.5                 # 0..1 → V_MIN..V_MAX
var cockpit_view := false
var rail_from := Vector3.ZERO       # początek i koniec szyn (globalnie)
var rail_to := Vector3.ZERO
var _rail_s := 0.0
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _bank := 0.0
var _t := 0.0
var _body: Node3D
var _flame: MeshInstance3D
var _light: OmniLight3D
var _snd: AudioStreamPlayer3D
var _cam: Camera3D
var remote := false                 # lot liczy inny komputer (sieć) — tu tylko podąża za pozycją
var shooter_remote = null           # gracz, który odpalił (u innych graczy: jego węzeł P<id>)
var _net_t := 0.0
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_age := 0.0
var _edge_msg := false


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	if ResourceLoader.exists(MODEL):
		var mi := MeshInstance3D.new()
		mi.mesh = load(MODEL)
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(TEX)
		m.albedo_color = Color(0.95, 0.88, 0.8)       # tekstura ma jaskrawy turkus — przygaszony do oliwkowej zieleni
		m.metallic = 0.35
		m.roughness = 0.55
		mi.material_override = m
		# siatka: dziób w −Y, góra w +Z → w grze dziób w −Z, góra w +Y
		mi.transform = Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)).scaled(Vector3.ONE * SCALE), Vector3.ZERO)
		_body.add_child(mi)
	else:
		var c := CapsuleMesh.new()
		c.radius = 0.42
		c.height = 7.5
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.rotation.x = PI * 0.5
		_body.add_child(mi)
	# płomień z wylotu rury pulsacyjnej (miga z rytmem zapłonów)
	_flame = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.28
	fm.height = 1.6
	_flame.mesh = fm
	var flm := StandardMaterial3D.new()
	flm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flm.albedo_color = Color(1.0, 0.6, 0.25)
	_flame.material_override = flm
	_flame.rotation.x = PI * 0.5
	_flame.position = Vector3(0, 0.84, 4.6)
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	_body.add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.3)
	_light.omni_range = 9.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.84, 4.8)
	_body.add_child(_light)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = FX._cache["pulsejet"]
	_snd.unit_size = 40.0
	_snd.max_distance = 3500.0
	_snd.volume_db = 4.0
	_snd.attenuation_filter_cutoff_hz = 9000.0
	_snd.position = Vector3(0, 0.8, 3.5)
	add_child(_snd)
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.far = 4000.0
	add_child(_cam)


# ---------------------------------------------------------------- sterowanie

func can_board(_p) -> bool:
	return false     # wsiada się przez pulpit wyrzutni (v1_site.gd)


## Start z pulpitu: żołnierz zostaje przy pulpicie, obraz i sterowanie przechodzą na pocisk.
func launch(p) -> void:
	pilot = p
	if p != null:
		p.enter_vehicle(self)
		p._msg("V-1 START! Mysz — kierunek, W/S — prędkość, Spacja — nurkowanie, F — detonacja")
	phase = 1
	add_to_group("v1_flying")       # HUD i minimapa innych graczy pokazują znacznik
	_rail_s = 0.0
	speed = 0.0
	var f := -global_basis.z
	_aim_yaw = atan2(-f.x, -f.z)
	_aim_pitch = asin(clampf(f.y, -1.0, 1.0))
	_cam.current = p != null and not p.is_remote
	_snd.play()
	_place_camera(1.0)


func pilot_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_aim_yaw -= e.relative.x * MOUSE_SENS * Settings.sens
		_aim_pitch = clampf(_aim_pitch - e.relative.y * MOUSE_SENS * Settings.sens, -1.3, 0.9)
		return
	if e.is_action_pressed("attack"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		cut_engine()
	elif e.is_action_pressed("jump"):
		cut_engine()
	elif e.is_action_pressed("use"):
		if phase >= 2:
			_explode(global_position)
	elif e.is_action_pressed("view_toggle"):
		cockpit_view = not cockpit_view
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Koniec paliwa albo rozkaz nurkowania: silnik gaśnie (cisza), pocisk nurkuje.
## (zdalnie) stan lotu od komputera, który pocisk odpalił.
func net_state(pos: Vector3, rot: Quaternion, spd: float, ph: int) -> void:
	if phase == 1:
		phase = 2
	_net_pos = pos
	_net_rot = rot
	_net_age = 0.0
	speed = spd
	if global_position.distance_to(pos) > 60.0:
		global_position = pos
	if ph == 3 and phase == 2:
		cut_engine()


func cut_engine() -> void:
	if phase != 2:
		return
	phase = 3
	_snd.stop()
	_flame.visible = false
	_light.light_energy = 0.0
	if pilot != null and is_instance_valid(pilot) and not pilot.is_remote:
		pilot._msg("Silnik zgasł — V-1 nurkuje")


func pilot_gone(p) -> void:
	if pilot == p:
		pilot = null


func aim_dir() -> Vector3:
	return Basis.from_euler(Vector3(_aim_pitch, _aim_yaw, 0.0)) * Vector3.FORWARD


func exit_point() -> Vector3:
	return global_position


# ---------------------------------------------------------------- lot

func _physics_process(dt: float) -> void:
	if phase == 0 or phase == 4:
		return
	_t += dt
	if remote and _t > FUEL + 150.0:
		queue_free()     # odpalający gracz się rozłączył — pocisk znika
		return
	if remote and phase >= 2:
		_net_age += dt
		if _net_age < 0.5:      # bez nowych paczek nie zgaduj dalej (pocisk uciekał za mapę)
			_net_pos += -global_basis.z * speed * dt
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-10.0 * dt))
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(_net_rot, 1.0 - exp(-10.0 * dt)))
		if phase == 2:
			_engine_fx()
		return
	if pilot != null and (not is_instance_valid(pilot) or pilot.down):
		pilot = null
	var p0 := global_position
	if phase == 1:
		# katapulta parowa: stałe przyspieszenie na długości szyn
		var length := rail_from.distance_to(rail_to)
		var acc := RAIL_V * RAIL_V / (2.0 * length)
		speed += acc * dt
		_rail_s += speed * dt
		if _rail_s >= length:
			phase = 2
			speed = RAIL_V
			_net_pos = rail_to
			_net_rot = global_basis.get_rotation_quaternion()
			if site != null and is_instance_valid(site):
				site.on_launched()
		global_position = rail_from.lerp(rail_to, minf(_rail_s / length, 1.0))
		_engine_fx()
		return
	var fwd := -global_basis.z
	var yaw_rate := 0.0
	if phase == 2:
		fuel -= dt
		if fuel <= 0.0:
			cut_engine()
		if pilot != null and pilot.get("is_remote") == false and not Player.chat_open:
			throttle = clampf(throttle + Input.get_axis("move_back", "move_forward") * dt * 0.5, 0.0, 1.0)
		var want := aim_dir() if pilot != null else fwd
		# granica mapy: zawraca w stronę środka (wysokość według celownika)
		var gp := global_position
		if maxf(absf(gp.x), absf(gp.z)) > TURN_BACK:
			var home := Vector3(-gp.x, 0, -gp.z).normalized()
			want = (home + Vector3.UP * clampf(want.y, -0.3, 0.3)).normalized()
			if not _edge_msg and pilot != null and is_instance_valid(pilot) and not pilot.is_remote:
				pilot._msg("Granica mapy — V-1 zawraca")
			_edge_msg = true
		else:
			_edge_msg = false
		var ang := fwd.angle_to(want)
		var nf := fwd
		if ang > 0.0001:
			nf = fwd.slerp(want, minf(TURN * dt / ang, 1.0)).normalized()
		yaw_rate = wrapf(atan2(-nf.x, -nf.z) - atan2(-fwd.x, -fwd.z), -PI, PI) / dt
		fwd = nf
		var target := lerpf(V_MIN, V_MAX, throttle)
		speed = move_toward(speed, target, dt * 6.0)
		speed -= GRAVITY_K * fwd.y * dt      # wznoszenie hamuje, opadanie rozpędza
		_engine_fx()
	else:
		# nurkowanie: nos schodzi w dół, prędkość rośnie
		var down := Vector3(fwd.x, 0, fwd.z).normalized().slerp(Vector3.DOWN, 0.85).normalized()
		var ang := fwd.angle_to(down)
		if ang > 0.0001:
			fwd = fwd.slerp(down, minf(0.6 * dt / ang, 1.0)).normalized()
		speed = minf(speed + 9.81 * maxf(-fwd.y, 0.0) * dt, 260.0)
	_bank = lerpf(_bank, clampf(-yaw_rate * 0.6, -0.9, 0.9), 1.0 - exp(-3.0 * dt))
	global_basis = Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.FORWARD, _bank)
	var p1 := p0 + fwd * speed * dt
	for a in get_tree().get_nodes_in_group("aircraft"):
		if a.get("destroyed") == true:
			continue
		var sz: Vector3 = a.get_meta("size", Vector3(12, 4, 12))
		var lp: Vector3 = a.global_transform.affine_inverse() * p1
		if absf(lp.y) < sz.y * 0.6 + 1.0 and Vector2(lp.x, lp.z).length() < maxf(sz.x, sz.z) * 0.45 + 1.5:
			_explode(p1)        # zderzenie w locie z maszyną
			return
	var excl: Array[RID] = []
	if site != null and is_instance_valid(site) and _t < 3.0:
		excl.append_array(site.body_rids())
	var q := PhysicsRayQueryParameters3D.create(p0 + fwd * 4.5, p1 + fwd * 4.5, 1 | 4 | 32, excl)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		_explode(r["position"])
		return
	global_position = p1
	if Player.net_on:
		_net_t -= dt
		if _net_t <= 0.0:
			_net_t = NET_RATE
			site.get_node("/root/GDSync").call_func_unreliable(site.net_fly, global_position, global_basis.get_rotation_quaternion(), speed, phase)
	if absf(p1.x) > BOUND or absf(p1.z) > BOUND or p1.y < -50.0 or p1.y > 3000.0 or _t > FUEL + 120.0:
		_explode(p1)

const GRAVITY_K := 9.81


func _engine_fx() -> void:
	var on := phase == 1 or phase == 2
	_flame.visible = on
	if on:
		var pulse := 0.5 + 0.5 * sin(_t * TAU * 47.0 / 6.0)    # migotanie (aliasing 47 Hz na ekranie)
		_flame.scale = Vector3(1.0, 1.0, 0.7 + 0.6 * pulse)
		_light.light_energy = 1.5 + 2.0 * pulse
		_snd.pitch_scale = 0.9 + 0.2 * (speed / V_MAX)


## Uderzenie: głowica 850 kg amatolu (bomb.gd, rodzaj "v1"), sterowanie wraca do żołnierza.
func _explode(pos: Vector3) -> void:
	if phase == 4:
		return
	phase = 4
	if Player.net_on and not remote and site != null and is_instance_valid(site):
		site.get_node("/root/GDSync").call_func(site.net_boom, pos)
	var b := Bomb.new()
	b.kind = "v1"
	b.shooter = pilot if (pilot != null and is_instance_valid(pilot)) else null
	if remote and shooter_remote != null and is_instance_valid(shooter_remote):
		b.shooter = shooter_remote
	get_parent().add_child(b)
	b.global_position = pos
	b._explode(pos)
	FX.I.crater(pos + Vector3(2.5, 0, 1.0))
	FX.I.crater(pos - Vector3(2.0, 0, 1.5))
	var p = pilot
	pilot = null
	if p != null and is_instance_valid(p) and p.vehicle == self:
		p.leave_vehicle(false)
		if not p.is_remote:
			p._msg("V-1 trafił — %d m od wyrzutni" % int(pos.distance_to(rail_from)))
	queue_free()


# ---------------------------------------------------------------- obraz

func _process(dt: float) -> void:
	if phase == 0 or phase == 4 or not _cam.current:
		return
	_place_camera(minf(dt, 0.1))


func _place_camera(rd: float) -> void:
	var f := -global_basis.z
	if cockpit_view:
		# kamera na grzbiecie, przed rurą silnika
		_cam.global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), global_transform * Vector3(0, 0.9, -2.5))
		_cam.fov = Settings.fov + 4.0
		return
	var look := aim_dir() if phase == 2 else f
	var tgt := global_position - look * 16.0 + Vector3.UP * 4.0
	if _cam.global_position.distance_to(tgt) > 40.0:
		_cam.global_position = tgt
	else:
		_cam.global_position = _cam.global_position.lerp(tgt, 1.0 - exp(-9.0 * rd))
	_cam.global_basis = Basis.looking_at(global_position + look * 60.0 - _cam.global_position, Vector3.UP)
	_cam.fov = lerpf(_cam.fov, Settings.fov + clampf(speed / V_MAX, 0.0, 1.0) * 8.0, 1.0 - exp(-2.0 * rd))
