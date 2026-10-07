extends Control
## HUD strzelanki: broń i amunicja, krew i rany, wytrzymałość, oddech, znacznik trafienia,
## kierunek ostrzału, komunikaty. Solo: licznik wyeliminowanych. PvP: wynik, kod gry, odrodzenie.

const Npc = preload("res://scripts/npc.gd")
const Vitals = preload("res://scripts/vitals.gd")

var player = null
var xray := false
var pvp := false
var code := ""
var status := ""
var respawn_in := -1.0
var _cards: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var font := get_theme_default_font()
	var vs := get_viewport_rect().size
	if xray:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.04, 0.1, 0.22))
		draw_string(font, Vector2(vs.x * 0.5 - 70, 70), "RENTGEN  [Tab]", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.5, 0.85, 1.0, 0.95))
	_draw_help(font)
	_draw_crosshair(vs)
	_draw_damage_dirs(vs)
	_draw_weapon(font, vs)
	_draw_vitals(font, vs)
	if player.message_t > 0.0:
		var a := clampf(player.message_t, 0.0, 1.0)
		_center_text(font, player.message, Vector2(vs.x * 0.5, vs.y * 0.5 + 90), 18, Color(1, 0.95, 0.8, a))
	if Time.get_ticks_msec() / 1000.0 - player.last_injury_time < 3.0:
		_center_text(font, "Trafiony: " + player.last_injury, Vector2(vs.x * 0.5, vs.y * 0.5 + 120), 18, Color(1, 0.45, 0.35))
	if pvp:
		_draw_pvp(font, vs)
	else:
		draw_string(font, Vector2(vs.x - 230, 34), "Wyeliminowani: %d" % Npc.deaths, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.95, 1.0, 0.9))
		if player.down:
			_center_text(font, "WYELIMINOWANY (%s) — F5: od nowa" % ("nie żyjesz" if player.vitals.dead else "nieprzytomny"),
				Vector2(vs.x * 0.5, vs.y * 0.5 - 40), 26, Color(1, 0.4, 0.3))
	_draw_enemies(font)


func _draw_help(font: Font) -> void:
	var help := [
		"WASD - ruch   Shift - bieg (w celowaniu: wstrzymanie oddechu)   Spacja - skok   Ctrl - kucanie   X - chód",
		"LPM - strzał   PPM - celowanie   R - przeładowanie   B - tryb ognia   1-0 / kółko - broń",
		"V - pierwsza osoba / zza ramienia   L - laser   H - opatrunek   E - amunicja poległych   Tab - rentgen   Esc - kursor",
	]
	for i in help.size():
		draw_string(font, Vector2(20, 28 + i * 20), help[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0, 0.6))


func _center_text(font: Font, t: String, at: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, at - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_crosshair(vs: Vector2) -> void:
	var c := vs * 0.5
	if player.scoped():
		_draw_scope(vs)
	elif (player.ads < 0.5 or not player.first_person) and not player.down:
		var col := Color(1, 1, 1, 0.7)
		var g: float = 6.0 + player._move.length() * 2.0
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * g, c + d * (g + 7.0), col, 1.5, true)
		draw_circle(c, 1.2, col)
	if player.hit_marker > 0.0:
		var hc := Color(1, 0.25, 0.2, player.hit_marker) if player.hit_kill else Color(1, 1, 1, player.hit_marker)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 6.0, c + d * 13.0, hc, 2.0, true)


