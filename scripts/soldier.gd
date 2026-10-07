extends CharacterBody3D
## Wspólna podstawa gracza i botów: model żołnierza, postać proceduralna z narządami (hitboxy,
## ragdoll, rentgen), broń, fizjologia (krew, rany), strzelanie i przeładowanie.

signal downed(who)        # utrata przytomności albo śmierć (wyeliminowany)
signal wounded(who, info)

const Humanoid = preload("res://scripts/humanoid.gd")
const Rig = preload("res://scripts/soldier_rig.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Vitals = preload("res://scripts/vitals.gd")
const FX = preload("res://scripts/fx.gd")
const Ballistics = preload("res://scripts/ballistics.gd")

const GRAVITY := 9.81
static var xray := false

var team := 0
var visual: Node3D            # obrót postaci w poziomie (przód -Z)
var body: Humanoid
var rig: Rig
var gun: Node3D               # broń w rękach (weapons.gd)
var vitals := Vitals.new()
var down := false             # wyeliminowany (nieprzytomny lub martwy)
var injuries: Dictionary = {} # narząd -> liczba trafień (HUD)
var last_injury := ""
var last_injury_time := -100.0
var last_hit_time := -100.0
var reloading := -1.0         # czas przeładowania (<0 = nie)
var _reload_total := 1.0
var cycling := -1.0
var helmet := true
var vest := true
var yaw := 0.0                # kierunek ciała
var _rids: Array[RID] = []
var _wound_nodes: Array = []
var _drip_t := 0.0
var _model_on := true
var _rig_skip := 0
var _shot_n := 0


func build_soldier(tint: Color, look: Dictionary) -> void:
	add_to_group("soldier")
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	body = Humanoid.new()
	visual.add_child(body)
	body.build(look, true, self)
	for nm: String in body.segs:
		for a in (body.segs[nm] as Node3D).find_children("*", "Area3D", false, false):
			_rids.append((a as Area3D).get_rid())
	rig = Rig.new()
	rig.name = "Rig"
	visual.add_child(rig)
	rig.setup(tint, body)
	_show_model(true)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	cs.name = "Shape"
	add_child(cs)


func hit_rids() -> Array[RID]:
	return _rids


func is_dead() -> bool:
	return down


func equip(g: Node3D) -> void:
	if gun and gun.get_parent() == rig:
		rig.remove_child(gun)
	gun = g
	if g:
		if g.get_parent():
			g.get_parent().remove_child(g)
		rig.add_child(g)
	rig.gun = g
	reloading = -1.0
	rig.reload_p = -1.0


## Punkt oczu (świat).
func eye_pos() -> Vector3:
	return global_position + Vector3(0, 1.62 - 0.5 * rig.crouch, 0)


func chest_pos() -> Vector3:
	return body.torso_position() if body else global_position + Vector3(0, 1.3, 0)


# ---------------------------------------------------------------- broń

## Strzał w kierunku dir (świat). spread_extra: dodatkowy rozrzut strzelca (rad).
func shoot(dir: Vector3, spread_extra := 0.0) -> bool:
	if gun == null or down or reloading >= 0.0:
		return false
	if not gun.can_fire():
		return false
	if not gun.consume():
		FX.I.play("click", gun.global_position, -10.0, 0.05)
		gun.cycle_t = 0.25
		return false
	var m: Vector3 = gun.muzzle()
	var sigma := float(gun.data["spread"]) + spread_extra
	var d := _jitter(dir, sigma)
	_shot_n += 1
	var tracer: bool = gun.cal.get("tracer", false) and _shot_n % 4 == 0
	Ballistics.I.fire(self, gun, m, d, tracer)
	_on_fired(m, d, tracer)
	gun.flash()
	_shot_fx(gun, m, d)
	FX.I.play(gun.data["sound"], m, 4.0, 0.06, 1.0, 40.0)
	rig.kick(1.0)
	var md: String = gun.fire_mode()
	if md == "pump" or md == "bolt":
		cycling = float(gun.data.get("cycle", 0.6))
		rig.reload_kind = md
		get_tree().create_timer(0.25).timeout.connect(func():
			if is_instance_valid(gun):
				FX.I.play("bolt", gun.global_position, -6.0, 0.05))
	# strzał słychać daleko
	for s in get_tree().get_nodes_in_group("soldier"):
		if s != self and s.has_method("heard_shot"):
			s.heard_shot(global_position, self)
	return true


## Dym z lufy i łuska z okna wyrzutowego (pompka / zamek / obrzyn / rewolwer: bez łuski przy strzale).
func _shot_fx(g: Node3D, m: Vector3, d: Vector3) -> void:
	FX.I.muzzle_smoke(m, d, 1.5 if g.data["cal"] == "12ga" else 1.0)
	var md: String = g.fire_mode()
	if md == "pump" or md == "bolt" or g.id in ["sawed", "m686"]:
		return
	var src: Node3D = _eject_from(g)
	var b := src.global_basis
	var port: Vector3 = src.global_transform * Vector3(0.012, 0.035, -0.06 if g.is_pistol() else -0.1)
	var v := b.x.normalized() * randf_range(2.2, 3.4) + b.y.normalized() * randf_range(1.0, 2.0) + b.z.normalized() * randf_range(0.0, 0.8)
	FX.I.eject_shell(port, v + velocity, g.data["cal"])


## Broń, z której wylatują łuski (gracz z pierwszej osoby: ta widoczna przy kamerze).
func _eject_from(g: Node3D) -> Node3D:
	return g


## Po wystrzale (gracz sieciowy wysyła strzał przeciwnikowi).
func _on_fired(_origin: Vector3, _dir: Vector3, _tracer: bool) -> void:
	pass


func _jitter(d: Vector3, sigma: float) -> Vector3:
	if sigma <= 0.0:
		return d.normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var x := d.cross(up).normalized()
	var y := x.cross(d).normalized()
	return (d.normalized() + x * randfn(0.0, sigma) + y * randfn(0.0, sigma)).normalized()


func start_reload() -> bool:
	if gun == null or reloading >= 0.0 or down or not gun.can_reload():
		return false
	_reload_total = gun.reload_time() / clampf(vitals.capacity() + 0.3, 0.6, 1.0)
	reloading = 0.0
	rig.reload_kind = "shell" if gun.data["feed"] == "tube" else "mag"
	FX.I.play("mag_out" if gun.data["feed"] == "mag" else "click", gun.global_position, -8.0)
	return true


func _tick_weapon(dt: float) -> void:
	if cycling >= 0.0:
		cycling -= dt
		rig.cycle_p = 1.0 - clampf(cycling / float(gun.data.get("cycle", 0.6)), 0.0, 1.0) if gun else -1.0
		if cycling < 0.0:
			rig.cycle_p = -1.0
	if reloading >= 0.0 and gun:
		reloading += dt
		rig.reload_p = reloading / _reload_total
		if reloading >= _reload_total:
			var more: bool = gun.finish_reload()
			FX.I.play("mag_in" if gun.data["feed"] == "mag" else "click", gun.global_position, -7.0)
			if gun.data["feed"] == "mag":
				get_tree().create_timer(0.15).timeout.connect(func():
					if is_instance_valid(gun):
						FX.I.play("bolt", gun.global_position, -9.0, 0.05, 1.3))
			if more and _want_more_shells():
				reloading = 0.0
			else:
				reloading = -1.0
				rig.reload_p = -1.0


func _want_more_shells() -> bool:
	return true


func cancel_reload() -> void:
	if gun and gun.data["feed"] == "tube" and reloading >= 0.0:
		reloading = -1.0
		rig.reload_p = -1.0


# ---------------------------------------------------------------- trafienia

## Kamizelka miękka (IIIA) na tułowiu i hełm. Zwraca nazwę osłony albo "".
func armor_at(seg: String, pos: Vector3, dir: Vector3) -> String:
	var n: Node3D = body.segs[seg]
	var lp := n.global_transform.affine_inverse() * pos
	if seg == "torso" and vest and lp.y > 0.12 and lp.y < 0.5:
		return "kamizelka"
	if seg == "head" and helmet and lp.y > 0.2 and not (lp.z < -0.05 and lp.y < 0.27):
		return "hełm"
	return ""


## Trafienie pociskiem (z balistyki).
func bullet_hit(h: Dictionary) -> void:
	var seg: String = h["seg"]
	var dir: Vector3 = h["dir"]
	var entry: Vector3 = h["entry"]
	var seg_n: Node3D = body.segs[seg]
	var energy: float = h.get("energy", 0.0)
	last_hit_time = Time.get_ticks_msec() / 1000.0
	var sh = h.get("shooter")
	if sh != null and is_instance_valid(sh) and sh != self:
		last_shooter = sh
		last_hit_seg = seg
	if h.get("armor", "") != "":
		_confirm(sh, 0)
		vitals.blunt(clampf(energy / 500.0, 0.2, 1.0))
		_note("%s zatrzymał%s pocisk" % [String(h["armor"]).capitalize(), "a" if h["armor"] == "kamizelka" else ""], [])
		if not down:
			rig.hit_react(visual.global_basis.inverse() * dir, seg, 0.6)
		_on_hit(h, {"names": PackedStringArray(), "kill": false})
		return
	var cav: float = h["cavity"]
	var cav_k := clampf(cav / 0.008, 0.5, 2.8)
	var organs: Array = h["organs"]
	for o: String in organs:
		injuries[o] = int(injuries.get(o, 0)) + 1
		body.mark_organ(seg, o)
	var was_down := down
	var res: Dictionary = vitals.wound(seg, organs, cav_k)
	var names: PackedStringArray = res["names"]
	_note(", ".join(names) if not names.is_empty() else "rana mięśni (%s)" % _seg_pl(seg), names)
	# krew: wlot, wylot, rozbryzg za ciałem
	var nrm := -dir
	FX.I.blood_spray(entry, nrm, clampf(0.25 + cav_k * 0.15, 0.2, 0.8))
	var w: Node3D = FX.I.bullet_wound(seg_n, entry, nrm, cav, false)
	_wound_nodes.append(w)
	if not h.get("stopped", false):
		var ex: Vector3 = h["exit"]
		var vo := float(h.get("v_out", 0.0))
		FX.I.blood_spray(ex, dir, clampf(0.4 + cav_k * 0.35, 0.3, 1.4))
		_wound_nodes.append(FX.I.bullet_wound(seg_n, ex, dir, cav * 1.6, true))
		if vo > 150.0:
			FX.I.wall_splatter(ex, dir, clampf(cav_k * 0.6, 0.4, 1.3))
	if _wound_nodes.size() > 12:
		_wound_nodes.pop_front()
	FX.I.play("hit", entry, -4.0 if not was_down else -10.0, 0.15)
	if down:
		var rb: RigidBody3D = body.rag_bodies.get(seg)
		if rb:
			rb.apply_impulse(dir * clampf(energy * 0.004, 2.0, 18.0), entry - rb.global_position)
		_on_hit(h, res)
		return
	rig.hit_react(visual.global_basis.inverse() * dir, seg, clampf(energy / 1500.0, 0.3, 1.6))
	# trafienie: zwykłe (biały znacznik) albo groźne — narząd / głowa (żółty)
	_confirm(sh, 1 if (seg == "head" or not names.is_empty()) else 0)
	if res.get("arm", false):
		rig.limp_arm = vitals.arms.duplicate()
	if res["kill"]:
		_collapse(dir, entry, seg, energy, true)
	elif vitals.legs >= 2:
		_collapse(dir, entry, seg, energy, false)
	elif seg == "head" and randf() < 0.5:
		_collapse(dir, entry, seg, energy, false)   # wstrząśnienie / utrata przytomności
	_on_hit(h, res)
	wounded.emit(self, h)


func _on_hit(_h: Dictionary, _res: Dictionary) -> void:
	pass


func _note(text: String, _names) -> void:
	last_injury = text
	last_injury_time = Time.get_ticks_msec() / 1000.0


static func _seg_pl(seg: String) -> String:
	return {"head": "głowa", "torso": "tułów", "uarm_l": "lewe ramię", "uarm_r": "prawe ramię",
		"farm_l": "lewe przedramię", "farm_r": "prawe przedramię", "thigh_l": "lewe udo",
		"thigh_r": "prawe udo", "shin_l": "lewa goleń", "shin_r": "prawa goleń"}.get(seg, seg)


## Przelot pocisku obok (trzask, przygniecenie ogniem).
func near_miss(_pos: Vector3, _dist: float, _speed: float, _shooter) -> void:
	pass


## Kto mnie ostatnio trafił (zabójstwo zaliczane także po wykrwawieniu).
var last_shooter = null
var last_hit_seg := ""


func _confirm(sh, strength: int) -> void:
	if sh != null and is_instance_valid(sh) and sh != self and sh.has_method("on_hit_confirmed"):
		sh.on_hit_confirmed(self, strength)


## Utrata przytomności / śmierć: ciało staje się ragdollem, broń wypada z rąk.
func _collapse(dir: Vector3, at: Vector3, seg: String, energy: float, instant: bool) -> void:
	if down:
		return
	down = true
	if last_shooter != null and is_instance_valid(last_shooter) and last_shooter.has_method("on_kill"):
		last_shooter.on_kill(self)
	reloading = -1.0
	var flat := Vector3(dir.x, 0, dir.z).normalized() if Vector3(dir.x, 0, dir.z).length() > 0.01 else -visual.global_basis.z
	var imp := flat * clampf(8.0 + energy * 0.01, 8.0, 30.0) * (0.4 if instant else 1.0)
	imp += Vector3(velocity.x, 0, velocity.z) * 50.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_do_ragdoll.call_deferred(imp, at, seg)
	downed.emit(self)


func _do_ragdoll(imp: Vector3, at: Vector3, seg: String) -> void:
	rig.update(0.0)
	body.make_ragdoll(imp, at, seg, self)
	rig.start_ragdoll()
	if gun:
		var g := gun
		gun = null
		rig.gun = null
		g.drop(get_parent(), imp * 0.05 + Vector3.UP)
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(body):
			FX.I.play("thud", body.torso_position(), -3.0))
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(body) and vitals.bleed_rate() > 1.0:
			FX.I.blood_pool(body.torso_position()))


