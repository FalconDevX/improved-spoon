extends Node3D
## Balistyka: każdy pocisk to punkt z prędkością, grawitacją i oporem powietrza (dv/dt = -k·v²).
## Co krok fizyki promień od starej do nowej pozycji. Trafienie w człowieka liczone analitycznie
## przez wszystkie kapsuły ciała na torze (ręka -> tułów), z narządami, kamizelką/hełmem
## i wylotem. Przeszkody: przebicie zależne od materiału i grubości, rykoszet przy małym kącie.

const Weapons = preload("res://scripts/weapons.gd")
const FX = preload("res://scripts/fx.gd")

const HURT_MASK := 8
const WORLD_MASK := 1
const MAX_LIFE := 4.0
const MIN_SPEED := 90.0
const GRAVITY := Vector3(0, -9.81, 0)
# prędkość, przy której zmierzono penetrację w tkance ("pen" w Weapons.CAL)
const V_REF := {"9x19": 380.0, "5.56x45": 910.0, "7.62x39": 715.0, "7.62x51": 790.0, "12ga": 400.0, "5.45x39": 900.0, "357": 440.0, "50ae": 470.0, "338lm": 900.0}
# materiał: twardość (ile metrów tkanki "zużywa" 1 m materiału), maks. kąt rykoszetu [stopnie]
const MATS := {
	"concrete": {"tough": 14.0, "ric": 14.0, "fx": "dust"},
	"brick": {"tough": 11.0, "ric": 12.0, "fx": "dust"},
	"wood": {"tough": 2.2, "ric": 4.0, "fx": "wood"},
	"metal": {"tough": 45.0, "ric": 22.0, "fx": "spark"},
	"sand": {"tough": 9.0, "ric": 0.0, "fx": "sand"},
	"dirt": {"tough": 9.0, "ric": 7.0, "fx": "sand"},
}

static var I = null

var bullets: Array = []
var _im: ImmediateMesh
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	I = self


func _exit_tree() -> void:
	if I == self:
		I = null


func _ready() -> void:
	_rng.randomize()
	_im = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 1.0, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 200, 1000))
	add_child(mi)


## Strzał z broni. dir: kierunek linii celowania (już z rozrzutem strzelca). Zwraca liczbę pocisków.
func fire(shooter: Node, gun, origin: Vector3, dir: Vector3, tracer := false) -> void:
	var cal: Dictionary = gun.cal
	var n := int(cal.get("pellets", 1))
	var v0 := float(gun.data["v0"]) * _rng.randf_range(0.985, 1.015)
	# przystrzelanie: lufa lekko w górę, tak by pocisk przeciął linię celownika na odległości zera
	var zero := float(gun.data["zero"])
	var drop_t := zero / v0
	var elev := 0.5 * 9.81 * drop_t * drop_t / zero
	var excl: Array = shooter.hit_rids() if shooter and shooter.has_method("hit_rids") else []
	for i in n:
		var d := dir
		if n > 1:
			var s := float(cal["pellet_spread"])
			d = _jitter(d, s)
		d = (d + Vector3.UP * elev).normalized()
		bullets.append({
			"p": origin, "v": d * v0, "cal": gun.data["cal"], "c": cal, "shooter": shooter,
			"excl": excl.duplicate(), "t": 0.0, "tracer": tracer and i == 0, "depth": 0.0,
			"near": {}, "bounces": 0,
		})


func _jitter(d: Vector3, sigma: float) -> Vector3:
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var x := d.cross(up).normalized()
	var y := x.cross(d).normalized()
	return (d + x * _rng.randfn(0.0, sigma) + y * _rng.randfn(0.0, sigma)).normalized()


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var soldiers := get_tree().get_nodes_in_group("soldier")
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		if not _step(b, delta, space, soldiers):
			bullets.remove_at(i)
	_draw_tracers()


func _speed(b: Dictionary) -> float:
	return (b["v"] as Vector3).length()


## Budżet penetracji w tkance przy obecnej prędkości [m].
func _pen(b: Dictionary) -> float:
	var c: Dictionary = b["c"]
	var vr: float = V_REF[b["cal"]]
	return float(c["pen"]) * pow(clampf(_speed(b) / vr, 0.0, 1.6), 1.5)


