extends "res://scripts/soldier.gd"
## Gracz: ruch, widok z pierwszej osoby (broń po prawej, PPM — celowanie przez kolimator / lunetę)
## albo zza ramienia [V], laser [L], odrzut, kołysanie broni (oddech, zmęczenie, ból, utrata krwi),
## wstrzymanie oddechu, trzynaście broni, magazynki, tryby ognia, opatrunki, zbieranie amunicji,
## samoloty (wsiadanie [E], sterowanie przejmuje plane.gd).

const WALK := 1.6
const JOG := 3.6
const SPRINT := 6.2
const CROUCH := 1.4
const ADS_SPEED := 1.5
const ACCEL := 10.0
const MOUSE_SENS := 0.0022
const LOADOUT := ["m4", "ak", "aug", "mp9", "r870", "m24", "glock", "deagle", "ak74", "uzi", "sawed", "awm", "m686"]
const OWN_LAYER := 1 << 10    # warstwa obrazu własnego ciała (niewidoczna z pierwszej osoby; 2 = ciała dla decali krwi)

var guns: Array = []
var gun_i := 0
var stamina := 100.0
var bandages := 5
var ads := 0.0
var aiming := false
var kills := 0
var hit_marker := 0.0
var hit_kill := false
var damage_dirs: Array = []
var message := ""
var message_t := 0.0
var bandaging := -1.0
var breath := 6.0
var holding_breath := false
var aim_point := Vector3.ZERO
var crouching := false
var first_person := true
var laser_on := true

var _yaw := 0.0
var _pitch := -0.1
var _cam_yaw: Node3D
var _cam_pitch: Node3D
var _arm: SpringArm3D
var _cam: Camera3D
var _holster: Node3D
var _trigger := false
var _trigger_fresh := false
var _switch_t := 0.0
var _rec_pending := Vector2.ZERO
var _sway_t := 0.0
var _sway := Vector2.ZERO
var _noise := FastNoiseLite.new()
var _trauma := 0.0
var _walk_mode := false
var _move := Vector3.ZERO
var _jump_buf := 0.0
var _death_t := 0.0
var _vm_pivot: Node3D          # broń z pierwszej osoby (przy kamerze)
var _vm: Node3D
var _vm_kick := 0.0
var _vm_kick_v := 0.0
var _vm_low := 0.0
var _bob_t := 0.0
var _aim_local := Vector3.FORWARD
var vehicle = null             # samolot, w którym siedzę (plane.gd)


func _ready() -> void:
	team = 1 if is_remote else 0
	if is_remote:
		# przeciwnik w PvP: tylko odtwarza stan przysyłany z jego komputera
		add_to_group("net_player")
		collision_layer = 4
		collision_mask = 0
		build_soldier(Color(0.72, 0.36, 0.3), soldier_look())  # przeciwnik: czerwonobrązowy
	else:
		add_to_group("player")
		collision_layer = 2
		collision_mask = 1 | 4 | 32
		build_soldier(Color(0.55, 0.6, 0.62), soldier_look())
	_holster = Node3D.new()
	_holster.visible = false
	add_child(_holster)
	for w in LOADOUT:
		var g = Weapons.make(w)
		g.add_optics()
		g.add_laser()
		g.laser_exclude.append(get_rid())
		guns.append(g)
		_holster.add_child(g)
	_equip_i(0, true)
	if net_on:
		var gd := _gd()
		for f in [net_state, net_shot, net_down, net_hit]:
			gd.expose_func(f)
	_yaw = rotation.y
	rotation.y = 0.0
	_net_pos = global_position
	if is_remote:
		visual.rotation.y = _yaw
		return
	_cam_yaw = Node3D.new()
	_cam_yaw.top_level = true
	add_child(_cam_yaw)
	_cam_pitch = Node3D.new()
	_cam_yaw.add_child(_cam_pitch)
	_arm = SpringArm3D.new()
	_arm.spring_length = 2.4
	_arm.collision_mask = 1
	_arm.margin = 0.15
	_arm.position = Vector3(0.55, 0.0, 0.0)
	_cam_pitch.add_child(_arm)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.03
	_cam.far = 900.0
	_cam.current = true
	_arm.add_child(_cam)
	_cam_yaw.global_position = global_position + Vector3(0, 1.6, 0)
	_noise.frequency = 0.35
	_vm_pivot = Node3D.new()
	_cam.add_child(_vm_pivot)
	_build_vm()
	_layer_body()


