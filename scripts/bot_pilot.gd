extends RefCounted
## Pilot-bot samolotu albo śmigłowca (liczony u hosta / w solo). Ustawia maszynie to, co gracz
## daje klawiszami i myszą: gaz / kolektyw, kierunek (aim), spust, rakiety, bomby, flary.
## Samolot: start z pasa, wznoszenie, nalot na najbliższego gracza z wyprzedzeniem, ogień
## z karabinów z bliska, bomby gdy cel jest pod celownikiem bombowym, wyrwanie w górę po przelocie.
## Śmigłowiec: start pionowy, zawis w odległości 150–250 m od celu na bezpiecznej wysokości,
## ogień z wieżyczki i salwy rakiet. Obaj wyrzucają flary, gdy leci na nich rakieta (z opóźnieniem).

var craft = null
var heli := false
var target: Node3D = null
var throttle := 1.0          # samolot: gaz
var fwd := 0.0               # śmigłowiec: pochylenie / w bok / kolektyw
var side := 0.0
var up := 0.0
var _retarget := 0.0
var _extend := 0.0           # samolot: odejście po nalocie
var _extending := false
var _flare_react := -1.0
var _orbit := 1.0
var _burst := 0.0
var _rocket_t := 0.0
var dbg := ""
var _bail := 1.0
const SAFE_ALT := 70.0       # samolot nie schodzi niżej poza nalotem
const MIN_ALT := 30.0
const HELI_ALT := 45.0
const CENTER := Vector2(250, 0)      # środek doliny (terrain.gd)
const RANGE := Vector2(600, 160)     # samolot zawraca przed zboczami gór
const Terrain = preload("res://scripts/terrain.gd")


func _init(c) -> void:
	craft = c
	heli = c.get("is_heli") == true
	_orbit = 1.0 if randf() < 0.5 else -1.0


func tick(dt: float) -> void:
	# maszyna płonie: po chwili namysłu bot się katapultuje (jeśli jest dość wysoko)
	if craft.hp <= 0.0:
		_bail -= dt
		if _bail <= 0.0 and craft.global_position.y - craft.GEAR_H > 20.0:
			craft.eject()
		return
	_bail = randf_range(0.5, 2.0)
	_retarget -= dt
	if _retarget <= 0.0 or target == null or not is_instance_valid(target) or target.down:
		_retarget = 3.0
		_pick_target()
	_flares(dt)
	if heli:
		_heli(dt)
	else:
		_plane(dt)


func _pick_target() -> void:
	target = null
	var best := 2500.0
	for n in craft.get_tree().get_nodes_in_group("player") + craft.get_tree().get_nodes_in_group("net_player"):
		if not is_instance_valid(n) or n.down or String(n.name).begins_with("Dead"):
			continue
		var d: float = n.global_position.distance_to(craft.global_position)
		if d < best:
			best = d
			target = n


## Rakieta na mnie: flary po krótkiej reakcji (czasem za późno — można je zestrzelić).
func _flares(dt: float) -> void:
	if craft._missile_near():
		if _flare_react < 0.0:
			_flare_react = randf_range(0.3, 1.6)
		_flare_react -= dt
		if _flare_react <= 0.0 and craft.flares > 0:
			craft.release_flares()
			_flare_react = 2.0
	else:
		_flare_react = -1.0


func _set_aim(dir: Vector3) -> void:
	dir = dir.normalized()
	craft._aim_yaw = atan2(-dir.x, -dir.z)
	craft._aim_pitch = asin(clampf(dir.y, -1.0, 1.0))


func _target_pos() -> Vector3:
	if target == null:
		return Vector3.ZERO
	return target.global_position + Vector3(0, 1.0, 0)


func _lead(v0: float) -> Vector3:
	var tp := _target_pos()
	var tv: Vector3 = target.velocity if target.get("velocity") != null else Vector3.ZERO
	var rel: Vector3 = tv - craft.velocity * (0.0 if heli else 1.0)
	var tof := tp.distance_to(craft.global_position) / v0
	return tp + rel * tof + Vector3.UP * 0.5 * 9.81 * tof * tof


# ---------------------------------------------------------------- samolot

