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
# siła wybuchu (rakieta RPG nadpisuje: mniejszy promień, mniej odłamków)
var kill_r := KILL_R
var stun_r := STUN_R
var plane_r := PLANE_R
var frags := FRAGS
var blast := 1.3


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


func _ready() -> void:
	make_mesh(self)


func _physics_process(dt: float) -> void:
	_t += dt
	var p0 := global_position
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
	if p1.y < -30.0 or _t > 40.0:
		queue_free()
		return
	global_position = p1
	var d := vel.normalized()
	global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)


func _explode(pos: Vector3) -> void:
	FX.I.explosion(pos, blast)
	FX.I.crater(pos)
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
	for p in get_tree().get_nodes_in_group("player"):
		var dp: float = p.global_position.distance_to(pos)
		if dp < 80.0:
			p._trauma = minf(p._trauma + 0.9 * (1.0 - dp / 80.0), 1.0)
	# samoloty obok (obrażenia liczy komputer bombowca i rozsyła)
	if my_bomb:
		for pl in get_tree().get_nodes_in_group("plane"):
			var dpl: float = pl.global_position.distance_to(pos)
			if dpl < plane_r and not pl.destroyed:
				pl._damage((plane_r - dpl) * 22.0)
	# odłamki: zwykłe pociski z balistyki (rozchodzą się głównie w bok i w górę)
	var origin := pos + Vector3.UP * 0.4
	for i in frags:
		var dir := Vector3(randfn(0.0, 1.0), absf(randfn(0.0, 0.5)) + 0.05, randfn(0.0, 1.0)).normalized()
		Ballistics.I.fire(sh, frag_gun(), origin, dir, false)
	queue_free()
