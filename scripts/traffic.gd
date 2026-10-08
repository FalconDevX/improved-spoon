extends AnimatableBody3D
## Ruch uliczny wioski (village.gd): osobówki, riksze (autorickshaw) i ciężarówki jeżdżą lewym pasem
## po sieci ulic, na skrzyżowaniach skręcają losowo (bez zawracania), zwalniają przed zakrętem.
## Przed przeszkodą (człowiek, inne auto, pojazd gracza) hamują i trąbią. Kule je niszczą: dym,
## wybuch, wrak znika i auto pojawia się znowu w innym miejscu.

const FX = preload("res://scripts/fx.gd")
const LANE := 2.6               # odsunięcie od osi ulicy (ruch lewostronny)
const SPEEDS := {"car": 11.0, "rickshaw": 7.5, "truck": 8.5}
const HP := {"car": 60.0, "rickshaw": 30.0, "truck": 110.0}
const COLORS := [Color(0.85, 0.85, 0.82), Color(0.15, 0.15, 0.17), Color(0.6, 0.1, 0.1), Color(0.15, 0.3, 0.6),
	Color(0.55, 0.55, 0.58), Color(0.85, 0.75, 0.3)]

var village
var kind := "car"
var from := 0
var to := 1
var progress := 0.0             # 0..1 wzdłuż odcinka from -> to
var hp := 60.0
var destroyed := false
var _speed := 0.0
var _horn_t := 0.0
var _wreck_t := 0.0
var _heading := 0.0
var _blocked_t := 0.0           # długo stoi (np. dwa auta naprzeciw na skrzyżowaniu): rusza powoli
var _body_mat: StandardMaterial3D
var _parts: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("traffic")
	collision_layer = 32
	collision_mask = 0
	sync_to_physics = true
	set_meta("mat", "metal")
	set_meta("hollow", 0.002)
	hp = HP[kind]
	_build()
	var a: Vector3 = village.nodes[from]
	var b: Vector3 = village.nodes[to]
	global_position = _lane_pos(a, b, progress)
	_heading = atan2(-(b - a).x, -(b - a).z)
	rotation.y = _heading


func _lane_pos(a: Vector3, b: Vector3, t: float) -> Vector3:
	var d := (b - a).normalized()
	var left := Vector3(d.z, 0, -d.x)
	return a.lerp(b, t) + left * LANE


# ---------------------------------------------------------------- model (proste bryły)