func _plane(dt: float) -> void:
	var p: Vector3 = craft.global_position
	var alt: float = p.y - craft.GEAR_H
	var v: float = craft.velocity.length()
	var nose: Vector3 = -craft.global_basis.z
	throttle = 1.0
	craft.trigger = false
	craft.ai_aim = Vector3.INF
	if craft.on_ground:
		# rozbieg: prosto, przy ~110 km/h nos lekko w górę
		var flat := Vector3(nose.x, 0, nose.z).normalized()
		_set_aim(flat + Vector3.UP * (0.3 if v > 31.0 else 0.0))
		return
	# teren przed nosem (góry wokół doliny): za mało miejsca — w górę i do środka doliny
	var rel := Vector2(p.x - CENTER.x, p.z - CENTER.y)
	var ahead: Vector3 = p + craft.velocity * 4.0
	var ground_ahead := maxf(Terrain.height(ahead.x, ahead.z), Terrain.height(p.x + craft.velocity.x * 2.0, p.z + craft.velocity.z * 2.0))
	var clear: float = ahead.y - ground_ahead
	if ground_ahead > 15.0 and clear < 60.0:
		dbg = "TEREN clear=%d" % clear
		_set_aim(Vector3(-rel.x, 0, -rel.y).normalized() * 0.6 + Vector3.UP * (1.0 if clear < 35.0 else 0.6))
		_extend = maxf(_extend, 1.0)
		return
	# granica obszaru: zawróć do środka
	if (rel / RANGE).length() > 1.0:
		dbg = "GRANICA rel=%s" % rel
		_set_aim(Vector3(-rel.x, 0, -rel.y).normalized() + Vector3.UP * clampf((150.0 - alt) / 120.0, -0.35, 0.35))
		return
	if alt < 160.0 and craft.velocity.y < -25.0:
		_set_aim(Vector3(nose.x, 0.8, nose.z))
		return
	if target == null:
		# patrol: krąg nad mapą na bezpiecznej wysokości
		var tang := Vector3(-rel.y, 0, rel.x).normalized() * _orbit
		_set_aim(tang + Vector3.UP * clampf((180.0 - alt) / 150.0, -0.3, 0.4))
		return
	var tp := _target_pos()
	var to := tp - p
	var dist := to.length()
	_extend -= dt
	if _extend > 0.0:
		# odejście po nalocie: prosto przed siebie na ~150 m, potem zawrót na cel
		dbg = "ODEJSCIE %.1f s" % _extend
		_set_aim(Vector3(nose.x, 0, nose.z).normalized() + Vector3.UP * clampf((150.0 - alt) / 120.0, -0.35, 0.35))
		return
	var aim := _lead(870.0)
	var dir := (aim - p).normalized()
	# nurkowanie najwyżej ~37°, a gdy za 3 s byłby za nisko — wyrwanie i odejście
	dir = Vector3(dir.x, maxf(dir.y, -0.6), dir.z).normalized()
	if alt + craft.velocity.y * 1.5 < 35.0 or alt < 20.0:
		_set_aim(Vector3(nose.x, 0.0, nose.z).normalized() + Vector3.UP * 0.7)
		_extend = 3.0
		return
	if alt < SAFE_ALT and dir.y < -0.2 and dist > 500.0:
		dir = Vector3(dir.x, maxf(dir.y, 0.25), dir.z).normalized()
	_set_aim(dir)
	var ang := nose.angle_to(aim - p)
	dbg = "ATAK dist=%d ang=%.2f" % [dist, ang]
	craft.ai_aim = aim
	if dist < 750.0 and ang < 0.33 and alt > 10.0:
		craft.trigger = true
	# bomby: cel pod przewidywanym punktem upadku
	if craft.bombs > 0 and alt > 60.0:
		var bi: Vector3 = craft.bomb_impact()
		if Vector2(bi.x - tp.x, bi.z - tp.z).length() < 12.0:
			craft.start_salvo()
	if dist < 160.0:
		_extend = randf_range(3.5, 5.0)


# ---------------------------------------------------------------- śmigłowiec

func _heli(dt: float) -> void:
	var p: Vector3 = craft.global_position
	var alt: float = p.y - craft.GEAR_H
	craft.trigger = false
	craft.rocket_trigger = false
	_rocket_t -= dt
	if craft.rpm < 0.95:
		fwd = 0.0
		side = 0.0
		up = 0.0
		return
	var want := Vector3(p.x, HELI_ALT, p.z)
	var look: Vector3 = -craft.global_basis.z
	var dist := INF
	if target != null:
		var tp := _target_pos()
		var flat := Vector3(p.x - tp.x, 0, p.z - tp.z)
		dist = Vector2(flat.x, flat.z).length()
		var r := clampf(dist, 160.0, 260.0)
		# krąży wokół celu w zadanej odległości
		var a := atan2(flat.z, flat.x) + _orbit * 0.25
		want = tp + Vector3(cos(a), 0, sin(a)) * r
		want.y = tp.y + HELI_ALT
		look = _lead(870.0) - craft._turret.global_position
	elif Vector2(p.x, p.z).length() > 200.0:
		want = Vector3(0, HELI_ALT + 20.0, 0)
	_set_aim(look)
	# sterowanie: prędkość w układzie śmigłowca ku zadanemu punktowi
	var to := want - p
	var dv := Vector3(to.x, 0, to.z).limit_length(40.0) * 0.5 - Vector3(craft.velocity.x, 0, craft.velocity.z)
	var local: Vector3 = craft.global_basis.inverse() * dv
	fwd = clampf(-local.z * 0.15, -1.0, 1.0)
	side = clampf(local.x * 0.15, -1.0, 1.0)
	up = clampf((want.y - p.y) * 0.15, -1.0, 1.0)
	if alt < 18.0:
		up = 1.0
	if target == null or dist > 650.0:
		return
	# ogień: wieżyczka (szeroki zakres), rakiety gdy nos patrzy na cel
	var space: PhysicsDirectSpaceState3D = craft.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(craft._turret.global_position, _target_pos(), 1)
	if not space.intersect_ray(q).is_empty():
		return
	_burst -= dt
	if _burst < -1.2:
		_burst = randf_range(0.8, 1.8)
	craft.trigger = _burst > 0.0
	var nose: Vector3 = -craft.global_basis.z
	if craft.rockets > 0 and nose.angle_to(_target_pos() - p) < 0.22 and _rocket_t <= 0.0 and dist < 420.0:
		craft.rocket_trigger = true
		if craft.rockets <= 9 and randf() < 0.3:
			_rocket_t = randf_range(4.0, 8.0)
