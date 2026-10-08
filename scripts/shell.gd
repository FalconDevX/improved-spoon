extends "res://scripts/bomb.gd"
## Pocisk odłamkowo-burzący 100 mm z armaty czołgu Type 59: ~700 m/s, lot balistyczny ze
## smugaczem, wybuch przy uderzeniu (teren, budynek, pojazd, człowiek). Trafienie bezpośrednie
## w pojazd zadaje dodatkowe obrażenia (jak przebicie pancerza).

const LIFE := 6.0
const DIRECT_HIT := 420.0

var _trail_t := 0.0
static var _smat: StandardMaterial3D


func _ready() -> void:
	kill_r = 4.0
	stun_r = 12.0
	plane_r = 7.0
	frags = 30
	blast = 1.0
	if _smat == null:
		_smat = StandardMaterial3D.new()
		_smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smat.albedo_color = Color(1.0, 0.85, 0.5)
	# smugacz: jasna kropla na dnie pocisku
	var tr := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.6
	tr.mesh = sm
	tr.material_override = _smat
	tr.rotation.x = PI * 0.5
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tr)


func _physics_process(dt: float) -> void:
	_t += dt
	var p0 := global_position
	vel += Vector3(0, -GRAVITY, 0) * dt
	vel -= vel * vel.length() * 0.00002 * dt
	var p1 := p0 + vel * dt
	var excl: Array[RID] = []
	if plane != null and is_instance_valid(plane):
		excl.append(plane.get_rid())   # własny czołg
	var q := PhysicsRayQueryParameters3D.create(p0, p1, 1 | 2 | 4 | 8 | 32, excl)
	q.collide_with_areas = true
	q.hit_from_inside = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		var col = r["collider"]
		var my_shot: bool = not Player.net_on or (shooter != null and is_instance_valid(shooter) and shooter.get("is_remote") == false)
		if my_shot and col is Node and col.has_method("_damage") and col.get("destroyed") == false:
			col._damage(DIRECT_HIT)
		_explode((r["position"] as Vector3) - vel.normalized() * 0.2)
		return
	if _t > LIFE or p1.y < -5.0:
		_explode(p1)
		return
	global_position = p1
	var d := vel.normalized()
	global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)
