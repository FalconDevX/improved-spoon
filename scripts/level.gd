extends NavigationRegion3D
## Mapa ~240 × 240 m: wieś (budynki z drzwiami, oknami i dachami), ogrodzona baza z kontenerami
## i workami z piaskiem, pola z kamiennymi murkami, sad, wraki samochodów, drogi.
## Każda przeszkoda ma materiał (balistyka: przebicie / rykoszet) i rozmiar.
## Z kolizji liczona jest siatka nawigacyjna botów, z przeszkód — punkty osłon.

signal ready_nav

const HALF := 120.0
const WALL_T := 0.25

var covers: Array = []            # {pos, normal, h}
var roofs: Array = []             # {mesh, aabb}
var spawn_player := Vector3(-8, 0, 104)
var posts: Array = []             # miejsca, w których startują oddziały wroga
var road_img: Image              # maska dróg 256 × 256 na całą mapę (trawa, minimapa)
var ground_body: StaticBody3D
var plane_spots: Array = []       # stanowiska samolotów (Transform3D, oś kadłuba nad ziemią)
const GROUND_SIZE := 6000.0
const AIRFIELD := Rect2(18, -14, 106, 50)   # lotnisko na wschodzie: pas wzdłuż drogi, bez przeszkód
var _mats := {}
var _rng := RandomNumberGenerator.new()
var _baked := false
var _nav_ready := false

const SURF_SHADER := """
shader_type spatial;
// Powierzchnia rzutowana z trzech osi (bez UV): kolor bazowy z szumem, plamy, opcjonalne pasy
// (deski, blacha falista, cegły) i ciemniejszy pas przy ziemi.
uniform vec3 base : source_color = vec3(0.6);
uniform vec3 alt : source_color = vec3(0.5);
uniform float noise_scale = 1.5;
uniform float stripe = 0.0;        // częstotliwość pasów [1/m] (0 = brak)
uniform int stripe_axis = 1;       // 0 = x/z poziomo, 1 = y
uniform float stripe_depth = 0.25;
uniform float bricks = 0.0;
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform float grime = 0.35;
uniform float bump = 1.0;
varying vec3 wp;
varying vec3 wn;
float h(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float bricks_m(vec2 pl, out vec2 id) {
	vec2 b = pl * vec2(1.0 / 0.25, 1.0 / 0.08);
	b.x += mod(floor(b.y), 2.0) * 0.5;
	id = floor(b);
	vec2 f = fract(b);
	return smoothstep(0.03, 0.08, f.x) * smoothstep(0.97, 0.92, f.x) * smoothstep(0.05, 0.14, f.y) * smoothstep(0.98, 0.9, f.y);
}
vec2 plane_of(vec3 p, vec3 nn) {
	if (abs(nn.y) > 0.5) return p.xz;
	return abs(nn.x) > 0.5 ? p.zy : p.xy;
}
// wysokość powierzchni (do wypukłości): ziarno, fugi, szpary między deskami
float surf_h(vec3 p, vec3 nn) {
	float hh = n3(p * 23.0) * 0.35 + n3(p * 61.0) * 0.2 + n3(p * noise_scale * 4.3) * 0.25;
	if (bricks > 0.0) {
		vec2 id;
		hh += bricks_m(plane_of(p, nn), id) * 1.4;
	}
	if (stripe > 0.0) {
		float coord = stripe_axis == 1 ? p.y : (abs(nn.x) > 0.5 ? p.z : p.x);
		float s = 0.5 + 0.5 * sin(coord * stripe * 6.2831);
		hh += smoothstep(0.0, 0.3, s) * 0.9;
	}
	return hh;
}
void fragment() {
	float n = n3(wp * noise_scale) * 0.6 + n3(wp * noise_scale * 4.3) * 0.3 + n3(wp * 23.0) * 0.1;
	vec3 c = mix(base, alt, smoothstep(0.35, 0.75, n));
	float rough = roughness;
	if (stripe > 0.0) {
		float coord = stripe_axis == 1 ? wp.y : (abs(wn.x) > 0.5 ? wp.z : wp.x);
		float s = 0.5 + 0.5 * sin(coord * stripe * 6.2831);
		c *= 1.0 - stripe_depth * (1.0 - smoothstep(0.0, 0.25, s));
		// każda deska / fala blachy w nieco innym odcieniu
		c *= 0.9 + 0.2 * h(vec3(floor(coord * stripe), 3.1, 7.7));
	}
	if (bricks > 0.0) {
		vec2 id;
		float m = bricks_m(plane_of(wp, wn), id);
		c *= 0.82 + 0.36 * h(vec3(id, 1.7));
		c = mix(vec3(0.58, 0.56, 0.52) * (0.8 + 0.3 * n), c, m);
	}
	if (abs(wn.y) < 0.5) {
		// zacieki od deszczu: pionowe smugi spływające spod dachu
		vec2 sp = plane_of(wp, wn);
		float streak = n3(vec3(sp.x * 3.1, sp.y * 0.18, 5.0)) * n3(vec3(sp.x * 11.0, sp.y * 0.6, 9.0));
		c *= 1.0 - grime * 0.55 * smoothstep(0.18, 0.5, streak);
		// błoto rozchlapane przy ziemi i zielonkawy nalot w cieniu
		float splash = smoothstep(0.75, 0.0, wp.y) * smoothstep(0.35, 0.7, n3(wp * 5.0));
		c = mix(c, vec3(0.24, 0.2, 0.15), splash * grime * 0.8);
		c = mix(c, vec3(0.2, 0.25, 0.14), smoothstep(0.62, 0.8, n3(wp * 0.9 + 3.0)) * smoothstep(1.5, 0.0, wp.y) * grime * 0.5);
		rough = mix(rough, 1.0, splash * 0.5);
	} else if (wn.y > 0.5) {
		// góra skrzyń, murków, dachów: kurz i liście
		c *= 0.9 + 0.12 * n3(wp * 9.0);
	}
	// starte krawędzie i ubytki: jaśniejsze, bardziej szorstkie plamy
	float chip = smoothstep(0.78, 0.86, n3(wp * 13.0 + 7.0));
	c = mix(c, c * 1.25 + vec3(0.03), chip * 0.5 * grime);
	c *= 1.0 - grime * (1.0 - smoothstep(0.0, 0.5, wp.y)) * step(abs(wn.y), 0.5);
	c *= 0.92 + 0.16 * n3(wp * 61.0);
	// wypukłości: normalna z różnic wysokości wzdłuż powierzchni (gasną z odległością — bez migotania)
	float dist = length(CAMERA_POSITION_WORLD - wp);
	float k = bump * (1.0 - smoothstep(12.0, 45.0, dist));
	if (k > 0.001) {
		vec3 t1 = normalize(abs(wn.y) > 0.9 ? cross(wn, vec3(1.0, 0.0, 0.0)) : cross(wn, vec3(0.0, 1.0, 0.0)));
		vec3 t2 = cross(wn, t1);
		float e = 0.004;
		float h0 = surf_h(wp, wn);
		vec3 g = t1 * (surf_h(wp + t1 * e, wn) - h0) / e + t2 * (surf_h(wp + t2 * e, wn) - h0) / e;
		vec3 nw = normalize(wn - g * k * 0.004);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metallic;
}
"""

