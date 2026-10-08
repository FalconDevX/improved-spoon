extends "res://scripts/soldier.gd"
## Mieszkaniec wioski (village.gd): bez broni, kolorowe ubranie. Spaceruje skrajem ulic po sieci
## węzłów wioski albo pracuje w jednym miejscu przy sklepie (schyla się, rozgląda). Strzał w pobliżu,
## świst kuli albo trafienie -> ucieka biegiem od zagrożenia, potem się uspokaja. Boty go nie
## atakują (grupa „civilian”), ale kule ranią go jak każdego.

const WALK := 1.35
const RUN := 4.8
const SHIRTS := [Color(0.85, 0.2, 0.15), Color(0.95, 0.85, 0.3), Color(0.2, 0.45, 0.8), Color(0.95, 0.95, 0.92),
	Color(0.3, 0.65, 0.35), Color(0.75, 0.45, 0.75), Color(0.95, 0.55, 0.2), Color(0.55, 0.75, 0.9)]

## Statystyka (HUD): ilu cywilów zginęło od startu mapy i ostatnie zgony {text, at}.
static var deaths := 0
static var feed: Array = []
const FEED_TIME := 8.0

var village
var from := 0
var to := 0
var worker := false
var work_dir := Vector3.FORWARD
var _side := 1.0             # po której stronie ulicy chodzi
var _fear := 0.0             # > 0: ucieka
var _threat := Vector3.ZERO
var _pause := 0.0
var _work_t := 0.0
var _gone_t := 0.0


# poziom szczegółu (dużo cywilów): dalecy myślą i idą co kilka klatek, animacja rzadziej
var _lod_i := randi() % 16
var _lod_t := 0.0
var _every := 1
var _acc := 0.0
var _anim_i := randi() % 16
var _anim_acc := 0.0


func _ready() -> void:
	team = 3
	add_to_group("civilian")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	helmet = false
	vest = false
	var look := soldier_look()
	look["shirt"] = SHIRTS[randi() % SHIRTS.size()]
	look["pants"] = Color(0.2, 0.2, 0.25) if randf() < 0.6 else Color(0.85, 0.82, 0.75)   # spodnie albo mundu
	look["skin"] = Color(0.55, 0.38, 0.27).lerp(Color(0.72, 0.52, 0.38), randf())
	look["gloves"] = false
	look["strap"] = false
	look["garment"] = "shirt"
	look["beard_style"] = "mustache" if randf() < 0.5 else "none"
	build_soldier(look["shirt"], look)
	_side = 1.0 if randf() < 0.5 else -1.0
	rig.aim_w = 0.0
	rig.aim_dir = Vector3.FORWARD
	yaw = randf() * TAU
	if worker:
		yaw = atan2(-work_dir.x, -work_dir.z)
	visual.rotation.y = yaw


func _physics_process(dt: float) -> void:
	# dalecy: cała logika i ruch co _every klatek, z zebranym czasem (każde przesunięcie postaci
	# przesuwa też jej strefy trafień w silniku fizyki — przy setkach cywilów to główny koszt)
	_lod_i += 1
	_lod_t -= dt
	if _lod_t <= 0.0:
		_lod_t = randf_range(0.3, 0.6)
		var cam := get_viewport().get_camera_3d()
		var d := cam.global_position.distance_to(global_position) if cam else 0.0
		_every = 1 if (d < 40.0 or down) else (4 if d < 90.0 else (8 if d < 250.0 else 16))
	_acc += dt
	if _every > 1 and _lod_i % _every != 0:
		return
	dt = _acc
	_acc = 0.0
	_tick_vitals(dt)
	if down:
		_gone_t += dt
		if _gone_t > 90.0:
			queue_free()
		return
	_fear = maxf(_fear - dt, 0.0)
	var want := Vector3.ZERO
	var spd := WALK
	rig.sprint = false
	if _fear > 0.0:
		# ucieczka: od zagrożenia, wzdłuż ulic (węzeł dalej od strzałów)
		spd = RUN
		rig.sprint = true
		rig.crouch = 0.0
		want = _goal_dir()
		if worker:
			var away := global_position - _threat
			away.y = 0.0
			want = away.normalized()
	elif worker:
		# praca: schyla się co jakiś czas, rozgląda
		_work_t -= dt
		if _work_t <= 0.0:
			_work_t = randf_range(2.0, 5.0)
			rig.crouch = 1.0 if rig.crouch < 0.5 and randf() < 0.6 else 0.0
			yaw = atan2(-work_dir.x, -work_dir.z) + randf_range(-0.6, 0.6)
	else:
		_pause -= dt
		if _pause <= 0.0:
			want = _goal_dir()
			if randf() < dt * 0.02:
				_pause = randf_range(2.0, 6.0)   # przystanek: rozmowa, wystawa sklepu
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(want * spd, 6.0 * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * dt
	if _every > 1 and is_on_floor():
		global_position += hv * dt      # dalej: krok o cały zebrany czas, ulicą, bez liczenia kolizji
	else:
		move_and_slide()
	if hv.length() > 0.3:
		yaw = atan2(-hv.x, -hv.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-6.0 * dt))
	rig.vel = visual.global_basis.inverse() * velocity
	rig.air = not is_on_floor()