func camera() -> Camera3D:
	return _cam


# ---------------------------------------------------------------- wejście

func _unhandled_input(e: InputEvent) -> void:
	if is_remote:
		return
	if vehicle and not down and e is InputEventMouseMotion:
		vehicle.pilot_input(e)
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := MOUSE_SENS * Settings.sens * lerpf(1.0, _cam.fov / Settings.fov, ads)
		_yaw -= e.relative.x * k
		_pitch = clampf(_pitch - e.relative.y * k, -1.35, 1.25)
		return
	if e.is_action_pressed("restart") and not net_on:
		get_tree().reload_current_scene()
		return
	if down:
		return
	if vehicle:
		vehicle.pilot_input(e)
		return
	if e.is_action_pressed("attack"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		_trigger = true
		_trigger_fresh = true
		if reloading >= 0.0 and gun and gun.data["feed"] == "tube" and gun.rounds > 0:
			cancel_reload()
	elif e.is_action_released("attack"):
		_trigger = false
	elif e.is_action_pressed("reload"):
		if bandaging < 0.0 and _switch_t <= 0.0:
			start_reload()
	elif e.is_action_pressed("fire_mode"):
		if gun and (gun.data["modes"] as Array).size() > 1:
			gun.cycle_mode()
			FX.I.play("click", gun.global_position, -12.0)
			_msg("Tryb ognia: " + {"auto": "seria", "semi": "pojedynczy"}.get(gun.fire_mode(), gun.fire_mode()))
	elif e.is_action_pressed("bandage"):
		_start_bandage()
	elif e.is_action_pressed("use"):
		if not _board_plane():
			_loot()
	elif e.is_action_pressed("view_toggle"):
		first_person = not first_person
	elif e.is_action_pressed("laser"):
		laser_on = not laser_on
		for g in guns:
			g.laser_on = laser_on
		if _vm:
			_vm.laser_on = laser_on
		FX.I.play("click", global_position + Vector3(0, 1.4, 0), -14.0)
	elif e.is_action_pressed("walk_toggle"):
		_walk_mode = not _walk_mode
	elif e.is_action_pressed("jump"):
		_jump_buf = 0.2
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e.is_action_pressed("next_weapon"):
		_equip_i((gun_i + 1) % guns.size())
	elif e.is_action_pressed("prev_weapon"):
		_equip_i((gun_i - 1 + guns.size()) % guns.size())
	else:
		for i in mini(guns.size(), 10):
			if e.is_action_pressed("weapon_%d" % (i + 1)):
				_equip_i(i)


func _equip_i(i: int, instant := false) -> void:
	if i == gun_i and gun != null:
		return
	if gun:
		rig.remove_child(gun)
		_holster.add_child(gun)
	gun_i = i
	var g = guns[i]
	_holster.remove_child(g)
	equip(g)
	if _vm_pivot:
		_build_vm()
	_switch_t = 0.0 if instant else 0.55
	if not instant:
		FX.I.play("mag_in", global_position + Vector3(0, 1.2, 0), -14.0, 0.1, 1.4)
		_msg(g.data["name"])


func _msg(t: String) -> void:
	message = t
	message_t = 2.5


func _start_bandage() -> void:
	if bandages <= 0 or bandaging >= 0.0 or down:
		return
	if vitals.bleed_rate() < 0.05:
		_msg("Nic nie krwawi")
		return
	bandaging = 0.0
	reloading = -1.0
	rig.reload_p = -1.0


func _loot() -> void:
	for c in get_tree().get_nodes_in_group("ammo_crate"):
		if c.near(self):
			var r: String = c.resupply(self)
			if r != "":
				FX.I.play("mag_in", global_position + Vector3(0, 1.0, 0), -4.0)
				FX.I.play("bolt", global_position + Vector3(0, 1.0, 0), -8.0, 0.05, 1.2)
				_msg(r)
			else:
				_msg("Skrzynka pusta — odnowi się za %d s" % ceili(c.cooldown))
			return
	var got := 0
	for rb in get_tree().get_nodes_in_group("dropped_gun"):
		if not is_instance_valid(rb) or (rb as Node3D).global_position.distance_to(global_position) > 2.5:
			continue
		var other = (rb as Node).get_meta("gun")
		if other == null or not is_instance_valid(other) or other.total_ammo() <= 0:
			continue
		for g in guns:
			got += g.take_ammo_from(other)
	if got > 0:
		FX.I.play("mag_in", global_position + Vector3(0, 1.0, 0), -8.0)
		_msg("Zebrano amunicję: %d naboi" % got)
	else:
		_msg("Brak pasującej amunicji w pobliżu")


# ---------------------------------------------------------------- pętla

func _physics_process(dt: float) -> void:
	if is_remote:
		_net_follow(dt)
		return
	_tick_kills(dt)
	_tick_vitals(dt)
	if down:
		_death_t += dt
		return
	if net_on:
		_net_send(dt)
	message_t -= dt
	hit_marker = maxf(hit_marker - dt * 3.0, 0.0)
	_trauma = maxf(_trauma - dt * 1.5, 0.0)
	for i in range(damage_dirs.size() - 1, -1, -1):
		damage_dirs[i][1] -= dt
		if damage_dirs[i][1] <= 0.0:
			damage_dirs.remove_at(i)
	if vehicle:
		return   # w kabinie: ruch i strzelanie prowadzi samolot
	_tick_weapon(dt)
	_switch_t = maxf(_switch_t - dt, 0.0)
	if bandaging >= 0.0:
		bandaging += dt
		if bandaging >= 3.0:
			bandaging = -1.0
			var r := vitals.treat()
			if r != "":
				bandages -= 1
				_msg(r)
	_movement(dt)
	_fire_logic()


func _movement(dt: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)
	crouching = Input.is_action_pressed("crouch") or vitals.legs >= 1
	aiming = Input.is_action_pressed("aim") and _switch_t <= 0.0 and bandaging < 0.0
	var sprinting := Input.is_action_pressed("run") and input.y < -0.3 and not crouching and not aiming and stamina > 1.0 and reloading < 0.0 and vitals.legs == 0
	holding_breath = Input.is_action_pressed("run") and aiming and breath > 0.0
	var speed := JOG
	if _walk_mode:
		speed = WALK
	if sprinting:
		speed = SPRINT
	if crouching:
		speed = CROUCH
	if aiming:
		speed = minf(speed, ADS_SPEED)
	if vitals.legs >= 1:
		speed = minf(speed, 0.9)
	speed *= clampf(vitals.capacity() + 0.2, 0.35, 1.0)
	_move = _move.lerp(wish * speed, 1.0 - exp(-ACCEL * dt))
	velocity.x = _move.x
	velocity.z = _move.z
	_jump_buf -= dt
	if is_on_floor():
		velocity.y = -0.5
		if _jump_buf > 0.0 and not crouching and stamina > 8.0:
			velocity.y = 3.2
			stamina -= 8.0
			_jump_buf = 0.0
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
	if sprinting and _move.length() > 3.0:
		stamina = maxf(stamina - 14.0 * dt, 0.0)
	else:
		stamina = minf(stamina + (9.0 if _move.length() < 2.0 else 4.0) * dt * clampf(1.0 - vitals.lost() * 1.5, 0.2, 1.0), 100.0)
	if holding_breath:
		breath = maxf(breath - dt, 0.0)
	else:
		breath = minf(breath + dt * 0.6, 6.0)
	rig.sprint = sprinting and _move.length() > 4.0
	rig.crouch = 1.0 if crouching else 0.0
	rig.air = not is_on_floor()
	rig.vel = visual.global_basis.inverse() * velocity
	yaw = atan2(-_move.x, -_move.z) if rig.sprint else _yaw
	visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-(16.0 if aiming else 11.0) * dt))


