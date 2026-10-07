extends "res://scripts/rocket.gd"
## Rakieta przeciwlotnicza Piorun: silnik startowy wyrzuca ją z tuby (~28 m/s), po 0,25 s zapala się
## marszowy i rozpędza do ~600 m/s. Głowica podczerwieni prowadzi ją na cel z wyprzedzeniem
## (ograniczona prędkość skrętu), zapalnik zbliżeniowy odpala ją kilka metrów od samolotu.
## Flary wyrzucone na czas (zanim rakieta jest tuż-tuż) ściągają ją na siebie.
## Obrażenia celu liczy komputer strzelającego (jak kule), wybuch i odłamki — każdy dla swoich.

const M_ACCEL := 260.0
const M_VMAX := 600.0
const M_BURN := 3.2
const M_LIFE := 10.0
const IGNITE := 0.25
const TURN := 2.4            # maks. prędkość skrętu [rad/s]
const FUZE := 7.0            # zapalnik zbliżeniowy [m]
const DAMAGE := 230.0        # przy samym celu (samolot ma 160 HP, śmigłowiec 170) — w zasięgu zapalnika zwykle zestrzela

var target: Node3D = null    # samolot / śmigłowiec albo flara, która go odciągnęła
var decoyed := false


func _ready() -> void:
	super._ready()
	add_to_group("missile")
	kill_r = 2.0
	stun_r = 6.0
	plane_r = 0.0            # obrażenia samolotu liczone osobno (zapalnik zbliżeniowy)
	frags = 20
	blast = 0.9
	scale = Vector3.ONE * 1.3


## Za ile sekund rakieta dogoni cel (kokpit: ostrzeżenie, flary: czy jeszcze zdążą).
func time_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	var d := global_position.distance_to(target.global_position)
	var tv: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
	var closing := vel.dot((target.global_position - global_position) / maxf(d, 0.01)) - tv.dot((target.global_position - global_position) / maxf(d, 0.01))
	return d / maxf(closing, 60.0)


func _physics_process(dt: float) -> void:
	_t += dt
	if target != null and (not is_instance_valid(target) or target.get("destroyed") == true):
		target = null
	var p0 := global_position
	var spd := vel.length()
	if _t > IGNITE and _t < M_BURN:
		_flame.visible = true
		spd = minf(spd + M_ACCEL * dt, M_VMAX)
	elif _t >= M_BURN:
		_flame.visible = false
		spd = maxf(spd - spd * 0.12 * dt, 80.0)
	else:
		_flame.visible = false
	var dir := vel.normalized()
	if target != null and _t > IGNITE:
		var tp := target.global_position
		var d := tp.distance_to(p0)
		if not target.is_in_group("flare"):
			target.set("missile_warn", time_to_target())
		# zapalnik zbliżeniowy
		if d < (FUZE if not target.is_in_group("flare") else 3.0):
			_detonate(p0)
			return
		var tv: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
		var lead := tp + tv * clampf(d / maxf(spd, 100.0), 0.0, 3.0) * 0.9
		var want := (lead - p0).normalized()
		var ang := dir.angle_to(want)
		if ang > 0.0001:
			dir = dir.slerp(want, minf(1.0, TURN * dt / ang)).normalized()
	elif _t >= IGNITE:
		dir = (dir * spd + Vector3(0, -GRAVITY, 0) * dt * 0.3).normalized()
	else:
		dir = (dir * spd + Vector3(0, -GRAVITY, 0) * dt).normalized()
	vel = dir * spd
	var p1 := p0 + vel * dt
	var excl: Array[RID] = []
	if shooter != null and is_instance_valid(shooter) and _t < 0.6:
		excl.append(shooter.get_rid())
		if shooter.has_method("hit_rids"):
			excl.append_array(shooter.hit_rids())
	var q := PhysicsRayQueryParameters3D.create(p0, p1, 1 | 2 | 4 | 32, excl)
	q.hit_from_inside = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		_detonate((r["position"] as Vector3) - dir * 0.2)
		return
	if _t > M_LIFE or p1.y < -5.0:
		_detonate(p1)
		return
	global_position = p1
	global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	_smoke_t -= dt
	if _smoke_t <= 0.0 and _t > IGNITE and _t < M_BURN + 0.5:
		_smoke_t = 0.03
		FX.I.muzzle_smoke(p1 - dir * 0.5, -dir * 0.2, 0.6)


## Wybuch: samolot / śmigłowiec w zasięgu zapalnika dostaje obrażenia (liczy komputer strzelca).
func _detonate(pos: Vector3) -> void:
	var sh = shooter if (shooter != null and is_instance_valid(shooter)) else null
	var mine: bool = not Player.net_on or (sh != null and sh.get("is_remote") == false)
	if mine:
		for a in get_tree().get_nodes_in_group("aircraft"):
			if a.destroyed:
				continue
			var d: float = a.global_position.distance_to(pos)
			if d < FUZE + 3.0:
				var was: float = a.hp
				a._damage(DAMAGE * clampf(1.0 - d / (FUZE + 3.0) * 0.35, 0.5, 1.0))
				if sh != null and sh.has_method("confirm_hit") and sh != a.pilot:
					sh.confirm_hit(a, was > 0.0 and a.hp <= 0.0)
	_explode(pos)
