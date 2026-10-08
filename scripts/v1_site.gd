extends Node3D
## Wyrzutnia V-1: pochylona stalowa rampa (katapulta parowa typu Walter, 48 m, 6°) na betonowych
## podporach, z murami osłonowymi u podstawy, wózkiem wytwornicy pary i bunkrem dowodzenia
## z pulpitem startowym. Przy pulpicie [F] odpala pocisk stojący na rampie (v1.gd); po starcie
## następny jest podwieszany po RELOAD sekundach.
## Układ lokalny: początek u stopy rampy na ziemi, start w −Z.

const V1 = preload("res://scripts/v1.gd")
const FX = preload("res://scripts/fx.gd")

const LENGTH := 48.0
const INCLINE := deg_to_rad(6.0)
const RAIL_H := 1.0                      # wysokość szyn u stopy rampy
const RIDE := 0.45                       # oś pocisku nad szynami
const START_S := 4.5                     # pocisk stoi tyle od stopy rampy
const CONSOLE := Vector3(5.5, 0.0, 3.0)  # miejsce żołnierza przy pulpicie
const RELOAD := 25.0

var board_name := "V-1"
var board_text := "[F] — odpal V-1 z pulpitu"
var missile = null
var _reload := 0.0
var _body: StaticBody3D
var _lamp: StandardMaterial3D


func _ready() -> void:
	add_to_group("launcher")
	_build()
	_new_missile()


func _mat(c: Color, metal := 0.0, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


## Bryła z kolizją (prostopadłościan w układzie wyrzutni).
func _block(size: Vector3, xf: Transform3D, mat: Material, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xf
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = xf
		_body.add_child(cs)


func rail_point(s: float) -> Vector3:
	return Vector3(0, RAIL_H + s * sin(INCLINE), -s * cos(INCLINE))


func _build() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var concrete := _mat(Color(0.56, 0.55, 0.52))
	var steel := _mat(Color(0.2, 0.21, 0.2), 0.7, 0.5)
	var rail := _mat(Color(0.45, 0.45, 0.46), 0.9, 0.3)
	var tilt := Basis(Vector3.RIGHT, INCLINE)
	# fundament
	_block(Vector3(4.2, 0.3, LENGTH + 4.0), Transform3D(Basis(), Vector3(0, 0.15, -LENGTH * 0.5 + 1.0)), concrete)
	# betonowe podpory co 6 m
	var s := 3.0
	while s < LENGTH:
		var top := rail_point(s).y - 0.75
		_block(Vector3(2.4, top, 0.8), Transform3D(Basis(), Vector3(0, top * 0.5, -s * cos(INCLINE))), concrete)
		s += 6.0
	# dźwigar rampy (skrzynka stalowa) z szynami i szczelinową rurą tłoka katapulty
	var mid := rail_point(LENGTH * 0.5)
	_block(Vector3(1.1, 0.6, LENGTH), Transform3D(tilt, mid + Vector3(0, -0.42, 0)), steel)
	for x: float in [-0.32, 0.32]:
		_block(Vector3(0.1, 0.14, LENGTH), Transform3D(tilt, mid + Vector3(x, -0.05, 0)), rail, false)
	var tube := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = 0.15
	cm.height = LENGTH
	tube.mesh = cm
	tube.material_override = steel
	tube.transform = Transform3D(tilt * Basis(Vector3.RIGHT, PI * 0.5), mid + Vector3(0, -0.02, 0))
	add_child(tube)
	# kratownica boczna dźwigara (pasy i słupki co 3 m)
	var k := 1.5
	while k < LENGTH:
		var p := rail_point(k)
		for x: float in [-0.62, 0.62]:
			_block(Vector3(0.08, 0.9, 0.08), Transform3D(tilt, p + Vector3(x, -0.6, 0)), steel, false)
		k += 3.0
	# mury osłonowe wzdłuż początku rampy
	for x: float in [-3.4, 3.4]:
		_block(Vector3(0.6, 2.8, 14.0), Transform3D(Basis(), Vector3(x, 1.4, -7.0)), concrete)
	# wózek wytwornicy pary za stopą rampy
	_block(Vector3(2.0, 0.9, 3.8), Transform3D(Basis(), Vector3(0, 0.75, 3.2)), _mat(Color(0.3, 0.33, 0.27), 0.4, 0.6))
	var tank := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.7
	tm.bottom_radius = 0.7
	tm.height = 3.2
	tank.mesh = tm
	tank.material_override = _mat(Color(0.36, 0.38, 0.32), 0.5, 0.5)
	tank.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.9, 3.2))
	add_child(tank)
	# bunkier dowodzenia z pulpitem startowym
	_block(Vector3(4.0, 2.6, 3.6), Transform3D(Basis(), Vector3(8.0, 1.3, 5.5)), concrete)
	_block(Vector3(1.3, 1.05, 0.5), Transform3D(Basis(), CONSOLE + Vector3(0, 0.52, -0.7)), _mat(Color(0.25, 0.28, 0.24), 0.3, 0.6))
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.07
	lm.height = 0.14
	lamp.mesh = lm
	_lamp = StandardMaterial3D.new()
	_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.material_override = _lamp
	lamp.position = CONSOLE + Vector3(0.3, 1.08, -0.6)
	add_child(lamp)


func body_rids() -> Array[RID]:
	return [_body.get_rid()]


func _new_missile() -> void:
	missile = V1.new()
	missile.site = self
	add_child(missile)
	missile.top_level = true
	missile.rail_from = global_transform * (rail_point(START_S) + Vector3.UP * RIDE)
	missile.rail_to = global_transform * (rail_point(LENGTH) + Vector3.UP * RIDE)
	var dir: Vector3 = (missile.rail_to - missile.rail_from).normalized()
	missile.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), missile.rail_from)
	_lamp.albedo_color = Color(0.3, 1.0, 0.3)


func ready_to_fire() -> bool:
	return missile != null and is_instance_valid(missile) and missile.phase == 0


func can_board(p) -> bool:
	if not ready_to_fire() or p.get("vehicle") != null or p.get("down") == true:
		return false
	var c := global_transform * CONSOLE
	var d: Vector3 = p.global_position - c
	return Vector2(d.x, d.z).length() < 2.6 and absf(d.y) < 2.0


func board(p) -> void:
	_lamp.albedo_color = Color(1.0, 0.25, 0.2)
	var foot := global_transform * rail_point(0.0)
	# katapulta: wybuch pary pod tłokiem, huk i obłok wzdłuż szyn
	FX.I.play("boom", foot, 6.0, 0.05, 1.7, 50.0)
	FX.I.play("whoosh", foot, 8.0, 0.05, 0.5, 40.0)
	_steam(foot, 1.0)
	missile.launch(p)


## Pocisk zszedł z rampy: obłok pary na końcu szyn, odliczanie do podwieszenia następnego.
func on_launched() -> void:
	_steam(global_transform * rail_point(LENGTH), 0.7)
	_reload = RELOAD


func _steam(pos: Vector3, k: float) -> void:
	FX.I._burst(pos, int(40 * k), 3.5, 2.0, 9.0, Vector3(0, 1.2, 0),
		[Color(0.95, 0.95, 0.95, 0.85), Color(0.9, 0.9, 0.9, 0.45), Color(0.9, 0.9, 0.9, 0.0)], 3.0 * k, false)


func _process(dt: float) -> void:
	if _reload > 0.0:
		_reload -= dt
		if _reload <= 0.0:
			_new_missile()