func _fire_logic() -> void:
	if gun == null:
		return
	var md: String = gun.fire_mode()
	var want := _trigger and (md == "auto" or _trigger_fresh)
	var blocked := _switch_t > 0.0 or bandaging >= 0.0 or rig.sprint or reloading >= 0.0
	if want and not blocked:
		var hip := 0.0 if aiming else 0.01 + _move.length() * 0.004
		hip += _move.length() * (0.0015 if aiming else 0.0)
		if crouching:
			hip *= 0.7
		if shoot(_shot_dir(), hip):
			_recoil_kick()
		_trigger_fresh = false
	if not _trigger:
		_trigger_fresh = false


## Z wylotu lufy w punkt pod celownikiem / kropką kolimatora (z kołysaniem broni).
func _shot_dir() -> Vector3:
	return (aim_point - gun.muzzle()).normalized()


func _recoil_kick() -> void:
	var r: Array = gun.data["recoil"]
	var k := (1.0 if not crouching else 0.8) * (1.0 if aiming else 1.15) / clampf(vitals.capacity(), 0.5, 1.0)
	var up := float(r[0]) * randf_range(0.8, 1.2) * k
	var side := float(r[1]) * randf_range(-1.0, 1.0) * k
	_pitch = clampf(_pitch + up, -1.35, 1.25)
	_yaw += side
	_rec_pending += Vector2(up, side) * 0.55
	_trauma = minf(_trauma + 0.06 + float(r[0]) * 2.0, 0.5)


