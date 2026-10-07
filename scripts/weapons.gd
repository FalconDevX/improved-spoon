extends Node3D
## Broń palna: model z paczki Quaternius (CC0) + dane z prawdziwych konstrukcji.
## Układ węzła: lufa wzdłuż -Z, góra +Y, początek = chwyt pistoletowy (środek dłoni).
## Model w pliku ma lufę wzdłuż +X — punkty kotwiczące podane w jednostkach modelu (x, y).

const Sfx = preload("res://scripts/sfx.gd")

# Amunicja. mass [kg], k: współczynnik oporu [1/m] (dv/dt = -k·v²), pen: głębokość penetracji
# w tkance miękkiej przy prędkości początkowej [m], cavity: promień stałej jamy rany [m],
# frag_v: od tej prędkości pocisk się fragmentuje (większa rana, mniejsza penetracja),
# armor: klasa przebijalności (1 = pistoletowa, 2 = śrut, 3 = karabinowa pośrednia, 4 = karabinowa pełna).
const CAL := {
	"9x19": {"name": "9×19 mm Parabellum FMJ", "mass": 0.0080, "k": 0.0014, "pen": 0.55, "cavity": 0.0055, "frag_v": 0.0, "armor": 1, "tracer": false},
	"5.56x45": {"name": "5,56×45 mm NATO M855", "mass": 0.0040, "k": 0.00112, "pen": 0.38, "cavity": 0.008, "frag_v": 760.0, "armor": 3, "tracer": true},
	"7.62x39": {"name": "7,62×39 mm M43", "mass": 0.0079, "k": 0.0015, "pen": 0.65, "cavity": 0.009, "frag_v": 0.0, "yaw_depth": 0.26, "armor": 3, "tracer": true},
	"7.62x51": {"name": "7,62×51 mm NATO M80", "mass": 0.0095, "k": 0.0007, "pen": 0.78, "cavity": 0.011, "frag_v": 0.0, "yaw_depth": 0.16, "armor": 4, "tracer": false},
	"5.45x39": {"name": "5,45×39 mm 7N6", "mass": 0.0034, "k": 0.0011, "pen": 0.45, "cavity": 0.008, "frag_v": 0.0, "yaw_depth": 0.09, "armor": 3, "tracer": true},
	"357": {"name": ".357 Magnum JSP", "mass": 0.0102, "k": 0.0018, "pen": 0.45, "cavity": 0.0065, "frag_v": 0.0, "armor": 1, "tracer": false},
	"50ae": {"name": ".50 Action Express JHP", "mass": 0.0195, "k": 0.0017, "pen": 0.5, "cavity": 0.009, "frag_v": 0.0, "armor": 2, "tracer": false},
	"338lm": {"name": ".338 Lapua Magnum", "mass": 0.0162, "k": 0.0005, "pen": 0.9, "cavity": 0.013, "frag_v": 0.0, "yaw_depth": 0.2, "armor": 4, "tracer": false},
	"12.7x99": {"name": "12,7×99 mm (.50 BMG) M2", "mass": 0.042, "k": 0.00042, "pen": 1.7, "cavity": 0.03, "frag_v": 0.0, "yaw_depth": 0.25, "armor": 5, "tracer": true},
	"frag": {"name": "odłamek bomby", "mass": 0.003, "k": 0.02, "pen": 0.24, "cavity": 0.007, "frag_v": 0.0, "armor": 3, "tracer": false},
	"pg7v": {"name": "PG-7V (rakieta kumulacyjna)", "mass": 2.2, "k": 0.0, "pen": 0.5, "cavity": 0.01, "frag_v": 0.0, "armor": 4, "tracer": false},
	"piorun": {"name": "Piorun (rakieta przeciwlotnicza)", "mass": 10.5, "k": 0.0, "pen": 0.5, "cavity": 0.01, "frag_v": 0.0, "armor": 4, "tracer": false},
	"12ga": {"name": "12/70 śrut 00 Buck (9 × 8,4 mm)", "mass": 0.0035, "k": 0.0044, "pen": 0.32, "cavity": 0.0045, "frag_v": 0.0, "armor": 2, "pellets": 9, "pellet_spread": 0.011, "tracer": false},
}

