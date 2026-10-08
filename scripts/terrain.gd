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
# wioska (village.gd) na południe od bazy: miasto z Kerala City Pack (długością wzdłuż X) z obwodnicą
const VILLAGE_C := Vector2(40, 212)
const VILLAGE_HALF := Vector2(176, 78)
const VILLAGE := Rect2(VILLAGE_C - VILLAGE_HALF, VILLAGE_HALF * 2.0)
const VILLAGE_ROAD := Rect2(-16, 110, 12, 30)       # droga z bramy bazy do wioski
# droga przez tunel pod grzbietem na wschód od wioski (tunnel.gd; wykopy są w mapie wysokości)
const TUNNEL_ROADS := [Rect2(206, 205, 40, 14), Rect2(334, 205, 102, 14), Rect2(420, 40, 16, 179)]

static var _hills: FastNoiseLite
static var _ridge: FastNoiseLite
static var _forest: FastNoiseLite

var body: Node3D                 # ziemia dla promieni (Terrain3D) — porównywana w level.gd / grass.gd
var t3d                          # Terrain3D
# Mapa wysokości (assets/terrain/height.res, obraz float): 2048² próbek co 1,5625 m na środkach pikseli
# ± WORLD, zrobiona z height_proc() + rzeźba gór i erozja wodna (_tmp/hsample.gd -> erode.py -> _tmp/hsave.gd).
# Mapa sterująca Terrain3D (control.res): wszędzie automat (trawa / skała na stokach), śnieg na szczytach.
const HN := 2048
static var _H := PackedFloat32Array()
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


static func _load_h() -> void:
	if not _H.is_empty() or not ResourceLoader.exists("res://assets/terrain/height.res"):
		return
	var img: Image = load("res://assets/terrain/height.res")
	_H = img.get_data().to_float32_array()