func _step(b: Dictionary, dt: float, space: PhysicsDirectSpaceState3D, soldiers: Array) -> bool:
	b["t"] = float(b["t"]) + dt
	if float(b["t"]) > MAX_LIFE or _speed(b) < MIN_SPEED:
		return false
	var v: Vector3 = b["v"]
	var k: float = (b["c"] as Dictionary)["k"]
	v += GRAVITY * dt
	var s := v.length()
	v *= 1.0 / (1.0 + k * s * dt)
	var p0: Vector3 = b["p"]
	var p1 := p0 + v * dt
	b["v"] = v
	b["prev"] = p0
	_near_misses(b, p0, p1, soldiers)
	# kilka przejść w jednym kroku (przebicie, rykoszet)
	var from := p0
	var guard := 0
	while guard < 6:
		guard += 1
		var q := PhysicsRayQueryParameters3D.create(from, p1, WORLD_MASK | HURT_MASK, b["excl"])
		q.collide_with_areas = true
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		var col = r["collider"]
		var hp: Vector3 = r["position"]
		var rest := p1.distance_to(hp)
		var dir := (b["v"] as Vector3).normalized()
		if col is Area3D and (col as Area3D).has_meta("npc"):
			var owner = (col as Area3D).get_meta("npc")
			if not is_instance_valid(owner):
				b["excl"].append((col as Area3D).get_rid())
				from = hp
				continue
			var out = _char_pass(b, owner, hp - dir * 0.02, dir)
			for rid in owner.hit_rids():
				b["excl"].append(rid)
			if out == null:
				b["p"] = hp
				return false
			from = out
			p1 = from + (b["v"] as Vector3).normalized() * rest
			continue
		# przeszkoda
		var res := _obstacle(b, col, hp, r["normal"], dir)
		if res.is_empty():
			b["p"] = hp
			return false
		from = res["from"]
		p1 = from + (b["v"] as Vector3).normalized() * maxf(rest, 0.05)
	b["p"] = p1
	return true


# ---------------------------------------------------------------- ludzie

## Przejście pocisku przez człowieka. Zwraca punkt wylotu (pocisk leci dalej) albo null (utkwił).
func _char_pass(b: Dictionary, owner, from: Vector3, dir: Vector3):
	var body = owner.body
	var hits: Array = []
	for seg: String in body.segs:
		var t: Vector2 = body.ray_segment(seg, from, dir)
		if t.x >= 0.0 and t.y > t.x + 0.005:
			hits.append([seg, t.x, t.y])
	hits.sort_custom(func(x, y): return x[1] < y[1])
	var last := from
	var travelled := 0.0
	for h: Array in hits:
		var seg: String = h[0]
		var t_in: float = maxf(h[1], travelled)
		var t_out: float = h[2]
		if t_out <= t_in + 0.003:
			continue
		travelled = t_out
		var entry := from + dir * t_in
		var c: Dictionary = b["c"]
		var v_in := _speed(b)
		# kamizelka (miękka IIIA) i hełm: zatrzymują pociski pistoletowe i śrut
		var armor: String = owner.armor_at(seg, entry, dir) if owner.has_method("armor_at") else ""
		if armor != "":
			var cls := int(c["armor"])
			if cls <= 2 and v_in < 520.0:
				owner.bullet_hit({"seg": seg, "entry": entry, "exit": entry, "dir": dir, "organs": [], "cavity": 0.0,
					"armor": armor, "stopped": true, "energy": 0.5 * float(c["mass"]) * v_in * v_in, "shooter": b["shooter"], "cal": b["cal"]})
				FX.I.impact(entry, -dir, "spark")
				FX.I.play("impact_metal", entry, -6.0, 0.15)
				return null
			b["v"] = (b["v"] as Vector3) * 0.94
			v_in = _speed(b)
		var pen := _pen(b)
		var cavity := float(c["cavity"])
		if float(c["frag_v"]) > 0.0 and v_in > float(c["frag_v"]):
			pen *= 0.75
			cavity *= 2.3   # 5,56 przy dużej prędkości łamie się w kanale rany -> rozległa rana
		if c.has("yaw_depth"):
			var yd := float(c["yaw_depth"])
			var dd := float(b["depth"])
			cavity *= 1.0 + 1.1 * smoothstep(yd - 0.05, yd + 0.08, dd + (t_out - t_in))
		var length := t_out - t_in
		var used := minf(length, pen)
		var seg_n: Node3D = body.segs[seg]
		var inv := seg_n.global_transform.affine_inverse()
		var organs: Array = body.organs_path(seg, inv * entry, (inv.basis * dir).normalized(), used, cavity)
		var names: Array = []
		for o: Array in organs:
			names.append(o[0])
		var stuck := length >= pen
		var v_out := 0.0 if stuck else v_in * sqrt(maxf(0.0, 1.0 - length / maxf(pen, 0.001)))
		var exit := entry + dir * used
		b["depth"] = float(b["depth"]) + used
		owner.bullet_hit({"seg": seg, "entry": entry, "exit": exit, "dir": dir, "organs": names,
			"cavity": cavity, "armor": "", "stopped": stuck, "shooter": b["shooter"], "cal": b["cal"],
			"energy": 0.5 * float(c["mass"]) * (v_in * v_in - v_out * v_out), "v_out": v_out})
		last = exit
		if stuck:
			return null
		b["v"] = _jitter(dir, 0.03) * v_out   # pocisk po wyjściu z ciała zmienia lekko kierunek
		dir = (b["v"] as Vector3).normalized()
		if v_out < MIN_SPEED:
			return null
	return last + dir * 0.01