# Broń. spread: rozrzut własny (odchylenie standardowe, rad; 1 MOA ≈ 0,00029 rad).
# recoil: [podrzut lufy rad, rozrzut boczny rad, cofnięcie m]. zero: odległość przystrzelania [m].
# feed: "mag" (magazynek) albo "tube" (ładowanie nabój po naboju).
# Kotwice (jednostki modelu): grip, support (lewa dłoń), butt (stopka kolby), muzzle, sight (linia celownika).
const DB := {
	"m4": {"name": "Colt M4A1", "model": "AssaultRifle2_1", "length": 0.84, "cal": "5.56x45", "v0": 910.0,
		"rpm": 800.0, "modes": ["auto", "semi"], "cap": 30, "mags": 6, "feed": "mag",
		"reload": 2.3, "reload_empty": 2.9, "spread": 0.00058, "recoil": [0.0095, 0.0045, 0.045], "zero": 100.0,
		"kind": "rifle", "weight": 3.4, "ads_fov": 42.0, "sound": "shot_556",
		"grip": Vector2(-0.03, -0.06), "support": Vector2(1.75, 0.5), "butt": Vector2(-1.5, 0.45),
		"muzzle": Vector2(3.6, 0.64), "sight": Vector2(-0.1, 1.0)},
	"ak": {"name": "AKM", "model": "AssaultRifle_2", "length": 0.88, "cal": "7.62x39", "v0": 715.0,
		"rpm": 600.0, "modes": ["auto", "semi"], "cap": 30, "mags": 5, "feed": "mag",
		"reload": 2.5, "reload_empty": 3.1, "spread": 0.0011, "recoil": [0.0135, 0.0065, 0.05], "zero": 100.0,
		"kind": "rifle", "weight": 3.6, "ads_fov": 44.0, "sound": "shot_762",
		"grip": Vector2(-0.05, -0.1), "support": Vector2(2.3, 0.45), "butt": Vector2(-1.55, 0.35),
		"muzzle": Vector2(3.8, 0.61), "sight": Vector2(0.9, 0.84)},
	"mp9": {"name": "B&T MP9", "model": "SubmachineGun_3", "length": 0.52, "cal": "9x19", "v0": 400.0,
		"rpm": 1000.0, "modes": ["auto", "semi"], "cap": 30, "mags": 5, "feed": "mag",
		"reload": 1.9, "reload_empty": 2.3, "spread": 0.0016, "recoil": [0.0065, 0.004, 0.025], "zero": 50.0,
		"kind": "rifle", "weight": 1.4, "ads_fov": 48.0, "sound": "shot_9",
		"grip": Vector2(0.0, -0.21), "support": Vector2(1.5, -0.17), "butt": Vector2(-1.8, 0.42),
		"muzzle": Vector2(2.1, 0.48), "sight": Vector2(-0.2, 0.8)},
	"glock": {"name": "Glock 17", "model": "Pistol_1", "length": 0.186, "cal": "9x19", "v0": 360.0,
		"rpm": 0.0, "modes": ["semi"], "cap": 17, "mags": 4, "feed": "mag",
		"reload": 1.5, "reload_empty": 1.9, "spread": 0.0013, "recoil": [0.03, 0.006, 0.02], "zero": 25.0,
		"kind": "pistol", "weight": 0.9, "ads_fov": 52.0, "sound": "shot_9",
		"grip": Vector2(-0.03, -0.08), "support": Vector2(-0.08, -0.12), "butt": Vector2.ZERO,
		"muzzle": Vector2(1.47, 0.5), "sight": Vector2(-0.2, 0.74)},
	"r870": {"name": "Remington 870", "model": "Shotgun_1", "length": 1.0, "cal": "12ga", "v0": 400.0,
		"rpm": 0.0, "cycle": 0.55, "modes": ["pump"], "cap": 6, "mags": 30, "feed": "tube",
		"reload": 0.52, "reload_empty": 0.52, "spread": 0.0015, "recoil": [0.045, 0.01, 0.07], "zero": 25.0,
		"kind": "rifle", "weight": 3.6, "ads_fov": 50.0, "sound": "shot_12",
		"grip": Vector2(-0.1, -0.1), "support": Vector2(2.2, 0.02), "butt": Vector2(-1.41, -0.12),
		"muzzle": Vector2(3.8, 0.3), "sight": Vector2(0.2, 0.38)},
	"m24": {"name": "Remington M24 SWS", "model": "SniperRifle_1", "length": 1.09, "cal": "7.62x51", "v0": 790.0,
		"rpm": 0.0, "cycle": 1.2, "modes": ["bolt"], "cap": 5, "mags": 25, "feed": "tube",
		"reload": 0.6, "reload_empty": 0.6, "spread": 0.0002, "recoil": [0.03, 0.006, 0.07], "zero": 300.0,
		"kind": "rifle", "weight": 5.5, "ads_fov": 4.2, "scope": true, "sound": "shot_308",
		"grip": Vector2(-0.16, -0.16), "support": Vector2(2.0, 0.05), "butt": Vector2(-2.0, -0.08),
		"muzzle": Vector2(5.21, 0.28), "sight": Vector2(-0.3, 0.54)},
	"ak74": {"name": "AKS-74", "model": "AssaultRifle_4", "length": 0.94, "cal": "5.45x39", "v0": 900.0,
		"rpm": 650.0, "modes": ["auto", "semi"], "cap": 30, "mags": 5, "feed": "mag",
		"reload": 2.4, "reload_empty": 3.0, "spread": 0.0009, "recoil": [0.0085, 0.004, 0.04], "zero": 100.0,
		"kind": "rifle", "weight": 3.0, "ads_fov": 46.0, "sound": "shot_556",
		"grip": Vector2(-0.05, -0.1), "support": Vector2(2.3, 0.45), "butt": Vector2(-1.6, 0.3),
		"muzzle": Vector2(3.83, 0.58), "sight": Vector2(0.9, 0.84)},
	"aug": {"name": "Steyr AUG A3", "model": "Bullpup_1", "length": 0.79, "cal": "5.56x45", "v0": 970.0,
		"rpm": 680.0, "modes": ["auto", "semi"], "cap": 30, "mags": 5, "feed": "mag",
		"reload": 2.6, "reload_empty": 3.2, "spread": 0.0005, "recoil": [0.0085, 0.004, 0.04], "zero": 100.0,
		"kind": "rifle", "weight": 3.6, "ads_fov": 44.0, "sound": "shot_556",
		"grip": Vector2(0.0, -0.2), "support": Vector2(1.9, 0.1), "butt": Vector2(-2.5, 0.55),
		"muzzle": Vector2(2.72, 0.81), "sight": Vector2(0.4, 1.12)},
	"uzi": {"name": "IMI Uzi", "model": "SubmachineGun_2", "length": 0.62, "cal": "9x19", "v0": 400.0,
		"rpm": 600.0, "modes": ["auto", "semi"], "cap": 32, "mags": 5, "feed": "mag",
		"reload": 2.0, "reload_empty": 2.5, "spread": 0.0018, "recoil": [0.006, 0.004, 0.025], "zero": 50.0,
		"kind": "rifle", "weight": 3.5, "ads_fov": 50.0, "sound": "shot_9",
		"grip": Vector2(0.0, -0.2), "support": Vector2(1.5, 0.45), "butt": Vector2(-1.8, 0.25),
		"muzzle": Vector2(2.25, 0.57), "sight": Vector2(0.0, 0.9)},
	"m686": {"name": "S&W 686 .357", "model": "Revolver_1", "length": 0.3, "cal": "357", "v0": 440.0,
		"rpm": 0.0, "modes": ["semi"], "cap": 6, "mags": 4, "feed": "mag",
		"reload": 2.6, "reload_empty": 2.6, "spread": 0.0011, "recoil": [0.05, 0.008, 0.025], "zero": 25.0,
		"kind": "pistol", "weight": 1.2, "ads_fov": 52.0, "sound": "shot_762",
		"grip": Vector2(0.0, -0.05), "support": Vector2(-0.05, -0.1), "butt": Vector2.ZERO,
		"muzzle": Vector2(1.74, 0.47), "sight": Vector2(0.2, 0.55)},
	"deagle": {"name": "Desert Eagle .50 AE", "model": "Pistol_4", "length": 0.27, "cal": "50ae", "v0": 470.0,
		"rpm": 0.0, "modes": ["semi"], "cap": 7, "mags": 4, "feed": "mag",
		"reload": 1.8, "reload_empty": 2.2, "spread": 0.0014, "recoil": [0.07, 0.012, 0.03], "zero": 25.0,
		"kind": "pistol", "weight": 2.0, "ads_fov": 52.0, "sound": "shot_762",
		"grip": Vector2(-0.15, -0.1), "support": Vector2(-0.2, -0.15), "butt": Vector2.ZERO,
		"muzzle": Vector2(1.61, 0.96), "sight": Vector2(0.0, 1.1)},
	"sawed": {"name": "Obrzyn 12/70", "model": "Shotgun_SawedOff", "length": 0.6, "cal": "12ga", "v0": 380.0,
		"rpm": 0.0, "cycle": 0.25, "modes": ["semi"], "cap": 2, "mags": 24, "feed": "tube",
		"reload": 0.9, "reload_empty": 0.9, "spread": 0.002, "recoil": [0.06, 0.015, 0.05], "zero": 15.0,
		"kind": "rifle", "weight": 2.6, "ads_fov": 55.0, "sound": "shot_12",
		"grip": Vector2(0.0, -0.05), "support": Vector2(1.8, 0.15), "butt": Vector2(-0.38, -0.3),
		"muzzle": Vector2(3.29, 0.4), "sight": Vector2(0.6, 0.53)},
	"rpg": {"name": "RPG-7", "model": "rpg", "proc": "rpg", "length": 1.075, "cal": "pg7v", "v0": 115.0,
		"rpm": 0.0, "modes": ["semi"], "cap": 1, "mags": 6, "feed": "tube", "rocket": true,
		"reload": 2.6, "reload_empty": 2.6, "spread": 0.0025, "recoil": [0.02, 0.006, 0.03], "zero": 100.0,
		"kind": "rifle", "weight": 7.0, "ads_fov": 50.0, "sound": "shot_50",
		"grip": Vector2(0.0, 0.0), "support": Vector2(0.24, 0.0), "butt": Vector2(-0.45, 0.075),
		"muzzle": Vector2(0.53, 0.075), "sight": Vector2(0.05, 0.16)},
	# przenośny zestaw przeciwlotniczy: namierzanie samolotu / śmigłowca (PPM na celu), rakieta
	# naprowadzana na podczerwień z zapalnikiem zbliżeniowym (missile.gd)
	"piorun": {"name": "Piorun (PPZR)", "model": "piorun", "proc": "manpad", "length": 1.6, "cal": "piorun", "v0": 28.0,
		"rpm": 0.0, "modes": ["semi"], "cap": 1, "mags": 3, "feed": "tube", "rocket": true, "seeker": true,
		"reload": 3.4, "reload_empty": 3.4, "spread": 0.001, "recoil": [0.012, 0.004, 0.02], "zero": 100.0,
		"kind": "rifle", "weight": 10.5, "ads_fov": 40.0, "sound": "shot_50",
		"grip": Vector2(0.0, 0.0), "support": Vector2(0.32, 0.02), "butt": Vector2(-0.55, 0.1),
		"muzzle": Vector2(0.82, 0.1), "sight": Vector2(0.05, 0.24)},
	"awm": {"name": "AI AWM .338", "model": "SniperRifle_3", "length": 1.2, "cal": "338lm", "v0": 900.0,
		"rpm": 0.0, "cycle": 1.3, "modes": ["bolt"], "cap": 5, "mags": 20, "feed": "tube",
		"reload": 0.65, "reload_empty": 0.65, "spread": 0.00015, "recoil": [0.04, 0.008, 0.08], "zero": 300.0,
		"kind": "rifle", "weight": 6.5, "ads_fov": 4.0, "scope": true, "sound": "shot_308",
		"grip": Vector2(-0.25, -0.15), "support": Vector2(1.8, 0.2), "butt": Vector2(-1.9, 0.0),
		"muzzle": Vector2(5.31, 0.4), "sight": Vector2(0.0, 0.72)},
}