const GROUND_SHADER := """
shader_type spatial;
// Teren: trawa i ziemia mieszane szumem, drogi gruntowe (maska z tekstury dróg), drobny detal.
uniform sampler2D road_mask : filter_linear;
uniform float half_size = 120.0;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float ground_h(vec2 p) {
	return n2(p * 7.0) * 0.4 + n2(p * 23.0) * 0.35 + n2(p * 61.0) * 0.25;
}
void fragment() {
	vec2 p = wp.xz;
	float big = n2(p * 0.03) * 0.6 + n2(p * 0.11) * 0.4;
	float fine = n2(p * 1.7) * 0.5 + n2(p * 7.0) * 0.3 + n2(p * 31.0) * 0.2;
	float blades = n2(p * vec2(140.0, 35.0)) * n2(p * vec2(37.0, 150.0));
	vec3 grass = mix(vec3(0.22, 0.29, 0.12), vec3(0.36, 0.39, 0.17), big);
	grass *= 0.75 + 0.35 * fine + 0.35 * blades;
	grass = mix(grass, vec3(0.42, 0.4, 0.22), smoothstep(0.6, 0.8, n2(p * 0.5 + 7.0)) * 0.4);  // suche kępy
	vec3 dirt = mix(vec3(0.34, 0.28, 0.2), vec3(0.46, 0.39, 0.28), fine);
	dirt *= 0.85 + 0.3 * n2(p * 45.0);
	float patchy = smoothstep(0.55, 0.75, n2(p * 0.07 + 13.0) + fine * 0.15);
	vec3 c = mix(grass, dirt, patchy);
	vec2 uv = (p + half_size) / (2.0 * half_size);
	float road = texture(road_mask, uv).r;
	road *= step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);   // poza mapą bez dróg
	float pebbles = smoothstep(0.62, 0.7, n2(p * 38.0));
	vec3 gravel = mix(vec3(0.42, 0.39, 0.34), vec3(0.52, 0.49, 0.43), fine) * (0.85 + 0.25 * n2(p * 60.0));
	gravel = mix(gravel, vec3(0.5, 0.48, 0.44), pebbles * 0.4);
	float rd = smoothstep(0.3, 0.7, road + (fine - 0.5) * 0.3);
	c = mix(c, gravel, rd);
	// koleiny na drogach
	ALBEDO = c;
	ROUGHNESS = 0.97;
	SPECULAR = 0.25;
	float dist = length(CAMERA_POSITION_WORLD - wp);
	float k = 1.0 - smoothstep(10.0, 40.0, dist);
	if (k > 0.001) {
		float e = 0.005;
		float h0 = ground_h(p) + pebbles * rd * 0.3 + blades * (1.0 - rd) * 0.5;
		float hx = ground_h(p + vec2(e, 0.0)) + smoothstep(0.62, 0.7, n2((p + vec2(e, 0.0)) * 38.0)) * rd * 0.3;
		float hz = ground_h(p + vec2(0.0, e)) + smoothstep(0.62, 0.7, n2((p + vec2(0.0, e)) * 38.0)) * rd * 0.3;
		vec3 nw = normalize(vec3(-(hx - h0) / e * 0.006 * k, 1.0, -(hz - h0) / e * 0.006 * k));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
}
"""


