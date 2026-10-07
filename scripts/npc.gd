extends "res://scripts/soldier.gd"
## Żołnierz wroga. Wzrok (stożek, linia wzroku, stopniowe wykrycie), słuch (strzały, trzask
## przelatujących kul), przygniecenie ogniem, krycie się za osłonami i wychylanie do strzału,
## ogień seriami z błędem celowania malejącym w trakcie składania się, przeładowanie w osłonie,
## przeszukiwanie miejsca ostatniego kontaktu, przekazywanie pozycji gracza sąsiadom.

const Weapons2 = preload("res://scripts/weapons.gd")

static var level: Node
static var deaths := 0
static var skill := 1         # poziom trudności: 0 łatwy, 1 normalny, 2 trudny
static var net_host := false  # PvP: ten komputer liczy boty i rozsyła ich stan (main.gd)

const SKILL_AIM := [1.9, 1.0, 0.6]      # mnożnik błędu celowania
const SKILL_REACT := [1.7, 1.0, 0.65]   # mnożnik czasu reakcji
const SKILL_SPOT := [0.6, 1.0, 1.45]    # mnożnik szybkości wykrywania

const WALK := 1.5
const RUN := 4.3
const FOV := 0.5             # cos połowy kąta widzenia (~120°)
const SEE_MAX := 150.0

var state := "patrol"        # patrol, alert, combat, search
var awareness := 0.0         # 0..1 (1 = wykrył gracza)
var suppression := 0.0
var last_known := Vector3.INF
var marksman := false
var _target: Node3D
var _sees := false
var _see_t := 0.0
var _sight_time := 0.0       # jak długo widzi cel nieprzerwanie (składanie się do strzału)
var _lost_time := 0.0
var _react := 0.0
var _aim_err := Vector2.ZERO
var _aim_err_goal := Vector2.ZERO
var _err_t := 0.0
var _burst := 0
var _burst_cd := 0.0
var _path := PackedVector3Array()
var _pi := 0
var _goal := Vector3.INF
var _repath := 0.0
var _speed := 0.0
var _cover := {}
var _in_cover := false
var _peek_t := 0.0
var _peeking := false
var _state_t := 0.0
var _post := Vector3.ZERO
var _wait := 0.0
var _crouch_t := 0.0
var _groan_t := 5.0
var _taken_cover := Vector3.INF
var _flank := false
var _retarget := 0.0
static var _covers_taken: Array = []

# PvP: u gościa bot jest kukiełką odtwarzającą stan przysyłany przez hosta
var is_remote := false
var weapon_id := ""          # z góry wybrana broń / wygląd (host przekazuje je gościowi)
var tint_i := -1
var vehicle = null           # bot-pilot: samolot / śmigłowiec, w którym siedzi
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO


func _ready() -> void:
	team = 2   # wrogowie obu graczy (PvP: gracze to drużyny 0 i 1)
	add_to_group("npc")
	if is_remote:
		collision_layer = 0   # kukiełka: pozycję ustawia host, bez blokowania gracza przy opóźnieniu
		collision_mask = 0
	else:
		collision_layer = 4
		collision_mask = 1 | 2 | 4
	# ciemniejsze, oliwkowe mundury — odcinają się od piasku i trawy
	var tints := [Color(0.5, 0.56, 0.4), Color(0.44, 0.5, 0.36), Color(0.55, 0.5, 0.4), Color(0.42, 0.45, 0.42)]
	if tint_i < 0:
		tint_i = randi() % tints.size()
	build_soldier(tints[tint_i % tints.size()], soldier_look())
	if weapon_id == "":
		weapon_id = roll_weapon()
		helmet = randf() < 0.75
		vest = randf() < 0.7
	marksman = weapon_id == "m24"
	var g = Weapons2.make(weapon_id)
	equip(g)
	_post = global_position
	yaw = rotation.y
	rotation.y = 0.0
	visual.rotation.y = yaw
	rig.aim_w = 0.2
	rig.aim_dir = Vector3.FORWARD
	_net_pos = global_position


