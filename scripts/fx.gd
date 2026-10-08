extends Node3D
## Efekty walki: kropelki krwi (fizyka + plamy na podłodze), mgiełka, rany,
## kałuże pod ciałami, dźwięki i hit-stop.

const TexGen = preload("res://scripts/tex_gen.gd")
const Sfx = preload("res://scripts/sfx.gd")

const MAX_DROPS := 1800
const MAX_DECALS := 360
const GRAVITY := 9.81
const FLOOR_LAYER := 1
const BODY_LAYER := 2

static var I = null
static var _cache: Dictionary = {}

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _size := PackedFloat32Array()
var _mm: MultiMesh
var _decals: Array = []
var _mist_mat: StandardMaterial3D
var _mist_ramp: GradientTexture1D
var _mist_curve: CurveTexture
var _hitstop_end := 0


func _enter_tree() -> void:
	I = self


func _exit_tree() -> void:
	if I == self:
		I = null
	Engine.time_scale = 1.0


func _ready() -> void:
	Engine.time_scale = 1.0
	if _cache.is_empty():
		var splats: Array = []
		for i in 6:
			splats.append(TexGen.blood_splat(1000 + i * 17, false))
		var wounds: Array = []
		for i in 3:
			wounds.append(TexGen.wound(77 + i * 31))
		_cache = {
			"splats": splats,
			"wounds": wounds,
			"pool": TexGen.blood_splat(4242, true),
			"orm": TexGen.solid(Color(1.0, 0.14, 0.0)),
			"dot": TexGen.soft_dot(),
			"whoosh": Sfx.whoosh(),
			"hit": Sfx.flesh(false),
			"hit_heavy": Sfx.flesh(true),
			"thud": Sfx.thud(),
			"shot": Sfx.gunshot(),
			"ricochet": Sfx.ricochet(),
			"shot_9": Sfx.shot(0.3, 1.25, 11),
			"shot_556": Sfx.shot(0.5, 1.0, 556),
			"shot_762": Sfx.shot(0.6, 0.85, 762),
			"shot_308": Sfx.shot(0.8, 0.7, 308),
			"shot_12": Sfx.shot(0.7, 0.6, 12),
			"crack": Sfx.crack(),
			"click": Sfx.click(0.04, 3000.0, 3),
			"mag_out": Sfx.click(0.09, 1400.0, 5),
			"mag_in": Sfx.click(0.12, 900.0, 8),
			"bolt": Sfx.click(0.22, 1100.0, 13),
			"impact_hard": Sfx.impact(2600.0, 21),
			"impact_wood": Sfx.impact(700.0, 22),
			"impact_metal": Sfx.ping(),
			"groan": Sfx.groan(),
			"shot_50": Sfx.shot(0.6, 0.55, 50),
			"engine": Sfx.engine(),
			"pulsejet": Sfx.pulsejet(),
			"rocket": Sfx.rocket(),
			"boom": Sfx.explosion(),
			"hole": TexGen.bullet_hole(),
		}

	# Kropelki krwi renderowane jednym MultiMeshem.
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.3, 0.01, 0.015)
	dm.roughness = 0.1
	dm.metallic_specular = 0.8
	sm.material = dm
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = sm
	_mm.instance_count = MAX_DROPS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.layers = 4
	mmi.custom_aabb = AABB(Vector3(-150, -1, -150), Vector3(300, 30, 300))
	add_child(mmi)

	# Mgiełka krwi (GPU particles).
	_mist_mat = StandardMaterial3D.new()
	_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mist_mat.vertex_color_use_as_albedo = true
	_mist_mat.albedo_texture = _cache["dot"]
	var g := Gradient.new()
	g.set_color(0, Color(0.2, 0.0, 0.005, 0.75))
	g.set_color(1, Color(0.12, 0.0, 0.0, 0.0))
	_mist_ramp = GradientTexture1D.new()
	_mist_ramp.gradient = g
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(1.0, 1.0))
	_mist_curve = CurveTexture.new()
	_mist_curve.curve = c


func _process(_delta: float) -> void:
	if _hitstop_end > 0 and Time.get_ticks_msec() >= _hitstop_end:
		_hitstop_end = 0
		Engine.time_scale = 1.0


# ---------------------------------------------------------------- hit-stop / audio