func build() -> void:
	_rng.seed = 20261007
	_make_materials()
	_ground()
	_village(Vector2(-10, -5))
	_compound(Vector2(68, -40))
	_farm(Vector2(-70, 40))
	_orchard(Vector2(-75, -60))
	_fields()
	_scatter()
	_perimeter()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.region_min_size = 4.0
	nm.filter_baking_aabb = AABB(Vector3(-HALF, -1, -HALF), Vector3(HALF * 2, 6, HALF * 2))
	navigation_mesh = nm
	bake_finished.connect(_on_baked)
	bake_navigation_mesh(true)


func _on_baked() -> void:
	_baked = true
	# punkty osłon na siatce nawigacyjnej (po kolejnej klatce mapa ma już nowe regiony)
	for i in 3:
		await get_tree().physics_frame
	var map := get_world_3d().navigation_map
	var keep: Array = []
	for c: Dictionary in covers:
		var p: Vector3 = c["pos"]
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(q.x - p.x, q.z - p.z).length() < 0.35:
			c["pos"] = Vector3(q.x, 0.0, q.z)
			keep.append(c)
	covers = keep
	_nav_ready = true
	ready_nav.emit()


func is_ready() -> bool:
	return _nav_ready


func random_point() -> Vector3:
	return NavigationServer3D.map_get_random_point(get_world_3d().navigation_map, 1, false)


func inside(p: Vector3) -> bool:
	return absf(p.x) < HALF - 2.0 and absf(p.z) < HALF - 2.0


## Czy punkt jest w budynku (pod dachem).
func indoors(p: Vector3) -> bool:
	for r: Dictionary in roofs:
		var a: AABB = r["aabb"]
		if p.x > a.position.x and p.x < a.end.x and p.z > a.position.z and p.z < a.end.z:
			return true
	return false


## Dachy znikają, gdy kamera / gracz są w środku budynku.
func update_roofs(player_pos: Vector3, cam_pos: Vector3) -> void:
	for r: Dictionary in roofs:
		var a: AABB = r["aabb"]
		var inside_p := player_pos.x > a.position.x and player_pos.x < a.end.x and player_pos.z > a.position.z and player_pos.z < a.end.z
		var inside_c := cam_pos.x > a.position.x - 1.0 and cam_pos.x < a.end.x + 1.0 and cam_pos.z > a.position.z - 1.0 and cam_pos.z < a.end.z + 1.0 and cam_pos.y < a.end.y + 3.0
		(r["mesh"] as MeshInstance3D).visible = not (inside_p or (inside_c and player_pos.distance_to(a.get_center()) < 20.0))


# ---------------------------------------------------------------- materiały