static func roll_weapon() -> String:
	var r := randf()
	if r < 0.12:
		return "mp9"
	elif r < 0.22:
		return "r870"
	elif r < 0.34:
		return "m4"
	elif r < 0.42:
		return "m24"
	elif r < 0.47:
		return "glock"
	return "ak"


func _physics_process(dt: float) -> void:
	if is_remote:
		if vehicle == null:
			_puppet_follow(dt)
		return
	_tick_vitals(dt)
	if vehicle != null:
		return   # leci: sterowanie daje bot_pilot.gd w maszynie
	if para > 0:
		_tick_para(dt)
		return
	if down:
		if not vitals.dead:
			_groan_t -= dt
			if _groan_t <= 0.0:
				_groan_t = randf_range(4.0, 9.0)
				FX.I.play("groan", chest_pos(), -12.0, 0.15)
		return
	_tick_weapon(dt)
	if level == null or not level.is_ready():
		return
	_retarget -= dt
	if _target == null or not is_instance_valid(_target) or _target.is_dead() or _retarget <= 0.0:
		_retarget = randf_range(2.0, 3.5)
		_pick_target()
	suppression = maxf(suppression - dt * 0.25, 0.0)
	_state_t += dt
	_perceive(dt)
	_think(dt)
	_move(dt)


func _process(dt: float) -> void:
	var far := true
	var cam := get_viewport().get_camera_3d()
	if cam:
		far = cam.global_position.distance_to(global_position) > 45.0
	_animate(dt, far)


# ---------------------------------------------------------------- zmysły

func _perceive(dt: float) -> void:
	if _target == null or _target.is_dead():
		_sees = false
		return
	_see_t -= dt
	if _see_t <= 0.0:
		_see_t = 0.15 if state == "combat" else 0.3
		_sees = _can_see()
	var d := global_position.distance_to(_target.global_position)
	if _sees:
		# im dalej, tym wolniej rozpoznaje; ruch i strzelanie gracza zwracają uwagę, kucanie mniej
		var rate := 2.2 / (1.0 + d / 18.0)
		if _target.velocity.length() > 2.5:
			rate *= 1.6
		if _target.rig.crouch > 0.5:
			rate *= 0.55
		if state != "patrol":
			rate *= 2.5
		rate *= SKILL_SPOT[skill]
		awareness = minf(awareness + rate * dt * 0.33, 1.0)
		if awareness >= 1.0:
			last_known = _target.global_position
			_sight_time += dt
			_lost_time = 0.0
			if state != "combat":
				_enter_combat()
		elif awareness > 0.35 and state == "patrol":
			state = "alert"
			_goal = _target.global_position
			_state_t = 0.0
	else:
		_sight_time = 0.0
		_lost_time += dt
		if state == "patrol":
			awareness = maxf(awareness - dt * 0.05, 0.0)


func _can_see() -> bool:
	var eye := eye_pos()
	var tp: Vector3 = _target.chest_pos()
	var to := tp - eye
	var d := to.length()
	if d > SEE_MAX:
		return false
	var fwd := -visual.global_basis.z
	var cosang := fwd.dot(to / d)
	if cosang < FOV and not (d < 6.0 and state != "patrol"):
		return false
	var space := get_world_3d().direct_space_state
	for p in [tp, _target.eye_pos(), _target.global_position + Vector3(0, 0.6, 0)]:
		var q := PhysicsRayQueryParameters3D.create(eye, p, 1)
		if space.intersect_ray(q).is_empty():
			return true
	return false


func heard_shot(pos: Vector3, shooter) -> void:
	if down or shooter == null or not is_instance_valid(shooter) or shooter.team == team:
		return
	var d := global_position.distance_to(pos)
	if d > 140.0:
		return
	# kierunek strzału słychać niedokładnie — tym gorzej, im dalej
	var guess := pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * d * 0.15
	if state == "patrol" or (state == "alert" and _state_t > 2.0):
		state = "alert"
		_state_t = 0.0
		_goal = guess
		awareness = maxf(awareness, 0.5)
		_turn_to(guess)
	if state == "search":
		last_known = guess