func hitstop(duration: float) -> void:
	Engine.time_scale = 0.03
	_hitstop_end = maxi(_hitstop_end, Time.get_ticks_msec() + int(duration * 1000.0))


var _voices := 0


func play(sound: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.12, pitch := 1.0, unit := 8.0) -> void:
	if _voices > 48:
		return
	_voices += 1
	var p := AudioStreamPlayer3D.new()
	p.stream = _cache[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_var, pitch_var))
	p.unit_size = unit
	p.max_distance = 700.0
	p.attenuation_filter_cutoff_hz = 4000.0
	p.attenuation_filter_db = -18.0
	p.finished.connect(func(): _voices -= 1)
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


# ---------------------------------------------------------------- krew

## Rozbryzg przy trafieniu. amount ~0.3 (draśnięcie) .. 1.6 (ciężkie cięcie).
func blood_spray(pos: Vector3, dir: Vector3, amount: float) -> void:
	var count := int(clampf(18.0 + amount * 60.0, 10.0, 140.0))
	for k in count:
		var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.55
		var d := (dir + spread).normalized()
		var speed := randf_range(0.8, 4.8) * (0.7 + amount * 0.45)
		var s := randf_range(0.003, 0.009) * (1.0 + randf() * randf() * 2.2)
		_add_drop(pos + d * 0.02, d * speed + Vector3(0, randf_range(0.0, 1.0), 0), s)
	# cięższe krople spływające prosto w dół z rany
	for k in int(4 + amount * 8):
		var v := Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.4), randf_range(-0.3, 0.3)) + dir * 0.4
		_add_drop(pos, v, randf_range(0.012, 0.02))
	_mist(pos, dir, amount)


## Pulsujący strumień z przeciętej tętnicy.
func spurt(pos: Vector3, dir: Vector3, strength: float) -> void:
	for k in int(5 + 16 * strength):
		var d := (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.13).normalized()
		_add_drop(pos, d * randf_range(1.2, 3.4) * (0.5 + strength * 0.6), randf_range(0.004, 0.011))


## Wypadające jelita: łańcuch małych brył połączonych przegubami + kilka organów.
func spill_guts(pos: Vector3, dir: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.84, 0.52, 0.48)
	mat.roughness = 0.2
	mat.subsurf_scatter_enabled = true
	mat.subsurf_scatter_strength = 0.3
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.11
	mesh.radial_segments = 10
	mesh.rings = 3
	var shape := CapsuleShape3D.new()
	shape.radius = 0.02
	shape.height = 0.11
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	if d.length_squared() < 0.1:
		d = Vector3.FORWARD
	var p := pos
	var prev: RigidBody3D = null
	for i in 12:
		var rb := RigidBody3D.new()
		rb.collision_layer = 16
		rb.collision_mask = 1
		rb.mass = 0.12
		rb.linear_damp = 0.6
		rb.angular_damp = 3.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.layers = 2
		rb.add_child(mi)
		add_child(rb)
		var y := d
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		rb.global_transform = Transform3D(Basis(x, y, x.cross(y)), p + d * 0.045)
		rb.linear_velocity = dir * randf_range(0.4, 1.4) + Vector3(0, randf_range(-0.5, 0.3), 0)
		if prev:
			var j := PinJoint3D.new()
			add_child(j)
			j.global_position = p
			j.node_a = j.get_path_to(prev)
			j.node_b = j.get_path_to(rb)
		prev = rb
		p += d * 0.09
		d = (d.rotated(Vector3.UP, randf_range(-1.2, 1.2)) + Vector3(0, randf_range(-0.6, 0.3), 0)).normalized()
	for k in 3:
		blood_spray(pos, (dir + Vector3.DOWN).normalized(), 0.8)


func drip(pos: Vector3) -> void:
	_add_drop(pos, Vector3(randf_range(-0.05, 0.05), -0.1, randf_range(-0.05, 0.05)), randf_range(0.005, 0.009))


func _add_drop(p: Vector3, v: Vector3, s: float) -> void:
	if _pos.size() >= MAX_DROPS:
		return
	_pos.append(p)
	_vel.append(v)
	_size.append(s)