var id := ""
var data: Dictionary
var cal: Dictionary
var scale_k := 1.0
var rounds := 0           # w magazynku / rurze
var chambered := false
var mags: Array = []      # pełne/częściowe magazynki w ładownicach (liczba nabojów); "tube": zapas nabojów w mags[0]
var mode := 0
var cycle_t := 0.0        # czas do następnego strzału (szybkostrzelność / przeładowanie zamka)
var needs_cycle := false  # pump / bolt: po strzale trzeba przeładować ręcznie (automatycznie po puszczeniu spustu)

var _flash: MeshInstance3D
var _light: OmniLight3D
var _flash_t := 0.0
var mesh_node: MeshInstance3D


static func make(wid: String) -> Node3D:
	var g = load("res://scripts/weapons.gd").new()
	g.setup(wid)
	return g


func setup(wid: String) -> void:
	id = wid
	data = DB[wid]
	cal = CAL[data["cal"]]
	var mesh: Mesh = _proc_mesh(data["proc"]) if data.has("proc") else load("res://assets/weapons/%s.obj" % data["model"]) as Mesh
	var bb := mesh.get_aabb()
	scale_k = float(data["length"]) / bb.size.x
	mesh_node = MeshInstance3D.new()
	mesh_node.mesh = mesh
	mesh_node.transform = Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * scale_k), Vector3.ZERO)
	mesh_node.transform.origin = -_raw(data["grip"])
	add_child(mesh_node)
	_fix_materials(mesh)
	if data.get("rocket", false) and not data.get("seeker", false):
		_build_warhead()
	_build_flash()
	rounds = int(data["cap"])
	chambered = data["feed"] == "mag"
	if data["feed"] == "mag":
		rounds = int(data["cap"])
		mags = []
		for i in int(data["mags"]) - 1:
			mags.append(int(data["cap"]))
	else:
		mags = [int(data["mags"])]