func _want_more_shells() -> bool:
	return not _trigger


# ---------------------------------------------------------------- obraz

func _process(dt: float) -> void:
	var rd := minf(dt, 0.1)
	if is_remote or vehicle:
		_animate(rd, false)
		return
	var rec := _rec_pending * (1.0 - exp(-7.0 * rd))
	_rec_pending -= rec
	_pitch -= rec.x
	_yaw -= rec.y
	ads = move_toward(ads, 1.0 if (aiming and not down) else 0.0, rd * 4.5)
	var cam_base := global_position + Vector3(0, 1.62 - 0.52 * rig._crouch_s, 0)
	_cam_yaw.global_position = _cam_yaw.global_position.lerp(cam_base, 1.0 - exp(-18.0 * rd))
	_cam_yaw.rotation = Vector3(0, _yaw, 0)
	_cam_pitch.rotation = Vector3(_pitch, 0, 0)
	_sway_t += rd
	var sway_amp := 0.0012 + (100.0 - stamina) * 0.00004 + vitals.pain * 0.004 + vitals.lost() * 0.012
	if gun:
		sway_amp *= clampf(float(gun.data["weight"]) / 3.5, 0.6, 1.4)
	if crouching:
		sway_amp *= 0.7
	if holding_breath:
		sway_amp *= 0.15
	elif breath < 1.0:
		sway_amp *= 2.0
	var tgt := Vector2(_noise.get_noise_2d(_sway_t * 18.0, 0.0), _noise.get_noise_2d(0.0, _sway_t * 18.0)) * sway_amp * 2.0
	tgt.y += sin(_sway_t * 1.3) * sway_amp * 0.8
	_sway = _sway.lerp(tgt, 1.0 - exp(-6.0 * rd))
	# kierunek broni względem kamery: kołysanie przesuwa kropkę kolimatora i punkt trafienia
	_aim_local = Vector3(_sway.x, _sway.y, -1.0).normalized()
	_place_camera(rd)
	_update_aim()
	var aim_world := (aim_point - eye_pos()).normalized()
	rig.aim_dir = (visual.global_basis.inverse() * aim_world).normalized()
	rig.aim_w = 1.0 if (aiming or _trigger or _rec_pending.length() > 0.002 or first_person) else 0.75
	if bandaging >= 0.0 or _switch_t > 0.0:
		rig.aim_w = 0.0
	rig.hide_head = false
	_animate(rd, false)
	_place_vm(rd)


func _update_aim() -> void:
	var from := _cam.global_position
	var dir := (_cam.global_basis * _aim_local).normalized()
	var skip := 0.1 if first_person else _arm.get_hit_length() + 0.4
	var q := PhysicsRayQueryParameters3D.create(from + dir * skip, from + dir * 600.0, 1 | 8 | 32, hit_rids())
	q.collide_with_areas = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	aim_point = r["position"] if not r.is_empty() else from + dir * 600.0


func _place_camera(rd: float) -> void:
	var fp := first_person and not down
	_cam.cull_mask = (0xFFFFF & ~OWN_LAYER) if fp else 0xFFFFF
	if down:
		_arm.position = Vector3(0.3, 0.0, 0.0)
		_arm.spring_length = lerpf(_arm.spring_length, 3.5, 1.0 - exp(-2.0 * rd))
		_cam_yaw.global_position = _cam_yaw.global_position.lerp(chest_pos() + Vector3(0, 0.5, 0), 1.0 - exp(-3.0 * rd))
		_cam.fov = 60.0
		return
	if fp:
		_arm.position = Vector3.ZERO
		_arm.spring_length = 0.0
	else:
		_arm.position = Vector3(0.55, 0.0, 0.0)
		_arm.spring_length = lerpf(2.4, 1.3, ads)
	var shake := _trauma * _trauma
	_cam.h_offset = _noise.get_noise_2d(Time.get_ticks_msec() * 0.05, 3.0) * 0.05 * shake
	_cam.v_offset = _noise.get_noise_2d(7.0, Time.get_ticks_msec() * 0.05) * 0.05 * shake
	var fov_ads: float = gun.data["ads_fov"] if gun else 50.0
	var f := lerpf(Settings.fov, fov_ads, ads)
	if gun and gun.data.get("scope", false):
		f = Settings.fov if ads < 0.9 else fov_ads
	_cam.fov = f