func _remove_drop(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_size[i] = _size[last]
	_pos.resize(last)
	_vel.resize(last)
	_size.resize(last)


func _physics_process(delta: float) -> void:
	_tick_shells(delta)
	var i := 0
	while i < _pos.size():
		var v := _vel[i]
		v.y -= GRAVITY * delta
		v *= 1.0 - minf(delta * (0.4 + 0.004 / _size[i]), 0.5)  # małe krople mocniej hamowane
		var p := _pos[i] + v * delta
		if p.y <= 0.0:
			_land(Vector3(p.x, 0.0, p.z), _size[i], v)
			_remove_drop(i)
			continue
		_pos[i] = p
		_vel[i] = v
		i += 1

	var n := _pos.size()
	_mm.visible_instance_count = n
	for j in n:
		var v := _vel[j]
		var s := _size[j]
		var sp := v.length()
		var b := Basis.from_scale(Vector3.ONE * s)
		if sp > 0.05:
			var y := v / sp
			var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			var z := x.cross(y)
			b = Basis(x * s, y * s * minf(1.0 + sp * 0.35, 3.5), z * s)
		_mm.set_instance_transform(j, Transform3D(b, _pos[j]))


func _land(pos: Vector3, s: float, v: Vector3) -> void:
	if s < 0.005 and randf() < 0.3:
		return
	var hv := Vector2(v.x, v.z)
	var hs := hv.length()
	var d := s * randf_range(6.0, 11.0)
	var yaw := atan2(-hv.x, -hv.y) if hs > 0.1 else randf() * TAU
	# szybkie krople zostawiają wydłużone ślady
	_floor_decal(pos, d * (1.0 + minf(hs * 0.18, 1.2)), d, yaw + PI * 0.5)


func _floor_decal(pos: Vector3, sx: float, sz: float, yaw: float) -> Decal:
	var splats: Array = _cache["splats"]
	var pair: Array = splats[randi() % splats.size()]
	var d := Decal.new()
	d.texture_albedo = pair[0]
	d.texture_normal = pair[1]
	d.texture_orm = _cache["orm"]
	d.size = Vector3(sx, 0.1, sz)
	d.cull_mask = FLOOR_LAYER
	add_child(d)
	d.global_position = pos
	d.rotation.y = yaw
	_decals.append(d)
	if _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return d


func _mist(pos: Vector3, dir: Vector3, amount: float) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = int(10 + 22 * amount)
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = 4
	var m := ParticleProcessMaterial.new()
	m.direction = dir
	m.spread = 28.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 2.6 * (0.6 + amount * 0.4)
	m.gravity = Vector3(0, -1.5, 0)
	m.damping_min = 2.0
	m.damping_max = 4.0
	m.scale_min = 0.6
	m.scale_max = 1.5
	m.scale_curve = _mist_curve
	m.color_ramp = _mist_ramp
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	q.material = _mist_mat
	p.draw_pass_1 = q
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## Rana na części ciała. Decal jest dzieckiem segmentu, więc porusza się z nim
## (także po zamianie w ragdoll). Zwraca węzeł rany (do kapania krwi).
func wound(seg: Node3D, pos: Vector3, normal: Vector3, slash_dir: Vector3, severity: float) -> Node3D:
	var y := normal.normalized()
	var x := slash_dir - y * slash_dir.dot(y)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT)
	x = x.normalized()
	var basis := Basis(x, y, x.cross(y))

	# plama krwi wsiąkająca w ubranie wokół rany
	var splats: Array = _cache["splats"]
	var sp: Array = splats[randi() % splats.size()]
	var soak := Decal.new()
	soak.texture_albedo = sp[0]
	soak.texture_normal = sp[1]
	soak.texture_orm = _cache["orm"]
	var ss := randf_range(0.16, 0.24) * severity
	soak.size = Vector3(ss * 1.3, 0.1, ss)
	soak.modulate = Color(0.8, 0.8, 0.8, 0.85)
	soak.cull_mask = BODY_LAYER
	soak.normal_fade = 0.3
	seg.add_child(soak)
	soak.global_transform = Transform3D(basis, pos)

	var wounds: Array = _cache["wounds"]
	var wp: Array = wounds[randi() % wounds.size()]
	var d := Decal.new()
	d.texture_albedo = wp[0]
	d.texture_normal = wp[1]
	d.texture_orm = _cache["orm"]
	var length := randf_range(0.11, 0.17) * clampf(severity, 0.6, 1.5)
	d.size = Vector3(length, 0.08, length * 0.38)
	d.cull_mask = BODY_LAYER
	d.normal_fade = 0.35
	seg.add_child(d)
	d.global_transform = Transform3D(basis, pos)
	return d