## Przelot obok człowieka: trzask przelatującego pocisku, przygniecenie ogniem.
func _near_misses(b: Dictionary, p0: Vector3, p1: Vector3, soldiers: Array) -> void:
	var near: Dictionary = b["near"]
	var seg := p1 - p0
	var l2 := seg.length_squared()
	if l2 < 1e-6:
		return
	for s in soldiers:
		if s == b["shooter"] or near.has(s) or s.is_dead():
			continue
		var h: Vector3 = s.global_position + Vector3(0, 1.4, 0)
		var t := clampf((h - p0).dot(seg) / l2, 0.0, 1.0)
		var d := (p0 + seg * t).distance_to(h)
		if d < 3.0 and t > 0.0 and t < 1.0:
			near[s] = true
			s.near_miss(p0 + seg * t, d, _speed(b), b["shooter"])


# ---------------------------------------------------------------- przeszkody

func _obstacle(b: Dictionary, col: Object, hp: Vector3, nrm: Vector3, dir: Vector3) -> Dictionary:
	var mat := "concrete"
	if col is Node and (col as Node).has_meta("mat"):
		mat = (col as Node).get_meta("mat")
	var m: Dictionary = MATS.get(mat, MATS["concrete"])
	var v := _speed(b)
	var c: Dictionary = b["c"]
	# rykoszet przy płaskim kącie
	var graze := rad_to_deg(asin(clampf(absf(dir.dot(nrm)), 0.0, 1.0)))
	if graze < float(m["ric"]) and int(b["bounces"]) < 2 and _rng.randf() < 0.75:
		var rd := (dir - nrm * 2.0 * dir.dot(nrm)).normalized()
		rd = (rd + nrm * _rng.randf_range(0.02, 0.15)).normalized()
		b["v"] = _jitter(rd, 0.04) * v * _rng.randf_range(0.45, 0.7)
		b["bounces"] = int(b["bounces"]) + 1
		FX.I.impact(hp, nrm, m["fx"], 0.6)
		FX.I.play("ricochet", hp, -4.0, 0.25)
		return {"from": hp + nrm * 0.01}
	# przebicie: grubość z bryły (skrzynie i kontenery są puste w środku — liczą się dwie ścianki)
	var thick := 9.0
	if col is Node and (col as Node).has_meta("hollow"):
		thick = float((col as Node).get_meta("hollow")) * 2.0
	elif col is Node3D and (col as Node).has_meta("size"):
		thick = _box_path(col as Node3D, hp, dir)
	var eq := thick * float(m["tough"])
	var pen := _pen(b)
	FX.I.impact(hp, nrm, m["fx"], 1.0)
	FX.I.bullet_hole(hp, nrm, col as Node3D, mat)
	FX.I.play("impact_" + ("metal" if mat == "metal" else ("wood" if mat == "wood" else "hard")), hp, -8.0, 0.2)
	if eq < pen:
		var vo := v * sqrt(maxf(0.0, 1.0 - eq / pen))
		var exit_d := thick if not (col as Node).has_meta("hollow") else _box_path(col as Node3D, hp, dir)
		var ex := hp + dir * (exit_d + 0.01)
		b["v"] = _jitter(dir, 0.02 + eq / pen * 0.05) * vo
		FX.I.impact(ex, dir, m["fx"], 0.5)
		return {"from": ex}
	return {}


## Długość drogi promienia przez prostopadłościan (meta "size") od punktu wejścia.
func _box_path(body: Node3D, p: Vector3, dir: Vector3) -> float:
	if not body.has_meta("size"):
		return 9.0
	var half: Vector3 = (body.get_meta("size") as Vector3) * 0.5
	var inv := body.global_transform.affine_inverse()
	var o := inv * p
	var d := (inv.basis * dir).normalized()
	var t := INF
	for a in 3:
		if absf(d[a]) > 1e-6:
			var tt := ((half[a] if d[a] > 0.0 else -half[a]) - o[a]) / d[a]
			if tt >= 0.0:
				t = minf(t, tt)
	return clampf(t, 0.0, 9.0)


func _draw_tracers() -> void:
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var any := false
	for b: Dictionary in bullets:
		if not b["tracer"]:
			continue
		if not any:
			_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			any = true
		var p: Vector3 = b["p"]
		var v: Vector3 = b["v"]
		var dir := v.normalized()
		var tail := p - dir * minf(v.length() * 0.014, 9.0)
		# wstęga zwrócona do kamery; szersza z daleka, żeby było ją widać (min. ~2 px)
		var w := clampf(p.distance_to(eye) * 0.0018, 0.012, 0.12)
		var side := dir.cross(eye - p).normalized() * w
		var hot := Color(1.0, 0.75, 0.45, 1.0)
		var cold := Color(1.0, 0.3, 0.1, 0.0)
		for t in [[tail - side, cold], [p - side, hot], [p + side, hot], [tail - side, cold], [p + side, hot], [tail + side, cold]]:
			_im.surface_set_color(t[1])
			_im.surface_add_vertex(t[0])
	if any:
		_im.surface_end()