static var _mat_cache := {}


## Kolory z plików .mtl są liniowe (Blender), a importer bierze je jako sRGB -> broń wychodzi
## smoliście czarna. Przeliczenie do sRGB + metal / drewno / polimer.
func _fix_materials(mesh: Mesh) -> void:
	if data.has("proc"):
		return   # własne materiały (już w sRGB)
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i) as StandardMaterial3D
		if src == null:
			continue
		var key := "%s/%d" % [data["model"], i]
		if not _mat_cache.has(key):
			var m := StandardMaterial3D.new()
			var c := src.albedo_color.linear_to_srgb()
			var wood := c.r > c.b * 1.4 and c.r > 0.15
			# stal oksydowana: ciemnoszara, półmatowa (bez niebieskiego odblasku nieba)
			m.albedo_color = c.lerp(Color(c.r, c.g, c.b) * 1.25, 0.5) if wood else c.lerp(Color(0.16, 0.16, 0.15), 0.35)
			m.metallic = 0.0 if wood else 0.3
			m.roughness = 0.65 if wood else 0.55
			m.metallic_specular = 0.4
			_mat_cache[key] = m
		mesh_node.set_surface_override_material(i, _mat_cache[key])


## Punkt modelu (x, y) w układzie węzła, ale bez przesunięcia chwytu.
func _raw(p: Vector2) -> Vector3:
	return Vector3(0.0, p.y * scale_k, -p.x * scale_k)