## Wysokość terenu (z mapy, interpolacja dwuliniowa jak siatka Terrain3D).
static func height(x: float, z: float) -> float:
	_load_h()
	if _H.is_empty():
		return height_proc(x, z)
	var st := WORLD * 2.0 / HN
	var gx := clampf((x + WORLD) / st, 0.0, HN - 1.001)      # piksel i = punkt -WORLD + i·st (jak w Terrain3D)
	var gz := clampf((z + WORLD) / st, 0.0, HN - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var k := j * HN + i
	var a := lerpf(_H[k], _H[k + 1], fx)
	var b := lerpf(_H[k + HN], _H[k + HN + 1], fx)
	return lerpf(a, b, fz)


## Mapa wysokości jako obraz float (Terrain3D, trawa).
static func height_image() -> Image:
	_load_h()
	return Image.create_from_data(HN, HN, false, Image.FORMAT_RF, _H.to_byte_array())


## Teren z szumu (źródło mapy wysokości: _tmp/hsample.gd -> erode.py -> height.res).
static func height_proc(x: float, z: float) -> float:
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
	# wioska i droga do niej: płasko na poziomie bazy, łagodne zbocza dookoła
	var vd := maxf(absf(x - VILLAGE_C.x) - VILLAGE_HALF.x, absf(z - VILLAGE_C.y) - VILLAGE_HALF.y)
	var rd := maxf(maxf(VILLAGE_ROAD.position.x - x, x - VILLAGE_ROAD.end.x), maxf(VILLAGE_ROAD.position.y - z, z - VILLAGE_ROAD.end.y))
	var flat := 1.0 - smoothstep(6.0, 80.0, minf(vd, rd + 20.0))
	return lerpf(h, 0.0, flat)


func build(level) -> void:
	_level = level
	_noise()
	_build_ground()
	_build_forest()
	_build_hangars()
	_build_map_image()


# ---------------------------------------------------------------- teren

func _build_ground() -> void:
	t3d = ClassDB.instantiate("Terrain3D")
	t3d.name = "Terrain3D"
	t3d.region_size = 1024
	t3d.vertex_spacing = WORLD * 2.0 / HN
	t3d.mesh_size = 48
	t3d.collision_layer = 1
	t3d.collision_mask = 0
	t3d.cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var assets = ClassDB.instantiate("Terrain3DAssets")
	# tekstury ambientCG (CC0): 0 skała (podstawa automatu: stoki, wysoko), 1 trawa (nakładka: płasko),
	# 2 śnieg, 3 ziemia leśna, 4 żwir (koryto rzeki) — mapa sterująca: control.res
	var names := ["rock", "grass", "snow", "dirt", "gravel"]
	var scales := [0.06, 0.12, 0.08, 0.12, 0.2]
	for k in names.size():
		var ta = ClassDB.instantiate("Terrain3DTextureAsset")
		ta.name = names[k]
		ta.albedo_texture = load("res://assets/terrain/%s_alb_ht.png" % names[k])
		ta.normal_texture = load("res://assets/terrain/%s_nrm_rgh.png" % names[k])
		ta.uv_scale = scales[k]
		ta.detiling_rotation = 0.25
		ta.detiling_shift = 0.25
		assets.set_texture(k, ta)
	_rock_assets(assets)
	add_child(t3d)
	t3d.assets = assets                   # po wejściu do drzewa (wtedy powstają materiał i tablice tekstur)
	t3d.material.world_background = 0     # NONE: poza mapą nic
	t3d.material.auto_shader = true
	t3d.material.set_shader_param("auto_slope", 1.2)             # więcej = skała już na łagodniejszych stokach
	t3d.material.set_shader_param("auto_height_reduction", 0.1)  # wyżej coraz więcej skały
	t3d.material.set_shader_param("blend_sharpness", 0.8)
	var h := height_image()
	t3d.data.import_images([h, load("res://assets/terrain/control.res"), null], Vector3(-WORLD, 0, -WORLD), 0.0, 1.0)
	t3d.collision.mode = 3            # FULL_GAME: kolizja na całym terenie (kule, boty daleko od kamery)
	t3d.collision.build()             # z zaimportowanej mapy (przy wejściu do drzewa danych jeszcze nie było)
	t3d.set_meta("mat", "dirt")
	_scatter_rocks()
	_build_river()
	body = t3d
	# baza i lotnisko: płaskie (wysokość 0) — dotychczasowy wygląd ziemi (beton, drogi, oznaczenia pasa)
	for r: Rect2 in [Rect2(-BASE, -BASE, BASE * 2.0, BASE * 2.0), RUNWAY.grow(25.0)]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		mi.mesh = pm
		mi.material_override = _level.ground_material()
		mi.position = Vector3(r.get_center().x, 0.04, r.get_center().y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# ---------------------------------------------------------------- kamienie (instancer Terrain3D)

## Głazy z dema Terrain3D (MIT): trzy kształty, skała tekstury terenu (rzut z trzech stron).
func _rock_assets(assets) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/terrain/rock_alb_ht.png")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/terrain/rock_nrm_rgh.png")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	mat.roughness = 0.9
	for k in 3:
		var ma = ClassDB.instantiate("Terrain3DMeshAsset")
		ma.name = "głaz %d" % k
		ma.scene_file = load("res://assets/terrain/rocks/Rock%s.glb" % ["A", "B", "C"][k])
		ma.material_override = mat
		ma.visibility_range = 500.0
		assets.set_mesh_asset(k, ma)


## Głazy: na stokach i halach (więcej wyżej), drobniejsze w korycie rzeki; nie w bazie, wiosce, przy drogach.
func _scatter_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var xf: Array = [[], [], []]
	for i in 9000:
		var x := rng.randf_range(-WORLD + 20, WORLD - 20)
		var z := rng.randf_range(-WORLD + 20, WORLD - 20)
		var y := height(x, z)
		if y < 2.0 and not _near_river(x, z, 14.0):
			continue
		var p := Vector2(x, z)
		if (absf(x) < BASE + 20 and absf(z) < BASE + 20) or RUNWAY.grow(40).has_point(p) or VILLAGE.grow(25).has_point(p):
			continue
		var ok := true
		for r: Rect2 in TUNNEL_ROADS:
			if r.grow(10).has_point(p):
				ok = false
		if not ok:
			continue
		var slope := absf(height(x + 2, z) - y) + absf(height(x, z + 2) - y)
		if rng.randf() > clampf(0.15 + slope * 0.25 + y / 500.0, 0.0, 0.9):
			continue
		var s := rng.randf_range(0.25, 1.1) * (0.5 if y < 2.0 else 1.0)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s))
		(xf[rng.randi() % 3] as Array).append(Transform3D(b, Vector3(x, y - 0.4 * s, z)))
	for k in 3:
		var arr: Array[Transform3D] = []
		arr.assign(xf[k])
		t3d.instancer.add_transforms(k, arr)


# ---------------------------------------------------------------- rzeka

static var _river: Array = []        # punkty [x, z, poziom wody]


static func river_points() -> Array:
	if _river.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://assets/terrain/river.json"))
		for p in j["points"]:
			_river.append(Vector3(p[0], p[2], p[1]))
	return _river


static func _near_river(x: float, z: float, r: float) -> bool:
	for p: Vector3 in river_points():
		if absf(p.x - x) < r * 4.0 and Vector2(p.x - x, p.z - z).length() < r:
			return true
	return false


