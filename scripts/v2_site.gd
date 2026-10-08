extends Node3D
## Stanowisko startowe V-2 w bazie: betonowa płyta, stalowy stół startowy (Brennstand) na
## czterech nogach ze stożkowym deflektorem płomienia, rakieta stojąca pionowo, pulpit obok.
## [F] przy pulpicie otwiera mapę — kliknięcie wybiera cel, rakieta odlicza i startuje (v2.gd).
## Następna staje na stole po RELOAD sekundach. W sieci wysyłany jest tylko cel (net_launch) —
## lot jest deterministyczny, więc u wszystkich rakieta leci tym samym torem.

const V2 = preload("res://scripts/v2.gd")
const Player = preload("res://scripts/player.gd")

const TABLE_H := 1.6                     # blat stołu startowego nad płytą
const CONSOLE := Vector3(9.0, 0.0, 0.0)  # pulpit (żołnierz stoi tu)
const RELOAD := 60.0
const MIN_RANGE := 300.0

var board_name := "V-2"
var board_text := "[F] — wybierz cel V-2 na mapie"
var rocket = null
var _reload := 0.0
var _body: StaticBody3D
var _lamp: StandardMaterial3D


func _ready() -> void:
	add_to_group("launcher")
	_build()
	_new_rocket()
	if Player.net_on:
		get_node("/root/GDSync").expose_func(net_launch)


func _mat(c: Color, metal := 0.0, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _block(size: Vector3, pos: Vector3, mat: Material, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		_body.add_child(cs)


func _build() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var concrete := _mat(Color(0.5, 0.5, 0.48))
	var steel := _mat(Color(0.24, 0.27, 0.22), 0.6, 0.55)
	_block(Vector3(12.0, 0.3, 12.0), Vector3(0, 0.15, 0), concrete)
	# stół startowy: blat z otworem (cztery belki), nogi, deflektor
	var top := TABLE_H + 0.3
	for s: float in [-1.0, 1.0]:
		_block(Vector3(3.2, 0.25, 0.5), Vector3(0, top, s * 1.35), steel)
		_block(Vector3(0.5, 0.25, 3.2), Vector3(s * 1.35, top, 0), steel)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_block(Vector3(0.3, TABLE_H, 0.3), Vector3(sx * 1.4, 0.3 + TABLE_H * 0.5, sz * 1.4), steel)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 1.2
	cm.height = 1.2
	cone.mesh = cm
	cone.material_override = steel
	cone.position = Vector3(0, 0.9, 0)
	add_child(cone)
	# pulpit z lampką
	_block(Vector3(0.6, 1.05, 1.3), CONSOLE + Vector3(0.6, 0.52, 0), _mat(Color(0.25, 0.28, 0.24), 0.3, 0.6))
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.07
	lm.height = 0.14
	lamp.mesh = lm
	_lamp = StandardMaterial3D.new()
	_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.material_override = _lamp
	lamp.position = CONSOLE + Vector3(0.5, 1.1, 0.3)
	add_child(lamp)
	# osłona z worków przed pulpitem (od strony stołu)
	_block(Vector3(0.8, 1.2, 3.0), CONSOLE + Vector3(-1.6, 0.6, 0), _mat(Color(0.55, 0.48, 0.34)))


func body_rids() -> Array[RID]:
	return [_body.get_rid()]


func _new_rocket() -> void:
	rocket = V2.new()
	rocket.site = self
	add_child(rocket)
	rocket.top_level = true
	rocket.global_transform = Transform3D(Basis(), global_transform * Vector3(0, TABLE_H + 0.45, 0))
	_lamp.albedo_color = Color(0.3, 1.0, 0.3)


func ready_to_fire() -> bool:
	return rocket != null and is_instance_valid(rocket) and rocket.phase == 0


func can_board(p) -> bool:
	if not ready_to_fire() or p.get("vehicle") != null or p.get("down") == true:
		return false
	var c := global_transform * CONSOLE
	var d: Vector3 = p.global_position - c
	return Vector2(d.x, d.z).length() < 2.6 and absf(d.y) < 2.0


## [F] przy pulpicie: mapa w trybie wyboru celu.
func board(p) -> void:
	var main := get_parent()
	if main.get("bigmap") == null:
		return
	main.bigmap.pick_target("CEL V-2", func(at: Vector3) -> void:
		if not ready_to_fire():
			return
		if Vector2(at.x - global_position.x, at.z - global_position.z).length() < MIN_RANGE:
			p._msg("Cel za blisko — minimum %d m od stanowiska" % int(MIN_RANGE))
			return
		_fire(at, p)
		if Player.net_on:
			get_node("/root/GDSync").call_func(net_launch, at, int(p.get("net_id") if p.get("net_id") != null else 0))
		p._msg("V-2: odliczanie... cel %d m" % int(Vector2(at.x - global_position.x, at.z - global_position.z).length())))


func _fire(at: Vector3, who) -> void:
	_lamp.albedo_color = Color(1.0, 0.25, 0.2)
	rocket.launch(at, who)


## (zdalnie) inny gracz odpalił rakietę z tego stanowiska na cel `at`.
func net_launch(at: Vector3, id: int) -> void:
	if not ready_to_fire():
		_reload = 0.0
		if rocket != null and is_instance_valid(rocket):
			rocket.queue_free()
		_new_rocket()
	_fire(at, get_parent().get_node_or_null("P%d" % id))


## Rakieta zeszła ze stołu: odliczanie do następnej.
func on_launched() -> void:
	_reload = RELOAD


func _process(dt: float) -> void:
	if _reload > 0.0:
		_reload -= dt
		if _reload <= 0.0:
			_new_rocket()