## Kałuża krwi powoli rozlewająca się pod ciałem.
func blood_pool(pos: Vector3) -> void:
	var pair: Array = _cache["pool"]
	var d := Decal.new()
	d.texture_albedo = pair[0]
	d.texture_normal = pair[1]
	d.texture_orm = _cache["orm"]
	d.size = Vector3(0.15, 0.12, 0.15)
	d.cull_mask = FLOOR_LAYER
	add_child(d)
	d.global_position = Vector3(pos.x, 0.0, pos.z)
	d.rotation.y = randf() * TAU
	var target := randf_range(1.1, 1.6)
	var tw := create_tween()
	tw.tween_property(d, "size", Vector3(target, 0.12, target * randf_range(0.75, 1.0)), 14.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)



# ---------------------------------------------------------------- pociski

var _impacts := 0
var _holes: Array = []
const MAX_HOLES := 260
const IMPACT_COLORS := {
	"dust": [Color(0.62, 0.6, 0.56, 0.8), Color(0.55, 0.53, 0.5, 0.0)],
	"sand": [Color(0.55, 0.47, 0.33, 0.85), Color(0.5, 0.43, 0.3, 0.0)],
	"wood": [Color(0.55, 0.4, 0.24, 0.9), Color(0.45, 0.33, 0.2, 0.0)],
	"spark": [Color(1.0, 0.75, 0.35, 1.0), Color(1.0, 0.4, 0.1, 0.0)],
	"blood": [Color(0.3, 0.0, 0.01, 0.8), Color(0.2, 0.0, 0.0, 0.0)],
}
static var _impact_mats := {}


## Trafienie w przeszkodę: chmurka pyłu / drzazgi / iskry z odbicia.
func impact(pos: Vector3, normal: Vector3, kind: String, amount := 1.0) -> void:
	if _impacts > 40:
		return
	_impacts += 1
	var p := GPUParticles3D.new()
	p.one_shot = true
	var spark := kind == "spark"
	p.amount = int((10 if spark else 14) * amount) + 2
	p.lifetime = 0.35 if spark else 0.9
	p.explosiveness = 1.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = normal
	m.spread = 35.0 if spark else 25.0
	m.initial_velocity_min = 2.0 if spark else 0.5
	m.initial_velocity_max = 9.0 if spark else 3.0
	m.gravity = Vector3(0, -9.8 if spark else -1.2, 0)
	m.damping_min = 0.5 if spark else 3.0
	m.damping_max = 1.0 if spark else 6.0
	m.scale_min = 0.3 if spark else 0.7
	m.scale_max = 0.6 if spark else 1.8
	m.scale_curve = _mist_curve
	var cols: Array = IMPACT_COLORS.get(kind, IMPACT_COLORS["dust"])
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[1])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02) if spark else Vector2(0.12, 0.12)
	if not _impact_mats.has(spark):
		var mm := _mist_mat.duplicate() as StandardMaterial3D
		if spark:
			mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		else:
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_impact_mats[spark] = mm
	q.material = _impact_mats[spark]
	p.draw_pass_1 = q
	add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(func():
		_impacts -= 1
		p.queue_free())


## Dziura po kuli (decal na ścianie / skrzyni).
func bullet_hole(pos: Vector3, normal: Vector3, parent: Node3D, mat: String) -> void:
	var d := Decal.new()
	d.texture_albedo = _cache["hole"]
	var s := randf_range(0.035, 0.05) if mat != "wood" else randf_range(0.03, 0.04)
	if mat == "dirt":
		s *= 2.0
	d.size = Vector3(s, 0.06, s)
	d.cull_mask = FLOOR_LAYER
	d.normal_fade = 0.5
	d.modulate = Color(1, 1, 1, 0.95)
	add_child(d)
	var y := normal.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	d.global_transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, randf() * TAU), pos)
	_holes.append(d)
	if _holes.size() > MAX_HOLES:
		var old = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## Rana postrzałowa na części ciała: mały otwór wlotowy, większy poszarpany wylot, plama krwi
