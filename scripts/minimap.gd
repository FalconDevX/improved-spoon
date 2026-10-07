extends Control
## Minimapa (lewy górny róg, obraca się z kierunkiem patrzenia — jak w CoD) i kompas u góry ekranu.
## Na mapie: drogi, budynki, granica, lotnisko, samoloty, wrogowie, którzy właśnie strzelali
## (czerwone kropki), w samolocie mapa się oddala.

const Level = preload("res://scripts/level.gd")

const SIZE := 210.0
const SHOT_SHOW := 2.5     # jak długo strzelający wróg widnieje na mapie [s]
const HEAR_SHOT := 150.0   # z jakiej odległości strzał „słychać” na minimapie [m]

var main
var level
var _view: Control
var _roads: ImageTexture
var _world: ImageTexture
var _zoom := 1.6           # piksele na metr


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = Control.new()
	_view.position = Vector2(20, 20)
	_view.size = Vector2(SIZE, SIZE)
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.draw.connect(_draw_map)
	var img: Image = level.road_img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var v := img.get_pixel(x, y).r
			img.set_pixel(x, y, Color(0.72, 0.68, 0.58, v * 0.85))
	_roads = ImageTexture.create_from_image(img)
	_world = ImageTexture.create_from_image(level.terrain.map_img)


func _process(dt: float) -> void:
	var p = main._player
	var flying: bool = p != null and is_instance_valid(p) and p.get("vehicle") != null
	_zoom = lerpf(_zoom, 0.32 if flying else 1.6, 1.0 - exp(-3.0 * dt))
	queue_redraw()
	_view.queue_redraw()


func _heading() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var f := -cam.global_basis.z
	return atan2(f.x, -f.z)      # 0 = północ (-Z), + = na wschód


func _draw() -> void:
	var p = main._player
	if p == null or not is_instance_valid(p):
		return
	# ramka minimapy
	var r := Rect2(_view.position - Vector2(3, 3), _view.size + Vector2(6, 6))
	draw_rect(r, Color(0, 0, 0, 0.55))
	draw_rect(r, Color(0.75, 0.85, 0.8, 0.5), false, 1.5)
	_draw_compass()


