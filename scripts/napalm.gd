extends Node3D
## Napalm: zapalona galareta rozlewa się pasem wzdłuż toru bomby (~50 × 16 m) i płonie ~18 s.
## Kto stoi w ogniu dłużej niż chwilę, ginie (każdy komputer liczy swoich żołnierzy); maszyny
## w pasie dostają obrażenia co ćwierć sekundy (liczy komputer bombowca). Czarny dym wysoko.

const FX = preload("res://scripts/fx.gd")
const Player = preload("res://scripts/player.gd")

const LEN := 50.0
const WIDTH := 16.0
const LIFE := 18.0
const BURN_KILL := 0.8        # tyle sekund w ogniu zabija

var shooter = null
var dir := Vector3.FORWARD
var _t := 0.0
var _tick := 0.0
var _burn := {}               # żołnierz -> czas w ogniu
var _light: OmniLight3D
var _fires: Array = []


func _ready() -> void:
	global_basis = Basis.looking_at(dir, Vector3.UP)
	# płomienie: kilka emiterów wzdłuż pasa, każdy dopasowany do terenu (promień w dół)
	var space := get_world_3d().direct_space_state
	for i in 7:
		var off := Vector3(randf_range(-0.3, 0.3) * WIDTH, 0.0, -LEN * (float(i) / 6.0) + LEN * 0.15)
		var wp := global_transform * off
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(wp + Vector3.UP * 20.0, wp + Vector3.DOWN * 30.0, 1))
		if not r.is_empty():
			wp = r["position"]
		var f := _particles(48, 1.4, Color(1.0, 0.75, 0.25, 1.0), Color(1.0, 0.25, 0.02, 0.0), 2.6, 3.0, 9.0, true)
		add_child(f)
		f.global_position = wp
		_fires.append(f)
		var sm := _particles(18, 7.0, Color(0.08, 0.07, 0.06, 0.8), Color(0.2, 0.2, 0.2, 0.0), 6.0, 6.0, 14.0, false)
		add_child(sm)
		sm.global_position = wp + Vector3.UP * 3.0
		_fires.append(sm)
		var d := Decal.new()
		d.texture_albedo = FX._cache["dot"]
		d.modulate = Color(0.03, 0.025, 0.02, 0.9)
		d.size = Vector3(WIDTH * 0.9, 6.0, LEN / 4.0)
		d.cull_mask = FX.FLOOR_LAYER
		add_child(d)
		d.global_position = wp
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 70.0
	_light.light_energy = 10.0
	add_child(_light)
	_light.position = Vector3(0, 6, -LEN * 0.4)
	FX.I.play("boom", global_position, 6.0, 0.1, 0.7, 60.0)


func _particles(n: int, life: float, c0: Color, c1: Color, size: float, v0: float, v1: float, add: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 80, 60))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(WIDTH * 0.3, 0.5, LEN / 10.0)
	m.direction = Vector3.UP
	m.spread = 15.0
	m.initial_velocity_min = v0 * 0.3
	m.initial_velocity_max = v1 * 0.3
	m.gravity = Vector3(0, v0 * 0.5, 0)
	m.scale_min = 0.6
	m.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = FX._cache["dot"]
	if add:
		mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = mm
	p.draw_pass_1 = q
	return p


## Czy punkt leży w płonącym pasie.
func _inside(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	return absf(l.x) < WIDTH * 0.5 and l.z < LEN * 0.2 and l.z > -LEN * 1.05 and absf(l.y) < 6.0


func _physics_process(dt: float) -> void:
	_t += dt
	_light.light_energy = (10.0 + randf() * 5.0) * clampf((LIFE - _t) / 4.0, 0.0, 1.0)
	if _t > LIFE - 3.0:
		for f: GPUParticles3D in _fires:
			f.emitting = false
	if _t > LIFE + 7.0:
		queue_free()
		return
	if _t > LIFE:
		return
	_tick -= dt
	if _tick > 0.0:
		return
	_tick = 0.25
	var sh = shooter if (shooter != null and is_instance_valid(shooter)) else null
	for s in get_tree().get_nodes_in_group("soldier"):
		if s.down or s.get("is_remote") == true:
			continue
		if not _inside(s.global_position):
			_burn.erase(s)
			continue
		_burn[s] = float(_burn.get(s, 0.0)) + 0.25
		s.vitals.blunt(0.6)
		if _burn[s] >= BURN_KILL:
			if sh != null and sh != s:
				s.last_shooter = sh
				s.last_hit_seg = "torso"
			s.vitals._die()
			s._collapse(Vector3.UP, s.chest_pos(), "torso", 500.0, true)
	var mine: bool = not Player.net_on or (sh != null and sh.get("is_remote") == false)
	if mine:
		for v in get_tree().get_nodes_in_group("car") + get_tree().get_nodes_in_group("plane"):
			if not v.destroyed and _inside(v.global_position):
				v._damage(6.0)