## Kotwica w układzie węzła (początek = chwyt).
func anchor(name: String) -> Vector3:
	return _raw(data[name]) - _raw(data["grip"])


func muzzle() -> Vector3:
	return global_transform * (anchor("muzzle") + Vector3(0, 0, -0.01))


func is_pistol() -> bool:
	return data["kind"] == "pistol"


func fire_mode() -> String:
	return data["modes"][mode]


func cycle_mode() -> void:
	mode = (mode + 1) % (data["modes"] as Array).size()


func can_fire() -> bool:
	return cycle_t <= 0.0 and not needs_cycle and (chambered or (data["feed"] == "tube" and rounds > 0))


## Zużywa nabój. Zwraca false, gdy komora pusta (suchy trzask).
func consume() -> bool:
	if data["feed"] == "mag":
		if not chambered:
			return false
		chambered = rounds > 0
		if rounds > 0:
			rounds -= 1
	else:
		if rounds <= 0:
			return false
		rounds -= 1
	var m := fire_mode()
	if m == "auto" or m == "semi":
		cycle_t = 60.0 / maxf(float(data["rpm"]), 60.0) if float(data["rpm"]) > 0.0 else 0.12
	else:
		cycle_t = float(data.get("cycle", 0.5))
		needs_cycle = false  # ruch zamka/czółenka wliczony w cycle_t
	return true


func total_ammo() -> int:
	var s := rounds + (1 if chambered else 0)
	for m in mags:
		s += int(m)
	return s


func reserve() -> int:
	var s := 0
	for m in mags:
		s += int(m)
	return s


func can_reload() -> bool:
	if data["feed"] == "mag":
		return not mags.is_empty() and rounds < int(data["cap"]) and mags.any(func(m): return int(m) > 0)
	return rounds < int(data["cap"]) and int(mags[0]) > 0


func reload_time() -> float:
	if data["feed"] == "tube":
		return float(data["reload"])
	return float(data["reload_empty"] if not chambered else data["reload"])


## Koniec przeładowania. Magazynki: wkłada najpełniejszy, wyjęty wraca do ładownicy z resztą nabojów.
## Rura: jeden nabój. Zwraca true, gdy można ładować dalej (rura).
func finish_reload() -> bool:
	if data["feed"] == "mag":
		var best := -1
		for i in mags.size():
			if best < 0 or int(mags[i]) > int(mags[best]):
				best = i
		if best < 0:
			return false
		var newm: int = mags[best]
		mags.remove_at(best)
		if rounds > 0:
			mags.append(rounds)
		rounds = newm
		if not chambered and rounds > 0:
			rounds -= 1
			chambered = true
		return false
	if int(mags[0]) > 0 and rounds < int(data["cap"]):
		mags[0] = int(mags[0]) - 1
		rounds += 1
	return rounds < int(data["cap"]) and int(mags[0]) > 0


## Zabiera naboje z innej broni tego samego kalibru (podnoszenie amunicji).
static var _proc_cache := {}
var _warhead: Node3D


## Głowica rakiety wystająca z wylotu — znika po strzale, wraca po przeładowaniu.
func _build_warhead() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.32, 0.2)
	mat.roughness = 0.6
	_warhead = Node3D.new()
	_warhead.position = anchor("muzzle")
	add_child(_warhead)
	var fwd := Basis(Vector3.RIGHT, -PI * 0.5)   # oś Y walca -> -Z (do przodu)
	var cone := MeshInstance3D.new()
	cone.mesh = _cyl(0.0, 0.055, 0.3)
	cone.material_override = mat
	cone.transform = Transform3D(fwd, Vector3(0, 0, -0.27))
	_warhead.add_child(cone)
	var back := MeshInstance3D.new()
	back.mesh = _cyl(0.055, 0.03, 0.12)
	back.material_override = mat
	back.transform = Transform3D(fwd, Vector3(0, 0, -0.06))
	_warhead.add_child(back)


