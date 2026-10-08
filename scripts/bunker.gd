extends Node3D
## Podziemne schrony połączone tunelami (14 m pod ziemią). Trzy wejścia — przy zachodniej bramie bazy,
## przy wiosce i na południe od lotniska: betonowa pochylnia schodzi w głąb (otwór w Terrain3D nad nią),
## na dole główna sala schronu i korytarze łączące wszystkie wejścia. Schron chroni przed wybuchem
## atomowym (nuke.gd sprawdza `underground()`).
## Korytarze są na siatce komórek CELL × CELL: podłoga i strop w każdej komórce, ściana tam, gdzie
## sąsiednia komórka jest pusta — skrzyżowania i sale składają się same.

const CELL := 4.0
const FLOOR := -14.0
const H := 4.0                  # wysokość korytarza
const RAMP_CELLS := 8           # pochylnia: 32 m na 14 m spadku (~24°)

# prostokąty komórek [x0, z0, x1, z1] w metrach (wielokrotności CELL)
const AREAS := [
	[-200, -56, -172, -24],     # główna sala schronu
	[-188, -24, -184, 164],     # korytarz na północ (pod wioskę)
	[-188, -140, -184, -56],    # korytarz na południe
	[-188, -140, 300, -136],    # korytarz na wschód (pod bazą, do lotniska)
	[296, -140, 300, -136],
]
# pochylnie: [komórka dolna (x, z — róg), kierunek w górę (dx, dz)], drzwi na górnym końcu
const RAMPS := [
	[Vector2i(-188, 160), Vector2i(1, 0), "SCHRON — WIOSKA"],
	[Vector2i(-176, -44), Vector2i(1, 0), "SCHRON — BAZA"],
	[Vector2i(296, -140), Vector2i(0, 1), "SCHRON — LOTNISKO"],
]

static var _cells := {}         # Vector2i(komórka) -> true (dla underground())

var _st: SurfaceTool
var _floor_st: SurfaceTool
var _col := PackedVector3Array()
var _ramp_open := {}            # [komórka, kierunek] -> brak ściany (wylot pochylni)


## Czy punkt jest w schronie (pod ziemią, w obrysie korytarzy) — fala i błysk tam nie docierają.
static func underground(p: Vector3) -> bool:
	if p.y > FLOOR + H + 1.0:
		return false
	return _cells.has(Vector2i(floori(p.x / CELL), floori(p.z / CELL)))


## Obrysy pochylni na ziemi (bez trawy nad nimi).
static func ramp_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Array in RAMPS:
		var b: Vector2i = r[0]
		var d: Vector2i = r[1]
		var a := Vector2(b.x, b.y) + Vector2(d) * CELL
		var e := a + Vector2(d) * RAMP_CELLS * CELL + Vector2(absi(d.y), absi(d.x)) * CELL
		out.append(Rect2(a, Vector2.ZERO).expand(e).grow(1.0))
	return out