## Obraz lunety: czarne tło, siatka celownicza z kreskami.
func _draw_scope(vs: Vector2) -> void:
	var c := vs * 0.5
	var r := vs.y * 0.46
	var k := Color(0, 0, 0)
	draw_rect(Rect2(0, 0, c.x - r, vs.y), k)
	draw_rect(Rect2(c.x + r, 0, vs.x - c.x - r, vs.y), k)
	for i in 64:
		var a0 := TAU * i / 64.0
		var a1 := TAU * (i + 1) / 64.0
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var q0 := c + Vector2(cos(a0), sin(a0)) * r * 1.6
		var q1 := c + Vector2(cos(a1), sin(a1)) * r * 1.6
		draw_colored_polygon(PackedVector2Array([p0, q0, q1, p1]), k)
	draw_arc(c, r, 0.0, TAU, 96, Color(0.05, 0.05, 0.05), 6.0, true)
	var lc := Color(0, 0, 0, 0.95)
	draw_line(c - Vector2(r, 0), c - Vector2(r * 0.08, 0), lc, 3.0)
	draw_line(c + Vector2(r * 0.08, 0), c + Vector2(r, 0), lc, 3.0)
	draw_line(c + Vector2(0, r * 0.08), c + Vector2(0, r), lc, 3.0)
	draw_line(c - Vector2(0, r), c - Vector2(0, r * 0.08), lc, 1.5)
	draw_line(c - Vector2(r * 0.08, 0), c + Vector2(r * 0.08, 0), lc, 1.0)
	draw_line(c - Vector2(0, r * 0.08), c + Vector2(0, r * 0.08), lc, 1.0)
	for i in range(1, 5):
		var y := c.y + r * 0.08 * i
		draw_line(Vector2(c.x - 5, y), Vector2(c.x + 5, y), lc, 1.0)
	draw_circle(c, 1.5, Color(0.9, 0.1, 0.05))


