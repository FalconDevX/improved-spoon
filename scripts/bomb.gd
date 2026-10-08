extends Node3D
## Bomba lotnicza 50 kg: spada balistycznie (prędkość samolotu + grawitacja + opór), obraca się
## zgodnie z torem lotu. Przy uderzeniu wybuch: fala uderzeniowa zabija w promieniu kilku metrów
## i ogłusza dalej (każdy komputer liczy swoich żołnierzy), odłamki lecą jak pociski przez
## balistykę (rany narządów jak od kul), lej po wybuchu, uszkodzenia samolotów obok.

const FX = preload("res://scripts/fx.gd")
const Ballistics = preload("res://scripts/ballistics.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Player = preload("res://scripts/player.gd")

const GRAVITY := 9.81
const DRAG := 0.00035
const KILL_R := 5.5
const STUN_R := 14.0
const PLANE_R := 10.0
const FRAGS := 40

## Rodzaje bomb (samolot przełącza [B]): nazwa, promienie wybuchu, odłamki, wielkość wybuchu, skala
## modelu, ile wchodzi do jednej serii (część kompletu wyrzutników) i czas przeładowania.
const KINDS := {
	"frag": {"name": "50 kg odłamkowe", "kill": 5.5, "stun": 14.0, "plane": 10.0, "frags": 40, "blast": 1.3, "scale": 1.0, "share": 1.0, "reload": 8.0},
	"he": {"name": "250 kg burzące", "kill": 13.0, "stun": 34.0, "plane": 22.0, "frags": 90, "blast": 2.8, "scale": 1.7, "share": 0.34, "reload": 12.0},
	"napalm": {"name": "napalm", "kill": 3.0, "stun": 9.0, "plane": 6.0, "frags": 0, "blast": 1.1, "scale": 1.45, "share": 0.34, "reload": 12.0},
	"cluster": {"name": "kasetowe (24 podpociski)", "kill": 0.0, "stun": 0.0, "plane": 0.0, "frags": 0, "blast": 0.4, "scale": 1.5, "share": 0.25, "reload": 14.0},
	"bomblet": {"name": "podpocisk", "kill": 3.2, "stun": 9.0, "plane": 5.0, "frags": 10, "blast": 0.55, "scale": 0.35, "share": 0.0, "reload": 0.0},
	"v1": {"name": "V-1 (850 kg amatolu)", "kill": 24.0, "stun": 60.0, "plane": 40.0, "frags": 160, "blast": 4.0, "scale": 2.2, "share": 0.0, "reload": 0.0},
	"v2": {"name": "V-2 (1000 kg amatolu)", "kill": 40.0, "stun": 100.0, "plane": 70.0, "frags": 260, "blast": 7.0, "scale": 2.5, "share": 0.0, "reload": 0.0},
	"moab": {"name": "MOAB (GBU-43, 8,5 t)", "kill": 60.0, "stun": 140.0, "plane": 90.0, "frags": 220, "blast": 10.0, "scale": 4.5, "share": 0.0, "reload": 40.0},
	"thermo": {"name": "termobaryczne", "kill": 30.0, "stun": 70.0, "plane": 45.0, "frags": 60, "blast": 5.0, "scale": 2.2, "share": 0.25, "reload": 20.0},
	"bunker": {"name": "przeciwbunkrowe (GBU-28)", "kill": 20.0, "stun": 40.0, "plane": 25.0, "frags": 80, "blast": 3.5, "scale": 1.9, "share": 0.25, "reload": 18.0},
	"nuke": {"name": "ATOMOWA", "kill": 0.0, "stun": 0.0, "plane": 0.0, "frags": 0, "blast": 0.0, "scale": 4.2, "share": 0.0, "reload": 60.0},
}
const CLUSTER_OPEN := 160.0    # kaseta otwiera się na tej wysokości nad ziemią
const NUKE_CHUTE := 2.0        # atomowa: spadochron otwiera się tyle sekund po zrzucie
const NUKE_SINK := 14.0        # i opada pod nim z taką prędkością [m/s] (samolot zdąży odlecieć)
const Parachute = preload("res://scripts/parachute.gd")


class Frag:
	var cal: Dictionary
	var data: Dictionary


static var _frag: Frag = null
static var _mesh_body: Mesh
static var _mesh_fin: Mesh
static var _mat: StandardMaterial3D

var vel := Vector3.ZERO
var shooter = null      # pilot: odłamki liczą obrażenia jak jego pociski
var plane = null        # samolot, z którego spadła (pomijany na początku lotu)
var _t := 0.0
var _chute: Node3D = null
# siła wybuchu (rakieta RPG nadpisuje: mniejszy promień, mniej odłamków)
var kill_r := KILL_R
var stun_r := STUN_R
var plane_r := PLANE_R
var frags := FRAGS
var blast := 1.3
var kind := "frag"


static func frag_gun() -> Frag:
	if _frag == null:
		_frag = Frag.new()
		_frag.cal = Weapons.CAL["frag"]
		_frag.data = {"v0": 1100.0, "zero": 1.0, "cal": "frag"}
	return _frag


## Model bomby (korpus, ostrołuk, stateczniki) — też na wyrzutnikach pod skrzydłami samolotu.
static func make_mesh(parent: Node3D) -> Node3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.22, 0.25, 0.2)
		_mat.metallic = 0.5
		_mat.roughness = 0.5
		var c := CylinderMesh.new()
		c.top_radius = 0.09
		c.bottom_radius = 0.12
		c.height = 0.85
		c.radial_segments = 12
		_mesh_body = c
		var f := BoxMesh.new()
		f.size = Vector3(0.36, 0.2, 0.015)
		_mesh_fin = f
	var root := Node3D.new()
	parent.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _mesh_body
	body.material_override = _mat
	body.rotation.x = PI * 0.5       # oś wzdłuż Z, nos do -Z
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.12
	sp.height = 0.32
	nose.mesh = sp
	nose.material_override = _mat
	nose.position = Vector3(0, 0, -0.43)
	nose.rotation.x = PI * 0.5
	root.add_child(nose)
	for k in 2:
		var fin := MeshInstance3D.new()
		fin.mesh = _mesh_fin
		fin.material_override = _mat
		fin.position = Vector3(0, 0, 0.45)
		fin.rotation = Vector3(PI * 0.5, 0, PI * 0.5 * k)
		root.add_child(fin)
	return root