func near_miss(_pos: Vector3, dist: float, _speed_: float, shooter) -> void:
	if down:
		return
	suppression = minf(suppression + (1.2 - dist * 0.3), 1.5)
	if shooter and is_instance_valid(shooter) and shooter.team != team:
		awareness = 1.0
		last_known = shooter.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		if state != "combat":
			_enter_combat()
		elif not _in_cover and randf() < 0.5:
			_seek_cover()


func _on_hit(h: Dictionary, _res: Dictionary) -> void:
	if down:
		return
	suppression = 1.5
	_burst = 0
	_burst_cd = randf_range(0.4, 1.0)
	var sh = h.get("shooter")
	if sh and is_instance_valid(sh) and sh.team != team:
		awareness = 1.0
		last_known = sh.global_position
		_turn_to(sh.global_position)
		if state != "combat":
			_enter_combat()
	if not _in_cover or randf() < 0.4:
		_seek_cover()
	_alert_friends(25.0)


func _enter_combat() -> void:
	state = "combat"
	_state_t = 0.0
	awareness = 1.0
	_react = randf_range(0.35, 0.8) * (1.4 - vitals.capacity() * 0.4) * SKILL_REACT[skill]
	_aim_err = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 0.06
	_alert_friends(45.0)
	if randf() < (0.7 if not marksman else 0.9):
		_seek_cover()


## Radio / krzyk: sąsiedzi dostają pozycję gracza.
func _alert_friends(r: float) -> void:
	for n in get_tree().get_nodes_in_group("npc"):
		if n == self or n.down or n.state == "combat":
			continue
		if n.global_position.distance_to(global_position) < r:
			n.last_known = last_known
			n.state = "search"
			n._state_t = 0.0
			n.awareness = maxf(n.awareness, 0.7)
			n._goal = last_known
			n._repath = 0.0


func _turn_to(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		yaw = atan2(-d.x, -d.z)


# ---------------------------------------------------------------- decyzje

func _think(dt: float) -> void:
	_crouch_t = maxf(_crouch_t - dt, 0.0)
	match state:
		"patrol":
			rig.aim_w = 0.15
			_wait -= dt
			if _wait <= 0.0 and _arrived():
				_wait = randf_range(3.0, 9.0)
				if randf() < 0.65:
					var p: Vector3 = _post + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
					_set_goal(NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p))
				else:
					_yaw_idle()
			_speed = WALK
		"alert":
			rig.aim_w = 0.5
			_speed = WALK * 1.1
			if _goal != Vector3.INF and (_path.is_empty() or _repath <= 0.0):
				_set_goal(_goal)
				_repath = 3.0
			if _state_t > 20.0:
				state = "patrol"
				awareness = 0.3
		"search":
			rig.aim_w = 0.8
			_speed = WALK * 1.3
			if _sees and awareness >= 1.0:
				_enter_combat()
			elif _repath <= 0.0:
				var g := last_known
				if _flank and last_known != Vector3.INF:
					var side := (last_known - global_position).cross(Vector3.UP).normalized() * randf_range(-12, 12)
					g = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, last_known + side)
				_set_goal(g)
				_repath = randf_range(4.0, 7.0)
			if _state_t > 35.0:
				state = "patrol"
				awareness = 0.4
		"combat":
			_combat(dt)
	_repath -= dt


