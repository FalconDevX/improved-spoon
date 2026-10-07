extends "res://scripts/bomb.gd"
## Granat odłamkowy (typ F-1 / M67): rzut łukiem, odbija się od ścian i ziemi, toczy się,
## wybuch po 3,5 s od rzutu. Wybuch jak bomba, ale mniejszy (promień zabicia ~4 m, odłamki).

const FUSE := 3.5
const BOUNCE := 0.35

var _rest := false
static var _gmat: StandardMaterial3D


func _ready() -> void:
	kill_r = 4.0
	stun_r = 10.0
	plane_r = 3.0
	frags = 34
	blast = 0.7
	if _gmat == null:
		_gmat = StandardMaterial3D.new()
		_gmat.albedo_color = Color(0.25, 0.3, 0.18)
		_gmat.roughness = 0.6
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.035
	s.height = 0.08
	body.mesh = s
	body.material_override = _gmat
	add_child(body)
	var top := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.012
	c.bottom_radius = 0.014
	c.height = 0.03
	top.mesh = c
	top.material_override = _gmat
	top.position.y = 0.045
	add_child(top)


func _physics_process(dt: float) -> void:
	_t += dt
	if _t >= FUSE:
		_explode(global_position + Vector3.UP * 0.15)
		return
	if _rest:
		return
	var p0 := global_position
	vel += Vector3(0, -GRAVITY, 0) * dt
	var p1 := p0 + vel * dt
	var excl: Array[RID] = []
	if shooter != null and is_instance_valid(shooter):
		excl.append(shooter.get_rid())
	var q := PhysicsRayQueryParameters3D.create(p0, p1, 1 | 32, excl)
	q.hit_from_inside = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		var n: Vector3 = r["normal"]
		if n == Vector3.ZERO:
			n = Vector3.UP
		# odbicie z utratą energii; na ziemi tarcie (toczy się i staje)
		vel = vel.bounce(n) * BOUNCE
		if n.y > 0.7:
			vel.x *= 0.7
			vel.z *= 0.7
		p1 = (r["position"] as Vector3) + n * 0.04
		if vel.length() > 1.5:
			FX.I.play("click", p1, -14.0, 0.2, 0.6, 6.0)
		if n.y > 0.7 and vel.length() < 0.6:
			_rest = true
			vel = Vector3.ZERO
	global_position = p1
	if not _rest:
		rotate_x(dt * 9.0)