## Czy patrzę przez lunetę (HUD rysuje wtedy obraz lunety).
func scoped() -> bool:
	return gun != null and gun.data.get("scope", false) and ads >= 0.9 and not down


## Broń widoczna z pierwszej osoby: osobna kopia modelu przy kamerze, po prawej stronie;
## w celowaniu kolimator wjeżdża na środek obrazu.
func _build_vm() -> void:
	if _vm:
		_vm.queue_free()
		_vm = null
	if gun == null:
		return
	_vm = Weapons.make(gun.id)
	_vm.add_optics()
	_vm.add_laser()
	_vm.laser_exclude.append(get_rid())
	_vm.laser_on = laser_on
	_vm_pivot.add_child(_vm)
	for gi in _vm.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_low = 1.0


func _place_vm(rd: float) -> void:
	if _vm == null:
		return
	_vm.visible = first_person and not down and not scoped()
	if not _vm.visible:
		return
	_vm_pivot.basis = Basis.looking_at(_aim_local, Vector3.UP)
	var pistol: bool = gun.is_pistol()
	var hip := Vector3(0.13, -0.15, -0.42) if pistol else Vector3(0.15, -0.24, -0.46)
	var ads_pos: Vector3 = Vector3(0, 0, -(0.38 if pistol else 0.26)) - _vm.sight_point
	var k := smoothstep(0.0, 1.0, ads)
	var pos := hip.lerp(ads_pos, k)
	# kołysanie w marszu
	var spd := Vector2(velocity.x, velocity.z).length()
	if spd > 0.3 and is_on_floor():
		_bob_t += rd * (4.0 + spd * 1.8)
	var bob_k := clampf(spd / 3.6, 0.0, 1.6) * (1.0 - k * 0.85)
	pos += Vector3(sin(_bob_t) * 0.009, -absf(cos(_bob_t)) * 0.011, 0.0) * bob_k
	# odrzut: sprężyna
	_vm_kick_v += (-_vm_kick * 320.0 - _vm_kick_v * 24.0) * rd
	_vm_kick += _vm_kick_v * rd
	pos.z += _vm_kick * 0.05
	pos.y += _vm_kick * 0.008
	# przeładowanie, opatrunek, zmiana broni, bieg: broń opuszczona i przechylona
	var low := reloading >= 0.0 or bandaging >= 0.0 or _switch_t > 0.0 or rig.sprint
	_vm_low = move_toward(_vm_low, 1.0 if low else 0.0, rd * 5.0)
	var lw := smoothstep(0.0, 1.0, _vm_low)
	pos += Vector3(-0.03, -0.1, 0.04) * lw
	var rot := Basis(Vector3.RIGHT, _vm_kick * 0.07 - 0.45 * lw) * Basis(Vector3.BACK, 0.5 * lw)
	_vm.transform = Transform3D(rot, pos)


## Własne ciało i broń w rękach na osobnej warstwie — kamera z pierwszej osoby ich nie widzi.
func _layer_body() -> void:
	for n in find_children("*", "VisualInstance3D", true, false):
		if _cam_yaw and _cam_yaw.is_ancestor_of(n):
			continue
		(n as VisualInstance3D).layers = OWN_LAYER


# ---------------------------------------------------------------- trafienia

func bullet_hit(h: Dictionary) -> void:
	if net_on:
		var sh = h.get("shooter")
		if is_remote:
			_net_forward_hit(h)
			return
		if sh != null and is_instance_valid(sh) and sh != self and sh.get("is_remote") == true and not h.get("_net", false):
			return  # kula odtworzona z cudzego strzału: obrażenia przyjdą od strzelca (net_hit)
	super.bullet_hit(h)
	_layer_body.call_deferred()
	damage_dirs.append([-(h["dir"] as Vector3), 2.5])
	_trauma = minf(_trauma + 0.45, 1.0)
	bandaging = -1.0
	FX.I.play("hit_heavy", global_position + Vector3(0, 1.4, 0), -2.0, 0.1)


