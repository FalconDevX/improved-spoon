extends Node3D
## Wioska na południe od bazy: miasteczko z paczki Kerala City Pack (budynki, sklepy, szyldy, bank,
## kino, szpital, szkoła, stacja paliw, przystanek), asfalt ulic, droga do bramy bazy.
## Ulice tworzą „drabinę”: obwodnica dookoła miasta + pięć ulic poprzecznych. Po niej jeżdżą
## auta (traffic.gd, ruch lewostronny jak w Indiach), a piesi (civilian.gd) chodzą skrajem ulic,
## część pracuje przy sklepach. Na strzały mieszkańcy uciekają.

const Terrain = preload("res://scripts/terrain.gd")
const CITY = preload("res://assets/village/kerala_city.res")
const Civilian = preload("res://scripts/civilian.gd")
const Traffic = preload("res://scripts/traffic.gd")
const Tunnel = preload("res://scripts/tunnel.gd")

const CITY_HALF := Vector2(68.9, 166.9)           # połowa miasta w jego układzie (x w poprzek, z wzdłuż)
const CROSS := [-147.15, -114.15, -14.15, 89.35, 140.35]   # osie ulic poprzecznych (z miasta)
const CROSS_W := [15.5, 25.5, 25.5, 25.5, 25.5]              # ich szerokość (wolny pas między budynkami)
const RING := 6.0                                  # obwodnica: tyle za krawędzią zabudowy
const CARS := 10

var nodes: Array[Vector3] = []                     # węzły sieci ulic (świat)
var links: Array = []                              # links[i] = sąsiedzi węzła i
var work_spots: Array = []                         # [pozycja, kierunek patrzenia] dla pracujących
var _rng := RandomNumberGenerator.new()


## Miasto -> świat: obrót o 90° (długość miasta wzdłuż osi X świata), środek w Terrain.VILLAGE_C.
func city_to_world(x: float, z: float) -> Vector3:
	return Vector3(Terrain.VILLAGE_C.x + z, 0.0, Terrain.VILLAGE_C.y - x)


func build(t3d = null) -> void:
	_rng.seed = 4242
	var city := MeshInstance3D.new()
	city.mesh = CITY
	city.position = Vector3(Terrain.VILLAGE_C.x, 0.0, Terrain.VILLAGE_C.y)
	city.rotation.y = PI * 0.5
	add_child(city)
	# kolizja budynków (statyczna siatka trójkątów)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("mat", "concrete")
	body.set_meta("hollow", 0.25)
	body.transform = city.transform
	var cs := CollisionShape3D.new()
	cs.shape = _collision_shape()
	body.add_child(cs)
	add_child(body)
	_ground()
	_graph()
	var tun := Tunnel.new()
	tun.name = "Tunnel"
	add_child(tun)
	tun.build(t3d)


## Kolizja budynków bez niskich elementów (krawężniki, cokoły, podłogi do 45 cm): po nich się chodzi
## po terenie, a nie zatrzymuje na każdym stopniu.
func _collision_shape() -> ConcavePolygonShape3D:
	var f := CITY.get_faces()
	var out := PackedVector3Array()
	for i in range(0, f.size(), 3):
		if maxf(f[i].y, maxf(f[i + 1].y, f[i + 2].y)) > 0.45:
			out.append(f[i])
			out.append(f[i + 1])
			out.append(f[i + 2])
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(out)
	return sh


## Asfalt: obwodnica (pas 11 m) i ulice poprzeczne + droga do bramy bazy. Między budynkami
## podwórka z trawą (grass.gd czyta maskę assets/village/kerala_grass.png).
func _ground() -> void:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = load("res://assets/village/kerala/c_asphalt.png")
	asphalt.normal_enabled = true
	asphalt.normal_texture = load("res://assets/village/kerala/n_asphalt.png")
	asphalt.roughness = 0.95
	asphalt.uv1_scale = Vector3(60, 25, 1)
	var lx := CITY_HALF.x + RING
	var lz := CITY_HALF.y + RING
	# [środek x, środek z, szerokość x, długość z] w układzie miasta
	var strips: Array = [[lx, 0.0, 11.0, lz * 2.0 + 11.0], [-lx, 0.0, 11.0, lz * 2.0 + 11.0],
		[0.0, lz, lx * 2.0, 11.0], [0.0, -lz, lx * 2.0, 11.0]]
	for i in CROSS.size():
		strips.append([0.0, CROSS[i], lx * 2.0, CROSS_W[i] - 2.0])
	for st: Array in strips:
		var g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(st[2], st[3])
		g.mesh = pm
		var m := asphalt.duplicate() as StandardMaterial3D
		m.uv1_scale = Vector3(float(st[2]) / 6.0, float(st[3]) / 6.0, 1)
		g.material_override = m
		g.position = city_to_world(st[0], st[1]) + Vector3(0, 0.015, 0)
		g.rotation.y = PI * 0.5
		add_child(g)
	# droga z bramy (x ≈ -10, z = 120) do obwodnicy
	var r := Terrain.VILLAGE_ROAD
	var road := MeshInstance3D.new()
	var rm := PlaneMesh.new()
	var z1: float = Terrain.VILLAGE_C.y - CITY_HALF.x - RING
	rm.size = Vector2(9.0, z1 - 116.0)
	road.mesh = rm
	var am := asphalt.duplicate() as StandardMaterial3D
	am.uv1_scale = Vector3(2, (z1 - 116.0) / 8.0, 1)
	road.material_override = am
	road.position = Vector3(r.get_center().x, 0.02, (116.0 + z1) * 0.5)
	add_child(road)