## Broń bez modelu w paczce (RPG-7): bryły złożone w jedną siatkę, oś lufy wzdłuż +X (metry),
## początek = chwyt pistoletowy — ta sama konwencja co modele OBJ.
static func _proc_mesh(kind: String) -> Mesh:
	if _proc_cache.has(kind):
		return _proc_cache[kind]
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.28, 0.32, 0.2)
	olive.roughness = 0.6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.16, 0.1)
	wood.roughness = 0.7
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.12, 0.12, 0.12)
	steel.metallic = 0.7
	steel.roughness = 0.4
	var am := ArrayMesh.new()
	var along_x := Basis(Vector3.BACK, -PI * 0.5)   # oś Y walca -> oś X
	var parts := [
		# [mesh, transform, material]
		[_cyl(0.042, 0.042, 0.95), Transform3D(along_x, Vector3(0.05, 0.075, 0)), steel],     # rura
		[_cyl(0.045, 0.06, 0.16), Transform3D(along_x, Vector3(-0.47, 0.075, 0)), steel],     # tylny lej (dysza)
		[_cyl(0.05, 0.05, 0.3), Transform3D(along_x, Vector3(0.0, 0.075, 0)), wood],          # osłona drewniana
		[_box(Vector3(0.035, 0.11, 0.03)), Transform3D(Basis(Vector3.BACK, 0.25), Vector3(0.0, -0.03, 0)), steel],   # chwyt
		[_box(Vector3(0.035, 0.1, 0.03)), Transform3D(Basis(Vector3.BACK, 0.15), Vector3(0.24, -0.02, 0)), steel],  # przedni chwyt
		[_box(Vector3(0.04, 0.05, 0.012)), Transform3D(Basis(), Vector3(0.05, 0.135, 0)), steel],    # celownik
	]
	if kind == "manpad":
		# Piorun: długa zielona tuba z czołowymi zaślepkami, blok baterii i głowicy pod spodem,
		# chwyt ze spustem, celownik ramkowy z boku
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.06, 0.06, 0.06)
		black.roughness = 0.8
		parts = [
			[_cyl(0.045, 0.045, 1.62), Transform3D(along_x, Vector3(0.13, 0.1, 0)), olive],          # tuba
			[_cyl(0.052, 0.052, 0.06), Transform3D(along_x, Vector3(0.9, 0.1, 0)), black],           # przednia zaślepka
			[_cyl(0.055, 0.05, 0.08), Transform3D(along_x, Vector3(-0.66, 0.1, 0)), black],          # tylna zaślepka
			[_box(Vector3(0.22, 0.07, 0.06)), Transform3D(Basis(), Vector3(-0.1, 0.03, 0)), black],   # blok startowy
			[_box(Vector3(0.035, 0.11, 0.03)), Transform3D(Basis(Vector3.BACK, 0.25), Vector3(0.0, -0.04, 0)), black],  # chwyt
			[_cyl(0.025, 0.025, 0.12), Transform3D(along_x, Vector3(-0.27, 0.0, 0)), steel],         # bateria (BCU)
			[_box(Vector3(0.012, 0.09, 0.07)), Transform3D(Basis(), Vector3(0.05, 0.2, 0.0)), black], # ramka celownika
			[_box(Vector3(0.03, 0.03, 0.03)), Transform3D(Basis(), Vector3(0.32, 0.02, 0)), black],   # przedni uchwyt
		]
	for prt: Array in parts:
		var st := SurfaceTool.new()
		st.append_from(prt[0], 0, prt[1])
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, prt[2])
	_proc_cache[kind] = am
	return am


static func _cyl(top: float, bottom: float, h: float) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	return c


static func _box(size: Vector3) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Pełny zapas (skrzynka z amunicją). Zwraca liczbę dodanych naboi.
func refill() -> int:
	var before := total_ammo()
	if data["feed"] == "mag":
		mags = []
		for i in int(data["mags"]) - 1:
			mags.append(int(data["cap"]))
	else:
		mags = [int(data["mags"])]
	return maxi(total_ammo() - before, 0)