func near_miss(pos: Vector3, dist: float, spd: float, _shooter) -> void:
	if down:
		return
	if spd > 345.0:
		FX.I.play("crack", pos, 2.0 - dist * 2.0, 0.15, 1.0, 3.0)
	_trauma = minf(_trauma + 0.12 / maxf(dist, 0.3), 0.6)


# ---------------------------------------------------------------- znaczniki trafień i zabójstw
# Jak w Battlefront II: znacznik trafienia biały (lekkie: mięśnie, kończyny), czerwony (krytyczne:
# narząd życiowy, głowa), duży czerwony (eliminacja). Przy ranie napis (czerwony / biały), osobny
# dźwięk headshota tylko gdy kula przebiła głowę. Nad zabitym czaszka, „ELIMINACJA +100”, lista.

const KILL_MARK_TIME := 3.5
var hit_kind := 0             # 0 biały (lekkie), 1 czerwony (krytyczne), 2 eliminacja
var hit_popups: Array = []    # {pos, text, crit, head, t} napisy przy ranach
var score := 0
var kill_marks: Array = []    # {node, pos, t, head}
var kill_feed: Array = []     # {text, t}
var kill_banner: Array = []   # [{text, pts}] ostatnie zdarzenie
var kill_banner_t := 0.0
var _streak := 0
var _streak_t := 0.0


func on_hit_confirmed(target, info) -> void:
	if is_remote:
		return
	if info is int:   # samolot (plane.gd przez confirm_hit)
		info = {"crit": info > 0, "head": false, "armor": false, "text": "", "pos": (target as Node3D).global_position}
	var crit: bool = info["crit"]
	var k := 1 if crit else 0
	if hit_marker < 0.35 or hit_kind < 2:
		hit_kind = maxi(k, hit_kind if hit_marker > 0.35 else 0)
	hit_marker = 1.0
	hit_kill = false
	var ear := global_position + Vector3(0, 1.6, 0)
	if info["head"]:
		FX.I.play("impact_metal", ear, -1.0, 0.03, 2.3, 30.0)    # „ding” — tylko prawdziwy headshot
	elif crit:
		FX.I.play("click", ear, -3.0, 0.05, 1.3, 30.0)
	else:
		FX.I.play("click", ear, -9.0, 0.05, 2.4, 30.0)
	if String(info["text"]) != "":
		hit_popups.append({"pos": info["pos"], "text": info["text"], "crit": crit, "head": info["head"],
			"armor": info["armor"], "t": 1.3, "off": Vector2(randf_range(44, 60), randf_range(-8, 8))})
		if hit_popups.size() > 8:
			hit_popups.pop_front()


## Zgodność ze starszym API (plane.gd): trafienie celu bez ciała (samolot); zniszczenie = eliminacja.
func confirm_hit(target, newly_down: bool) -> void:
	on_hit_confirmed(target, 1)
	if newly_down:
		kills += 1
		score += 150
		hit_kind = 2
		hit_kill = true
		kill_banner = [{"text": "ZESTRZELENIE", "pts": 150}]
		kill_banner_t = 2.6
		kill_feed.push_front({"text": "Ty  zestrzeliłeś samolot", "t": 6.0})


func on_kill(target) -> void:
	if is_remote or not is_instance_valid(target):
		return
	kills += 1
	hit_marker = 1.0
	hit_kind = 2
	hit_kill = true
	var head: bool = target.last_hit_seg == "head"
	FX.I.play("impact_metal", global_position + Vector3(0, 1.6, 0), -3.0, 0.0, 0.9, 30.0)
	var pts := 100 + (50 if head else 0)
	_streak = _streak + 1 if _streak_t > 0.0 else 1
	_streak_t = 6.0
	var lines := [{"text": "ELIMINACJA", "pts": pts}]
	if head:
		lines.append({"text": "Strzał w głowę", "pts": 0})
	if _streak >= 2:
		var bonus := 25 * (_streak - 1)
		lines.append({"text": "Seria zabójstw x%d" % _streak, "pts": bonus})
		pts += bonus
	score += pts
	kill_banner = lines
	kill_banner_t = 2.6
	kill_marks.append({"node": target, "pos": target.chest_pos(), "t": KILL_MARK_TIME, "head": head})
	var who: String = "Przeciwnik" if target.get("is_remote") == true else "Żołnierz wroga"
	kill_feed.push_front({"text": "Ty  [%s]%s  %s" % [gun.data["name"] if gun else "?", "  ☠" if head else "", who], "t": 6.0})
	if kill_feed.size() > 5:
		kill_feed.pop_back()


