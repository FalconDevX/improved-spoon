extends Node3D
## Trawa wokół kamery na całej mapie: kępy (dwa skrzyżowane płaty z teksturą krzaczka trawy
## z SimpleGrassTextured, IcterusGames, MIT — assets/grass/LICENSE_SimpleGrassTextured.txt).
## Dwie warstwy: gęsta blisko (do NEAR_R) i rzadsza z większymi kępami dalej (do FAR_R), żeby łąka
## była widać z daleka. Każda warstwa to jeden MultiMesh z powtarzalnym wzorem (okres PERIOD),
## przesuwany skokami za kamerą — nic nie jest liczone w skrypcie przy ruchu. Wysokość terenu
## (te same trójkąty co siatka terrain.gd) shader czyta z tekstury, miejsca bez trawy w bazie (drogi,
## domy) z maski, a pas, hangary, skały i śnieg wylicza sam.

const Level = preload("res://scripts/level.gd")
const Terrain = preload("res://scripts/terrain.gd")

# [okres wzoru, odstęp kęp, promień, początek (warstwa daleka zaczyna się tam, gdzie bliska gaśnie), skala kępy]
const LAYERS := [[8.0, 0.42, 62.0, 0.0, 1.0], [16.0, 1.25, 185.0, 50.0, 1.9]]
const BASE_MASK := 256           # maska bazy (± Level.HALF): drogi, budynki, przeszkody

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D blades : source_color, filter_linear_mipmap;
uniform sampler2D heights : filter_nearest;
uniform vec4 runway = vec4(0.0);          // x0, z0, x1, z1 — beton pasa i płyty
uniform vec4 hangars[3];                   // prostokąty placów przed hangarami
uniform vec4 roads[3];                     // droga przez tunel
uniform vec4 village = vec4(0.0);          // wioska: trawa tylko na podwórkach (maska w układzie miasta)
uniform sampler2D village_mask : filter_linear;
uniform vec2 village_c = vec2(0.0);        // środek miasta (świat)
uniform vec4 village_uv = vec4(0.0, 0.0, 1.0, 1.0);   // min x, min z, rozmiar x, rozmiar z (układ miasta)
uniform sampler2D mask_base : filter_linear;
uniform float world_half = 1600.0;
uniform float grid = 256.0;
uniform float base_half = 120.0;
uniform float r_in = 0.0;        // warstwa daleka: od tej odległości
uniform float r_out = 60.0;
uniform float wind = 1.0;
uniform vec3 trample = vec3(100000.0);   // gracz: trawa ugina się na boki pod nogami
varying vec3 wp;
varying float tipk;
varying float shade;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float hv(ivec2 c) { return texelFetch(heights, clamp(c, ivec2(0), ivec2(int(grid) - 1)), 0).r; }
// wysokość terenu: mapa wysokości (terrain.gd, próbki na środkach pikseli), interpolacja dwuliniowa
float terrain_h(vec2 p) {
	float st = world_half * 2.0 / grid;
	vec2 g = (p + world_half) / st;
	ivec2 c = ivec2(floor(g));
	vec2 f = g - vec2(c);
	float a = mix(hv(c), hv(c + ivec2(1, 0)), f.x);
	float b = mix(hv(c + ivec2(0, 1)), hv(c + ivec2(1, 1)), f.x);
	return mix(a, b, f.y);
}
void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	tipk = 1.0 - UV.y;
	// poza bazą: bez betonu, hangarów, skał na stromiznach i wysoko (hale, śnieg)
	float ty = terrain_h(base.xz);
	float slope = (abs(terrain_h(base.xz + vec2(3.0, 0.0)) - ty) + abs(terrain_h(base.xz + vec2(0.0, 3.0)) - ty)) / 3.0;
	float m = (1.0 - smoothstep(0.45, 0.8, slope)) * (1.0 - smoothstep(260.0, 330.0, ty)) * mix(1.0, 0.55, smoothstep(40.0, 200.0, ty));
	if (base.x > runway.x && base.x < runway.z && base.z > runway.y && base.z < runway.w)
		m = 0.0;
	if (base.x > village.x && base.x < village.z && base.z > village.y && base.z < village.w) {
		// świat -> miasto (obrót o 90°): x = cz - wz, z = wx - cx
		vec2 cl = vec2(village_c.y - base.z, base.x - village_c.x);
		vec2 vu = (cl - village_uv.xy) / village_uv.zw;
		m = (vu.x > 0.0 && vu.x < 1.0 && vu.y > 0.0 && vu.y < 1.0) ? texture(village_mask, vu).r : 0.0;
	}
	for (int i = 0; i < 3; i++) {
		vec4 rr = roads[i];
		if (base.x > rr.x && base.x < rr.z && base.z > rr.y && base.z < rr.w)
			m = 0.0;
		vec4 r = hangars[i];
		if (base.x > r.x && base.x < r.z && base.z > r.y && base.z < r.w)
			m = 0.0;
	}
	vec2 bu = (base.xz + base_half) / (2.0 * base_half);
	if (bu.x > 0.0 && bu.x < 1.0 && bu.y > 0.0 && bu.y < 1.0)
		m = min(m, texture(mask_base, bu).r);
	// gęstość: maska, koniec zasięgu, początek warstwy dalekiej — przerzedzanie losowe, bez krawędzi
	float d = distance(base.xz, CAMERA_POSITION_WORLD.xz);
	float k = m * (1.0 - smoothstep(r_out * 0.75, r_out, d));
	if (r_in > 0.0)
		k *= smoothstep(r_in, r_in + 15.0, d);
	float keep = clamp((k - h(base.xz * 1.37)) * 6.0, 0.0, 1.0);
	VERTEX *= keep;
	// podmuchy: wolna fala przechodząca przez pole + drobne drżenie
	float gust = n2(base.xz * 0.05 + vec2(TIME * 0.35, TIME * 0.2));
	float sway = (sin(TIME * 2.1 + base.x * 0.7 + base.z * 0.4) * 0.5 + 0.5) * 0.35 + gust * 0.9;
	vec3 push = vec3(0.8, 0.0, 0.5) * sway * 0.22 * wind;
	vec2 away = base.xz - trample.xz;
	float tr = (1.0 - smoothstep(0.3, 1.1, length(away))) * (1.0 - smoothstep(0.8, 2.0, abs(ty - trample.y)));
	vec2 an = normalize(away + vec2(0.001));
	push += vec3(an.x, -0.6, an.y) * tr * 0.45;
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += (inv * push) * tipk * tipk * keep;
	VERTEX += inv * vec3(0.0, ty - base.y - 0.03, 0.0);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shade = 0.85 + 0.3 * h(base.xz * 0.71);
	NORMAL = mix(NORMAL, inv * vec3(0.0, 1.0, 0.0), 0.7);
}
void fragment() {
	vec4 t = texture(blades, UV);
	// lekka zmienność plamami (soczysta zieleń, gdzieniegdzie cieplejsze kępy)
	float big = n2(wp.xz * 0.03) * 0.6 + n2(wp.xz * 0.11) * 0.4;
	vec3 tint = mix(vec3(0.82, 0.9, 0.7), vec3(1.0, 1.0, 0.85), big);
	tint = mix(tint, vec3(1.05, 0.95, 0.65), smoothstep(0.65, 0.85, n2(wp.xz * 0.4 + 7.0)) * 0.4);
	ALBEDO = t.rgb * tint * shade * (0.6 + 0.4 * tipk);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = vec3(0.25, 0.32, 0.1) * tipk;
}
"""

var _mats: Array[ShaderMaterial] = []
var _layers: Array[MultiMeshInstance3D] = []


func build(level) -> void:
	var sh := Shader.new()
	sh.code = SHADER
	var hm := _height_texture(level.terrain)
	var rw: Rect2 = Terrain.RUNWAY.grow(1.0)
	var hangars: Array[Vector4] = []
	for hc: Vector2 in Terrain.HANGARS:
		hangars.append(Vector4(hc.x - 15.0, hc.y - 18.0, hc.x + 15.0, hc.y + 22.0))
	var mb := _base_mask(level)
	var tex: Texture2D = load("res://assets/grass/grass_bush.png")
	# maska podwórek wioski: układ miasta, 0,5 m/piksel, zakres jak kerala_grass.json (zapisane przy konwersji)
	var vmask: Texture2D = load("res://assets/village/kerala_grass.png")
	var vuv := Vector4(-84.912, -182.923, 169.824, 365.846)
	var mesh := _clump_mesh()
	for L: Array in LAYERS:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("blades", tex)
		mat.set_shader_parameter("heights", hm)
		mat.set_shader_parameter("runway", Vector4(rw.position.x, rw.position.y, rw.end.x, rw.end.y))
		mat.set_shader_parameter("hangars", hangars)
		var roads: Array[Vector4] = []
		for rr: Rect2 in Terrain.TUNNEL_ROADS:
			roads.append(Vector4(rr.position.x, rr.position.y, rr.end.x, rr.end.y))
		mat.set_shader_parameter("roads", roads)
		var vr: Rect2 = Terrain.VILLAGE.grow(-2.0)
		mat.set_shader_parameter("village", Vector4(vr.position.x, vr.position.y, vr.end.x, vr.end.y))
		mat.set_shader_parameter("village_mask", vmask)
		mat.set_shader_parameter("village_c", Terrain.VILLAGE_C)
		mat.set_shader_parameter("village_uv", vuv)
		mat.set_shader_parameter("mask_base", mb)
		mat.set_shader_parameter("world_half", Terrain.WORLD)
		mat.set_shader_parameter("grid", float(Terrain.HN))
		mat.set_shader_parameter("base_half", Level.HALF)
		mat.set_shader_parameter("r_in", float(L[3]))
		mat.set_shader_parameter("r_out", float(L[2]))
		var lm := mesh.duplicate() as ArrayMesh
		lm.surface_set_material(0, mat)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = _pattern(lm, L[0], L[1], L[2], L[4])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var r: float = L[2] + L[0]
		mi.custom_aabb = AABB(Vector3(-r, -20.0, -r), Vector3(r * 2.0, 520.0, r * 2.0))
		add_child(mi)
		_mats.append(mat)
		_layers.append(mi)


## Wzór kęp: kwadrat okresu P powtórzony na cały obszar (2R + P), losowe przesunięcia i obroty.
func _pattern(mesh: Mesh, period: float, step: float, radius: float, scale: float) -> MultiMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var tile: Array[Transform3D] = []
	var gx := 0.0
	while gx < period - 0.001:
		var gz := 0.0
		while gz < period - 0.001:
			var s := rng.randf_range(0.75, 1.25) * scale
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
			tile.append(Transform3D(b, Vector3(gx + rng.randf_range(0, step), 0.0, gz + rng.randf_range(0, step))))
			gz += step
		gx += step
	var n := int(ceil(radius * 2.0 / period)) + 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = tile.size() * n * n
	var half := n * period * 0.5
	var i := 0
	for tx in n:
		for tz in n:
			var o := Vector3(tx * period - half, 0.0, tz * period - half)
			for t in tile:
				mm.set_instance_transform(i, Transform3D(t.basis, t.origin + o))
				i += 1
	return mm


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		# skok o pełny okres wzoru: kępy zostają w tych samych miejscach świata
		for k in _layers.size():
			var p: float = LAYERS[k][0]
			var c := cam.global_position
			_layers[k].global_position = Vector3(roundf(c.x / p) * p, 0.0, roundf(c.z / p) * p)
	var pl = get_parent().get("_player")
	if pl != null and is_instance_valid(pl):
		for m in _mats:
			m.set_shader_parameter("trample", pl.global_position)


## Mapa wysokości terenu jako tekstura (float).
func _height_texture(_terrain) -> ImageTexture:
	return ImageTexture.create_from_image(Terrain.height_image())


## Baza: drogi, wnętrza domów, lądowiska i przeszkody (promień z góry trafia coś innego niż ziemię).
func _base_mask(level) -> ImageTexture:
	var img := Image.create(BASE_MASK, BASE_MASK, false, Image.FORMAT_L8)
	var space := get_world_3d().direct_space_state
	var road: Image = level.road_img
	var rects: Array[Rect2] = []
	for nz: Rect2 in level.no_grass:
		rects.append(nz)
	for rf: Dictionary in level.roofs:
		var a: AABB = rf["aabb"]
		rects.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(0.4))
	var step: float = Level.HALF * 2.0 / BASE_MASK
	for j in BASE_MASK:
		for i in BASE_MASK:
			var p := Vector2(-Level.HALF + (i + 0.5) * step, -Level.HALF + (j + 0.5) * step)
			var v := 1.0
			var u := int((p.x + Level.HALF) / (Level.HALF * 2.0) * 256.0)
			var w := int((p.y + Level.HALF) / (Level.HALF * 2.0) * 256.0)
			if road.get_pixel(clampi(u, 0, 255), clampi(w, 0, 255)).r > 0.25:
				v = 0.0   # droga
			else:
				for rr in rects:
					if rr.has_point(p):
						v = 0.0   # wnętrze domu, lądowisko
						break
			if v > 0.0:
				var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 9.0, p.y), Vector3(p.x, -0.5, p.y), 1)
				var r := space.intersect_ray(q)
				if r.is_empty() or r["collider"] != level.ground_body:
					v = 0.0   # budynek, mur, skrzynia
			img.set_pixel(i, j, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## Kępa (jak w SimpleGrassTextured): dwa skrzyżowane płaty z teksturą krzaczka trawy.
func _clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.36
	var hgt := 0.6
	for k in 2:
		var a := PI * 0.5 * k
		var d := Vector3(cos(a), 0, sin(a)) * w
		var nrm := Vector3(-sin(a), 0, cos(a))
		var v := [[-d, Vector2(0, 1)], [d, Vector2(1, 1)], [d + Vector3(0, hgt, 0), Vector2(1, 0)], [-d + Vector3(0, hgt, 0), Vector2(0, 0)]]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nrm)
			st.set_uv(v[i][1])
			st.add_vertex(v[i][0])
	return st.commit()
