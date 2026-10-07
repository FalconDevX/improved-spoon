extends "res://scripts/bomb.gd"
## Rakieta PG-7V z RPG-7: start z prędkością ~115 m/s, silnik marszowy rozpędza ją do ~290 m/s
## (dym za nią, płomień dyszy), potem lot balistyczny. Wybucha przy uderzeniu w teren, budynek,
## samolot albo człowieka; po 4,5 s samolikwidacja. Wybuch jak bomba, ale mniejszy.

const ACCEL := 220.0
const VMAX := 290.0
const BURN := 1.2
const LIFE := 4.5

var _smoke_t := 0.0
var _flame: MeshInstance3D
static var _rmat: StandardMaterial3D
static var _fmat: StandardMaterial3D


func _ready() -> void:
	kill_r = 3.2
	stun_r = 9.0
	plane_r = 6.0
	frags = 26
	blast = 0.8
	if _rmat == null:
		_rmat = StandardMaterial3D.new()
		_rmat.albedo_color = Color(0.3, 0.33, 0.22)
		_rmat.metallic = 0.4
		_rmat.roughness = 0.5
		_fmat = StandardMaterial3D.new()
		_fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fmat.albedo_color = Color(1.0, 0.75, 0.35)
	# głowica (stożek) + korpus silnika, oś wzdłuż -Z
	var head := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.0
	hc.bottom_radius = 0.045
	hc.height = 0.28
	head.mesh = hc
	head.material_override = _rmat
	head.rotation.x = -PI * 0.5
	head.position.z = -0.25
	add_child(head)
	var body := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.022
	bc.bottom_radius = 0.022
	bc.height = 0.45
	body.mesh = bc
	body.material_override = _rmat
	body.rotation.x = PI * 0.5
	body.position.z = 0.1
	add_child(body)
	_flame = MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.05
	fs.height = 0.22
	_flame.mesh = fs
	_flame.material_override = _fmat
	_flame.rotation.x = PI * 0.5
	_flame.position.z = 0.38
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 2.5
	light.omni_range = 4.0
	light.position.z = 0.4
	add_child(light)


func _physics_process(dt: float) -> void:
	_t += dt
	var p0 := global_position
	var spd := vel.length()
	if _t < BURN:
		spd = minf(spd + ACCEL * dt, VMAX)
		vel = vel.normalized() * spd
	else:
		_flame.visible = false
		vel += Vector3(0, -GRAVITY, 0) * dt
	var p1 := p0 + vel * dt
	var excl: Array[RID] = []
	if shooter != null and is_instance_valid(shooter) and _t < 0.4:
		excl.append(shooter.get_rid())
		if shooter.has_method("hit_rids"):
			excl.append_array(shooter.hit_rids())
	# teren, budynki, samoloty, ciała ludzi (kapsuły) i strefy trafień
	var q := PhysicsRayQueryParameters3D.create(p0, p1, 1 | 2 | 4 | 8 | 32, excl)
	q.collide_with_areas = true
	q.hit_from_inside = true    # krok lotu (~1,2 m) dłuższy niż grubość człowieka: odcinek może zacząć się w ciele
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		if OS.has_feature("editor") or OS.get_environment("ROCKET_DEBUG") != "":
			print("[rocket] hit ", r["collider"], " ", (r["collider"] as Node).get_path() if r["collider"] is Node else "", " t=", _t, " at ", r["position"])
		_explode((r["position"] as Vector3) - vel.normalized() * 0.15)
		return
	if _t > LIFE or p1.y < -5.0:
		_explode(p1)
		return
	global_position = p1
	var d := vel.normalized()
	global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)
	# smuga dymu za silnikiem
	_smoke_t -= dt
	if _smoke_t <= 0.0 and _t < BURN + 0.5:
		_smoke_t = 0.035
		FX.I.muzzle_smoke(p1 - d * 0.4, -d * 0.2, 0.5)