## wsiąkająca w mundur. Zwraca węzeł rany (kapanie krwi).
func bullet_wound(seg: Node3D, pos: Vector3, normal: Vector3, size: float, exit: bool) -> Node3D:
	var y := normal.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var basis := Basis(x, y, x.cross(y)).rotated(y, randf() * TAU)
	var splats: Array = _cache["splats"]
	var sp: Array = splats[randi() % splats.size()]
	var soak := Decal.new()
	soak.texture_albedo = sp[0]
	soak.texture_normal = sp[1]
	soak.texture_orm = _cache["orm"]
	var ss := (0.07 if not exit else 0.12) + size * 4.0
	soak.size = Vector3(ss, 0.1, ss * randf_range(0.8, 1.3))
	soak.cull_mask = BODY_LAYER
	soak.normal_fade = 0.3
	seg.add_child(soak)
	soak.global_transform = Transform3D(basis, pos)
	var wounds: Array = _cache["wounds"]
	var wp: Array = wounds[randi() % wounds.size()]
	var d := Decal.new()
	d.texture_albedo = wp[0]
	d.texture_normal = wp[1]
	d.texture_orm = _cache["orm"]
	var l := (0.018 if not exit else 0.045) + size * (1.5 if not exit else 4.0)
	d.size = Vector3(l, 0.06, l * 0.8)
	d.cull_mask = BODY_LAYER
	d.normal_fade = 0.35
	seg.add_child(d)
	d.global_transform = Transform3D(basis, pos)
	return d


## Krew z rany wylotowej rozbryzgnięta na ścianie za trafionym.
func wall_splatter(from: Vector3, dir: Vector3, amount: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.5, FLOOR_LAYER)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var splats: Array = _cache["splats"]
	var pair: Array = splats[randi() % splats.size()]
	var d := Decal.new()
	d.texture_albedo = pair[0]
	d.texture_normal = pair[1]
	d.texture_orm = _cache["orm"]
	var dist := from.distance_to(r["position"])
	var s := (0.25 + dist * 0.25) * amount
	d.size = Vector3(s, 0.15, s * randf_range(0.7, 1.4))
	d.cull_mask = FLOOR_LAYER
	add_child(d)
	var y: Vector3 = r["normal"]
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	d.global_transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, randf() * TAU), r["position"])
	_decals.append(d)


# ---------------------------------------------------------------- strzał: łuski, dym

const MAX_SHELLS := 60
var _shells: Array = []          # [MeshInstance3D, vel, spin, floor_y, life]
var _shell_mesh: Dictionary = {}
var _brass: StandardMaterial3D
var _smoke_n := 0


## Wyrzucona łuska (mosiądz; śrut: czerwona plastikowa).
func eject_shell(pos: Vector3, vel: Vector3, cal: String) -> void:
	if not _shell_mesh.has(cal):
		var c := CylinderMesh.new()
		var dims := {"9x19": [0.0049, 0.019], "5.56x45": [0.0048, 0.045], "7.62x39": [0.0056, 0.039],
			"7.62x51": [0.006, 0.051], "12ga": [0.0105, 0.065], "5.45x39": [0.005, 0.039],
			"50ae": [0.0068, 0.033], "338lm": [0.0074, 0.069], "357": [0.0048, 0.033]}
		var d: Array = dims.get(cal, [0.005, 0.03])
		c.top_radius = d[0] * 0.85
		c.bottom_radius = d[0]
		c.height = d[1]
		c.radial_segments = 8
		c.rings = 1
		_shell_mesh[cal] = c
	if _brass == null:
		_brass = StandardMaterial3D.new()
		_brass.albedo_color = Color(0.86, 0.66, 0.3)
		_brass.metallic = 0.9
		_brass.roughness = 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = _shell_mesh[cal]
	if cal == "12ga":
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.6, 0.08, 0.06)
		red.roughness = 0.5
		mi.material_override = red
	else:
		mi.material_override = _brass
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 3.0, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var fy: float = (r["position"] as Vector3).y if not r.is_empty() else pos.y - 1.5
	_shells.append([mi, vel, Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(-30, 30)), fy, 6.0, false])
	while _shells.size() > MAX_SHELLS:
		var old: Array = _shells.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Node).queue_free()


