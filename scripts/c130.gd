extends "res://scripts/plane.gd"
## Lockheed C-130 Hercules: czterosilnikowy transportowiec (model z pliku, ~25 tys. trójkątów).
## Lata jak myśliwiec (ten sam model lotu), ale jest cięższy i bardziej ociężały: mniejszy ciąg,
## wolniej się przechyla i pochyla, ma dużo więcej wytrzymałości. Bez karabinów; z luku w brzuchu
## zrzuca serię 8 bomb [Spacja]; [B] zmienia rodzaj — jako jedyny może wziąć bombę atomową. Wsiada się przy drzwiach z lewej strony kabiny.

const MODEL_PATH := "res://assets/vehicles/c130.glb"

var _len := 29.8


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
	bomb_kinds = ["frag", "he", "napalm", "cluster", "nuke"]
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
	# śmigła modelu są jedną siatką (nie kręcą się osobno); puste węzły dla wspólnego kodu
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
