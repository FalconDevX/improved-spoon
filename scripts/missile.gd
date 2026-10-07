extends "res://scripts/rocket.gd"
## Rakieta przeciwlotnicza (Piorun, wyrzutnie OPL): silnik startowy wyrzuca ją z tuby, po 0,25 s zapala
## się marszowy i rozpędza ją do ~300 m/s (wolniej niż prawdziwa — widać, jak goni cel). Głowica
## podczerwieni widzi cel w stożku ±60° przed sobą i prowadzi rakietę z umiarkowanym wyprzedzeniem;
## skręt ograniczony przeciążeniem, więc przy prędkości rakieta zakręca szerokim łukiem, a gdy cel
## ucieknie ze stożka — leci w ostatnio widziany punkt i próbuje go odzyskać. Za silnikiem gęsta,
## ciemna smuga dymu, która zostaje w powietrzu. Zapalnik zbliżeniowy odpala ją kilka metrów od celu.
## Flary wyrzucone na czas ściągają ją na siebie. Obrażenia celu liczy komputer strzelającego.

const M_ACCEL := 90.0
const M_VMAX := 300.0
const M_BURN := 6.5
const M_LIFE := 16.0
const IGNITE := 0.25
const G_MAX := 110.0         # maks. przyspieszenie poprzeczne [m/s²] (~11 g) — przy prędkości szerokie łuki
const TURN_MAX := 1.6        # i tak nie szybciej niż tyle [rad/s] (zaraz po starcie, gdy jest wolna)
const SEEKER := 1.05         # stożek głowicy (±60°)
const NAV := 4.0             # stała nawigacji proporcjonalnej
const FUZE := 9.0            # zapalnik zbliżeniowy [m]
const DAMAGE := 230.0        # przy samym celu (samolot ma 160 HP, śmigłowiec 170) — w zasięgu zapalnika zwykle zestrzela

var target: Node3D = null    # samolot / śmigłowiec albo flara, która go odciągnęła
var decoyed := false
var _last_seen := Vector3.INF   # gdzie głowica ostatnio widziała cel
var _los_prev := Vector3.ZERO   # kierunek do celu w poprzedniej klatce (nawigacja proporcjonalna)
var _trail: GPUParticles3D


func _ready() -> void:
	super._ready()
	add_to_group("missile")
	kill_r = 2.0
	stun_r = 6.0
	plane_r = 0.0            # obrażenia samolotu liczone osobno (zapalnik zbliżeniowy)
	frags = 20
	blast = 0.9
	scale = Vector3.ONE * 1.3
	_trail = _make_trail()


## Za ile sekund rakieta dogoni cel (kokpit: ostrzeżenie, flary: czy jeszcze zdążą).
func time_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	var to := target.global_position - global_position
	var d := to.length()
	var tv: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
	var closing := (vel - tv).dot(to / maxf(d, 0.01))
	return d / maxf(closing, 60.0)


func _physics_process(dt: float) -> void:
	_t += dt
	if target != null and (not is_instance_valid(target) or target.get("destroyed") == true):
		target = null
	var p0 := global_position
	var spd := vel.length()
	var burning := _t > IGNITE and _t < M_BURN
	_flame.visible = burning
	if burning:
		spd = minf(spd + M_ACCEL * dt, M_VMAX)
	elif _t >= M_BURN:
		spd = maxf(spd - spd * 0.1 * dt, 70.0)
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
		var los := (tp - p0) / maxf(d, 0.01)
		if dir.angle_to(los) < SEEKER:
			# głowica widzi cel: nawigacja proporcjonalna — skręt NAV razy szybszy niż obrót linii
			# widzenia celu (płynne wyjście na punkt spotkania) + lekkie dociąganie do celu
			_last_seen = tp
			var rot := dir.cross(los) * 0.6
			if _los_prev != Vector3.ZERO:
				rot += _los_prev.cross(los) / maxf(dt, 0.0001) * NAV
			_los_prev = los
			var mag := rot.length()
			if mag > 0.0001:
				dir = dir.rotated(rot / mag, minf(mag, minf(G_MAX / maxf(spd, 1.0), TURN_MAX)) * dt).normalized()
		else:
			# cel poza stożkiem: leci w ostatnio widziany punkt i próbuje go znów złapać
			_los_prev = Vector3.ZERO
			var aimp := _last_seen if _last_seen != Vector3.INF else tp
			if aimp.distance_to(p0) > 2.0:
				dir = _steer(dir, (aimp - p0).normalized(), spd, dt)
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
	if _trail:
		_trail.emitting = _t > IGNITE * 0.5 and _t < M_BURN + 1.5


## Skręt ku punktowi: szybkość obrotu ograniczona przeciążeniem (G_MAX / prędkość) i TURN_MAX.
## Gdy punkt jest prawie dokładnie za rakietą, zawraca stałym łukiem w poziomie (bez pętli).
func _steer(dir: Vector3, want: Vector3, spd: float, dt: float) -> Vector3:
	var ang := dir.angle_to(want)
	if ang < 0.0001:
		return dir
	var rate := minf(G_MAX / maxf(spd, 1.0), TURN_MAX)
	var axis := dir.cross(want)
	if axis.length() < 0.05 or ang > 2.8:
		var flat := dir.cross(Vector3.UP)
		if flat.length() < 0.05:
			flat = Vector3.RIGHT
		axis = -flat if flat.dot(axis) < 0.0 else flat
	return dir.rotated(axis.normalized(), minf(ang, rate * dt)).normalized()


## Gęsta smuga ciemnego dymu za silnikiem (cząsteczki w świecie: zostaje i powoli się rozwiewa).
func _make_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 900
	p.lifetime = 7.0
	p.local_coords = false
	p.emitting = false
	p.position = Vector3(0, 0, 0.45)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-1500, -300, -1500), Vector3(3000, 900, 3000))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0, 1)
	m.spread = 6.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 2.0
	m.gravity = Vector3(0, 0.3, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 0.8
	m.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.45))
	curve.add_point(Vector2(0.3, 0.9))
	curve.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(0.12, 0.11, 0.1, 0.95), Color(0.2, 0.19, 0.18, 0.85), Color(0.38, 0.37, 0.36, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.6)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = FX._cache["dot"]
	q.material = mm
	p.draw_pass_1 = q
	add_child(p)
	return p


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
	if _trail:
		# smuga zostaje w powietrzu i rozwiewa się po wybuchu
		var tr := _trail
		_trail = null
		var xf := tr.global_transform
		remove_child(tr)
		get_parent().add_child(tr)
		tr.global_transform = xf
		tr.emitting = false
		get_tree().create_timer(tr.lifetime + 0.5).timeout.connect(tr.queue_free)
	_explode(pos)
