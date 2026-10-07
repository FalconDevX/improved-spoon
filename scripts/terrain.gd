extends Node3D
## Świat wokół bazy: teren 3,2 × 3,2 km. Baza (240 × 240 m) i lotnisko leżą na płaskim dnie doliny
## ciągnącej się ze wschodu na zachód; dalej pagórki, a na krańcach góry (do ~450 m) z lasem na
## zboczach, skałami na stromiznach i śniegiem na szczytach. Pas startowy biegnie z lotniska na
## wschód, przy nim hangary. Wysokość terenu: height(x, z) — z niej siatka, kolizja, las i mapa.

const WORLD := 1600.0              # połowa boku świata [m]
const GRID := 256                  # komórek siatki na bok (12,5 m)
const BASE := 135.0                # płaski kwadrat bazy (z zapasem za murem)
const VALLEY_C := Vector2(250, 0)  # środek doliny (przesunięty na wschód, wzdłuż pasa)
const VALLEY_R := Vector2(760, 280)
const RUNWAY := Rect2(18, -14, 860, 50)   # beton: płyta lotniska i pas startowy na wschód
const HANGARS := [Vector2(170, -62), Vector2(215, -62), Vector2(260, -62)]

static var _hills: FastNoiseLite
static var _ridge: FastNoiseLite
static var _forest: FastNoiseLite

var body: StaticBody3D
var map_img: Image               # mapa z góry (cieniowanie terenu, las, pas) — duża mapa [M]
var _level


static func _noise() -> void:
	if _hills != null:
		return
	_hills = FastNoiseLite.new()
	_hills.seed = 77
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0045
	_hills.fractal_octaves = 4
	_ridge = FastNoiseLite.new()
	_ridge.seed = 1234
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.frequency = 0.0016
	_ridge.fractal_octaves = 5
	_forest = FastNoiseLite.new()
	_forest.seed = 99
	_forest.frequency = 0.004


## Jak daleko od osi doliny (1 = brzeg płaskiego dna).
static func valley(x: float, z: float) -> float:
	var vx := (x - VALLEY_C.x) / VALLEY_R.x
	var vz := (z - VALLEY_C.y) / VALLEY_R.y
	return sqrt(vx * vx + vz * vz)


static func height(x: float, z: float) -> float:
	_noise()
	var v := valley(x, z)
	# pagórki: tylko poza bazą i z dala od pasa
	var base_d := maxf(absf(x) - BASE, absf(z) - BASE)
	var rw := RUNWAY.grow(30.0)
	var rw_d := maxf(maxf(rw.position.x - x, x - rw.end.x), maxf(rw.position.y - z, z - rw.end.y))
	var keep := smoothstep(0.0, 60.0, base_d) * smoothstep(0.0, 50.0, rw_d)
	var h := maxf(_hills.get_noise_2d(x, z) * 16.0 + 4.0, 0.0) * keep
	# góry wokół doliny, coraz wyższe ku krańcom świata
	var m := smoothstep(0.85, 1.75, v)
	h += m * (35.0 + 300.0 * (_ridge.get_noise_2d(x, z) * 0.5 + 0.5))
	h += smoothstep(1.6, 2.6, v) * 120.0
	return h


func build(level) -> void:
	_level = level
	_noise()
	_build_ground()
	_build_forest()
	_build_hangars()
	_build_map_image()


# ---------------------------------------------------------------- teren