## Woda: wstęga wzdłuż koryta (poziom z mapy rzeki), shader z płynącymi falami.
func _build_river() -> void:
	var pts := river_points()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 13.0
	var along := 0.0
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var n := Vector3(-d.z, 0, d.x) * w
		var l := Vector2(b.x - a.x, b.z - a.z).length()
		var v := [[a - n, Vector2(0, along)], [a + n, Vector2(1, along)], [b - n, Vector2(0, along + l / (2.0 * w))], [b + n, Vector2(1, along + l / (2.0 * w))]]
		for k in [0, 1, 2, 1, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[k][1])
			st.add_vertex(v[k][0])
		along += l / (2.0 * w)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WATER
	mat.shader = sh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


const WATER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D depth_tex : hint_depth_texture;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = UV * vec2(4.0, 4.0) - vec2(0.0, TIME * 0.6);
	float e = 0.05;
	float a = n2(uv * 3.0) + 0.5 * n2(uv * 7.0 + 3.0);
	float bx = n2((uv + vec2(e, 0)) * 3.0) + 0.5 * n2((uv + vec2(e, 0)) * 7.0 + 3.0);
	float bz = n2((uv + vec2(0, e)) * 3.0) + 0.5 * n2((uv + vec2(0, e)) * 7.0 + 3.0);
	NORMAL_MAP = normalize(vec3((a - bx) * 4.0, (a - bz) * 4.0, 1.0)) * 0.5 + 0.5;
	// głębokość wody pod powierzchnią: płycizny przejrzyste przy brzegu
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 wp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float depth = clamp((-wp.z / wp.w + VERTEX.z) * 0.5, 0.0, 1.0);
	float edge = smoothstep(0.0, 0.45, abs(UV.x - 0.5) * -2.0 + 1.0);
	ALBEDO = mix(vec3(0.16, 0.22, 0.2), vec3(0.04, 0.09, 0.12), depth);
	ALPHA = clamp(0.35 + depth * 0.6, 0.0, 0.92) * edge;
	ROUGHNESS = 0.05;
	METALLIC = 0.2;
	SPECULAR = 0.8;
}
"""


# ---------------------------------------------------------------- las

# Drzewa liściaste z generatora Tree3D (siatki wygenerowane raz, zapisane w assets/trees):
# 0–3 dęby (~9 m), 4–5 brzozy (~7,5 m). Powierzchnia 0 = pień, 1 = gałązki z liśćmi.
const TREE3D_N := 6
const FOREST_CELL := 80.0    # komórka lasu [m] (zasięgi widoczności liczone od jej środka)
const FOREST_STEP := 6.5     # odstęp siatki, na której losowane są drzewa [m]
const LOD_FULL := 55.0       # do tej odległości pełne drzewo
const LOD_MID := 170.0       # dalej: uproszczony pień; za tym billboard
# bok kwadratu billboardu każdego wariantu (ten sam kadr co w impostors.png, _tmp/impostor.gd)
const IMPOSTOR_S := [9.5, 9.24, 9.4, 9.57, 7.81, 7.83]
static var _tree3d_mid: Array = []
static var _tree3d: Array = []


static func tree3d_meshes() -> Array:
	if not _tree3d.is_empty():
		return _tree3d
	var sh: Shader = load("res://shaders/tree3d.gdshader")
	var bark := ShaderMaterial.new()
	bark.shader = sh
	bark.set_shader_parameter("texture_albedo", load("res://assets/trees/bark.jpg"))
	bark.set_shader_parameter("texture_normal", load("res://assets/trees/bark_normal.jpg"))
	var twig := ShaderMaterial.new()
	twig.shader = sh
	twig.set_shader_parameter("texture_albedo", load("res://assets/trees/twig.png"))
	twig.set_shader_parameter("normal_strength", 0.0)
	twig.set_shader_parameter("roughness", 1.0)
	twig.set_shader_parameter("flutter_strength", 0.03)
	twig.set_shader_parameter("backlight", 0.6)
	twig.set_shader_parameter("tint_color", Color(1.2, 1.25, 1.0))
	for i in TREE3D_N:
		for mid in [false, true]:
			var m: ArrayMesh = load("res://assets/trees/tree3d_%d%s.res" % [i, "_mid" if mid else ""])
			m.surface_set_material(0, bark)
			m.surface_set_material(1, twig)
			(_tree3d_mid if mid else _tree3d).append(m)
	return _tree3d


## Czy w tym miejscu może rosnąć drzewo (gęstość lasu 0..1).
static func forest_density(x: float, z: float) -> float:
	_noise()
	if absf(x) < BASE + 15.0 and absf(z) < BASE + 15.0:
		return 0.0
	if RUNWAY.grow(45.0).has_point(Vector2(x, z)):
		return 0.0
	if VILLAGE.grow(30.0).has_point(Vector2(x, z)) or VILLAGE_ROAD.grow(20.0).has_point(Vector2(x, z)):
		return 0.0
	for r: Rect2 in TUNNEL_ROADS:
		if r.grow(8.0).has_point(Vector2(x, z)):
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


## Las z drzew Tree3D: komórki 80 m, w każdej osobny MultiMesh na wariant drzewa (pełny
## i uproszczony) oraz jeden z billboardami wszystkich wariantów (kolumna atlasu w custom data).
func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var full: Array = tree3d_meshes()
	var cells := {}
	var x := -WORLD + 20.0
	while x < WORLD - 20.0:
		var z := -WORLD + 20.0
		while z < WORLD - 20.0:
			var px := x + rng.randf_range(-2.8, 2.8)
			var pz := z + rng.randf_range(-2.8, 2.8)
			z += FOREST_STEP
			if rng.randf() > forest_density(px, pz):
				continue
			var hgt := height(px, pz)
			# brzozy częściej wyżej na zboczach
			var v := rng.randi_range(4, 5) if rng.randf() < (0.25 if hgt < 60.0 else 0.5) else rng.randi_range(0, 3)
			var key := Vector2i(int(floor(px / FOREST_CELL)), int(floor(pz / FOREST_CELL)))
			if not cells.has(key):
				cells[key] = []
			var s := rng.randf_range(0.6, 1.1)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s))
			(cells[key] as Array).append([v, Transform3D(b, Vector3(px, hgt - 0.05, pz))])
		x += FOREST_STEP
	var imp_mesh := _impostor_mesh()
	var total := 0
	for key: Vector2i in cells:
		var list: Array = cells[key]
		total += list.size()
		var by_v := {}
		for it: Array in list:
			if not by_v.has(it[0]):
				by_v[it[0]] = []
			(by_v[it[0]] as Array).append(it[1])
		for v: int in by_v:
			var a := _forest_mm(full[v], by_v[v])
			a.visibility_range_end = LOD_FULL
			a.visibility_range_end_margin = 8.0
			var m := _forest_mm(_tree3d_mid[v], by_v[v])
			m.visibility_range_begin = LOD_FULL
			m.visibility_range_begin_margin = 8.0
			m.visibility_range_end = LOD_MID
			m.visibility_range_end_margin = 15.0
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # cienie tylko z bliska (wydajność)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = imp_mesh
		mm.instance_count = list.size()
		for i in list.size():
			var v: int = list[i][0]
			var t: Transform3D = list[i][1]
			mm.set_instance_transform(i, Transform3D(t.basis.scaled(Vector3.ONE * IMPOSTOR_S[v]), t.origin))
			mm.set_instance_custom_data(i, Color(float(v), 0, 0, 0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_begin = LOD_MID
		mi.visibility_range_begin_margin = 15.0
		mi.visibility_range_end = 1500.0
		mi.visibility_range_end_margin = 100.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
	print("[teren] drzew: ", total)


func _forest_mm(mesh: Mesh, xf: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
	return mi


const IMPOSTOR_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float columns = 6.0;
varying float col;
void vertex() {
	col = INSTANCE_CUSTOM.r;
	// światło jak na koronę z góry (płaty nie ciemnieją, gdy są bokiem do słońca)
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + NORMAL * 0.3);
}
void fragment() {
	vec4 t = texture(atlas, vec2((UV.x + col) / columns, UV.y));
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 1.0;
}
"""


## Billboard: dwa skrzyżowane kwadraty 1 × 1 (dół w 0), skalowane per drzewo bokiem kadru.
func _impostor_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var d := Vector3(0.5, 0, 0) if k == 0 else Vector3(0, 0, 0.5)
		var nrm := Vector3(0, 0, 1) if k == 0 else Vector3(1, 0, 0)
		var v := [[-d, Vector2(0, 1)], [d, Vector2(1, 1)], [d + Vector3.UP, Vector2(1, 0)], [-d + Vector3.UP, Vector2(0, 0)]]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nrm)
			st.set_uv(v[i][1])
			st.add_vertex(v[i][0])
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = IMPOSTOR_SHADER
	mat.shader = sh
	mat.set_shader_parameter("atlas", load("res://assets/trees/impostors.png"))
	mat.set_shader_parameter("columns", float(TREE3D_N))
	mesh.surface_set_material(0, mat)
	return mesh


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
			if VILLAGE.has_point(Vector2(x, z)):
				c = Color(0.42, 0.4, 0.38)   # wioska: asfalt i dachy
			map_img.set_pixel(i, j, c * shade)
