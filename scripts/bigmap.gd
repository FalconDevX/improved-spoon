extends Control
## Pełna mapa [M]: cały świat z góry (teren, las, pas, baza z budynkami i drogami), maszyny,
## stanowiska przeciwlotnicze, skrzynki, ja. LPM — punkt nawigacyjny (waypoint), PPM — usuń,
## kółko — przybliżenie. Waypoint widać też na minimapie, kompasie i w świecie (HUD).

const Terrain = preload("res://scripts/terrain.gd")
const Level = preload("res://scripts/level.gd")

var main
var level
var _tex: ImageTexture
var _roads: ImageTexture
var _zoom := 1.0
var _center := Vector2(0, 0)    # środek widoku w metrach (x, z)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_tex = ImageTexture.create_from_image(level.terrain.map_img)
	var img: Image = level.road_img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var v := img.get_pixel(x, y).r
			img.set_pixel(x, y, Color(0.72, 0.68, 0.58, v * 0.9))
	_roads = ImageTexture.create_from_image(img)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("map"):
		_toggle(not visible)
		get_viewport().set_input_as_handled()
	elif visible and e.is_action_pressed("ui_cancel"):
		_toggle(false)
		get_viewport().set_input_as_handled()


func _toggle(on: bool) -> void:
	visible = on
	if on:
		var p = main._player
		_center = Vector2(p.global_position.x, p.global_position.z) if is_instance_valid(p) else Vector2.ZERO
		_zoom = 1.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Kwadrat mapy na ekranie i skala [px/m].
func _frame() -> Rect2:
	var vs := get_viewport_rect().size
	var s := minf(vs.x, vs.y) * 0.86
	return Rect2((vs - Vector2(s, s)) * 0.5, Vector2(s, s))


func _scale() -> float:
	return _frame().size.x / (Terrain.WORLD * 2.0) * _zoom


func _view_center() -> Vector2:
	# przy zbliżeniu widok trzyma się w granicach świata
	var half := Terrain.WORLD / _zoom
	return Vector2(clampf(_center.x, -Terrain.WORLD + half, Terrain.WORLD - half), clampf(_center.y, -Terrain.WORLD + half, Terrain.WORLD - half))


func to_screen(w: Vector2) -> Vector2:
	var f := _frame()
	return f.get_center() + (w - _view_center()) * _scale()