func take_ammo_from(other) -> int:
	if other == null or other.data["cal"] != data["cal"]:
		return 0
	var got := 0
	if data["feed"] == "mag" and other.data["feed"] == "mag":
		var all: Array = other.mags.duplicate()
		if other.rounds > 0:
			all.append(other.rounds + (1 if other.chambered else 0))
		for m in all:
			if int(m) <= 0:
				continue
			var n := mini(int(m), int(data["cap"]))
			mags.append(n)
			got += n
		other.mags.clear()
		other.rounds = 0
		other.chambered = false
	else:
		var n: int = other.total_ammo()
		got = n
		if data["feed"] == "tube":
			mags[0] = int(mags[0]) + n
		else:
			while n > 0:
				var c := mini(n, int(data["cap"]))
				mags.append(c)
				n -= c
		other.mags = [0] if other.data["feed"] == "tube" else []
		other.rounds = 0
		other.chambered = false
	return got


func _process(delta: float) -> void:
	cycle_t = maxf(cycle_t - delta, 0.0)
	if _warhead:
		_warhead.visible = rounds > 0
	if _laser_emit:
		_update_laser()
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
			_flare.visible = false
			_light.light_energy = 0.0


func flash() -> void:
	_flash_t = 0.045
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	var big := 1.6 if data["cal"] in ["7.62x51", "12ga", "7.62x39", "338lm", "50ae"] else 1.0
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.3) * big
	_flare.visible = true
	_flare.rotation = Vector3(0, 0, randf() * PI)
	_flare.scale = Vector3(1.0, 1.0, randf_range(0.7, 1.3)) * big
	_light.light_energy = 6.0 * big


func _build_flash() -> void:
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	_flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(1.0, 0.72, 0.32)
	fm.albedo_texture = _flash_tex()
	_flash.material_override = fm
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.position = anchor("muzzle") + Vector3(0, 0, -0.06)
	_flash.visible = false
	add_child(_flash)
	# płomień wzdłuż lufy: dwa skrzyżowane prostokąty widoczne z boku
	_flare = Node3D.new()
	_flare.position = anchor("muzzle")
	_flare.visible = false
	add_child(_flare)
	var fq := QuadMesh.new()
	fq.size = Vector2(0.07, 0.2)
	var flm := fm.duplicate() as StandardMaterial3D
	flm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	flm.cull_mode = BaseMaterial3D.CULL_DISABLED
	flm.albedo_texture = _flare_tex()
	flm.albedo_color = Color(1.0, 0.75, 0.4)
	for a in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = fq
		mi.material_override = flm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lay := Basis(Vector3.RIGHT, -PI * 0.5)   # długość prostokąta wzdłuż lufy (-Z)
		mi.transform = Transform3D(Basis(Vector3.BACK, a * PI * 0.5) * lay, Vector3(0, 0, -0.09))
		_flare.add_child(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.35)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.position = anchor("muzzle")
	add_child(_light)


static var _ftex: Texture2D
static var _fltex: Texture2D
var _flare: Node3D


## Tekstura płomienia bocznego: jasny rdzeń przy wylocie, stożek gasnący ku przodowi.
static func _flare_tex() -> Texture2D:
	if _fltex:
		return _fltex
	var img := Image.create(32, 96, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.frequency = 0.15
	for y in 96:
		for x in 32:
			var t := 1.0 - y / 95.0                  # 0 = przód, 1 = wylot
			var w := lerpf(0.15, 1.0, pow(t, 0.6))
			var dx := absf(x - 15.5) / 15.5 / w
			var v := clampf((1.0 - dx * dx) * pow(t, 0.7), 0.0, 1.0) * (0.75 + 0.5 * nz.get_noise_2d(x, y))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(v, 0.0, 1.0)))
	_fltex = ImageTexture.create_from_image(img)
	return _fltex