func _combat(dt: float) -> void:
	if _target == null or _target.is_dead():
		state = "search"
		_state_t = 0.0
		return
	var tp: Vector3 = _target.global_position
	var d := global_position.distance_to(tp)
	rig.aim_w = 1.0
	# brak przytomności celu albo zgubiony kontakt -> przeszukanie
	if not _sees and _lost_time > (6.0 if _in_cover else 4.0):
		state = "search"
		_state_t = 0.0
		_flank = randf() < 0.5
		_in_cover = false
		_release_cover()
		_repath = 0.0
		return
	if _sees:
		_turn_to(tp)
	elif last_known != Vector3.INF:
		_turn_to(last_known)
	# osłona: kucnięcie / wychylenie
	if _in_cover:
		_speed = 0.0
		_peek_t -= dt
		if _peek_t <= 0.0:
			_peeking = not _peeking
			_peek_t = randf_range(1.8, 3.6) if _peeking else randf_range(1.0, 2.6) * (1.0 + suppression)
		if gun and gun.rounds == 0 and not gun.chambered and reloading < 0.0:
			_peeking = false
			start_reload()
		var low_cover := float(_cover.get("h", 2.0)) < 1.6
		rig.crouch = 0.0 if (_peeking and low_cover and suppression < 1.2) else (1.0 if low_cover else 0.0)
		if not low_cover:
			# za wysoką osłoną: wychyla się bokiem (krok w bok i z powrotem)
			rig.crouch = 0.0
	else:
		rig.crouch = 0.0
		if not _path.is_empty() and _pi < _path.size():
			_speed = RUN
		else:
			_speed = 0.0
			if _state_t > randf_range(4.0, 8.0) and randf() < 0.02:
				_seek_cover()
	if _sees and _target and not _target.is_dead():
		_engage(dt, d)
	if gun and gun.rounds == 0 and not gun.chambered and reloading < 0.0 and not _in_cover:
		start_reload()


## Celowanie i ogień seriami.
func _engage(dt: float, d: float) -> void:
	_react -= dt
	var eye := eye_pos()
	var aim_p: Vector3 = _target.chest_pos()
	if d < 12.0 and randf() < 0.02:
		aim_p = _target.eye_pos()
	# wyprzedzenie celu w ruchu (częściowe — człowiek nie liczy idealnie)
	var tof := d / float(gun.data["v0"]) if gun else 0.0
	aim_p += _target.velocity * tof * 0.6
	# błąd celowania: duży na początku, maleje w trakcie składania; rośnie z odległością,
	# przygnieceniem ogniem, ruchem celu, ranami
	var cap := vitals.capacity()
	var settle := lerpf(1.0, 0.45, smoothstep(0.0, 2.0, _sight_time))
	var base := 0.012 + d * 0.00022
	if marksman:
		base *= 0.4
	var err: float = base * settle * (1.0 + suppression * 1.6) * (1.0 + _target.velocity.length() * 0.15) / maxf(cap, 0.25)
	if limp_any():
		err *= 2.5
	err *= SKILL_AIM[skill]
	_err_t -= dt
	if _err_t <= 0.0:
		_err_t = randf_range(0.25, 0.6)
		_aim_err_goal = Vector2(randfn(0.0, 1.0), randfn(0.0, 1.0))
	_aim_err = _aim_err.lerp(_aim_err_goal, 1.0 - exp(-4.0 * dt))
	var dir := (aim_p - eye).normalized()
	var x := dir.cross(Vector3.UP).normalized()
	var y := x.cross(dir).normalized()
	dir = (dir + x * _aim_err.x * err + y * _aim_err.y * err).normalized()
	rig.aim_dir = (visual.global_basis.inverse() * dir).normalized()
	if _react > 0.0 or reloading >= 0.0 or gun == null:
		return
	if _in_cover and not _peeking:
		return
	# linia strzału nie może iść przez swoich
	_burst_cd -= dt
	if _burst <= 0 and _burst_cd <= 0.0:
		var md: String = gun.fire_mode()
		if md == "auto":
			_burst = randi_range(5, 9) if d < 15.0 else (randi_range(3, 5) if d < 50.0 else 1)
		else:
			_burst = 1
		if not _friend_in_line(eye, aim_p):
			_burst_cd = 0.0
		else:
			_burst = 0
			_burst_cd = 0.5
	if _burst > 0 and gun.can_fire():
		if absf(wrapf(visual.rotation.y - yaw, -PI, PI)) < 0.25:
			var muzzle_dir: Vector3 = (aim_p - gun.muzzle()).normalized()
			muzzle_dir = (muzzle_dir + x * _aim_err.x * err + y * _aim_err.y * err).normalized()
			if shoot(muzzle_dir, 0.002 * (1.0 + suppression)):
				_burst -= 1
				if _burst <= 0:
					var md: String = gun.fire_mode()
					_burst_cd = randf_range(0.25, 0.7) if md == "auto" else (randf_range(0.35, 0.9) if md == "semi" else 0.3)
					if marksman:
						_burst_cd = randf_range(1.6, 3.2)
					if d > 40.0:
						_burst_cd += randf_range(0.3, 0.9)
				if gun.rounds == 0 and not gun.chambered:
					_burst = 0
			else:
				_burst = 0