func to_world(s: Vector2) -> Vector2:
	var f := _frame()
	return _view_center() + (s - f.get_center()) / _scale()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and _frame().has_point(mb.position):
			var w := to_world(mb.position)
			main.waypoint = Vector3(w.x, Terrain.height(w.x, w.y), w.y)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			main.waypoint = Vector3.INF
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			var before := to_world(mb.position)
			_zoom = minf(_zoom * 1.25, 8.0)
			_center += before - to_world(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(_zoom / 1.25, 1.0)
		accept_event()
	elif e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_center -= (e as InputEventMouseMotion).relative / _scale()
		accept_event()


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	var f := _frame()
	var font := get_theme_default_font()
	# świat (przycięty do ramki)
	var tl := to_screen(Vector2(-Terrain.WORLD, -Terrain.WORLD))
	var br := to_screen(Vector2(Terrain.WORLD, Terrain.WORLD))
	var src := Rect2(Vector2.ZERO, _tex.get_size())
	var dst := Rect2(tl, br - tl)
	var clip := dst.intersection(f)
	if clip.size.x > 0.0:
		var k := _tex.get_size() / dst.size
		draw_texture_rect_region(_tex, clip, Rect2((clip.position - dst.position) * k, clip.size * k))
	var hs: float = Level.HALF
	var rtl := to_screen(Vector2(-hs, -hs))
	var rbr := to_screen(Vector2(hs, hs))
	draw_texture_rect(_roads, Rect2(rtl, rbr - rtl), false)
	for rf: Dictionary in level.roofs:
		var a: AABB = rf["aabb"]
		var p0 := to_screen(Vector2(a.position.x, a.position.z))
		var p1 := to_screen(Vector2(a.end.x, a.end.z))
		draw_rect(Rect2(p0, p1 - p0), Color(0.6, 0.6, 0.62))
	draw_rect(Rect2(rtl, rbr - rtl), Color(0.85, 0.75, 0.5, 0.8), false, 1.5)
	for h: Vector2 in Terrain.HANGARS:
		var hp := to_screen(h)
		draw_rect(Rect2(hp - Vector2(13, 17) * _scale(), Vector2(26, 34) * _scale()), Color(0.5, 0.52, 0.5))
	# skrzynki, stanowiska OPL, maszyny
	for cr in get_tree().get_nodes_in_group("ammo_crate"):
		var q := to_screen(Vector2(cr.global_position.x, cr.global_position.z))
		draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), Color(0.95, 0.3, 0.25) if cr.kind == "med" else Color(1.0, 0.82, 0.25))
	for aa in get_tree().get_nodes_in_group("emplacement"):
		var q := to_screen(Vector2(aa.global_position.x, aa.global_position.z))
		draw_circle(q, 5.0, Color(0.4, 0.8, 1.0))
		draw_string(font, q + Vector2(7, 4), "OPL" if aa.kind == "gun" else "RAK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.9, 1.0))
	var me = main._player
	for pl in get_tree().get_nodes_in_group("plane"):
		if pl.destroyed:
			continue
		var q := to_screen(Vector2(pl.global_position.x, pl.global_position.z))
		var fw: Vector3 = -pl.global_basis.z
		var d := Vector2(fw.x, fw.z).normalized() if Vector2(fw.x, fw.z).length() > 0.01 else Vector2.UP
		var sd := Vector2(-d.y, d.x)
		var enemy: bool = pl.pilot != null and is_instance_valid(pl.pilot) and pl.pilot != me
		var col := Color(1.0, 0.3, 0.2) if enemy else Color(0.75, 0.88, 1.0)
		if pl.get("is_heli") == true:
			draw_circle(q, 5.0, col)
			draw_line(q - d * 9.0, q + d * 9.0, col, 1.5)
			draw_line(q - sd * 9.0, q + sd * 9.0, col, 1.5)
		else:
			draw_colored_polygon(PackedVector2Array([q + d * 10.0, q - d * 7.0 + sd * 7.0, q - d * 3.0, q - d * 7.0 - sd * 7.0]), col)
	# ja
	if is_instance_valid(me):
		var q := to_screen(Vector2(me.global_position.x, me.global_position.z))
		var cam := get_viewport().get_camera_3d()
		var fw := -cam.global_basis.z if cam else Vector3.FORWARD
		var d := Vector2(fw.x, fw.z).normalized() if Vector2(fw.x, fw.z).length() > 0.01 else Vector2.UP
		var sd := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([q + d * 11.0, q - d * 7.0 + sd * 7.0, q - d * 3.0, q - d * 7.0 - sd * 7.0]), Color(1.0, 0.92, 0.35))
	# waypoint
	var wp: Vector3 = main.waypoint
	if wp != Vector3.INF:
		var q := to_screen(Vector2(wp.x, wp.z))
		_diamond(q, 9.0, Color(0.3, 1.0, 0.9))
		if is_instance_valid(me):
			draw_line(to_screen(Vector2(me.global_position.x, me.global_position.z)), q, Color(0.3, 1.0, 0.9, 0.5), 1.5)
			draw_string(font, q + Vector2(12, 5), "%d m" % int(Vector2(wp.x - me.global_position.x, wp.z - me.global_position.z).length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 1.0, 0.9))
	draw_rect(f, Color(0.85, 0.75, 0.5, 0.9), false, 2.0)
	# podziałka 500 m i opis
	var bar := 500.0 * _scale()
	var bp := f.position + Vector2(16, f.size.y - 20)
	draw_line(bp, bp + Vector2(bar, 0), Color(1, 1, 1, 0.9), 2.0)
	draw_string(font, bp + Vector2(0, -6), "500 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(f.position.x, f.position.y - 10), "MAPA  [M]   LPM — punkt nawigacyjny   PPM — usuń   kółko — przybliżenie, środkowy — przesuń",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.92, 0.7))
	draw_string(font, to_screen(Vector2(0, -Terrain.WORLD)) + Vector2(-5, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.4))


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)
	draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), Color(0, 0, 0, 0.8), 1.5)