func _make_materials() -> void:
	var sh := Shader.new()
	sh.code = SURF_SHADER
	var defs := {
		"plaster": [Color(0.74, 0.69, 0.6), Color(0.62, 0.57, 0.49), {"grime": 0.5}],
		"plaster2": [Color(0.66, 0.66, 0.62), Color(0.55, 0.55, 0.52), {"grime": 0.5}],
		"brick": [Color(0.55, 0.3, 0.22), Color(0.45, 0.24, 0.18), {"bricks": 1.0, "grime": 0.3}],
		"concrete": [Color(0.55, 0.55, 0.53), Color(0.46, 0.46, 0.45), {"noise_scale": 2.5, "grime": 0.4}],
		"wood": [Color(0.46, 0.34, 0.21), Color(0.36, 0.26, 0.16), {"stripe": 6.0, "stripe_axis": 1, "stripe_depth": 0.35, "grime": 0.2}],
		"roof": [Color(0.42, 0.2, 0.15), Color(0.32, 0.15, 0.11), {"stripe": 5.0, "stripe_axis": 0, "stripe_depth": 0.3, "grime": 0.0}],
		"container_r": [Color(0.5, 0.17, 0.12), Color(0.38, 0.2, 0.14), {"stripe": 6.0, "stripe_axis": 0, "stripe_depth": 0.3, "metallic": 0.5, "roughness": 0.6}],
		"container_b": [Color(0.15, 0.25, 0.38), Color(0.22, 0.24, 0.26), {"stripe": 6.0, "stripe_axis": 0, "stripe_depth": 0.3, "metallic": 0.5, "roughness": 0.6}],
		"container_g": [Color(0.22, 0.32, 0.2), Color(0.3, 0.27, 0.2), {"stripe": 6.0, "stripe_axis": 0, "stripe_depth": 0.3, "metallic": 0.5, "roughness": 0.6}],
		"sand": [Color(0.6, 0.53, 0.38), Color(0.5, 0.44, 0.31), {"stripe": 3.3, "stripe_axis": 1, "stripe_depth": 0.4, "noise_scale": 4.0, "grime": 0.0}],
		"stone": [Color(0.5, 0.49, 0.45), Color(0.38, 0.37, 0.35), {"noise_scale": 3.0, "grime": 0.2}],
		"car": [Color(0.3, 0.32, 0.3), Color(0.35, 0.22, 0.14), {"metallic": 0.6, "roughness": 0.55, "noise_scale": 1.0}],
		"bark": [Color(0.27, 0.2, 0.14), Color(0.2, 0.15, 0.1), {"stripe": 9.0, "stripe_axis": 1, "stripe_depth": 0.3}],
		"hay": [Color(0.72, 0.6, 0.33), Color(0.6, 0.5, 0.27), {"noise_scale": 9.0, "grime": 0.0}],
		"floor": [Color(0.42, 0.38, 0.33), Color(0.35, 0.31, 0.27), {"noise_scale": 3.0, "grime": 0.0}],
	}
	for k: String in defs:
		var d: Array = defs[k]
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("base", d[0])
		m.set_shader_parameter("alt", d[1])
		for p: String in d[2]:
			m.set_shader_parameter(p, d[2][p])
		_mats[k] = m
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.2, 0.3, 0.12)
	leaf.roughness = 0.9
	_mats["leaf"] = leaf


# ---------------------------------------------------------------- prymitywy