## Ile bomb danego rodzaju wchodzi do jednej serii przy komplecie `racks` wyrzutników.
static func salvo_size(k: String, racks: int) -> int:
	if k == "nuke":
		return 1
	return maxi(int(round(racks * float(KINDS[k]["share"]))), 1)


func _ready() -> void:
	add_to_group("ordnance")     # restart mapy usuwa spadające bomby
	var c: Dictionary = KINDS[kind]
	kill_r = c["kill"]
	stun_r = c["stun"]
	plane_r = c["plane"]
	frags = c["frags"]
	blast = c["blast"]
	var m := make_mesh(self)
	m.scale = Vector3.ONE * float(c["scale"])
	if kind == "nuke":
		preload("res://scripts/nuke.gd").alarm(get_parent(), 60.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.75, 0.2)     # „Fat Man”: pękaty, żółty korpus
		mat.metallic = 0.3
		mat.roughness = 0.6
		for mi in m.get_children():
			mi.material_override = mat
		m.scale = Vector3(5.5, 5.5, 3.2)
	elif kind == "napalm":
		for mi in m.get_children():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.55, 0.5)
			mi.material_override = mat


func _physics_process(dt: float) -> void:
	_t += dt
	var p0 := global_position
	if kind == "nuke" and _t > NUKE_CHUTE:
		_nuke_chute(dt)
	else:
		vel += Vector3(0, -GRAVITY, 0) * dt
		vel -= vel * vel.length() * DRAG * dt
	var p1 := p0 + vel * dt
	var excl: Array[RID] = []
	if _t < 1.5 and plane != null and is_instance_valid(plane):
		excl.append(plane.get_rid())
	var q := PhysicsRayQueryParameters3D.create(p0, p1, 1 | 32, excl)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		_explode(r["position"] + (r["normal"] as Vector3) * 0.3)
		return
	# kaseta otwiera się nad ziemią; atomowa wybucha dopiero przy uderzeniu, tam gdzie spadła
	if kind == "cluster" and _t > 1.0 and vel.y < 0.0:
		var g := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p1, p1 + Vector3.DOWN * CLUSTER_OPEN, 1))
		if not g.is_empty():
			_open_cluster(p1)
			return
	if p1.y < -30.0 or _t > (180.0 if kind == "nuke" else 40.0):
		queue_free()
		return
	global_position = p1
	if _chute != null:
		# pod czaszą: wisi nosem w dół, czasza nad nią lekko się kołysze
		global_basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
		_chute.global_position = p1 + Vector3.UP * 1.5
		_chute.rotation = Vector3(sin(_t * 0.9) * 0.06, _t * 0.15, cos(_t * 0.7) * 0.06)
		return
	var d := vel.normalized()
	global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)


## Atomowa pod spadochronem: czasza się otwiera, prędkość spada do NUKE_SINK, ruch w poziomie gaśnie.
func _nuke_chute(dt: float) -> void:
	if _chute == null:
		_chute = Parachute.canopy()
		_chute.top_level = true
		add_child(_chute)
		_chute.scale = Vector3.ONE * 0.3
		FX.I.play("whoosh", global_position, 6.0, 0.05, 0.6, 80.0)
	var open := clampf((_t - NUKE_CHUTE) / Parachute.OPEN_TIME, 0.0, 1.0)
	_chute.scale = Vector3.ONE * lerpf(0.3, 2.6, open)       # duża czasza: bomba waży kilka ton
	vel.y = move_toward(vel.y, -NUKE_SINK, (GRAVITY + 30.0 * open) * dt)
	var k := exp(-0.6 * open * dt)
	vel.x *= k
	vel.z *= k