func _tick_shells(dt: float) -> void:
	for i in range(_shells.size() - 1, -1, -1):
		var s: Array = _shells[i]
		var mi := s[0] as MeshInstance3D
		s[4] = float(s[4]) - dt
		if not is_instance_valid(mi) or float(s[4]) <= 0.0:
			if is_instance_valid(mi):
				mi.queue_free()
			_shells.remove_at(i)
			continue
		if s[5]:
			continue   # leży
		var v: Vector3 = s[1]
		v.y -= GRAVITY * dt
		var p := mi.global_position + v * dt
		mi.rotation += (s[2] as Vector3) * dt
		if p.y <= float(s[3]) + 0.006:
			p.y = float(s[3]) + 0.006
			if absf(v.y) > 1.2:
				v = Vector3(v.x * 0.4, -v.y * 0.3, v.z * 0.4)
				s[2] = (s[2] as Vector3) * 0.5
				if randf() < 0.6:
					play("click", p, -22.0, 0.3, 2.4, 2.0)
			else:
				s[5] = true
				mi.rotation = Vector3(PI * 0.5, randf() * TAU, 0)
		s[1] = v
		mi.global_position = p


## Dym z lufy: kilka szarych kłębów unoszących się powoli.
func muzzle_smoke(pos: Vector3, dir: Vector3, amount := 1.0) -> void:
	if _smoke_n > 24:
		return
	_smoke_n += 1
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = int(4 * amount) + 2
	p.lifetime = 1.6
	p.explosiveness = 0.9
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = dir
	m.spread = 20.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 2.2
	m.gravity = Vector3(0, 0.35, 0)
	m.damping_min = 2.5
	m.damping_max = 4.0
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.scale_curve = _mist_curve
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.74, 0.72, 0.35))
	g.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	if not _impact_mats.has("smoke"):
		var mm := _mist_mat.duplicate() as StandardMaterial3D
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_impact_mats["smoke"] = mm
	q.material = _impact_mats["smoke"]
	p.draw_pass_1 = q
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.9).timeout.connect(func():
		_smoke_n -= 1
		p.queue_free())


# ---------------------------------------------------------------- wybuch

## Wybuch (rozbity samolot): kula ognia, błysk, kłęby czarnego dymu, odłamki iskier, huk.
func explosion(pos: Vector3, size := 1.0) -> void:
	play("boom", pos, 10.0, 0.08, 1.0, 60.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 12.0 * size
	light.omni_range = 30.0 * size
	add_child(light)
	light.global_position = pos + Vector3(0, 1.5, 0)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.9)
	tw.tween_callback(light.queue_free)
	_burst(pos, 60, 0.9, 4.0 * size, 14.0 * size, Vector3(0, 2.0, 0), [Color(1.0, 0.85, 0.45, 1.0), Color(1.0, 0.35, 0.05, 0.9), Color(0.15, 0.1, 0.08, 0.0)], 1.2 * size, true)
	_burst(pos, 40, 4.5, 1.0 * size, 6.0 * size, Vector3(0, 1.8, 0), [Color(0.12, 0.11, 0.1, 0.85), Color(0.25, 0.24, 0.23, 0.5), Color(0.3, 0.3, 0.3, 0.0)], 2.6 * size, false)
	_burst(pos, 50, 1.6, 8.0 * size, 26.0 * size, Vector3(0, -9.8, 0), [Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.4, 0.1, 1.0), Color(0.5, 0.1, 0.0, 0.0)], 0.08, true)


## Lej po wybuchu: ciemna, osmalona plama na ziemi.
func crater(pos: Vector3) -> void:
	var d := Decal.new()
	d.texture_albedo = _cache["dot"]
	d.modulate = Color(0.05, 0.04, 0.035, 0.95)
	d.size = Vector3(7.0, 3.0, 7.0)
	d.cull_mask = FLOOR_LAYER
	add_child(d)
	d.global_position = pos
	d.rotation.y = randf() * TAU
	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _burst(pos: Vector3, amount: int, life: float, v0: float, v1: float, grav: Vector3, cols: Array, size: float, add: bool) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 60, 80))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 90.0
	m.initial_velocity_min = v0
	m.initial_velocity_max = v1
	m.gravity = grav
	m.damping_min = 1.0
	m.damping_max = 3.0
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.scale_curve = _mist_curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray(cols)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var key := "boom_add" if add else "boom_smoke"
	if not _impact_mats.has(key):
		var mm := _mist_mat.duplicate() as StandardMaterial3D
		if add:
			mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_impact_mats[key] = mm
	q.material = _impact_mats[key]
	p.draw_pass_1 = q
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