func limp_any() -> bool:
	return vitals.arms["_l"] or vitals.arms["_r"]


func _friend_in_line(from: Vector3, to: Vector3) -> bool:
	var seg := to - from
	var l2 := seg.length_squared()
	for n in get_tree().get_nodes_in_group("npc"):
		if n == self or n.down:
			continue
		var p: Vector3 = n.global_position + Vector3(0, 1.2, 0)
		var t := clampf((p - from).dot(seg) / l2, 0.0, 1.0)
		if t > 0.02 and (from + seg * t).distance_to(p) < 0.7:
			return true
	return false


func _seek_cover() -> void:
	if level == null or _target == null:
		return
	var threat := last_known if last_known != Vector3.INF else _target.global_position
	var c: Dictionary = level.find_cover(global_position, threat, 26.0 if not marksman else 35.0, _covers_taken, get_world_3d().direct_space_state)
	if c.is_empty():
		_in_cover = false
		return
	_release_cover()
	_cover = c
	_taken_cover = c["pos"]
	_covers_taken.append(_taken_cover)
	_in_cover = false
	_set_goal(c["pos"])


func _release_cover() -> void:
	if _taken_cover != Vector3.INF:
		_covers_taken.erase(_taken_cover)
		_taken_cover = Vector3.INF


func _yaw_idle() -> void:
	yaw += randf_range(-1.5, 1.5)


# ---------------------------------------------------------------- ruch

func _set_goal(p: Vector3) -> void:
	_goal = p
	_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, p, true)
	_pi = 1 if _path.size() > 1 else 0


func _arrived() -> bool:
	return _path.is_empty() or _pi >= _path.size()


func _move(dt: float) -> void:
	var want := Vector3.ZERO
	var spd := _speed * clampf(vitals.capacity() + 0.25, 0.4, 1.0)
	if vitals.legs >= 1:
		spd = minf(spd, 0.0)
		rig.kneel = 1.0
	if reloading >= 0.0 and state == "combat":
		spd = minf(spd, WALK)
	if not _path.is_empty() and _pi < _path.size() and spd > 0.0:
		var nxt := _path[_pi] - global_position
		nxt.y = 0.0
		if nxt.length() < 0.45:
			_pi += 1
			if _pi >= _path.size():
				_on_arrive()
		else:
			want = nxt.normalized() * spd
	# rozpychanie
	for n in get_tree().get_nodes_in_group("npc"):
		if n == self or n.down:
			continue
		var d: Vector3 = global_position - n.global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.9 and l > 0.001:
			want += d / l * (0.9 - l) * 4.0
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(want, (10.0 if want.length() > hv.length() else 8.0) * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
	# obrót: w walce do celu, inaczej w stronę ruchu
	if state != "combat" and hv.length() > 0.4:
		yaw = atan2(-hv.x, -hv.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-(9.0 if state == "combat" else 5.0) * dt))
	rig.vel = visual.global_basis.inverse() * velocity
	rig.air = not is_on_floor()
	if state != "combat":
		var look := Vector3(0, -0.1 if state == "patrol" else 0.0, -1)
		rig.aim_dir = rig.aim_dir.lerp(look.normalized(), 1.0 - exp(-3.0 * dt)).normalized()
	if state == "patrol" or state == "alert":
		rig.crouch = 0.0
	elif state == "search":
		rig.crouch = 0.0


func _on_arrive() -> void:
	if state == "combat" and not _cover.is_empty() and global_position.distance_to(_cover["pos"]) < 1.2:
		_in_cover = true
		_peeking = false
		_peek_t = randf_range(0.6, 1.5)
	elif state == "search" and global_position.distance_to(last_known) < 4.0:
		_repath = 0.0
		_flank = randf() < 0.5