## Kaseta: rozpada się nad celem na 24 podpociski rozsypane w elipsę wzdłuż toru lotu.
func _open_cluster(pos: Vector3) -> void:
	FX.I.play("click", pos, 6.0, 0.1, 0.6, 60.0)
	FX.I.explosion(pos, 0.35)
	for i in 24:
		var b = get_script().new()
		b.kind = "bomblet"
		b.shooter = shooter
		b.vel = vel + Vector3(randfn(0.0, 1.0), randfn(0.0, 0.3), randfn(0.0, 1.0)) * 13.0
		get_parent().add_child(b)
		b.global_position = pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	queue_free()


func _nuke(pos: Vector3) -> void:
	var n := preload("res://scripts/nuke.gd").new()
	n.shooter = shooter
	get_parent().add_child(n)
	n.global_position = pos
	queue_free()


func _explode(pos: Vector3) -> void:
	if kind == "nuke":
		_nuke(pos)
		return
	if kind == "cluster":
		_open_cluster(pos + Vector3.UP)
		return
	if kind == "napalm":
		var f := preload("res://scripts/napalm.gd").new()
		f.shooter = shooter
		f.dir = Vector3(vel.x, 0.0, vel.z).normalized() if Vector2(vel.x, vel.z).length() > 1.0 else Vector3.FORWARD
		f.position = pos       # przed add_child: _ready dopasowuje płomienie do terenu w tym miejscu
		get_parent().add_child(f)
	FX.I.explosion(pos, blast)
	if kind != "napalm":
		FX.I.crater(pos)
		if kind == "he":
			FX.I.crater(pos + Vector3(1.5, 0, 0))
			FX.I.crater(pos - Vector3(1.5, 0, 0))
	var sh = shooter if (shooter != null and is_instance_valid(shooter)) else null
	var my_bomb: bool = not Player.net_on or (sh != null and sh.get("is_remote") == false)
	# fala uderzeniowa: każdy komputer liczy tylko swoich (gracz lokalny, boty)
	for s in get_tree().get_nodes_in_group("soldier"):
		if s.down or s.get("is_remote") == true:
			continue
		var c: Vector3 = s.chest_pos()
		var d := c.distance_to(pos)
		if d < kill_r:
			if sh != null and sh != s:
				s.last_shooter = sh      # zabójstwo zaliczone strzelcowi / pilotowi
				s.last_hit_seg = "torso"
			s.vitals._die()
			s._collapse((c - pos).normalized(), c, "torso", 6000.0, true)
		elif d < stun_r:
			s.vitals.blunt(clampf((stun_r - d) / stun_r, 0.1, 1.0))
	if kind == "bunker":
		# przebija strop schronu: zabija ukrytych pod ziemią w promieniu 30 m
		for s in get_tree().get_nodes_in_group("soldier"):
			if s.down or s.get("is_remote") == true:
				continue
			var hp_: Vector3 = s.global_position
			if preload("res://scripts/bunker.gd").underground(hp_) and Vector2(hp_.x - pos.x, hp_.z - pos.z).length() < 30.0:
				if sh != null and sh != s:
					s.last_shooter = sh
				s.vitals._die()
				s._collapse(Vector3.UP, s.chest_pos(), "torso", 6000.0, true)
	for p in get_tree().get_nodes_in_group("player"):
		var dp: float = p.global_position.distance_to(pos)
		var shake_r := 80.0 * maxf(blast / 1.3, 0.6)
		if dp < shake_r:
			p._trauma = minf(p._trauma + 0.9 * (1.0 - dp / shake_r), 1.0)
	# samoloty obok (obrażenia liczy komputer bombowca i rozsyła)
	if my_bomb:
		for pl in get_tree().get_nodes_in_group("plane") + get_tree().get_nodes_in_group("car"):
			var dpl: float = pl.global_position.distance_to(pos)
			if dpl < plane_r and not pl.destroyed:
				pl._damage((plane_r - dpl) * 22.0)
	# odłamki: zwykłe pociski z balistyki (rozchodzą się głównie w bok i w górę)
	var origin := pos + Vector3.UP * 0.4
	for i in frags:
		var dir := Vector3(randfn(0.0, 1.0), absf(randfn(0.0, 0.5)) + 0.05, randfn(0.0, 1.0)).normalized()
		Ballistics.I.fire(sh, frag_gun(), origin, dir, false)
	queue_free()