func build(t3d, level) -> void:
	_cells.clear()
	for a: Array in AREAS:
		var x := int(a[0])
		while x < int(a[2]):
			var z := int(a[1])
			while z < int(a[3]):
				_cells[Vector2i(floori(x / CELL), floori(z / CELL))] = true
				z += int(CELL)
			x += int(CELL)
	var conc := StandardMaterial3D.new()
	conc.albedo_texture = load("res://assets/village/kerala/c_concrete.png")
	conc.normal_enabled = true
	conc.normal_texture = load("res://assets/village/kerala/n_concrete.png")
	conc.uv1_triplanar = true
	conc.uv1_scale = Vector3(0.3, 0.3, 0.3)
	conc.roughness = 0.92
	conc.cull_mode = BaseMaterial3D.CULL_DISABLED
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_texture = load("res://assets/village/kerala/c_concrete.png")
	floor_m.uv1_triplanar = true
	floor_m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	floor_m.albedo_color = Color(0.6, 0.6, 0.58)
	floor_m.roughness = 0.95
	floor_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_floor_st = SurfaceTool.new()
	_floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: Array in RAMPS:
		var c: Vector2i = r[0]
		var d: Vector2i = r[1]
		_ramp_open[[Vector2i(floori(c.x / CELL), floori(c.y / CELL)), d]] = true
		_cells[Vector2i(floori(c.x / CELL), floori(c.y / CELL))] = true
	for k: Vector2i in _cells:
		_cell(k)
	for r: Array in RAMPS:
		_ramp(r[0], r[1], r[2], t3d, level, conc)
	_st.generate_normals()
	_floor_st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = _st.commit()
	mi.material_override = conc
	add_child(mi)
	var fi := MeshInstance3D.new()
	fi.mesh = _floor_st.commit()
	fi.material_override = floor_m
	add_child(fi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("mat", "concrete")
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(_col)
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	_lights()
	_furnish(conc)
	if t3d:
		t3d.data.update_maps(1, true, false)
		t3d.collision.build()


# ---------------------------------------------------------------- geometria

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# a-b-c-d przeciwnie do wskazówek patrząc od strony widocznej
	for p: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(p)
		_col.append(p)


func _cell(k: Vector2i) -> void:
	var x0 := k.x * CELL
	var z0 := k.y * CELL
	var x1 := x0 + CELL
	var z1 := z0 + CELL
	var f := FLOOR
	var c := FLOOR + H
	_quad(_floor_st, Vector3(x0, f, z0), Vector3(x1, f, z0), Vector3(x1, f, z1), Vector3(x0, f, z1))
	_quad(_st, Vector3(x0, c, z0), Vector3(x0, c, z1), Vector3(x1, c, z1), Vector3(x1, c, z0))
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _cells.has(k + d) or _ramp_open.has([k, d]):
			continue
		var p0: Vector3
		var p1: Vector3
		if d.x == 1:
			p0 = Vector3(x1, 0, z1); p1 = Vector3(x1, 0, z0)
		elif d.x == -1:
			p0 = Vector3(x0, 0, z0); p1 = Vector3(x0, 0, z1)
		elif d.y == 1:
			p0 = Vector3(x0, 0, z1); p1 = Vector3(x1, 0, z1)
		else:
			p0 = Vector3(x1, 0, z0); p1 = Vector3(x0, 0, z0)
		_quad(_st, Vector3(p0.x, f, p0.z), Vector3(p0.x, c, p0.z), Vector3(p1.x, c, p1.z), Vector3(p1.x, f, p1.z))


## Pochylnia od komórki dolnej w kierunku d: podłoga wznosi się do poziomu terenu przy drzwiach,
## strop równoległy; nad ziemią wystaje betonowy klin z wejściem. Teren nad nią dostaje otwór.
func _ramp(bottom: Vector2i, d: Vector2i, label: String, t3d, level, conc: Material) -> void:
	var dir := Vector3(d.x, 0, d.y)
	var side := Vector3(-d.y, 0, d.x)                     # w prawo od kierunku w górę
	var start := Vector3(bottom.x + CELL * 0.5, 0, bottom.y + CELL * 0.5) + dir * CELL * 0.5   # koniec komórki dolnej
	var L := RAMP_CELLS * CELL
	var top := start + dir * L
	var gy := 0.0
	if t3d:
		gy = maxf(t3d.data.get_height(top), 0.0)
	var w := CELL * 0.5
	var steps := 16
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var a := start + dir * L * t0
		var b := start + dir * L * t1
		var fa := lerpf(FLOOR, gy + 0.05, t0)
		var fb := lerpf(FLOOR, gy + 0.05, t1)
		var ca := fa + H
		var cb := fb + H
		# podłoga, strop, ściany
		_quad(_floor_st, a - side * w + Vector3.UP * fa, b - side * w + Vector3.UP * fb, b + side * w + Vector3.UP * fb, a + side * w + Vector3.UP * fa)
		_quad(_st, a - side * w + Vector3.UP * ca, a + side * w + Vector3.UP * ca, b + side * w + Vector3.UP * cb, b - side * w + Vector3.UP * cb)
		for sgn: float in [-1.0, 1.0]:
			var s := side * w * sgn
			if sgn > 0.0:
				_quad(_st, a + s + Vector3.UP * fa, a + s + Vector3.UP * ca, b + s + Vector3.UP * cb, b + s + Vector3.UP * fb)
			else:
				_quad(_st, b + s + Vector3.UP * fb, b + s + Vector3.UP * cb, a + s + Vector3.UP * ca, a + s + Vector3.UP * fa)
	# klin nad ziemią: dach i ściany boczne już są (strop pochylni), dodaj ścianę czołową nad wejściem
	var tc := gy + 0.05 + H
	var wall_top := tc + 0.6
	_quad(_st, top + side * w + Vector3.UP * (tc - 0.4), top + side * w + Vector3.UP * wall_top, top - side * w + Vector3.UP * wall_top, top - side * w + Vector3.UP * (tc - 0.4))
	# napis i lampa nad wejściem
	var lab := Label3D.new()
	lab.text = label
	lab.font_size = 64
	lab.pixel_size = 0.01
	lab.modulate = Color(1.0, 0.85, 0.2)
	lab.outline_size = 12
	lab.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(lab)
	lab.global_position = top + Vector3.UP * (wall_top + 1.2)
	var ll := OmniLight3D.new()
	ll.light_color = Color(1.0, 0.8, 0.5)
	ll.light_energy = 1.5
	ll.omni_range = 9.0
	add_child(ll)
	ll.global_position = top - dir * 2.0 + Vector3.UP * (gy + 3.2)
	# otwór w terenie nad pochylnią (tam, gdzie strop pochylni jest nad ziemią albo tuż pod nią)
	if t3d:
		var st: float = t3d.vertex_spacing
		var u := 0.0
		while u <= L - 0.6:
			var v := -w + 0.3
			while v <= w - 0.3:
				var p := start + dir * u + side * v
				var floor_here := lerpf(FLOOR, gy + 0.05, clampf(u / L, 0.0, 1.0))
				if floor_here + H > t3d.data.get_height(p) - 2.5:
					t3d.data.set_control_hole(p, true)
				v += st * 0.5
			u += st * 0.5
	if level and level.get("no_grass") != null:
		var r := Rect2(Vector2(minf(start.x, top.x), minf(start.z, top.z)), Vector2.ZERO).expand(Vector2(maxf(start.x, top.x), maxf(start.z, top.z)))
		level.no_grass.append(r.grow(CELL))


func _lights() -> void:
	var lamp_m := StandardMaterial3D.new()
	lamp_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_m.albedo_color = Color(1.0, 0.9, 0.7)
	var n := 0
	for k: Vector2i in _cells:
		if (k.x + k.y) % 4 != 0:
			continue
		n += 1
		var p := Vector3((k.x + 0.5) * CELL, FLOOR + H - 0.05, (k.y + 0.5) * CELL)
		var lm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.06, 0.5)
		lm.mesh = bm
		lm.material_override = lamp_m
		lm.position = p
		add_child(lm)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 1.2
		l.omni_range = 10.0
		l.position = p + Vector3.DOWN * 0.4
		add_child(l)


## Sala schronu: prycze, skrzynie z zapasami, napis.
func _furnish(conc: Material) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.27, 0.18)
	wood.roughness = 0.9
	var body := StaticBody3D.new()
	add_child(body)
	for i in 5:
		var p := Vector3(-198.0 + 0.9, FLOOR + 0.45, -54.0 + i * 6.0)
		_box(body, Vector3(1.8, 0.15, 0.9), p, wood)
		_box(body, Vector3(1.8, 0.15, 0.9), p + Vector3(0, 1.1, 0), wood)
	for i in 4:
		_box(body, Vector3(1.0, 1.0, 1.0), Vector3(-174.0, FLOOR + 0.5, -52.0 + i * 1.3), wood)
	var lab := Label3D.new()
	lab.text = "SCHRON PRZECIWATOMOWY"
	lab.font_size = 72
	lab.pixel_size = 0.008
	lab.modulate = Color(0.95, 0.9, 0.3)
	lab.position = Vector3(-199.9 + 0.05, FLOOR + 2.8, -40.0)
	lab.rotation.y = PI * 0.5
	add_child(lab)


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
