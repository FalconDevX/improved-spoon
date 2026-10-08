extends Node3D
## Tunel drogowy pod skalnym grzbietem na wschód od wioski (grzbiet i wykopy są w mapie wysokości).
## Droga: wschodni koniec obwodnicy wioski -> tunel (x 248..332, z = 212) -> wschodnia część lotniska.
## Betonowa rura z oświetleniem, portale (ściana czołowa), kolizja, otwory w Terrain3D przy wjazdach.

const A := Vector3(247.0, 0.0, 212.0)   # zachodni portal
const B := Vector3(333.0, 0.0, 212.0)   # wschodni portal
const W := 9.0                          # szerokość wnętrza
const H := 6.5                          # wysokość wnętrza
const T := 0.6                          # grubość ścian


func build(t3d) -> void:
	var conc := StandardMaterial3D.new()
	conc.albedo_texture = load("res://assets/village/kerala/c_concrete.png")
	conc.normal_enabled = true
	conc.normal_texture = load("res://assets/village/kerala/n_concrete.png")
	conc.uv1_triplanar = true
	conc.uv1_scale = Vector3(0.25, 0.25, 0.25)
	conc.roughness = 0.9
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = load("res://assets/village/kerala/c_asphalt.png")
	asphalt.uv1_triplanar = true
	asphalt.uv1_scale = Vector3(0.15, 0.15, 0.15)
	asphalt.roughness = 0.95
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("mat", "concrete")
	body.set_meta("size", Vector3(B.x - A.x, H, W))
	add_child(body)
	var len := B.x - A.x
	var c := (A + B) * 0.5
	# rura: podłoga, ściany, strop
	for p: Array in [
			[Vector3(len, 0.2, W), Vector3(c.x, -0.1, c.z), asphalt],
			[Vector3(len, H, T), Vector3(c.x, H * 0.5, c.z - W * 0.5 - T * 0.5), conc],
			[Vector3(len, H, T), Vector3(c.x, H * 0.5, c.z + W * 0.5 + T * 0.5), conc],
			[Vector3(len, T, W + T * 2.0), Vector3(c.x, H + T * 0.5, c.z), conc]]:
		_box(body, p[0], p[1], p[2])
	# portale: ściana czołowa z otworem (osłania brzeg otworu w terenie) + krawędź dachu
	for x: float in [A.x, B.x]:
		var face := 1.0 if x == A.x else -1.0
		for side: float in [-1.0, 1.0]:
			_box(body, Vector3(1.2, H + 9.0, 7.0), Vector3(x - face * 0.6, (H + 9.0) * 0.5, c.z + side * (W * 0.5 + 3.5)), conc)
		_box(body, Vector3(1.2, 9.0, W + 14.0), Vector3(x - face * 0.6, H + 4.5, c.z), conc)
		# napis nad wjazdem
		var lab := Label3D.new()
		lab.text = "TUNEL"
		lab.font_size = 96
		lab.pixel_size = 0.012
		lab.modulate = Color(0.95, 0.85, 0.3)
		lab.position = Vector3(x - face * 1.25, H + 1.6, c.z)
		lab.rotation.y = -PI * 0.5 * face
		add_child(lab)
	# droga: od obwodnicy wioski do tunelu i od tunelu na wschodni kraniec lotniska
	for r: Array in [[Vector3(213.0, 0, 205.5), Vector3(247.0, 0, 218.5)], [Vector3(333.0, 0, 205.5), Vector3(435.0, 0, 218.5)],
			[Vector3(421.0, 0, 42.0), Vector3(435.0, 0, 205.5)]]:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(b.x - a.x, b.z - a.z)
		g.mesh = pm
		g.material_override = asphalt
		g.position = Vector3((a.x + b.x) * 0.5, 0.03, (a.z + b.z) * 0.5)
		add_child(g)
	# oświetlenie co 12 m (lampy w stropie)
	var lamp_m := StandardMaterial3D.new()
	lamp_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_m.albedo_color = Color(1.0, 0.85, 0.55)
	var x2 := A.x + 6.0
	while x2 < B.x - 3.0:
		var lm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.08, 0.35)
		lm.mesh = bm
		lm.material_override = lamp_m
		lm.position = Vector3(x2, H - 0.05, c.z)
		add_child(lm)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.light_energy = 1.6
		l.omni_range = 11.0
		l.shadow_enabled = false
		l.position = Vector3(x2, H - 0.6, c.z)
		add_child(l)
		x2 += 12.0
	# otwory w terenie przy wjazdach: tam, gdzie zbocze wchodzi w światło tunelu
	if t3d:
		var st: float = t3d.vertex_spacing
		var xx := A.x - 2.0
		while xx <= B.x + 2.0:
			var zz := c.z - W * 0.5 - 0.5
			while zz <= c.z + W * 0.5 + 0.5:
				var p := Vector3(xx, 0, zz)
				var h: float = t3d.data.get_height(p)
				if h > 0.15 and h < H + 0.5 and minf(absf(xx - A.x), absf(xx - B.x)) < 5.0:
					t3d.data.set_control_hole(p, true)
				zz += st * 0.5
			xx += st * 0.5
		t3d.data.update_maps(1, true, false)    # TYPE_CONTROL: przebuduj mapę sterującą
		t3d.collision.build()


func _box(body: StaticBody3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)