func _collapse(dir: Vector3, at: Vector3, seg: String, energy: float, instant: bool) -> void:
	if down:
		return
	_release_cover()
	deaths += 1
	if vehicle != null and is_instance_valid(vehicle):
		var v = vehicle
		leave_vehicle(false)
		v.pilot_gone(self)
	if net_host and not is_remote and get_parent().has_method("bot_down"):
		get_parent().bot_down(self, dir, at, seg, energy, instant)
	super._collapse(dir, at, seg, energy, instant)
	if not is_remote:
		_alert_friends(20.0)


# ---------------------------------------------------------------- bot-pilot

func enter_vehicle(v) -> void:
	vehicle = v
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	reloading = -1.0
	if gun:
		gun.visible = false


func leave_vehicle(place: bool) -> void:
	var v = vehicle
	vehicle = null
	if not is_remote:
		collision_layer = 4
		collision_mask = 1 | 2 | 4
	if gun:
		gun.visible = true
	if place and v != null and is_instance_valid(v):
		global_position = v.exit_point()
	visual.rotation = Vector3(0, visual.rotation.y, 0)


## Zginął w rozbitej maszynie.
func vehicle_death() -> void:
	vitals.cause = "katastrofa lotnicza"
	vitals._die()
	_collapse(Vector3.UP, chest_pos(), "torso", 4000.0, true)


func is_pilot() -> bool:
	return vehicle != null


# ---------------------------------------------------------------- spadochron (bot-pilot)

const Parachute = preload("res://scripts/parachute.gd")
var para := 0
var para_t := 0.0
var _canopy: Node3D


func start_freefall(pos: Vector3, vel: Vector3) -> void:
	global_position = pos
	velocity = vel
	para = 1
	para_t = 0.0


func _show_canopy(on: bool) -> void:
	if on and _canopy == null:
		_canopy = Parachute.canopy()
		add_child(_canopy)
		_canopy.scale = Vector3.ONE * 0.1
	elif not on and _canopy != null:
		_canopy.queue_free()
		_canopy = null


## Bot otwiera spadochron po chwili, pod czaszą opada prosto, po wylądowaniu walczy dalej.
func _tick_para(dt: float) -> void:
	para_t += dt
	if para == 1 and para_t > 1.2:
		para = 2
		para_t = 0.0
		_show_canopy(true)
	elif para == 2:
		_canopy.scale = Vector3.ONE * clampf(para_t / Parachute.OPEN_TIME, 0.1, 1.0)
		if para_t >= Parachute.OPEN_TIME:
			para = 3
	var r: String = Parachute.step(self, para, para_t, Vector3.ZERO, dt)
	rig.air = true
	if r == "dead":
		vitals._die()
		_collapse(Vector3.DOWN, chest_pos(), "torso", 5000.0, true)
	if r != "":
		para = 0
		_show_canopy(false)
		state = "search"
		_post = global_position


## Cel: najbliższy żywy gracz (solo: gracz; PvP u hosta: także kukiełka gościa). Obecny cel
## zostaje, chyba że inny jest wyraźnie bliżej.
func _pick_target() -> void:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("net_player"):
		if not is_instance_valid(n) or n.down or String(n.name).begins_with("Dead"):
			continue
		var d: float = n.global_position.distance_to(global_position)
		if n == _target:
			d *= 0.7
		if d < best_d:
			best_d = d
			best = n
	if best != _target:
		_target = best
		_sight_time = 0.0


# ---------------------------------------------------------------- sieć (PvP)
# Host liczy boty i rozsyła ich stan, strzały i upadki (main.gd); u gościa bot jest kukiełką.
# Kule gościa trafiające kukiełkę idą do hosta (jak trafienia przeciwnika w PvP).

## Host: strzał bota leci też u gościa.
func _on_fired(origin: Vector3, dir: Vector3, tracer: bool) -> void:
	if net_host and not is_remote and get_parent().has_method("bot_shot"):
		get_parent().bot_shot(self, origin, dir, tracer)