func _build_ground() -> void:
	var n := GRID + 1
	var step := WORLD * 2.0 / GRID
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = height(-WORLD + i * step, -WORLD + j * step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var hl := hs[j * n + maxi(i - 1, 0)]
			var hr := hs[j * n + mini(i + 1, n - 1)]
			var hd := hs[maxi(j - 1, 0) * n + i]
			var hu := hs[mini(j + 1, n - 1) * n + i]
			verts[j * n + i] = Vector3(-WORLD + i * step, hs[j * n + i], -WORLD + j * step)
			norms[j * n + i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
	var idx := PackedInt32Array()
	for j in GRID:
		for i in GRID:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _level.ground_material()
	mi.extra_cull_margin = 50.0
	add_child(mi)
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("mat", "dirt")
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------- las

func _pine() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [[0.25, 0.25, 2.2, 1.1, Color(0.22, 0.15, 0.09)], [2.4, 0.0, 4.5, 3.6, Color(0.05, 0.1, 0.05)],
		[1.9, 0.0, 3.8, 5.6, Color(0.06, 0.12, 0.055)], [1.3, 0.0, 3.0, 7.5, Color(0.07, 0.14, 0.06)]]
	for p: Array in parts:
		var c := CylinderMesh.new()
		c.bottom_radius = p[0]
		c.top_radius = p[1]
		c.height = p[2]
		c.radial_segments = 7
		c.rings = 1
		var tmp := SurfaceTool.new()
		tmp.create_from(c, 0)
		var arrays := tmp.commit_to_arrays()
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for k in ix:
			st.set_color(p[4])
			st.set_normal(ns[k])
			st.add_vertex(vs[k] + Vector3(0, p[3], 0))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	return mesh


func _leafy() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.bottom_radius = 0.3
	trunk.top_radius = 0.2
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 1
	var crown := SphereMesh.new()
	crown.radius = 2.8
	crown.height = 4.6
	crown.radial_segments = 8
	crown.rings = 5
	for p: Array in [[trunk, Vector3(0, 1.5, 0), Color(0.22, 0.16, 0.1)], [crown, Vector3(0, 4.6, 0), Color(0.1, 0.16, 0.06)]]:
		var tmp := SurfaceTool.new()
		tmp.create_from(p[0], 0)
		var arrays := tmp.commit_to_arrays()
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for k in ix:
			st.set_color(p[2])
			st.set_normal(ns[k])
			st.add_vertex(vs[k] + p[1])
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	return mesh


## Czy w tym miejscu może rosnąć drzewo (gęstość lasu 0..1).
static func forest_density(x: float, z: float) -> float:
	_noise()
	if absf(x) < BASE + 15.0 and absf(z) < BASE + 15.0:
		return 0.0
	if RUNWAY.grow(45.0).has_point(Vector2(x, z)):
		return 0.0
	for hc: Vector2 in HANGARS:
		if Rect2(hc.x - 25.0, hc.y - 30.0, 50.0, 60.0).has_point(Vector2(x, z)):
			return 0.0   # hangary i plac przed nimi
	var h := height(x, z)
	if h > 330.0:
		return 0.0
	var slope := absf(height(x + 4.0, z) - h) + absf(height(x, z + 4.0) - h)
	if slope > 3.2:
		return 0.0
	var v := valley(x, z)
	var f := _forest.get_noise_2d(x, z) * 0.5 + 0.5
	# las na zboczach doliny i pas lasu wokół lotniska / bazy
	var band := smoothstep(0.7, 0.95, v) * (1.0 - smoothstep(1.9, 2.3, v))
	var ring := 1.0 - smoothstep(0.0, 220.0, Vector2(x - clampf(x, RUNWAY.position.x - 160.0, RUNWAY.end.x), z - clampf(z, -BASE - 20.0, BASE + 20.0)).length())
	return clampf(maxf(band, ring * 0.8) * smoothstep(0.3, 0.6, f) * 1.4, 0.0, 1.0)


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var meshes := [_pine(), _leafy()]
	var cell := 200.0
	var cells := {}
	var spacing := 8.0
	var x := -WORLD + 20.0
	while x < WORLD - 20.0:
		var z := -WORLD + 20.0
		while z < WORLD - 20.0:
			var px := x + rng.randf_range(-3.5, 3.5)
			var pz := z + rng.randf_range(-3.5, 3.5)
			z += spacing
			if rng.randf() > forest_density(px, pz):
				continue
			var hgt := height(px, pz)
			var kind := 0 if (hgt > 60.0 or rng.randf() < 0.55) else 1
			var key := Vector3i(int(floor(px / cell)), int(floor(pz / cell)), kind)
			if not cells.has(key):
				cells[key] = []
			var s := rng.randf_range(0.8, 1.5)
			(cells[key] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), Vector3(px, hgt - 0.3, pz)))
		x += spacing
	var total := 0
	for key: Vector3i in cells:
		var xf: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key.z]
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.visibility_range_end = 1400.0
		mi.visibility_range_end_margin = 100.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
		total += xf.size()
	print("[teren] drzew: ", total)