func _draw_map() -> void:
	var p = main._player
	if p == null or not is_instance_valid(p):
		return
	var v := _view
	var c := v.size * 0.5
	v.draw_rect(Rect2(Vector2.ZERO, v.size), Color(0.11, 0.15, 0.1, 0.85))
	var me: Vector3 = p.global_position
	var th := _heading()
	v.draw_set_transform(c, -th, Vector2(_zoom, _zoom))
	var o := Vector2(-me.x, -me.z)
	var ws: float = level.terrain.WORLD
	v.draw_texture_rect(_world, Rect2(o + Vector2(-ws, -ws), Vector2(ws * 2.0, ws * 2.0)), false, Color(1, 1, 1, 0.75))
	var hs: float = Level.HALF
	v.draw_texture_rect(_roads, Rect2(o + Vector2(-hs, -hs), Vector2(hs * 2.0, hs * 2.0)), false)
	v.draw_rect(Rect2(o + Vector2(-hs, -hs), Vector2(hs * 2.0, hs * 2.0)), Color(0.85, 0.75, 0.5, 0.6), false, 2.0 / _zoom)
	for rf: Dictionary in level.roofs:
		var a: AABB = rf["aabb"]
		v.draw_rect(Rect2(o + Vector2(a.position.x, a.position.z), Vector2(a.size.x, a.size.z)), Color(0.55, 0.58, 0.6, 0.85))
	var now := Time.get_ticks_msec() / 1000.0
	# wrogowie, którzy właśnie strzelali — tylko gdy strzał słychać (blisko, nie z kabiny maszyny)
	var in_air: bool = p.get("vehicle") != null and is_instance_valid(p.vehicle) and p.vehicle.get("is_emplacement") != true
	for n in get_tree().get_nodes_in_group("npc") + get_tree().get_nodes_in_group("net_player"):
		if in_air or not is_instance_valid(n) or n.down or not n.has_meta("shot_t"):
			continue
		if n.global_position.distance_to(p.global_position) > HEAR_SHOT:
			continue
		var age: float = now - float(n.get_meta("shot_t"))
		if age > SHOT_SHOW:
			continue
		var q := o + Vector2(n.global_position.x, n.global_position.z)
		v.draw_circle(q, 4.5 / _zoom, Color(1.0, 0.2, 0.15, 1.0 - age / SHOT_SHOW))
	# skrzynki z amunicją: żółte (pełne) / szare (odnawiają się)
	for cr in get_tree().get_nodes_in_group("ammo_crate"):
		var q := o + Vector2(cr.global_position.x, cr.global_position.z)
		var s2 := 4.5 / _zoom
		var full: bool = cr.is_ready()
		v.draw_rect(Rect2(q - Vector2(s2, s2), Vector2(s2, s2) * 2.0), Color(0, 0, 0, 0.7))
		if cr.kind == "med":
			# apteczka: biały kwadrat z czerwonym krzyżem
			v.draw_rect(Rect2(q - Vector2(s2, s2) * 0.75, Vector2(s2, s2) * 1.5), Color(0.95, 0.95, 0.95) if full else Color(0.55, 0.55, 0.55))
			var rc := Color(0.9, 0.1, 0.08) if full else Color(0.35, 0.35, 0.35)
			v.draw_rect(Rect2(q - Vector2(s2 * 0.55, s2 * 0.18), Vector2(s2 * 1.1, s2 * 0.36)), rc)
			v.draw_rect(Rect2(q - Vector2(s2 * 0.18, s2 * 0.55), Vector2(s2 * 0.36, s2 * 1.1)), rc)
		else:
			v.draw_rect(Rect2(q - Vector2(s2, s2) * 0.75, Vector2(s2, s2) * 1.5), Color(1.0, 0.82, 0.25) if full else Color(0.55, 0.55, 0.55))
			v.draw_line(q - Vector2(0, s2 * 0.6), q + Vector2(0, s2 * 0.6), Color(0.15, 0.12, 0.05), 1.2 / _zoom)
	# samoloty
	for pl in get_tree().get_nodes_in_group("plane"):
		if pl.destroyed or pl == p.get("vehicle"):
			continue
		var f: Vector3 = -pl.global_basis.z
		var dir := Vector2(f.x, f.z).normalized() if Vector2(f.x, f.z).length() > 0.01 else Vector2.UP
		var q := o + Vector2(pl.global_position.x, pl.global_position.z)
		var enemy: bool = pl.pilot != null and is_instance_valid(pl.pilot) and pl.pilot != p
		var col := Color(1.0, 0.3, 0.2) if enemy else Color(0.7, 0.85, 1.0, 0.8)
		var s := 7.0 / _zoom
		var side := Vector2(-dir.y, dir.x)
		v.draw_colored_polygon(PackedVector2Array([q + dir * s * 1.4, q - dir * s + side * s, q - dir * s * 0.4, q - dir * s - side * s]), col)
	# punkt nawigacyjny (przy krawędzi, gdy poza minimapą)
	if main.waypoint != Vector3.INF:
		var wq := o + Vector2(main.waypoint.x, main.waypoint.z)
		var lim := (SIZE * 0.5 - 8.0) / _zoom
		if wq.length() > lim:
			wq = wq.normalized() * lim
		var r := 6.0 / _zoom
		v.draw_colored_polygon(PackedVector2Array([wq + Vector2(0, -r), wq + Vector2(r, 0), wq + Vector2(0, r), wq + Vector2(-r, 0)]), Color(0.3, 1.0, 0.9))
	v.draw_set_transform(c, 0.0, Vector2.ONE)
	# ja: strzałka w środku, zawsze w górę
	var col_me := Color(1.0, 0.92, 0.35)
	v.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)]), col_me)
	# stożek widzenia
	v.draw_line(c, c + Vector2(-40, -70), Color(1, 1, 1, 0.12), 1.0, true)
	v.draw_line(c, c + Vector2(40, -70), Color(1, 1, 1, 0.12), 1.0, true)
	# litera N na krawędzi mapy
	var npos := c + Vector2(sin(-th), -cos(-th)) * (SIZE * 0.5 - 12.0)
	var font := get_theme_default_font()
	v.draw_string(font, npos - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.4))


## Kompas: pasek z kierunkami świata i podziałką co 15°.
func _draw_compass() -> void:
	var vs := get_viewport_rect().size
	var font := get_theme_default_font()
	var cx := vs.x * 0.5
	var y := 86.0
	var w := 520.0
	var th := rad_to_deg(_heading())
	draw_rect(Rect2(cx - w * 0.5, y - 18, w, 30), Color(0, 0, 0, 0.3))
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	var px_per_deg := w / 120.0
	for k in range(-60, 61):
		var deg := int(round(th)) + k
		var dn := posmod(deg, 360)
		if dn % 5 != 0:
			continue
		var x := cx + (deg - th) * px_per_deg
		if absf(x - cx) > w * 0.5 - 4.0:
			continue
		var a := 1.0 - absf(x - cx) / (w * 0.5)
		var col := Color(1, 1, 1, 0.85 * a)
		if names.has(dn):
			var t: String = names[dn]
			var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, Vector2(x - ts * 0.5, y + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.4, a) if dn == 0 else col)
		elif dn % 15 == 0:
			draw_line(Vector2(x, y - 12), Vector2(x, y - 2), col, 1.5)
			var t2 := str(dn)
			var ts2 := font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(font, Vector2(x - ts2 * 0.5, y + 10), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.5 * a))
		else:
			draw_line(Vector2(x, y - 8), Vector2(x, y - 3), Color(1, 1, 1, 0.4 * a), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, y - 14), Vector2(cx - 6, y - 22), Vector2(cx + 6, y - 22)]), Color(1, 0.85, 0.4))
	var hd := posmod(int(round(th)), 360)
	var s := "%03d" % hd
	var sw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(cx - sw * 0.5, y + 26), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.6, 0.9))
