extends "res://scripts/plane.gd"
## Lockheed C-130 Hercules: czterosilnikowy transportowiec (model z pliku, ~25 tys. trójkątów).
## Lata jak myśliwiec (ten sam model lotu), ale jest cięższy i bardziej ociężały: mniejszy ciąg,
## wolniej się przechyla i pochyla, ma dużo więcej wytrzymałości. Bez karabinów; z luku w brzuchu
## zrzuca serię 8 bomb [Spacja]; [B] zmienia rodzaj — jako jedyny może wziąć bombę atomową. Wsiada się przy drzwiach z lewej strony kabiny.

const MODEL_PATH := "res://assets/vehicles/c130.glb"

var _len := 29.8
var _spinners: Array = []      # piasty śmigieł (Node3D, obrót wokół osi Z modelu)
var _prop_discs: Array = []    # rozmyte tarcze przy dużych obrotach


func _init() -> void:
	GEAR_H = 3.0
	THRUST = 8.5
	PITCH_RATE = 0.55
	ROLL_RATE = 0.9
	YAW_RATE = 0.25
	V_MIN = 33.0
	V_MAX = 100.0
	TURN_RATE = 0.5
	MAX_HP = 420.0
	AMMO = 0
	BOMBS = 8
	GUNS = []
	bomb_kinds = ["frag", "nuke", "he", "napalm", "cluster"]   # [B] raz = atomowa
	BOARD_R = 7.0
	CAM_DIST = 42.0
	CAM_UP = 9.0
	paint = Color(0.35, 0.4, 0.3)


func _build_model() -> void:
	_burnt = StandardMaterial3D.new()
	_burnt.albedo_color = Color(0.06, 0.055, 0.05)
	_burnt.roughness = 0.95
	# model z pliku (ładowany w biegu: bez zaimportowanego .glb gra i tak wystartuje — zastępczy kadłub)
	var res: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null
	var m: Node3D
	if res:
		m = res.instantiate()
	else:
		push_warning("C-130: brak zaimportowanego modelu %s — uruchom grę przez start.bat" % MODEL_PATH)
		m = Node3D.new()
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.0, 4.0, 29.8)
		box.mesh = bm
		box.position.y = 2.0
		m.add_child(box)
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(40.0, 0.6, 4.0)
		wing.mesh = wm
		wing.position = Vector3(0, 5.5, -1.0)
		m.add_child(wing)
	add_child(m)
	# wymiary i kierunek: nos (kabina, część 4) ma patrzeć w −Z, środek kadłuba w początku układu
	var all := AABB()
	var first := true
	var cockpit := Vector3.ZERO
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = mi.transform * mi.get_aabb()
		all = bb if first else all.merge(bb)
		first = false
		if mi.name.begins_with("part4") or (mi.get_parent() and mi.get_parent().name.begins_with("part4")):
			cockpit = bb.get_center()
		_parts.append(mi)
	var c := all.get_center()
	_len = all.size.z
	if cockpit != Vector3.ZERO and cockpit.z > c.z:
		m.rotation.y = PI
		c = Vector3(-c.x, c.y, -c.z)
	m.position = Vector3(-c.x, -GEAR_H - all.position.y, -c.z)
	SEAT = Vector3(0, -0.6, -_len * 0.5 + 3.6)
	EYE = SEAT + Vector3(-0.55, 2.45, -1.3)   # lewy fotel (pierwszy pilot), na wysokości szyb
	BOARD = Vector3(-2.3, 0, -_len * 0.5 + 4.5)
	EXIT = Vector3(-3.5, 0, -_len * 0.5 + 4.5)
	# śmigła: dyski śmigieł wycięte z siatki modelu i przypięte do obracających się piast (_split_props)
	if res:
		_split_props(m)
	_prop = Node3D.new()
	add_child(_prop)
	_blades = Node3D.new()
	_prop.add_child(_blades)
	_disc = MeshInstance3D.new()
	_prop.add_child(_disc)
	# luk bombowy: punkty zrzutu w brzuchu
	for i in BOMBS:
		var r := Node3D.new()
		r.position = Vector3(0.0, -2.2, -2.0 + i * 0.6)
		add_child(r)
		_racks.append(r)


func _collision_boxes() -> Array:
	return [[Vector3(4.2, 4.0, _len * 0.92), Vector3(0, 0.4, 0)],          # kadłub
		[Vector3(40.0, 0.9, 4.2), Vector3(0, 2.7, -1.5)],                   # skrzydło (górnopłat)
		[Vector3(0.6, 6.0, 4.0), Vector3(0, 5.0, _len * 0.5 - 2.5)],       # statecznik pionowy
		[Vector3(16.0, 0.4, 3.0), Vector3(0, 2.3, _len * 0.5 - 2.5)]]      # statecznik poziomy


func _ready() -> void:
	super._ready()
	set_meta("size", Vector3(40.0, 4.0, _len))
	set_meta("hollow", 0.002)