# ---------------------------------------------------------------- hangary

func _build_hangars() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.42, 0.44, 0.4)
	metal.metallic = 0.5
	metal.roughness = 0.55
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.32, 0.34, 0.3)
	back.roughness = 0.8
	var r := 13.0
	var depth := 34.0
	for c: Vector2 in HANGARS:
		var hb := StaticBody3D.new()
		hb.collision_layer = 1
		hb.collision_mask = 0
		hb.set_meta("mat", "metal")
		hb.set_meta("hollow", 0.003)
		hb.set_meta("size", Vector3(r * 2.0, r, depth))
		hb.position = Vector3(c.x, 0, c.y)
		add_child(hb)
		# łukowy dach: walec wzdłuż osi Z, dolna połowa w ziemi (od środka ściany wnętrza)
		var roof := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = depth
		cm.radial_segments = 24
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		roof.mesh = cm
		var dm := metal.duplicate() as StandardMaterial3D
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		roof.material_override = dm
		roof.rotation.x = PI * 0.5
		hb.add_child(roof)
		# tylna ściana (półkole) i żebra wejścia
		var wall := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = r
		wm.bottom_radius = r
		wm.height = 0.3
		wm.radial_segments = 24
		wall.mesh = wm
		wall.material_override = back
		wall.rotation.x = PI * 0.5
		wall.position.z = -depth * 0.5
		hb.add_child(wall)
		# kolizja: łuk z płyt + tylna ściana (wejście od strony pasa, na południe)
		for k in 9:
			var a := PI * (k + 0.5) / 9.0
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(2.0 * r * sin(PI / 18.0) + 0.3, 0.3, depth)
			cs.shape = bs
			cs.position = Vector3(cos(a) * r, sin(a) * r, 0)
			cs.rotation.z = a + PI * 0.5
			hb.add_child(cs)
		var bw := CollisionShape3D.new()
		var bbs := BoxShape3D.new()
		bbs.size = Vector3(r * 2.0, r, 0.3)
		bw.shape = bbs
		bw.position = Vector3(0, r * 0.5, -depth * 0.5)
		hb.add_child(bw)
		# napis z numerem nad wejściem
		var lab := Label3D.new()
		lab.text = "HANGAR %d" % (HANGARS.find(c) + 1)
		lab.font_size = 160
		lab.pixel_size = 0.011
		lab.modulate = Color(0.9, 0.9, 0.85)
		lab.position = Vector3(0, r * 0.82, depth * 0.5 + 0.2)
		hb.add_child(lab)
		_level.no_grass.append(Rect2(c.x - r, c.y - depth * 0.5, r * 2.0, depth))


# ---------------------------------------------------------------- mapa z góry

## Obraz świata 512 × 512: kolor terenu z cieniowaniem zboczy, las, beton lotniska, baza.
func _build_map_image() -> void:
	var sz := 256
	map_img = Image.create(sz, sz, false, Image.FORMAT_RGB8)
	var step := WORLD * 2.0 / sz
	for j in sz:
		for i in sz:
			var x := -WORLD + (i + 0.5) * step
			var z := -WORLD + (j + 0.5) * step
			var h := height(x, z)
			var hx := height(x + step, z)
			var hz := height(x, z + step)
			var shade := clampf(1.0 + ((h - hx) - (h - hz) * 0.6) * 0.04, 0.65, 1.25)
			var c := Color(0.26, 0.33, 0.18).lerp(Color(0.42, 0.4, 0.3), smoothstep(40.0, 200.0, h))
			c = c.lerp(Color(0.85, 0.87, 0.9), smoothstep(350.0, 420.0, h))
			if forest_density(x, z) > 0.45:
				c = c.lerp(Color(0.12, 0.2, 0.1), 0.6)
			if RUNWAY.has_point(Vector2(x, z)):
				c = Color(0.55, 0.55, 0.52)
			map_img.set_pixel(i, j, c * shade)