func _tick_vitals(dt: float) -> void:
	var ev: String = vitals.step(dt)
	if ev != "" and not down:
		_collapse(-visual.global_basis.z, chest_pos(), "torso", 0.0, ev == "dead")
	# krew kapiąca z ran (tym więcej, im większy krwotok)
	var r := vitals.bleed_rate()
	if r > 0.3 and not _wound_nodes.is_empty():
		_drip_t -= dt
		if _drip_t <= 0.0:
			_drip_t = clampf(1.2 / r, 0.03, 0.8)
			var w = _wound_nodes[randi() % _wound_nodes.size()]
			if is_instance_valid(w):
				if r > 10.0 and randf() < 0.4:
					FX.I.spurt((w as Node3D).global_position, (w as Node3D).global_basis.y, clampf(r / 40.0, 0.3, 1.0))
				else:
					FX.I.drip((w as Node3D).global_position)


func _animate(dt: float, far: bool) -> void:
	var want := _model_on and not xray
	if want != rig.model.visible:
		_show_model(want)
	if down:
		rig.update(dt)
		return
	if far:
		_rig_skip += 1
		if _rig_skip % 3 != 0:
			return
		dt *= 3.0
	rig.update(dt)


func _show_model(on: bool) -> void:
	rig.set_visible_model(on)
	for seg: String in body.meshes:
		(body.meshes[seg] as MeshInstance3D).visible = not on
	if gun:
		gun.visible = true


static func soldier_look() -> Dictionary:
	return {
		"skin": Color(0.84, 0.66, 0.53), "shirt": Color(0.36, 0.33, 0.24), "pants": Color(0.33, 0.3, 0.22),
		"hair": Color(0.08, 0.06, 0.05), "belt": Color(0.12, 0.11, 0.09), "boots": Color(0.15, 0.12, 0.09),
		"garment": "tunic", "hood": false, "pauldrons": false, "gloves": true, "strap": true,
		"hair_style": "short", "beard_style": "none", "bulk": 1.05,
	}