## Sieć ulic: dwie podłużne krawędzie obwodnicy (północ / południe) i poprzeczki na końcach oraz
## w ulicach CROSS. Węzły na krawędziach, krawędzie wzdłuż i w poprzek.
func _graph() -> void:
	var zs: Array[float] = [-CITY_HALF.y - RING]
	for c: float in CROSS:
		zs.append(c)
	zs.append(CITY_HALF.y + RING)
	var xa := -CITY_HALF.x - RING     # strona miasta przy bazie (północ świata)
	var xb := CITY_HALF.x + RING
	var north: Array[int] = []
	var south: Array[int] = []
	for z in zs:
		north.append(_node(city_to_world(xb, z)))
		south.append(_node(city_to_world(xa, z)))
	for i in zs.size():
		_link(north[i], south[i])
		if i > 0:
			_link(north[i - 1], north[i])
			_link(south[i - 1], south[i])
	# droga przez tunel (tunnel.gd): ze środka wschodniej poprzeczki obwodnicy na wschód, potem na lotnisko
	var e := _node(Vector3(nodes[north[-1]].x, 0, Terrain.VILLAGE_C.y))
	links[north[-1]].erase(south[-1])
	links[south[-1]].erase(north[-1])
	_link(north[-1], e)
	_link(e, south[-1])
	var t1 := _node(Vector3(247.0, 0, 212.0))
	var t2 := _node(Vector3(333.0, 0, 212.0))
	var e1 := _node(Vector3(428.0, 0, 212.0))
	var e2 := _node(Vector3(428.0, 0, 48.0))
	_link(e, t1)
	_link(t1, t2)
	_link(t2, e1)
	_link(e1, e2)
	# miejsca pracy: przy fasadach wzdłuż ulic poprzecznych (sklepy, warsztaty)
	for c: float in CROSS:
		for k in 6:
			var x := _rng.randf_range(-CITY_HALF.x + 8.0, CITY_HALF.x - 8.0)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var p := city_to_world(x, c + side * 9.0)
			var face := city_to_world(x, c + side * 20.0) - p
			work_spots.append([p, face.normalized()])


func _node(p: Vector3) -> int:
	nodes.append(p)
	links.append([])
	return nodes.size() - 1


func _link(a: int, b: int) -> void:
	links[a].append(b)
	links[b].append(a)


## Losowy węzeł i sąsiad (start pieszego / auta).
func random_edge() -> Array:
	var a := _rng.randi() % nodes.size()
	var nb: Array = links[a]
	return [a, nb[_rng.randi() % nb.size()]]


## Następny węzeł po dojściu do b (z a), bez zawracania, jeśli jest inna droga.
func next_node(a: int, b: int) -> int:
	var nb: Array = (links[b] as Array).filter(func(n): return n != a)
	if nb.is_empty():
		return a
	return nb[randi() % nb.size()]


## Mieszkańcy: tylu, ile w opcjach (Settings.CIV_COUNTS) — ok. ćwierć pracuje przy sklepach,
## reszta spaceruje bez celu po ulicach. Wcześniejszych usuwa (restart mapy).
func spawn_people() -> void:
	for c in get_tree().get_nodes_in_group("civilian"):
		c.get_parent().remove_child(c)
		c.queue_free()
	var total: int = Settings.CIV_COUNTS[Settings.civilians]
	var workers := mini(int(round(total * 0.28)), work_spots.size() * 2)
	for i in total - workers:
		var c := Civilian.new()
		c.village = self
		c.name = "Civ%d" % i
		var e := random_edge()
		var t := randf()
		c.position = nodes[e[0]].lerp(nodes[e[1]], t) + Vector3(randf_range(-2, 2), 0.1, randf_range(-2, 2))
		c.from = e[0]
		c.to = e[1]
		get_parent().add_child(c)
	for i in workers:
		var c := Civilian.new()
		c.village = self
		c.name = "Work%d" % i
		var w: Array = work_spots[i % work_spots.size()]
		c.position = (w[0] as Vector3) + Vector3(0, 0.1, 0)
		c.work_dir = w[1]
		c.worker = true
		get_parent().add_child(c)


func spawn_traffic() -> void:
	for i in CARS:
		var t := Traffic.new()
		t.village = self
		t.name = "Traffic%d" % i
		t.kind = ["car", "car", "rickshaw", "rickshaw", "truck"][i % 5]
		var e := random_edge()
		t.from = e[0]
		t.to = e[1]
		t.progress = randf() * 0.8
		get_parent().add_child(t)