static func _flash_tex() -> Texture2D:
	if _ftex:
		return _ftex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(x - 31.5, y - 31.5) / 31.5
			var r := p.length()
			var a := atan2(p.y, p.x)
			var star := pow(absf(cos(a * 2.5)), 8.0) * (1.0 - r)
			var v := clampf(maxf(1.0 - r * 1.7, star * 1.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	_ftex = ImageTexture.create_from_image(img)
	return _ftex


## Zamienia broń w bryłę fizyczną (upuszczona przez martwego / ciężko rannego).
func drop(container: Node, impulse: Vector3) -> RigidBody3D:
	var xf := global_transform
	laser_on = false
	var rb := RigidBody3D.new()
	rb.collision_layer = 16
	rb.collision_mask = 1
	rb.mass = float(data["weight"])
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var l := float(data["length"])
	bs.size = Vector3(0.05, 0.16 if not is_pistol() else 0.12, l)
	cs.shape = bs
	cs.position = Vector3(0, 0.03, -l * 0.3 if not is_pistol() else -0.05)
	rb.add_child(cs)
	container.add_child(rb)
	rb.global_transform = xf
	get_parent().remove_child(self)
	rb.add_child(self)
	transform = Transform3D.IDENTITY
	rb.apply_central_impulse(impulse * rb.mass)
	rb.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	rb.add_to_group("dropped_gun")
	rb.set_meta("gun", self)
	return rb


# ---------------------------------------------------------------- dodatki: kolimator, laser

var sight_point := Vector3.INF   # środek kolimatora / lunety (układ węzła) — linia celowania
var laser_on := true
var laser_exclude: Array[RID] = []
var _laser_emit: Node3D
var _beam: MeshInstance3D
var _dot: MeshInstance3D


static func _mat(c: Color, unshaded := false, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.5
	m.metallic = 0.3 if not unshaded else 0.0
	return m


func _part(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Najwyższy punkt modelu (jednostki modelu) między x0 a x1 — szyna / grzbiet zamka.
func _top_units(x0: float, x1: float) -> float:
	var top := -INF
	for v in (mesh_node.mesh as Mesh).get_faces():
		if v.x >= x0 and v.x <= x1:
			top = maxf(top, v.y)
	return top


## Kolimator (red dot) na szynie nad chwytem. Broń z lunetą celuje przez lunetę.
func add_optics() -> void:
	if data.get("scope", false):
		sight_point = anchor("sight")
		return
	var g: Vector2 = data["grip"]
	var u := 1.0 / scale_k
	var pistol := is_pistol()
	var top := _top_units(g.x - (0.03 if pistol else 0.06) * u, g.x + (0.08 if pistol else 0.14) * u)
	var cx := g.x + (0.035 if pistol else 0.06) * u
	var base := _raw(Vector2(cx, top)) - _raw(g)
	var r := 0.012 if pistol else 0.017
	var h := 0.035 if pistol else 0.05
	var center := base + Vector3(0, 0.007 + r, 0)
	sight_point = center
	var dark := _mat(Color(0.07, 0.07, 0.075))
	var mount := BoxMesh.new()
	mount.size = Vector3(r * 1.3, 0.009, h * 0.8)
	_part(mount, base + Vector3(0, 0.0045, 0), dark)
	var tube := CylinderMesh.new()
	tube.top_radius = r
	tube.bottom_radius = r
	tube.height = h
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 24
	_part(tube, center, dark).rotation.x = PI * 0.5
	# szkło: okrągły krążek w tubie, ledwo zabarwiony (powłoka antyrefleksyjna)
	var lens := CylinderMesh.new()
	lens.top_radius = r * 0.96
	lens.bottom_radius = r * 0.96
	lens.height = 0.0004
	lens.radial_segments = 32
	lens.rings = 1
	var lm := _mat(Color(0.75, 0.85, 1.0), true, 0.05)
	lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_part(lens, center + Vector3(0, 0, -h * 0.45), lm).rotation.x = PI * 0.5
	var dot := SphereMesh.new()
	dot.radius = 0.0009
	dot.height = 0.0018
	var dm := _mat(Color(1.0, 0.08, 0.05), true)
	dm.render_priority = 1
	_part(dot, center + Vector3(0, 0, -h * 0.2), dm)


## Laser na łożu (pistolet: pod lufą). Wiązka i kropka w miejscu, w które padają.
func add_laser() -> void:
	var g: Vector2 = data["grip"]
	var m: Vector2 = data["muzzle"]
	var pistol := is_pistol()
	var p := _raw(Vector2(lerpf(g.x, m.x, 0.72 if pistol else 0.6), m.y)) - _raw(g)
	p += Vector3(0, -0.028, 0) if pistol else Vector3(0.026, -0.006, 0)
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.018, 0.045)
	_part(box, p, _mat(Color(0.1, 0.1, 0.1)))
	_laser_emit = Node3D.new()
	_laser_emit.position = p + Vector3(0, 0, -0.024)
	add_child(_laser_emit)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0011
	cyl.bottom_radius = 0.0011
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	var bm := _mat(Color(1.0, 0.1, 0.05), true, 0.28)
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam = _part(cyl, Vector3.ZERO, bm)
	_beam.top_level = true
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sph := SphereMesh.new()
	sph.radius = 0.012
	sph.height = 0.024
	_dot = _part(sph, Vector3.ZERO, _mat(Color(1.0, 0.15, 0.1), true))
	_dot.top_level = true
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _update_laser() -> void:
	var on := laser_on and is_visible_in_tree()
	_beam.visible = on
	_dot.visible = on
	if not on:
		return
	var from := _laser_emit.global_position
	var dir := -_laser_emit.global_basis.z.normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 250.0, 1 | 2 | 4, laser_exclude)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var dist := 250.0
	if r.is_empty():
		_dot.visible = false
	else:
		dist = from.distance_to(r["position"])
		_dot.global_position = (r["position"] as Vector3) - dir * 0.01
	var x := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(dir).normalized()
	_beam.global_transform = Transform3D(Basis(x, dir * dist, z), from + dir * dist * 0.5)