## Osie śmigieł w układzie modelu (x, y) — cztery silniki; płaszczyzna łopat ok. z = −3,5
## (kołpak z przodu do z = −3,0, gondola za śmigłem).
const PROP_HUBS := [Vector2(-10.31, 4.27), Vector2(-5.22, 3.95), Vector2(4.97, 3.95), Vector2(10.05, 4.27)]
const PROP_Z := Vector2(-3.85, -2.9)     # warstwa śmigła (łopaty, kołpak) wzdłuż osi
const PROP_R := 1.95                     # promień śmigła [m] (łopaty mają 1,82 m)


## Śmigła są w siatce modelu zrośnięte z gondolami: trójkąty z dysku śmigła (wokół osi silnika,
## w warstwie łopat i kołpaka) przenoszone są do osobnych siatek na obracających się piastach.
func _split_props(m: Node3D) -> void:
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() != 1:
			continue
		# siatka -> układ modelu
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != m and n != null:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			continue
		var keep := PackedInt32Array()
		var per: Array = []
		for h in PROP_HUBS.size():
			per.append(PackedInt32Array())
		var hit := false
		for t in range(0, idx.size() - 2, 3):
			var c := xf * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)
			var hub := -1
			if c.z > PROP_Z.x and c.z < PROP_Z.y:
				for h in PROP_HUBS.size():
					var hp: Vector2 = PROP_HUBS[h]
					if Vector2(c.x - hp.x, c.y - hp.y).length() < PROP_R:
						hub = h
						break
			if hub < 0:
				keep.append(idx[t]); keep.append(idx[t + 1]); keep.append(idx[t + 2])
			else:
				hit = true
				var pa: PackedInt32Array = per[hub]
				pa.append(idx[t]); pa.append(idx[t + 1]); pa.append(idx[t + 2])
				per[hub] = pa
		if not hit:
			continue
		var mat := mi.get_active_material(0)
		var rest := arr.duplicate()
		rest[Mesh.ARRAY_INDEX] = keep
		var nm := ArrayMesh.new()
		nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rest)
		nm.surface_set_material(0, mat)
		mi.mesh = nm
		for h in PROP_HUBS.size():
			var sel: PackedInt32Array = per[h]
			if sel.is_empty():
				continue
			_add_prop_piece(m, h, _compact(arr, sel, xf, Vector3(PROP_HUBS[h].x, PROP_HUBS[h].y, -3.5)), mat)


## Podsiatka z wybranych trójkątów: tylko użyte wierzchołki, w układzie piasty (środek = 0).
func _compact(arr: Array, sel: PackedInt32Array, xf: Transform3D, hub: Vector3) -> Array:
	var remap := {}
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns = arr[Mesh.ARRAY_NORMAL]
	var uvs = arr[Mesh.ARRAY_TEX_UV]
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ou := PackedVector2Array()
	var oi := PackedInt32Array()
	for i in sel:
		if not remap.has(i):
			remap[i] = ov.size()
			ov.append(xf * vs[i] - hub)
			if ns != null:
				on.append((xf.basis * (ns as PackedVector3Array)[i]).normalized())
			if uvs != null:
				ou.append((uvs as PackedVector2Array)[i])
		oi.append(remap[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	if ns != null:
		out[Mesh.ARRAY_NORMAL] = on
	if uvs != null:
		out[Mesh.ARRAY_TEX_UV] = ou
	out[Mesh.ARRAY_INDEX] = oi
	return out


## Kawałek śmigła na piaście h (piasta tworzona przy pierwszym kawałku, z rozmytą tarczą).
func _add_prop_piece(m: Node3D, h: int, arrays: Array, mat: Material) -> void:
	while _spinners.size() <= h:
		_spinners.append(null)
		_prop_discs.append(null)
	if _spinners[h] == null:
		var spin := Node3D.new()
		m.add_child(spin)
		spin.position = Vector3(PROP_HUBS[h].x, PROP_HUBS[h].y, -3.5)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.85
		cm.bottom_radius = 1.85
		cm.height = 0.02
		cm.radial_segments = 32
		disc.mesh = cm
		var dm := StandardMaterial3D.new()
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(0.08, 0.08, 0.08, 0.25)
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		disc.material_override = dm
		disc.rotation.x = PI * 0.5
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.visible = false
		spin.add_child(disc)
		_spinners[h] = spin
		_prop_discs[h] = disc
	var bm := ArrayMesh.new()
	bm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	bm.surface_set_material(0, mat)
	var bi := MeshInstance3D.new()
	bi.mesh = bm
	(_spinners[h] as Node3D).add_child(bi)
	_parts.append(bi)


func _process(dt: float) -> void:
	super._process(dt)
	if destroyed:
		return
	for i in _spinners.size():
		if _spinners[i] == null:
			continue
		(_spinners[i] as Node3D).rotation.z = _prop_a
		(_prop_discs[i] as MeshInstance3D).visible = _disc.visible