func bullet_hit(h: Dictionary) -> void:
	if is_remote:
		_puppet_hit(h)
		return
	# host: kula odtworzona ze strzału gościa — trafienie przyśle sam gość (net_bot_hit);
	# odłamki granatów i rakiet liczy każdy komputer dla swoich botów
	var sh = h.get("shooter")
	if net_host and sh != null and is_instance_valid(sh) and sh.get("is_remote") == true \
			and not h.get("_net", false) and h.get("cal", "") != "frag":
		return
	super.bullet_hit(h)


## (kukiełka u gościa) moja kula trafiła bota: krew tutaj, obrażenia liczy host.
func _puppet_hit(h: Dictionary) -> void:
	if down:
		return
	var dir: Vector3 = h["dir"]
	if h.get("armor", "") == "":
		FX.I.blood_spray(h["entry"], -dir, 0.5)
		if not h.get("stopped", false):
			FX.I.blood_spray(h["exit"], dir, 0.8)
		FX.I.play("hit", h["entry"], -4.0, 0.15)
	rig.hit_react(visual.global_basis.inverse() * dir, h["seg"], 0.8)
	var sh = h.get("shooter")
	if sh == null or not is_instance_valid(sh) or not sh.is_in_group("player") or h.get("cal", "") == "frag":
		return
	if get_parent().has_method("send_bot_hit"):
		var d := h.duplicate()
		d.erase("shooter")
		d["_net"] = true
		get_parent().send_bot_hit(self, d)
	last_hit_time = Time.get_ticks_msec() / 1000.0
	if h.get("armor", "") == "":
		last_hit_seg = h["seg"]
	sh.on_hit_confirmed(self, hit_info(h))


const NET_STRIDE := 15

## Host: stan do paczki (NET_STRIDE liczb na bota — kolejność jak w net_apply).
func net_pack(f: PackedFloat32Array, idx: int) -> void:
	var a: Vector3 = rig.aim_dir
	f.append_array([float(idx), global_position.x, global_position.y, global_position.z, velocity.x, velocity.z,
		visual.rotation.y, a.x, a.y, a.z, rig.aim_w, rig.crouch, rig.kneel, rig.reload_p, float(para)])


## (kukiełka) stan z paczki hosta: pozycja, prędkość, obrót, celowanie, postawa, przeładowanie.
func net_apply(f: PackedFloat32Array, i: int) -> void:
	if down:
		return
	_net_pos = Vector3(f[i + 1], f[i + 2], f[i + 3])
	_net_vel = Vector3(f[i + 4], 0.0, f[i + 5])
	yaw = f[i + 6]
	rig.aim_dir = Vector3(f[i + 7], f[i + 8], f[i + 9])
	rig.aim_w = f[i + 10]
	rig.crouch = f[i + 11]
	rig.kneel = f[i + 12]
	if gun:
		rig.reload_kind = "mag" if gun.data["feed"] == "mag" else "shell"
	rig.reload_p = f[i + 13]
	_show_canopy(f[i + 14] >= 2.0)
	if _canopy:
		_canopy.scale = _canopy.scale.move_toward(Vector3.ONE, 0.12)


func _puppet_follow(dt: float) -> void:
	if down:
		return
	var target := _net_pos + _net_vel * 0.05
	if global_position.distance_to(target) > 4.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-10.0 * dt))
	velocity = _net_vel
	visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-12.0 * dt))
	rig.vel = visual.global_basis.inverse() * velocity
	rig.air = false


## (kukiełka) host przysłał strzał bota: ten sam pocisk leci u mnie (trafienia we mnie liczy host).
func net_fire(origin: Vector3, dir: Vector3, tracer: bool) -> void:
	if down or gun == null:
		return
	fire_projectile(gun, origin, dir, tracer)
	gun.flash()
	_shot_fx(gun, origin, dir)
	FX.I.play(gun.data["sound"], origin, 4.0, 0.06, 1.0, 40.0)
	rig.kick(1.0)
	set_meta("shot_t", Time.get_ticks_msec() / 1000.0)