func _tick_kills(dt: float) -> void:
	kill_banner_t = maxf(kill_banner_t - dt, 0.0)
	for i in range(hit_popups.size() - 1, -1, -1):
		hit_popups[i]["t"] = float(hit_popups[i]["t"]) - dt
		if float(hit_popups[i]["t"]) <= 0.0:
			hit_popups.remove_at(i)
	_streak_t = maxf(_streak_t - dt, 0.0)
	for i in range(kill_marks.size() - 1, -1, -1):
		var m: Dictionary = kill_marks[i]
		m["t"] = float(m["t"]) - dt
		var n = m["node"]
		if is_instance_valid(n) and n.body:
			m["pos"] = n.chest_pos()
		if float(m["t"]) <= 0.0:
			kill_marks.remove_at(i)
	for i in range(kill_feed.size() - 1, -1, -1):
		kill_feed[i]["t"] = float(kill_feed[i]["t"]) - dt
		if float(kill_feed[i]["t"]) <= 0.0:
			kill_feed.remove_at(i)


# ---------------------------------------------------------------- sieć (PvP 1 na 1, GD-Sync)
# Każdy steruje swoim żołnierzem; u przeciwnika ten sam węzeł (P<id>) jest kukiełką odtwarzającą
# ruch i strzały. Trafienie wykrywa strzelec (swoja balistyka), skutki liczy ofiara (narządy,
# krwawienie, kamizelka) i rozsyła upadek.

const NET_RATE := 1.0 / 30.0

static var net_on := false
var net_id := 0
var is_remote := false
var deaths := 0               # ile razy zginąłem = punkty przeciwnika
var _net_t := 0.0
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO


func _gd() -> Node:
	return get_node("/root/GDSync")


func _net_send(dt: float) -> void:
	_net_t -= dt
	if _net_t > 0.0:
		return
	_net_t = NET_RATE
	_gd().call_func_unreliable(net_state, global_position, velocity, visual.rotation.y, rig.aim_dir, rig.aim_w,
		rig.crouch, rig.sprint, rig.air, gun_i, rig.reload_p, rig.reload_kind)


func _eject_from(g: Node3D) -> Node3D:
	return _vm if (_vm and _vm.visible and not is_remote) else g


func _on_fired(origin: Vector3, dir: Vector3, tracer: bool) -> void:
	if _vm and not is_remote:
		_vm.flash()
		_vm_kick_v += 1.6 + float(gun.data["recoil"][0]) * 60.0
	if net_on and not is_remote:
		_gd().call_func(net_shot, origin, dir, tracer)


func _collapse(dir: Vector3, at: Vector3, seg: String, energy: float, instant: bool) -> void:
	if down:
		return
	if vehicle:
		var v = vehicle
		leave_vehicle(false)
		v.pilot_gone(self)
	if net_on and not is_remote:
		deaths += 1
		_gd().call_func(net_down, dir, at, seg, energy, instant, deaths)
	super._collapse(dir, at, seg, energy, instant)


## Moja kula trafiła kukiełkę przeciwnika: krew u mnie, obrażenia liczy jego komputer.
func _net_forward_hit(h: Dictionary) -> void:
	if down:
		return
	var sh = h.get("shooter")
	if sh == null or not is_instance_valid(sh) or sh.get("is_remote") != false:
		return
	var d := h.duplicate()
	d.erase("shooter")
	d["_net"] = true
	_gd().call_func(net_hit, d)
	var dir: Vector3 = h["dir"]
	if h.get("armor", "") == "":
		FX.I.blood_spray(h["entry"], -dir, 0.5)
		if not h.get("stopped", false):
			FX.I.blood_spray(h["exit"], dir, 0.8)
		FX.I.play("hit", h["entry"], -4.0, 0.15)
	rig.hit_react(visual.global_basis.inverse() * dir, h["seg"], 0.8)
	last_hit_time = Time.get_ticks_msec() / 1000.0
	if h.get("armor", "") == "":
		last_hit_seg = h["seg"]
	sh.on_hit_confirmed(self, hit_info(h))