## Prostopadłościan z kolizją. mat: materiał balistyczny, look: materiał wyglądu.
func _box(pos: Vector3, size: Vector3, mat: String, look: String, yaw := 0.0, hollow := 0.0, cover := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	body.set_meta("mat", mat)
	body.set_meta("size", size)
	if hollow > 0.0:
		body.set_meta("hollow", hollow)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if look != "":
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = _mats[look]
		body.add_child(mi)
	add_child(body)
	if cover and size.y >= 0.85:
		_add_covers(pos, size, yaw)
	return body


func _cyl(pos: Vector3, r: float, h: float, mat: String, look: String, hollow := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos + Vector3(0, h * 0.5, 0)
	body.set_meta("mat", mat)
	body.set_meta("size", Vector3(r * 1.6, h, r * 1.6))
	if hollow > 0.0:
		body.set_meta("hollow", hollow)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = _mats[look]
	body.add_child(mi)
	add_child(body)
	return body


## Punkty osłon wokół przeszkody (co ~1.3 m, 0.65 m od ścianki).
func _add_covers(pos: Vector3, size: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for ax in [0, 2]:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sgn
			var other: int = 2 - ax
			var len: float = size[other]
			var cnt := maxi(int(len / 1.3), 1)
			for k in cnt:
				var along := (float(k) + 0.5) / cnt * len - len * 0.5
				var lp := n * (size[ax] * 0.5 + 0.65)
				lp[other] = along
				covers.append({"pos": pos + b * Vector3(lp.x, 0, lp.z) - Vector3(0, pos.y, 0), "normal": b * n, "h": size.y + pos.y - size.y * 0.5})


## Ściana od a do b (XZ) z otworami: [[środek wzdłuż ściany od a, szerokość, dół, góra], ...].
func _wall(a: Vector2, b: Vector2, h: float, openings: Array, mat: String, look: String, t := WALL_T) -> void:
	var d := b - a
	var len := d.length()
	var dir := d / len
	var yaw := atan2(-dir.y, dir.x)
	var cuts: Array = []
	for o: Array in openings:
		cuts.append([float(o[0]) - float(o[1]) * 0.5, float(o[0]) + float(o[1]) * 0.5, o[2], o[3]])
	cuts.sort_custom(func(x, y): return x[0] < y[0])
	var s := 0.0
	var pieces: Array = []
	for c: Array in cuts:
		pieces.append([s, c[0], 0.0, h])
		pieces.append([c[0], c[1], 0.0, c[2]])
		pieces.append([c[0], c[1], c[3], h])
		s = c[1]
	pieces.append([s, len, 0.0, h])
	for p: Array in pieces:
		var l0: float = p[0]
		var l1: float = p[1]
		var y0: float = p[2]
		var y1: float = p[3]
		if l1 - l0 < 0.03 or y1 - y0 < 0.03:
			continue
		var mid := a + dir * (l0 + l1) * 0.5
		var extra := t if (l0 <= 0.001 or l1 >= len - 0.001) else 0.0
		_box(Vector3(mid.x, (y0 + y1) * 0.5, mid.y), Vector3(l1 - l0 + extra, y1 - y0, t), mat, look, yaw, 0.0, y0 < 0.01 and y1 > 0.85)


## Budynek: ściany z drzwiami i oknami, dach, czasem ścianka działowa.
func _building(c: Vector2, w: float, d: float, look: String, doors: Array) -> void:
	var h := 3.0
	var x0 := c.x - w * 0.5
	var x1 := c.x + w * 0.5
	var z0 := c.y - d * 0.5
	var z1 := c.y + d * 0.5
	var sides := [[Vector2(x0, z0), Vector2(x1, z0), "n"], [Vector2(x1, z1), Vector2(x0, z1), "s"],
		[Vector2(x0, z1), Vector2(x0, z0), "w"], [Vector2(x1, z0), Vector2(x1, z1), "e"]]
	for s: Array in sides:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var len := a.distance_to(b)
		var ops: Array = []
		if s[2] in doors:
			ops.append([len * 0.5 + _rng.randf_range(-len * 0.2, len * 0.2), 1.1, 0.0, 2.15])
		var nwin := int(len / 3.5)
		for k in nwin:
			var at := (k + 0.5) / nwin * len
			var clash := false
			for o: Array in ops:
				if absf(at - float(o[0])) < 1.5:
					clash = true
			if not clash:
				ops.append([at, 1.0, 0.95, 2.0])
		_wall(a, b, h, ops, "brick" if look == "brick" else "concrete", look)
	if w > 8.0 and _rng.randf() < 0.7:
		var xm := c.x + _rng.randf_range(-w * 0.15, w * 0.15)
		_wall(Vector2(xm, z0), Vector2(xm, z1), h, [[d * 0.5, 1.0, 0.0, 2.1]], "concrete", "plaster2", 0.15)
	# podłoga (bez kolizji, tylko wygląd)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	fl.mesh = pm
	fl.material_override = _mats["floor"]
	fl.position = Vector3(c.x, 0.012, c.y)
	add_child(fl)
	# dach (wygląd; znika, gdy jesteś w środku)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(w + 0.6, 0.22, d + 0.6)
	roof.mesh = rm
	roof.material_override = _mats["roof"]
	roof.position = Vector3(c.x, h + 0.11, c.y)
	add_child(roof)
	roofs.append({"mesh": roof, "aabb": AABB(Vector3(x0, 0, z0), Vector3(w, h, d))})


func _crate(p: Vector3, s := 1.0, yaw := 0.0) -> void:
	_box(p + Vector3(0, 0.5 * s, 0), Vector3(s, s, s), "wood", "wood", yaw, 0.025)


func _container(p: Vector2, yaw: float, look: String) -> void:
	_box(Vector3(p.x, 1.3, p.y), Vector3(6.06, 2.6, 2.44), "metal", look, yaw, 0.002)


func _sandbags(a: Vector2, b: Vector2, h := 1.1) -> void:
	var d := b - a
	_box(Vector3((a.x + b.x) * 0.5, h * 0.5, (a.y + b.y) * 0.5), Vector3(d.length(), h, 0.6), "sand", "sand", atan2(-d.y, d.x))


func _car(p: Vector2, yaw: float) -> void:
	var b := _box(Vector3(p.x, 0.75, p.y), Vector3(4.3, 1.0, 1.8), "metal", "car", yaw, 0.003)
	var cab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 0.6, 1.6)
	cab.mesh = bm
	cab.material_override = _mats["car"]
	cab.position = Vector3(-0.2, 0.8, 0)
	b.add_child(cab)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	cs.position = cab.position
	b.add_child(cs)
	# koła
	for sx in [-1.4, 1.4]:
		for sz in [-0.85, 0.85]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.33
			cm.bottom_radius = 0.33
			cm.height = 0.22
			w.mesh = cm
			w.material_override = _mats["stone"]
			w.position = Vector3(sx, -0.45, sz)
			w.rotation.x = PI * 0.5
			b.add_child(w)


func _tree(p: Vector2, s := 1.0) -> void:
	_cyl(Vector3(p.x, 0, p.y), 0.18 * s, 3.2 * s, "wood", "bark")
	for k in 3:
		var leaves := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = (1.5 - k * 0.3) * s
		sm.height = sm.radius * 1.6
		leaves.mesh = sm
		leaves.material_override = _mats["leaf"]
		leaves.position = Vector3(p.x + _rng.randf_range(-0.4, 0.4), (3.0 + k * 0.9) * s, p.y + _rng.randf_range(-0.4, 0.4))
		add_child(leaves)


# ---------------------------------------------------------------- części mapy

func _ground() -> void:
	# maska dróg (tekstura 256 × 256 na całą mapę)
	var img := Image.create(256, 256, false, Image.FORMAT_L8)
	var roads := [
		[Vector2(-120, 0), Vector2(120, -6), 4.5], [Vector2(-10, 120), Vector2(-10, -120), 4.0],
		[Vector2(-10, -5), Vector2(68, -40), 3.5], [Vector2(-10, 40), Vector2(-70, 40), 3.0],
		[Vector2(-10, -50), Vector2(-75, -60), 2.5], [Vector2(24, -2), Vector2(120, -2), 11.0],
	]
	for y in 256:
		for x in 256:
			var p := Vector2((x + 0.5) / 256.0 * HALF * 2.0 - HALF, (y + 0.5) / 256.0 * HALF * 2.0 - HALF)
			var v := 0.0
			for r: Array in roads:
				var a: Vector2 = r[0]
				var b: Vector2 = r[1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var dist := p.distance_to(a + ab * t)
				v = maxf(v, 1.0 - smoothstep(float(r[2]) * 0.5, float(r[2]) * 0.5 + 1.2, dist))
			img.set_pixel(x, y, Color(v, v, v))
	road_img = img
	var tex := ImageTexture.create_from_image(img)
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("road_mask", tex)
	m.set_shader_parameter("half_size", HALF)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_SIZE, GROUND_SIZE)   # daleko poza mapą — widać z samolotu
	mi.mesh = pm
	mi.material_override = m
	add_child(mi)
	var fb := StaticBody3D.new()
	ground_body = fb
	fb.collision_layer = 1
	fb.collision_mask = 0
	fb.set_meta("mat", "dirt")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(GROUND_SIZE, 1.0, GROUND_SIZE)
	cs.shape = bs
	cs.position.y = -0.5
	fb.add_child(cs)
	add_child(fb)


func _village(o: Vector2) -> void:
	var houses := [
		[Vector2(-14, -16), 9.0, 7.0, "plaster", ["s", "e"]], [Vector2(0, -18), 7.0, 6.0, "brick", ["s"]],
		[Vector2(14, -15), 10.0, 8.0, "plaster2", ["s", "w"]], [Vector2(-16, 6), 8.0, 9.0, "brick", ["e", "n"]],
		[Vector2(16, 8), 9.0, 7.0, "plaster", ["w"]], [Vector2(-2, 20), 12.0, 7.0, "plaster2", ["n", "e"]],
		[Vector2(-26, -2), 6.0, 6.0, "plaster", ["e"]], [Vector2(28, -4), 7.0, 6.0, "brick", ["w", "s"]],
		[Vector2(-18, 30), 7.0, 6.0, "plaster", ["n"]], [Vector2(18, 28), 8.0, 6.0, "brick", ["w"]],
		[Vector2(4, -34), 9.0, 7.0, "plaster", ["s", "w"]], [Vector2(-22, -34), 7.0, 7.0, "brick", ["e"]],
	]
	for hdef: Array in houses:
		var c: Vector2 = o + (hdef[0] as Vector2)
		_building(c, hdef[1], hdef[2], hdef[3], hdef[4])
		posts.append(Vector3(c.x, 0, c.y))
	# murki, skrzynie, samochody na placu
	_wall(o + Vector2(-8, -6), o + Vector2(-3, -6), 1.1, [], "stone", "stone", 0.45)
	_wall(o + Vector2(4, 5), o + Vector2(9, 5), 1.1, [], "stone", "stone", 0.45)
	_car(o + Vector2(5, -5), 0.4)
	_car(o + Vector2(-6, 10), -1.2)
	for p in [Vector2(-4, 2), Vector2(9, -7), Vector2(-9, -9), Vector2(2, 12), Vector2(22, 2), Vector2(-24, 14)]:
		_crate(Vector3(o.x + p.x, 0, o.y + p.y), _rng.randf_range(0.9, 1.2), _rng.randf() * PI)
	posts.append(Vector3(o.x, 0, o.y))


func _compound(o: Vector2) -> void:
	var s := 26.0
	# mur obwodowy z bramą i wyrwą
	_wall(o + Vector2(-s, -s), o + Vector2(s, -s), 2.6, [[s * 0.6, 3.0, 0.0, 2.6]], "concrete", "concrete", 0.35)
	_wall(o + Vector2(s, -s), o + Vector2(s, s), 2.6, [], "concrete", "concrete", 0.35)
	_wall(o + Vector2(s, s), o + Vector2(-s, s), 2.6, [[s * 1.3, 2.5, 0.0, 2.6]], "concrete", "concrete", 0.35)
	_wall(o + Vector2(-s, s), o + Vector2(-s, -s), 2.6, [[s, 6.0, 0.0, 2.6]], "concrete", "concrete", 0.35)
	_building(o + Vector2(10, -12), 14.0, 9.0, "plaster2", ["w", "s"])
	_building(o + Vector2(-12, 12), 10.0, 8.0, "plaster2", ["e"])
	var looks := ["container_r", "container_b", "container_g"]
	_container(o + Vector2(-12, -14), 0.0, looks[0])
	_container(o + Vector2(-12, -11), 0.0, looks[1])
	_container(o + Vector2(4, 4), PI * 0.5, looks[2])
	_container(o + Vector2(13, 10), 0.3, looks[0])
	_container(o + Vector2(-2, -4), 0.0, looks[1])
	_sandbags(o + Vector2(-22, -3), o + Vector2(-22, 3))
	_sandbags(o + Vector2(-19, -6), o + Vector2(-19, -2))
	_sandbags(o + Vector2(12, 19), o + Vector2(18, 19))
	_sandbags(o + Vector2(-6, 12), o + Vector2(-2, 15))
	for p in [Vector2(0, 14), Vector2(19, -2), Vector2(-5, -18), Vector2(6, -2), Vector2(20, 14)]:
		_crate(Vector3(o.x + p.x, 0, o.y + p.y), 1.1, _rng.randf() * PI)
		_crate(Vector3(o.x + p.x + 1.2, 0, o.y + p.y + 0.2), 1.0, _rng.randf() * PI)
	for p in [Vector2(3, 18), Vector2(4, 18.8), Vector2(-15, 4)]:
		_cyl(Vector3(o.x + p.x, 0, o.y + p.y), 0.3, 0.9, "metal", "container_b", 0.0012)
	posts.append(Vector3(o.x, 0, o.y))
	posts.append(Vector3(o.x + 10, 0, o.y - 12))
	posts.append(Vector3(o.x - 12, 0, o.y + 12))


func _farm(o: Vector2) -> void:
	_building(o + Vector2(0, 0), 14.0, 9.0, "wood", ["e", "s"])   # stodoła
	_building(o + Vector2(-14, 16), 8.0, 7.0, "plaster", ["e"])
	for k in 9:
		var p := o + Vector2(_rng.randf_range(8, 22), _rng.randf_range(-12, 14))
		_cyl(Vector3(p.x, 0, p.y), 0.75, 1.3, "sand", "hay")
	_car(o + Vector2(12, -3), 1.9)
	# płot drewniany wokół zagrody
	_wall(o + Vector2(-6, 8), o + Vector2(-6, 24), 1.2, [[8.0, 2.0, 0.0, 1.2]], "wood", "wood", 0.08)
	posts.append(Vector3(o.x, 0, o.y))


func _orchard(o: Vector2) -> void:
	for ix in 6:
		for iz in 5:
			var p := o + Vector2(ix * 6.0 + _rng.randf_range(-1, 1), iz * 6.0 + _rng.randf_range(-1, 1))
			_tree(p, _rng.randf_range(0.85, 1.15))
	_building(o + Vector2(-10, 12), 7.0, 6.0, "brick", ["e"])
	posts.append(Vector3(o.x + 12, 0, o.y + 12))


## Kamienne murki dzielące pola.
func _fields() -> void:
	var lines := [
		[Vector2(-110, 20), Vector2(-40, 20)], [Vector2(-40, 70), Vector2(-40, 30)], [Vector2(30, 40), Vector2(100, 40)],
		[Vector2(40, 60), Vector2(40, 110)], [Vector2(-100, -20), Vector2(-50, -20)], [Vector2(20, 70), Vector2(80, 75)],
		[Vector2(-100, 80), Vector2(-60, 95)], [Vector2(60, -100), Vector2(100, -80)], [Vector2(-40, -100), Vector2(10, -95)],
	]
	for l: Array in lines:
		var a: Vector2 = l[0]
		var b: Vector2 = l[1]
		var len := a.distance_to(b)
		var ops := []
		for k in int(len / 18.0):
			ops.append([_rng.randf_range(5.0, len - 5.0), 2.5, 0.0, 1.0])
		_wall(a, b, 1.0, ops, "stone", "stone", 0.5)
	for k in 26:
		var p := Vector2(_rng.randf_range(-110, 110), _rng.randf_range(-110, 110))
		if p.distance_to(Vector2(-10, -5)) < 45.0 or p.distance_to(Vector2(68, -40)) < 34.0 or AIRFIELD.grow(6.0).has_point(p):
			continue
		_tree(p, _rng.randf_range(0.9, 1.3))


func _scatter() -> void:
	for k in 22:
		var p := Vector2(_rng.randf_range(-105, 105), _rng.randf_range(-105, 105))
		if p.distance_to(Vector2(-10, -5)) < 40.0 or p.distance_to(Vector2(68, -40)) < 30.0 or AIRFIELD.grow(4.0).has_point(p):
			continue
		match k % 4:
			0: _car(p, _rng.randf() * TAU)
			1: _crate(Vector3(p.x, 0, p.y), 1.2, _rng.randf() * PI)
			2: _sandbags(p, p + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)).normalized() * 3.5 + p * 0.0)
			3: _cyl(Vector3(p.x, 0, p.y), 0.75, 1.3, "sand", "hay")
	# punkt startowy gracza: kilka osłon
	_sandbags(Vector2(-12, 100), Vector2(-6, 100))
	_crate(Vector3(-3, 0, 102), 1.1, 0.3)