func _mat(c: Color, metal := 0.3, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	_parts.append(mi)
	return mi


func _wheel(pos: Vector3, r: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.22
	mi.mesh = cm
	mi.material_override = _mat(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	mi.rotation.z = PI * 0.5
	mi.position = pos
	add_child(mi)
	_parts.append(mi)


func _build() -> void:
	var glass := _mat(Color(0.12, 0.16, 0.2), 0.6, 0.1)
	var size := Vector3(1.8, 1.5, 4.3)
	match kind:
		"rickshaw":
			# autoriksza: żółty dach, czarny dół, trzy koła
			_body_mat = _mat(Color(0.15, 0.15, 0.12))
			_box(Vector3(1.3, 0.7, 2.5), Vector3(0, 0.6, 0), _body_mat)
			_box(Vector3(1.35, 0.08, 2.0), Vector3(0, 1.75, 0.15), _mat(Color(0.95, 0.8, 0.1)))
			_box(Vector3(1.3, 0.85, 0.06), Vector3(0, 1.3, -0.95), glass)
			for x in [-0.6, 0.6]:
				_box(Vector3(0.06, 0.8, 0.06), Vector3(x, 1.35, 1.1), _body_mat)
			_wheel(Vector3(0, 0.25, -1.0), 0.25)
			_wheel(Vector3(-0.6, 0.25, 0.85), 0.25)
			_wheel(Vector3(0.6, 0.25, 0.85), 0.25)
			size = Vector3(1.4, 1.8, 2.6)
		"truck":
			_body_mat = _mat(Color(0.25, 0.45, 0.75))
			_box(Vector3(2.2, 1.7, 1.8), Vector3(0, 1.45, -2.2), _body_mat)
			_box(Vector3(2.1, 0.7, 0.05), Vector3(0, 1.85, -3.12), glass)
			_box(Vector3(2.3, 1.8, 4.2), Vector3(0, 1.75, 0.9), _mat(Color(0.75, 0.55, 0.2), 0.1, 0.8))
			_box(Vector3(2.0, 0.4, 6.6), Vector3(0, 0.6, -0.1), _mat(Color(0.12, 0.12, 0.12)))
			for z in [-2.4, 1.0, 2.4]:
				for x in [-1.0, 1.0]:
					_wheel(Vector3(x, 0.45, z), 0.45)
			size = Vector3(2.3, 2.7, 6.8)
		_:
			_body_mat = _mat(COLORS[randi() % COLORS.size()])
			_box(Vector3(1.75, 0.65, 4.2), Vector3(0, 0.65, 0), _body_mat)
			_box(Vector3(1.6, 0.55, 2.2), Vector3(0, 1.25, 0.2), _body_mat)
			_box(Vector3(1.5, 0.45, 0.05), Vector3(0, 1.25, -0.91), glass)
			_box(Vector3(1.5, 0.45, 0.05), Vector3(0, 1.25, 1.31), glass)
			for z in [-1.35, 1.35]:
				for x in [-0.85, 0.85]:
					_wheel(Vector3(x, 0.32, z), 0.32)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)


# ---------------------------------------------------------------- jazda

func _physics_process(dt: float) -> void:
	if destroyed:
		_wreck_t += dt
		if _wreck_t > 40.0:
			_respawn()
		return
	var a: Vector3 = village.nodes[from]
	var b: Vector3 = village.nodes[to]
	var seg := a.distance_to(b)
	var remain := (1.0 - progress) * seg
	# prędkość docelowa: wolniej przed skrzyżowaniem, stop przed przeszkodą
	var vmax: float = SPEEDS[kind]
	var target := vmax * clampf(remain / 25.0, 0.35, 1.0)
	var block := _obstacle(_blocked_t < 4.0)
	_blocked_t = _blocked_t + dt if block < 6.0 else 0.0
	if _blocked_t > 6.0:
		_blocked_t = 0.0
	if block < 9.0:
		target = 0.0 if block < 6.0 else 2.0
		_horn_t -= dt
		if _horn_t <= 0.0 and block < 6.0 and randf() < 0.3:
			_horn_t = randf_range(3.0, 6.0)
			FX.I.play("click", global_position, 6.0, 0.0, 0.5, 30.0)
	_speed = move_toward(_speed, target, (6.0 if target < _speed else 2.5) * dt)
	progress += _speed * dt / maxf(seg, 0.1)
	if progress >= 1.0:
		var n: int = village.next_node(from, to)
		from = to
		to = n
		progress = 0.0
		a = village.nodes[from]
		b = village.nodes[to]
	var p := _lane_pos(a, b, progress)
	var dir := b - a
	var want := atan2(-dir.x, -dir.z)
	_heading = lerp_angle(_heading, want, 1.0 - exp(-4.0 * dt))
	global_transform = Transform3D(Basis(Vector3.UP, _heading), Vector3(p.x, 0.02, p.z))


## Odległość do najbliższej przeszkody przed maską (ludzie, auta, pojazdy graczy).
func _obstacle(with_traffic := true) -> float:
	var fwd := -global_basis.z
	var best := INF
	var list := get_tree().get_nodes_in_group("soldier") + get_tree().get_nodes_in_group("car")
	if with_traffic:
		list += get_tree().get_nodes_in_group("traffic")
	for n in list:
		if n == self or not is_instance_valid(n) or n.get("down") == true:
			continue
		var to_n: Vector3 = n.global_position - global_position
		to_n.y = 0.0
		var d := to_n.length()
		if d > 14.0:
			continue
		var ahead := to_n.dot(fwd)
		if ahead > 0.0 and absf(to_n.dot(Vector3(fwd.z, 0, -fwd.x))) < 2.4:
			best = minf(best, ahead)
	return best


# ---------------------------------------------------------------- uszkodzenia

func bullet_struck(_shooter, energy: float, _at: Vector3) -> void:
	_damage(clampf(sqrt(energy) / 8.0, 0.3, 25.0))


func _damage(d: float) -> void:
	if destroyed:
		return
	hp -= d
	if hp <= 0.0:
		destroyed = true
		_speed = 0.0
		_wreck_t = 0.0
		FX.I.explosion(global_position + Vector3(0, 0.8, 0), 0.8)
		var burnt := _mat(Color(0.05, 0.045, 0.04), 0.1, 0.95)
		for mi in _parts:
			mi.material_override = burnt


func _respawn() -> void:
	destroyed = false
	hp = HP[kind]
	for mi in _parts:
		mi.queue_free()
	_parts.clear()
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	_build()
	var e: Array = village.random_edge()
	from = e[0]
	to = e[1]
	progress = 0.0