# --- wywoływane zdalnie

## (kukiełka) stan przeciwnika ~30 razy na sekundę.
func net_state(p: Vector3, v: Vector3, vyaw: float, aim: Vector3, aim_w: float, crouch: float, sprint: bool,
		air: bool, gi: int, reload_p: float, reload_kind: String) -> void:
	if not is_remote or down:
		return
	_net_pos = p
	_net_vel = v
	_yaw = vyaw
	if gi != gun_i and gi >= 0 and gi < guns.size():
		_equip_i(gi, true)
	rig.aim_dir = aim
	rig.aim_w = aim_w
	rig.crouch = crouch
	rig.sprint = sprint
	rig.air = air
	rig.reload_kind = reload_kind
	rig.reload_p = reload_p


## (kukiełka) przeciwnik strzelił: ten sam pocisk leci u mnie (trzask, rykoszety, smugi).
func net_shot(origin: Vector3, dir: Vector3, tracer: bool) -> void:
	if not is_remote or down or gun == null:
		return
	Ballistics.I.fire(self, gun, origin, dir, tracer)
	gun.flash()
	_shot_fx(gun, origin, dir)
	FX.I.play(gun.data["sound"], origin, 4.0, 0.06, 1.0, 40.0)
	rig.kick(1.0)
	for s in get_tree().get_nodes_in_group("soldier"):
		if s != self and s.has_method("heard_shot"):
			s.heard_shot(global_position, self)


## (kukiełka) przeciwnik padł: ragdoll, punkt dla mnie.
func net_down(dir: Vector3, at: Vector3, seg: String, energy: float, instant: bool, d: int) -> void:
	if not is_remote:
		return
	deaths = d
	if down:
		return
	global_position = _net_pos
	_collapse(dir, at, seg, energy, instant)
	for p in get_tree().get_nodes_in_group("player"):
		if not p.down and not String(p.name).begins_with("Dead"):
			p.on_kill(self)


## (mój żołnierz) kula przeciwnika trafiła mnie u niego — liczę skutki.
func net_hit(h: Dictionary) -> void:
	if is_remote or down:
		return
	h["shooter"] = get_parent().get_node_or_null("P%d" % _gd().get_sender_id())
	bullet_hit(h)


func _net_follow(dt: float) -> void:
	if down or vehicle:
		return
	var target := _net_pos + _net_vel * 0.05
	if global_position.distance_to(target) > 4.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-14.0 * dt))
	velocity = _net_vel
	visual.rotation.y = lerp_angle(visual.rotation.y, _yaw, 1.0 - exp(-16.0 * dt))
	rig.vel = visual.global_basis.inverse() * velocity
	yaw = _yaw


# ---------------------------------------------------------------- samoloty

func _board_plane() -> bool:
	for pl in get_tree().get_nodes_in_group("plane"):
		if pl.can_board(self):
			pl.board(self)
			return true
	return false


## Siadam w kabinie: ciało przestaje kolidować, broń chowam, obraz daje kamera samolotu.
func enter_vehicle(v) -> void:
	vehicle = v
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_move = Vector3.ZERO
	_trigger = false
	reloading = -1.0
	rig.reload_p = -1.0
	bandaging = -1.0
	if gun:
		gun.visible = false


## Wysiadam (place: staję obok kabiny) albo wypadam z kabiny (śmierć, wybuch).
func leave_vehicle(place: bool) -> void:
	var v = vehicle
	vehicle = null
	if is_remote:
		collision_layer = 4
		collision_mask = 0
	else:
		collision_layer = 2
		collision_mask = 1 | 4 | 32
	if gun:
		gun.visible = true
	var f: Vector3 = -v.global_basis.z
	var y := atan2(-f.x, -f.z)
	if place:
		global_position = v.exit_point()
		_net_pos = global_position
	velocity = Vector3.ZERO
	_move = Vector3.ZERO
	visual.rotation = Vector3(0, y, 0)
	yaw = y
	_yaw = y
	if not is_remote and _cam:
		_pitch = -0.05
		_cam_yaw.global_position = global_position + Vector3(0, 1.6, 0)
		_cam.current = true


## Zginąłem w rozbitym samolocie.
func vehicle_death() -> void:
	vitals.cause = "katastrofa lotnicza"
	vitals._die()
	_note("katastrofa lotnicza", [])
	_collapse(Vector3.UP, chest_pos(), "torso", 4000.0, true)