## Granica mapy: wysoki nasyp (niewidzialna ściana + wał ziemny); na wschodzie przerwa na pas startowy.
func _perimeter() -> void:
	var g0 := AIRFIELD.position.y
	var g1 := AIRFIELD.end.y
	for s in [[Vector3(0, 1.5, -HALF), Vector3(HALF * 2, 3, 3)], [Vector3(0, 1.5, HALF), Vector3(HALF * 2, 3, 3)],
			[Vector3(-HALF, 1.5, 0), Vector3(3, 3, HALF * 2)],
			[Vector3(HALF, 1.5, (-HALF + g0) * 0.5), Vector3(3, 3, g0 + HALF)], [Vector3(HALF, 1.5, (g1 + HALF) * 0.5), Vector3(3, 3, HALF - g1)]]:
		_box(s[0], s[1], "dirt", "sand", 0.0, 0.0, false)
	_airfield()


## Lotnisko: trzy myśliwce nosem na wschód, worki z piaskiem i beczki z paliwem przy stanowiskach.
func _airfield() -> void:
	for z in [-2.0, 11.0, 24.0]:
		var t := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(30.0, 1.55, z))
		plane_spots.append(t)
	_sandbags(Vector2(21, 30), Vector2(21, 36))
	_sandbags(Vector2(21, -12), Vector2(21, -7))
	for p in [Vector2(22, 4.5), Vector2(22.8, 5.3), Vector2(22, 17.5)]:
		_cyl(Vector3(p.x, 0, p.y), 0.3, 0.9, "metal", "container_r", 0.0012)
	_crate(Vector3(23, 0, 30), 1.1, 0.2)


## Najlepsza osłona dla bota: blisko niego, zasłania przed zagrożeniem, nie zajęta przez innych.
func find_cover(me: Vector3, threat: Vector3, max_d: float, taken: Array, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var best := {}
	var best_s := INF
	var checks := 0
	for c: Dictionary in covers:
		var p: Vector3 = c["pos"]
		var dm := p.distance_to(me)
		if dm > max_d:
			continue
		var dt := p.distance_to(threat)
		if dt < 6.0:
			continue
		var n: Vector3 = c["normal"]
		var to_t := (threat - p)
		to_t.y = 0.0
		if (-n).dot(to_t.normalized()) < 0.35:
			continue  # przeszkoda nie stoi między punktem a zagrożeniem
		var busy := false
		for t: Vector3 in taken:
			if t.distance_to(p) < 1.0:
				busy = true
				break
		if busy:
			continue
		var s := dm * 1.0 + absf(dt - 22.0) * 0.25
		if s < best_s:
			if checks < 14:
				checks += 1
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.9, 0), threat + Vector3(0, 1.4, 0), 1)
				if space.intersect_ray(q).is_empty():
					continue
			else:
				continue
			best_s = s
			best = c
	return best