## Czerwone łuki od strony, z której padły strzały.
func _draw_damage_dirs(vs: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := vs * 0.5
	for dd: Array in player.damage_dirs:
		var w: Vector3 = dd[0]
		var lo := cam.global_basis.inverse() * w
		var ang := atan2(lo.x, -lo.z)
		var a := clampf(float(dd[1]) / 2.5, 0.0, 1.0)
		var mid := ang - PI * 0.5
		draw_arc(c, 120.0, mid - 0.3, mid + 0.3, 16, Color(1, 0.15, 0.1, 0.8 * a), 6.0, true)


func _draw_weapon(font: Font, vs: Vector2) -> void:
	var g = player.gun
	if g == null:
		return
	var x := vs.x - 300
	var y := vs.y - 90
	draw_rect(Rect2(x - 12, y - 30, 300, 100), Color(0, 0, 0, 0.35))
	draw_string(font, Vector2(x, y), String(g.data["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.92, 0.7))
	var mode: String = {"auto": "seria", "semi": "pojedynczy", "pump": "pompka", "bolt": "zamek"}.get(g.fire_mode(), g.fire_mode())
	draw_string(font, Vector2(x, y + 22), "%s   [B]" % mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 1, 0.75))
	var rounds: int = g.rounds + (1 if g.chambered else 0)
	var col := Color(1, 1, 1) if rounds > 0 else Color(1, 0.35, 0.3)
	draw_string(font, Vector2(x, y + 56), "%d" % rounds, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, col)
	var res := "/ %d" % g.reserve()
	if g.data["feed"] == "mag":
		res += "   (mag. %d)" % g.mags.size()
	draw_string(font, Vector2(x + 64, y + 56), res, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.9, 1, 0.85))
	if player.reloading >= 0.0:
		_center_text(font, "PRZEŁADOWANIE", Vector2(vs.x * 0.5, vs.y * 0.5 + 60), 16, Color(1, 0.9, 0.5))
	elif rounds == 0:
		_center_text(font, "PUSTY — R", Vector2(vs.x * 0.5, vs.y * 0.5 + 60), 16, Color(1, 0.45, 0.35))


func _bar(at: Vector2, w: float, frac: float, col: Color, label: String, font: Font) -> void:
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(w + 4, 12)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(at, Vector2(w * clampf(frac, 0.0, 1.0), 8)), col)
	draw_string(font, at + Vector2(w + 10, 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.93, 1, 0.8))


func _draw_vitals(font: Font, vs: Vector2) -> void:
	var v = player.vitals
	var x := 24.0
	var y := vs.y - 120
	draw_rect(Rect2(x - 12, y - 26, 330, 118), Color(0, 0, 0, 0.35))
	var blood: float = v.blood / Vitals.BLOOD
	var bcol := Color(0.85, 0.15, 0.12) if blood > 0.75 else Color(1.0, 0.3, 0.1)
	_bar(Vector2(x, y), 200, blood, bcol, "krew %d%%" % int(blood * 100.0), font)
	_bar(Vector2(x, y + 20), 200, player.stamina / 100.0, Color(0.92, 0.85, 0.55), "kondycja", font)
	if player.ads > 0.3 or player.breath < 6.0:
		_bar(Vector2(x, y + 40), 200, player.breath / 6.0, Color(0.55, 0.8, 1.0), "oddech", font)
	var r: float = v.bleed_rate()
	var t := "opatrunki: %d [H]" % player.bandages
	if r > 0.05:
		t = "KRWAWIENIE %.1f ml/s   " % r + t
	if player.bandaging >= 0.0:
		t = "zakładanie opatrunku... %d%%" % int(player.bandaging / 3.0 * 100.0)
	draw_string(font, Vector2(x, y - 8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.55, 0.45) if r > 0.05 else Color(0.85, 0.9, 1, 0.8))
	var lines := PackedStringArray()
	for w: Dictionary in v.wounds:
		lines.append(("✓ " if w["dressed"] else "• ") + String(w["name"]))
	for i in mini(lines.size(), 3):
		draw_string(font, Vector2(x, y + 62 + i * 15), lines[lines.size() - 1 - i], HORIZONTAL_ALIGNMENT_LEFT, 300, 12, Color(1, 0.7, 0.6, 0.85))


## Nad trafionymi wrogami: ostatnia rana; w rentgenie pełna karta obrażeń.
func _draw_enemies(font: Font) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_cards.clear()
	var list := get_tree().get_nodes_in_group("npc") + get_tree().get_nodes_in_group("net_player")
	for n in list:
		if n.global_position.distance_to(cam.global_position) > 80.0:
			continue
		var wp: Vector3 = n.global_position + Vector3(0, 2.2, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var since: float = now - n.last_injury_time
		if since < 2.5 and not xray:
			_center_text(font, n.last_injury, sp - Vector2(0, 14 + since * 12.0), 15, Color(1.0, 0.55, 0.35, clampf(2.5 - since, 0.0, 1.0)))
		if xray and not n.injuries.is_empty():
			_card(font, n, sp)


func _card(font: Font, n, sp: Vector2) -> void:
	var lines := PackedStringArray()
	lines.append("MARTWY" if n.vitals.dead else ("NIEPRZYTOMNY" if n.down else "krew %d%%" % int(n.vitals.blood / Vitals.BLOOD * 100.0)))
	for w: Dictionary in n.vitals.wounds:
		lines.append("- " + String(w["name"]))
	var h := lines.size() * 16 + 8
	var rect := Rect2(sp - Vector2(90, h), Vector2(180, h))
	for _i in 12:
		var hit := false
		for r: Rect2 in _cards:
			if r.grow(3.0).intersects(rect):
				rect.position.y = r.position.y - h - 4.0
				hit = true
		if not hit:
			break
	_cards.append(rect)
	draw_rect(rect, Color(0.0, 0.06, 0.12, 0.7))
	draw_rect(rect, Color(0.4, 0.75, 1.0, 0.6), false, 1.0)
	for i in lines.size():
		var col := Color(0.75, 0.92, 1.0) if i == 0 else Color(1.0, 0.6, 0.45)
		draw_string(font, rect.position + Vector2(7, 16 + i * 16), lines[i], HORIZONTAL_ALIGNMENT_LEFT, 166, 12, col)


## Mecz PvP: wynik, kod gry, odrodzenie.
func _draw_pvp(font: Font, vs: Vector2) -> void:
	var opp = null
	for p in get_tree().get_nodes_in_group("net_player"):
		if is_instance_valid(p) and String(p.name).begins_with("P"):
			opp = p
	var mine: int = opp.deaths if opp else 0
	_center_text(font, "Ty %d : %d Przeciwnik" % [mine, player.deaths], Vector2(vs.x * 0.5, 40), 26, Color(1, 0.95, 0.8))
	var info := "Gra: %s" % code
	if opp == null:
		info += "  — czekam na przeciwnika..."
	if status != "":
		info += "   " + status
	draw_string(font, Vector2(vs.x * 0.5 - 200, 66), info, HORIZONTAL_ALIGNMENT_LEFT, 400, 14, Color(0.8, 0.9, 1, 0.75))
	if player.down:
		_center_text(font, "WYELIMINOWANY — odrodzenie za %.0f s" % maxf(respawn_in, 0.0), Vector2(vs.x * 0.5, vs.y * 0.5 - 40), 26, Color(1, 0.4, 0.3))