## Kierunek do celu na skraju ulicy; po dojściu następny węzeł (w ucieczce: dalej od zagrożenia).
func _goal_dir() -> Vector3:
	if village == null:
		return Vector3.ZERO
	var a: Vector3 = village.nodes[from]
	var b: Vector3 = village.nodes[to]
	var d := (b - a).normalized()
	var side := Vector3(d.z, 0, -d.x) * 4.5 * _side
	var goal := b + side - d * 4.5
	var to_goal := goal - global_position
	to_goal.y = 0.0
	if to_goal.length() < 1.5:
		var n: int = village.next_node(from, to)
		if _fear > 0.0:
			var best := -1.0
			for c: int in village.links[to]:
				var dd: float = (village.nodes[c] as Vector3).distance_to(_threat)
				if dd > best:
					best = dd
					n = c
		from = to
		to = n
	return to_goal.normalized()


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var k := 1
	if cam:
		var d := cam.global_position.distance_to(global_position)
		k = 1 if d < 25.0 else (2 if d < 60.0 else (4 if d < 120.0 else (8 if d < 300.0 else 16)))
		if not cam.is_position_in_frustum(global_position + Vector3.UP):
			k = maxi(k, 15)
	_anim_acc += dt
	_anim_i += 1
	if k > 1 and _anim_i % k != 0 and not down:
		return
	dt = minf(_anim_acc, 0.5)
	_anim_acc = 0.0
	_animate(dt, false)


func _scare(at: Vector3, t: float) -> void:
	if down:
		return
	if _fear <= 0.0 and randf() < 0.5:
		FX.I.play("groan", chest_pos(), -10.0, 0.2, 1.3)
	_threat = at
	_fear = maxf(_fear, t)
	_pause = 0.0


func heard_shot(pos: Vector3, _shooter) -> void:
	if global_position.distance_to(pos) < 80.0:
		_scare(pos, randf_range(8.0, 14.0))


func near_miss(pos: Vector3, _dist: float, _speed: float, _shooter) -> void:
	_scare(pos, 15.0)


func _on_hit(h: Dictionary, _res: Dictionary) -> void:
	var sh = h.get("shooter")
	_scare(sh.global_position if sh != null and is_instance_valid(sh) else global_position, 20.0)


func _collapse(dir: Vector3, at: Vector3, seg: String, energy: float, instant: bool) -> void:
	if down:
		return
	var sh = last_shooter
	var mine: bool = sh != null and is_instance_valid(sh) and sh.is_in_group("player") and sh.get("is_remote") != true
	super._collapse(dir, at, seg, energy, instant)
	deaths += 1
	feed.push_front({"text": "Cywil zginął" + ("  (ty)" if mine else ""), "at": Time.get_ticks_msec() / 1000.0})
	if feed.size() > 400:
		feed.resize(400)
