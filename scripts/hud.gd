extends Control
## HUD strzelanki: broń i amunicja, krew i rany, wytrzymałość, oddech, znacznik trafienia,
## kierunek ostrzału, komunikaty. Solo: licznik wyeliminowanych. PvP: wynik, kod gry, odrodzenie.

const Npc = preload("res://scripts/npc.gd")
const Vitals = preload("res://scripts/vitals.gd")
const Aircraft = preload("res://scripts/plane.gd")

var player = null
var xray := false
var pvp := false
var code := ""
var status := ""
var respawn_in := -1.0
var _cards: Array = []
var show_help := false      # F1: lista sterowania (domyślnie schowana — jak w CoD)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("help"):
		show_help = not show_help


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
	var pl = player.vehicle
	if pl != null and is_instance_valid(pl):
		if pl.get("is_heli") == true:
			_draw_heli(font, vs, pl)
		else:
			_draw_plane(font, vs, pl)
	else:
		if show_help:
			_draw_help(font)
		_draw_crosshair(vs)
		_draw_weapon(font, vs)
		_draw_lock(font, vs)
		_draw_plane_hint(font, vs)
	_draw_damage_dirs(vs)
	_draw_kills(font, vs)
	_draw_vitals(font, vs)
	if player.message_t > 0.0:
		var a := clampf(player.message_t, 0.0, 1.0)
		_center_text(font, player.message, Vector2(vs.x * 0.5, vs.y * 0.5 + 90), 18, Color(1, 0.95, 0.8, a))
	if Time.get_ticks_msec() / 1000.0 - player.last_injury_time < 3.0:
		_center_text(font, "Trafiony: " + player.last_injury, Vector2(vs.x * 0.5, vs.y * 0.5 + 120), 18, Color(1, 0.45, 0.35))
	if pvp:
		_draw_pvp(font, vs)
	else:
		_panel(Rect2(vs.x - 250, 12, 234, 58))
		draw_string(font, Vector2(vs.x - 232, 36), "WYELIMINOWANI", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.82, 0.8, 0.8))
		draw_string(font, Vector2(vs.x - 120, 38), "%d" % Npc.deaths, HORIZONTAL_ALIGNMENT_RIGHT, 90, 24, Color(1, 1, 1, 0.95))
		if player.down:
			_center_text(font, "WYELIMINOWANY (%s) — F5: od nowa" % ("nie żyjesz" if player.vitals.dead else "nieprzytomny"),
				Vector2(vs.x * 0.5, vs.y * 0.5 - 40), 26, Color(1, 0.4, 0.3))
	_draw_enemies(font)


func _draw_help(font: Font) -> void:
	var help := [
		"WASD - ruch   Shift - bieg (w celowaniu: wstrzymanie oddechu)   Spacja - skok   Ctrl - kucanie   X - chód",
		"LPM - strzał   PPM - celowanie   R - przeładowanie   B - tryb ognia   1-0 / kółko - broń",
		"V - pierwsza osoba / zza ramienia   L - laser   H - opatrunek   F - samolot / skrzynki   Q/E - wychylanie   G - granat   Tab - rentgen   Esc - kursor",
	]
	if show_help:
		draw_rect(Rect2(10, 244, 820, help.size() * 20 + 14), Color(0, 0, 0, 0.45))
	for i in help.size() if show_help else 0:
		draw_string(font, Vector2(20, 262 + i * 20), help[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0, 0.85))


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
	_draw_hit_marker(c)


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
	# panel w stylu CoD: skośny pasek, duża liczba naboi, rządek nabojów w magazynku
	var x := vs.x - 330
	var y := vs.y - 110
	var bg := PackedVector2Array([Vector2(x + 18, y - 22), Vector2(vs.x - 16, y - 22), Vector2(vs.x - 16, y + 74), Vector2(x, y + 74)])
	draw_colored_polygon(bg, Color(0.02, 0.03, 0.03, 0.5))
	draw_line(Vector2(x + 18, y - 22), Vector2(vs.x - 16, y - 22), Color(1, 0.85, 0.4, 0.7), 2.0)
	var rounds: int = g.rounds + (1 if g.chambered else 0)
	var cap: int = int(g.data["cap"]) + 1
	var col := Color(1, 1, 1) if rounds > cap / 4 else (Color(1, 0.75, 0.3) if rounds > 0 else Color(1, 0.35, 0.3))
	var rs := "%d" % rounds
	draw_string(font, Vector2(vs.x - 150, y + 36), rs, HORIZONTAL_ALIGNMENT_RIGHT, 110, 46, col)
	draw_string(font, Vector2(vs.x - 36, y + 36), "/", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.4))
	draw_string(font, Vector2(vs.x - 150, y + 62), "%d" % g.reserve(), HORIZONTAL_ALIGNMENT_RIGHT, 125, 18, Color(0.85, 0.9, 1, 0.75))
	draw_string(font, Vector2(x + 26, y - 2), String(g.data["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.92, 0.75))
	var mode: String = {"auto": "SERIA", "semi": "POJEDYNCZY", "pump": "POMPKA", "bolt": "ZAMEK"}.get(g.fire_mode(), g.fire_mode())
	draw_string(font, Vector2(x + 26, y + 16), mode + "  [B]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1, 0.6))
	if g.data["feed"] == "mag":
		draw_string(font, Vector2(x + 26, y + 34), "MAGAZYNKI  %d" % g.mags.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1, 0.6))
	# granaty: pełne / puste ikonki i klawisz
	var gn: int = player.grenades
	for k in player.MAX_GRENADES:
		var c := Vector2(x + 150 + k * 13, y + 30)
		if k < gn:
			draw_circle(c, 4.5, Color(0.55, 0.62, 0.4))
			draw_rect(Rect2(c + Vector2(-1.5, -8), Vector2(3, 3)), Color(0.8, 0.8, 0.7))
		else:
			draw_arc(c, 4.5, 0, TAU, 12, Color(1, 1, 1, 0.2), 1.0)
	draw_string(font, Vector2(x + 150 + player.MAX_GRENADES * 13, y + 34), "[G]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.9, 1, 0.5))
	# naboje w magazynku jako pionowe kreski
	var n := mini(cap, 40)
	var bw := minf(150.0 / n, 6.0)
	for k in n:
		var full := k < int(round(float(rounds) / cap * n))
		var bx := x + 26 + k * bw
		draw_rect(Rect2(bx, y + 46, maxf(bw - 1.5, 1.0), 14), Color(1, 0.88, 0.55, 0.9) if full else Color(1, 1, 1, 0.12))
	if player.reloading >= 0.0:
		_center_text(font, "PRZEŁADOWANIE", Vector2(vs.x * 0.5, vs.y * 0.5 + 60), 16, Color(1, 0.9, 0.5))
		var pr: float = clampf(player.rig.reload_p, 0.0, 1.0)
		draw_rect(Rect2(vs.x * 0.5 - 60, vs.y * 0.5 + 68, 120, 3), Color(1, 1, 1, 0.2))
		draw_rect(Rect2(vs.x * 0.5 - 60, vs.y * 0.5 + 68, 120 * pr, 3), Color(1, 0.9, 0.5))
	elif rounds == 0:
		_center_text(font, "PUSTY — R", Vector2(vs.x * 0.5, vs.y * 0.5 + 60), 16, Color(1, 0.45, 0.35))
	elif rounds <= cap / 4:
		_center_text(font, "MAŁO AMUNICJI", Vector2(vs.x * 0.5, vs.y * 0.5 + 60), 14, Color(1, 0.75, 0.3, 0.8))
	if not show_help:
		draw_string(font, Vector2(x + 26, y + 92), "F1 — sterowanie", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.4))


func _bar(at: Vector2, w: float, frac: float, col: Color, label: String, font: Font) -> void:
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(w + 4, 12)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(at, Vector2(w * clampf(frac, 0.0, 1.0), 8)), col)
	draw_string(font, at + Vector2(w + 10, 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.93, 1, 0.8))


## Ciemny panel ze skośną krawędzią i bursztynowym akcentem u góry (wspólny styl HUD-u).
func _panel(r: Rect2, slant := 16.0) -> void:
	var pts := PackedVector2Array([r.position + Vector2(slant, 0), r.position + Vector2(r.size.x, 0), r.end, Vector2(r.position.x, r.end.y)])
	draw_colored_polygon(pts, Color(0.02, 0.03, 0.03, 0.5))
	draw_line(r.position + Vector2(slant, 0), r.position + Vector2(r.size.x, 0), Color(1, 0.85, 0.4, 0.7), 2.0)


## Stan żołnierza: krew (segmenty), kondycja, oddech, opatrunki, krwawienie, rany.
func _draw_vitals(font: Font, vs: Vector2) -> void:
	var v = player.vitals
	var x := 26.0
	var y := vs.y - 104
	_panel(Rect2(x - 10, y - 26, 330, 112))
	var blood: float = clampf(v.blood / Vitals.BLOOD, 0.0, 1.0)
	var r: float = v.bleed_rate()
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.012)
	# krew w mililitrach, na czerwono (przy dużej utracie pulsuje)
	var red := Color(0.9, 0.12, 0.1) if blood > 0.7 else Color(1.0, 0.2, 0.15, pulse)
	draw_string(font, Vector2(x + 8, y - 4), "KREW", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.35, 0.3, 0.9))
	draw_string(font, Vector2(x + 140, y - 2), "%d ml" % int(v.blood), HORIZONTAL_ALIGNMENT_RIGHT, 160, 22, red)
	# 12 segmentów krwi
	var segs := 12
	var sw := 290.0 / segs
	for k in segs:
		var f := clampf(blood * segs - k, 0.0, 1.0)
		var rr := Rect2(x + 8 + k * sw, y + 6, sw - 3, 12)
		draw_rect(rr, Color(0.35, 0.02, 0.02, 0.45))
		if f > 0.0:
			draw_rect(Rect2(rr.position, Vector2(rr.size.x * f, rr.size.y)), red)
	# kondycja i oddech: cienkie paski
	draw_rect(Rect2(x + 8, y + 26, 290, 4), Color(1, 1, 1, 0.1))
	draw_rect(Rect2(x + 8, y + 26, 290 * player.stamina / 100.0, 4), Color(0.95, 0.82, 0.45, 0.9))
	if player.ads > 0.3 or player.breath < 6.0:
		draw_rect(Rect2(x + 8, y + 34, 290, 4), Color(1, 1, 1, 0.1))
		draw_rect(Rect2(x + 8, y + 34, 290 * player.breath / 6.0, 4), Color(0.55, 0.8, 1.0, 0.9))
	var t := "OPATRUNKI  %d   [H]" % player.bandages
	var tc := Color(0.85, 0.9, 0.88, 0.8)
	if player.bandaging >= 0.0:
		t = "ZAKŁADANIE OPATRUNKU  %d%%" % int(player.bandaging / 3.0 * 100.0)
		tc = Color(0.7, 1.0, 0.7)
	elif r > 0.05:
		t = "KRWAWIENIE  %.1f ml/s   —   H" % r
		tc = Color(1, 0.35, 0.25, pulse)
	draw_string(font, Vector2(x + 8, y + 60), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tc)
	# rany nad panelem
	var lines := PackedStringArray()
	for w: Dictionary in v.wounds:
		lines.append(("✓ " if w["dressed"] else "● ") + String(w["name"]))
	for i in mini(lines.size(), 3):
		draw_string(font, Vector2(x, y - 36 - i * 18), lines[lines.size() - 1 - i], HORIZONTAL_ALIGNMENT_LEFT, 320, 14, Color(1, 0.62, 0.5, 0.9))


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
	var theirs: int = opp.pvp_kills if opp else 0
	_center_text(font, "Ty %d : %d Przeciwnik" % [player.pvp_kills, theirs],Vector2(vs.x * 0.5, 40), 26, Color(1, 0.95, 0.8))
	var info := "Gra: %s" % code
	if opp == null:
		info += "  — czekam na przeciwnika..."
	if status != "":
		info += "   " + status
	draw_string(font, Vector2(vs.x * 0.5 - 200, 132), info, HORIZONTAL_ALIGNMENT_LEFT, 400, 14, Color(0.8, 0.9, 1, 0.75))  # pod kompasem
	if player.down:
		_center_text(font, "WYELIMINOWANY — odrodzenie za %.0f s" % maxf(respawn_in, 0.0), Vector2(vs.x * 0.5, vs.y * 0.5 - 40), 26, Color(1, 0.4, 0.3))


## Podpowiedź przy samolocie, do którego można wsiąść.
func _draw_plane_hint(font: Font, vs: Vector2) -> void:
	if player.down:
		return
	var rt = player.repair_target()
	if rt != null:
		var k: float = rt.hp / rt.MAX_HP
		var what := "śmigłowiec" if rt.get("is_heli") == true else "samolot"
		var at := Vector2(vs.x * 0.5, vs.y * 0.5 + 180)
		_center_text(font, "[R] przytrzymaj — napraw %s (%d%%)" % [what, int(k * 100.0)], at, 17, Color(0.8, 0.95, 1.0))
		draw_rect(Rect2(at.x - 80, at.y + 8, 160, 5), Color(1, 1, 1, 0.2))
		draw_rect(Rect2(at.x - 80, at.y + 8, 160 * k, 5), Color(0.5, 0.9, 1.0) if player.repair_t > 0.0 else Color(0.8, 0.8, 0.8, 0.7))
	for pl in get_tree().get_nodes_in_group("plane"):
		if pl.can_board(player):
			_center_text(font, "[F] — wsiądź do %s" % String(pl.get("board_name") if pl.get("board_name") != null else "samolotu"),Vector2(vs.x * 0.5, vs.y * 0.5 + 150), 18, Color(0.85, 1.0, 0.8))
			return
	for c in get_tree().get_nodes_in_group("ammo_crate"):
		if c.near(player):
			var med: bool = c.kind == "med"
			if c.is_ready():
				_center_text(font, "[F] — apteczka (lecz rany)" if med else "[F] — uzupełnij amunicję", Vector2(vs.x * 0.5, vs.y * 0.5 + 150), 18, Color(1.0, 0.45, 0.4) if med else Color(1.0, 0.88, 0.45))
			else:
				_center_text(font, "%s pusta — %d s" % ["Apteczka" if med else "Skrzynka", ceili(c.cooldown)], Vector2(vs.x * 0.5, vs.y * 0.5 + 150), 16, Color(0.75, 0.75, 0.75))
			return


## Samolot: celownik karabinów, kierunek lotu, przyrządy, ostrzeżenia.
func _draw_plane(font: Font, vs: Vector2, pl) -> void:
	var help := [
		"Mysz - kierunek lotu (samolot leci tam, gdzie patrzysz)   W/S - gaz   A/D - ster kierunku   strzałki - drążek ręcznie",
		"LPM - karabiny maszynowe   Spacja - bomby (seria, nalot dywanowy) / na ziemi hamulce   C - flary   V - kabina / widok z tyłu   F - wysiądź (na ziemi)",
	]
	if show_help:
		draw_rect(Rect2(10, 244, 820, help.size() * 20 + 14), Color(0, 0, 0, 0.45))
	for i in help.size() if show_help else 0:
		draw_string(font, Vector2(20, 262 + i * 20), help[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0, 0.85))
	var cam := get_viewport().get_camera_3d()
	var c := vs * 0.5
	var green := Color(0.55, 1.0, 0.55, 0.9)
	# kierunek, w który patrzy pilot (tam leci samolot)
	draw_arc(c, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.75), 1.5, true)
	# celownik: zbieżność karabinów przed nosem
	if cam and not cam.is_position_behind(pl.gun_point()):
		var g: Vector2 = cam.unproject_position(pl.gun_point())
		draw_arc(g, 22.0, 0.0, TAU, 32, green, 1.5, true)
		draw_circle(g, 2.0, green)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
			draw_line(g + d * 26.0, g + d * 36.0, green, 1.5, true)
		if player.hit_marker > 0.0:
			var hc := Color(1, 0.25, 0.2, player.hit_marker) if player.hit_kill else Color(1, 1, 1, player.hit_marker)
			for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(g + d * 8.0, g + d * 16.0, hc, 2.0, true)
	# przyrządy
	var x := vs.x - 300
	var y := vs.y - 170
	draw_rect(Rect2(x - 12, y - 30, 300, 190), Color(0, 0, 0, 0.35))
	var spd: float = pl.velocity.length() * 3.6
	draw_string(font, Vector2(x, y), "PRĘDKOŚĆ  %d km/h" % int(spd), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.92, 0.7))
	draw_string(font, Vector2(x, y + 24), "WYSOKOŚĆ  %d m" % int(maxf(pl.global_position.y - Aircraft.GEAR_H, 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.92, 0.7))
	var climb: float = pl.velocity.y
	draw_string(font, Vector2(x, y + 46), "wznoszenie %+.1f m/s" % climb, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 1, 0.8))
	_bar(Vector2(x, y + 60), 160, pl.throttle, Color(0.9, 0.75, 0.3), "gaz %d%% [W/S]" % int(pl.throttle * 100.0), font)
	var hpk: float = pl.hp / Aircraft.MAX_HP
	_bar(Vector2(x, y + 80), 160, hpk, Color(0.45, 0.85, 0.45) if hpk > 0.5 else (Color(1, 0.7, 0.2) if hpk > 0.25 else Color(1, 0.3, 0.2)), "płatowiec %d%%" % int(maxf(hpk, 0.0) * 100.0), font)
	var am: int = pl.ammo
	draw_string(font, Vector2(x, y + 124), "%d" % am, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1) if am > 0 else Color(1, 0.35, 0.3))
	draw_string(font, Vector2(x + 90, y + 124), "4 × KM 12,7 mm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 1, 0.8))
	if not show_help:
		draw_string(font, Vector2(x, y + 168), "F1 — sterowanie samolotem", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))
	var nb: int = pl.bombs
	if nb < Aircraft.BOMBS:
		var rk: float = pl.bomb_reload / Aircraft.BOMB_RELOAD
		_bar(Vector2(x, y + 138), 160, rk, Color(1, 0.75, 0.3), "bomby: przeładowanie %d s" % ceili(Aircraft.BOMB_RELOAD - pl.bomb_reload), font)
	else:
		draw_string(font, Vector2(x, y + 146), "BOMBY  %d × 50 kg  [Spacja]  — bez limitu" % nb, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.85, 0.5))
	if cam:
		_draw_bomb_sight(cam, pl, nb)
		_draw_air_targets(font, cam, pl)
	if pl.on_ground and pl.velocity.length() < 2.0 and pl.global_position.distance_to(pl.home.origin) < 45.0 and (am < Aircraft.AMMO or pl.hp < Aircraft.MAX_HP):
		_center_text(font, "Dozbrajanie i naprawa...", Vector2(c.x, c.y + 180), 16, Color(0.8, 1, 0.8))
	# ostrzeżenia
	var warns := PackedStringArray()
	if pl.hp <= 0.0:
		warns.append("SAMOLOT W OGNIU — SPADASZ")
	elif pl.hp < Aircraft.MAX_HP * 0.25:
		warns.append("SILNIK USZKODZONY")
	if pl.stall:
		warns.append("PRZECIĄGNIĘCIE — OPUŚĆ NOS")
	if pl.warn != "":
		warns.append(pl.warn)
	if not pl.on_ground and pl.global_position.y < 25.0 and pl.velocity.y < -8.0:
		warns.append("ZIEMIA — PODCIĄGNIJ")
	if am <= 0:
		warns.append("BRAK AMUNICJI — WYLĄDUJ NA LOTNISKU")
	var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
	for i in warns.size():
		_center_text(font, warns[i], Vector2(c.x, c.y - 120 - i * 28), 22, Color(1, 0.35, 0.25, blink))
	if pl.on_ground and pl.throttle < 0.05 and pl.velocity.length() < 1.0:
		_center_text(font, "W — gaz do startu, spójrz lekko w górę przy ~110 km/h", Vector2(c.x, c.y + 150), 16, Color(0.85, 1.0, 0.8, 0.85))
	_draw_countermeasures(font, vs, pl, Vector2(x, y - 52))


## Śmigłowiec: celownik wieżyczki i rakiet, przyrządy, uzbrojenie, flary, ostrzeżenia.
func _draw_heli(font: Font, vs: Vector2, pl) -> void:
	var help := [
		"Spacja / Ctrl - w górę / w dół   W/S - lot do przodu / do tyłu   A/D - w bok   mysz - kierunek i celowanie",
		"LPM - działko 12,7 mm (wieżyczka)   PPM - rakiety   C - flary   V - kabina / z tyłu   F - wysiądź (na ziemi)",
	]
	if show_help:
		draw_rect(Rect2(10, 244, 820, help.size() * 20 + 14), Color(0, 0, 0, 0.45))
		for i in help.size():
			draw_string(font, Vector2(20, 262 + i * 20), help[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0, 0.85))
	var cam := get_viewport().get_camera_3d()
	var c := vs * 0.5
	var green := Color(0.55, 1.0, 0.55, 0.9)
	if cam and not cam.is_position_behind(pl.aim_point()):
		var g: Vector2 = cam.unproject_position(pl.aim_point())
		draw_arc(g, 14.0, 0.0, TAU, 32, green, 1.5, true)
		draw_circle(g, 2.0, green)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(g + d * 18.0, g + d * 28.0, green, 1.5, true)
		if player.hit_marker > 0.0:
			var hc := Color(1, 0.25, 0.2, player.hit_marker) if player.hit_kill else Color(1, 1, 1, player.hit_marker)
			for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(g + d * 8.0, g + d * 16.0, hc, 2.0, true)
		var dist: float = pl.aim_point().distance_to(pl.global_position)
		draw_string(font, g + Vector2(20, 26), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(green, 0.7))
	# oś kadłuba (tam celują rakiety, wieżyczka obraca się szerzej)
	if cam:
		var nose_p: Vector3 = pl.global_position - pl.global_basis.z * 200.0
		if not cam.is_position_behind(nose_p):
			var np := cam.unproject_position(nose_p)
			draw_line(np + Vector2(-12, 0), np + Vector2(-4, 0), Color(1, 1, 1, 0.6), 1.5)
			draw_line(np + Vector2(4, 0), np + Vector2(12, 0), Color(1, 1, 1, 0.6), 1.5)
			draw_line(np + Vector2(0, 4), np + Vector2(0, 10), Color(1, 1, 1, 0.6), 1.5)
	var x := vs.x - 300
	var y := vs.y - 170
	draw_rect(Rect2(x - 12, y - 30, 300, 190), Color(0, 0, 0, 0.35))
	draw_string(font, Vector2(x, y), "PRĘDKOŚĆ  %d km/h" % int(pl.velocity.length() * 3.6), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.92, 0.7))
	draw_string(font, Vector2(x, y + 24), "WYSOKOŚĆ  %d m" % int(maxf(pl.global_position.y - pl.GEAR_H, 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.92, 0.7))
	draw_string(font, Vector2(x, y + 46), "wznoszenie %+.1f m/s" % pl.velocity.y, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 1, 0.8))
	_bar(Vector2(x, y + 60), 160, pl.rpm, Color(0.9, 0.75, 0.3), "wirnik %d%%" % int(pl.rpm * 100.0), font)
	var hpk: float = pl.hp / pl.MAX_HP
	_bar(Vector2(x, y + 80), 160, hpk, Color(0.45, 0.85, 0.45) if hpk > 0.5 else (Color(1, 0.7, 0.2) if hpk > 0.25 else Color(1, 0.3, 0.2)), "kadłub %d%%" % int(maxf(hpk, 0.0) * 100.0), font)
	var am: int = pl.ammo
	draw_string(font, Vector2(x, y + 124), "%d" % am, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1) if am > 0 else Color(1, 0.35, 0.3))
	draw_string(font, Vector2(x + 90, y + 124), "2 × KM 12,7 mm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 1, 0.8))
	var nr: int = pl.rockets
	if nr <= 0 or (nr < pl.ROCKETS and pl.rocket_reload > 0.0):
		_bar(Vector2(x, y + 138), 160, pl.rocket_reload / pl.ROCKET_RELOAD, Color(1, 0.75, 0.3), "rakiety: przeładowanie %d s" % ceili(pl.ROCKET_RELOAD - pl.rocket_reload), font)
	else:
		draw_string(font, Vector2(x, y + 146), "RAKIETY  %d / %d  [PPM]" % [nr, pl.ROCKETS], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.85, 0.5))
	if not show_help:
		draw_string(font, Vector2(x, y + 168), "F1 — sterowanie śmigłowcem", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))
	if cam:
		_draw_air_targets(font, cam, pl)
	if pl.on_ground and pl.global_position.distance_to(pl.home.origin) < 30.0 and (am < pl.AMMO or pl.hp < pl.MAX_HP):
		_center_text(font, "Dozbrajanie i naprawa...", Vector2(c.x, c.y + 180), 16, Color(0.8, 1, 0.8))
	var warns := PackedStringArray()
	if pl.hp <= 0.0:
		warns.append("ŚMIGŁOWIEC TRAFIONY — AUTOROTACJA")
	elif pl.hp < pl.MAX_HP * 0.25:
		warns.append("SILNIK USZKODZONY")
	if pl.warn != "":
		warns.append(pl.warn)
	if am <= 0:
		warns.append("BRAK AMUNICJI — WYLĄDUJ NA LĄDOWISKU")
	var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
	for i in warns.size():
		_center_text(font, warns[i], Vector2(c.x, c.y - 120 - i * 28), 22, Color(1, 0.35, 0.25, blink))
	if pl.on_ground and pl.rpm < 0.9:
		_center_text(font, "Rozkręcanie wirnika... potem Spacja — start", Vector2(c.x, c.y + 150), 16, Color(0.85, 1.0, 0.8, 0.85))
	_draw_countermeasures(font, vs, pl, Vector2(x, y - 52))


## Flary (salwy, przeładowanie) i ostrzeżenia: namierzanie, nadlatująca rakieta (samolot, śmigłowiec).
func _draw_countermeasures(font: Font, vs: Vector2, pl, at: Vector2) -> void:
	var nf: int = pl.flares
	if nf > 0:
		draw_string(font, at, "FLARY  %d / %d   [C]" % [nf, pl.FLARES], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.85, 0.5))
	if nf < pl.FLARES:
		_bar(at + Vector2(0, 8), 160, pl.flare_reload / pl.FLARE_RELOAD, Color(1, 0.6, 0.3), "flary: przeładowanie %d s" % ceili(pl.FLARE_RELOAD - pl.flare_reload), font)
	var c := vs * 0.5
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
	if pl._missile_near():
		var tt: float = pl.missile_warn
		var txt := "RAKIETA!  FLARY — [C]" if nf > 0 else "RAKIETA!  UNIK — BRAK FLAR"
		if tt < 30.0:
			txt += "   %.1f s" % tt
		_center_text(font, txt, Vector2(c.x, c.y - 190), 30, Color(1, 0.2, 0.15, blink))
	elif pl.lock_warn > 0.0:
		_center_text(font, "NAMIERZANIE — PRZECIWNIK CELUJE RAKIETĄ", Vector2(c.x, c.y - 190), 22, Color(1, 0.75, 0.2, 0.6 + 0.4 * blink))


## Wyrzutnia przeciwlotnicza: ramka na namierzanym celu, postęp i stan namierzenia.
func _draw_lock(font: Font, vs: Vector2) -> void:
	var g = player.gun
	if g == null or not g.data.get("seeker", false):
		return
	var c := vs * 0.5
	if player.ads < 0.6:
		_center_text(font, "PPM — namierzanie samolotu / śmigłowca", Vector2(c.x, c.y + 60), 14, Color(1, 0.9, 0.6, 0.8))
		return
	# stożek głowicy
	draw_arc(c, 46.0, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 1.0, true)
	var t = player.lock_cand
	var cam := get_viewport().get_camera_3d()
	if t == null or not is_instance_valid(t) or cam == null or cam.is_position_behind(t.global_position):
		_center_text(font, "SZUKANIE CELU", Vector2(c.x, c.y + 70), 14, Color(1, 1, 1, 0.6))
		return
	var p: Vector2 = cam.unproject_position(t.global_position)
	var k: float = clampf(player.lock_t / player.LOCK_TIME, 0.0, 1.0)
	var locked: bool = player.locked()
	var col := Color(1, 0.25, 0.2) if locked else Color(1, 0.85, 0.3)
	var s := lerpf(40.0, 20.0, k)
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var corner := p + d * s
		draw_line(corner, corner - Vector2(d.x * 10.0, 0), col, 2.0)
		draw_line(corner, corner - Vector2(0, d.y * 10.0), col, 2.0)
	if locked:
		draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), Color(col, 0.15))
		_center_text(font, "NAMIERZONO — LPM", Vector2(c.x, c.y + 70), 18, col)
	else:
		draw_arc(p, s + 8.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, col, 2.0, true)
		_center_text(font, "NAMIERZANIE...", Vector2(c.x, c.y + 70), 16, col)
	var d3: float = t.global_position.distance_to(cam.global_position)
	draw_string(font, p + Vector2(s + 6, -s), "%d m" % int(d3), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


## Celownik bombowy: krzyż w przewidywanym miejscu upadku bomb.
func _draw_bomb_sight(cam: Camera3D, pl, nb: int) -> void:
	if pl.on_ground or nb <= 0:
		return
	var ip: Vector3 = pl.bomb_impact()
	if cam.is_position_behind(ip):
		return
	var sp := cam.unproject_position(ip)
	var col := Color(1.0, 0.8, 0.3, 0.9)
	draw_arc(sp, 14.0, 0.0, TAU, 24, col, 1.5, true)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(sp + d * 6.0, sp + d * 22.0, col, 1.5, true)
	var font := get_theme_default_font()
	draw_string(font, sp + Vector2(18, -10), "BOMBY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


## Wrogie samoloty: ramka z odległością i punkt wyprzedzenia (tam celuj, by trafić).
func _draw_air_targets(font: Font, cam: Camera3D, pl) -> void:
	var v0: float = 870.0
	for o in get_tree().get_nodes_in_group("plane"):
		if o == pl or o.destroyed or o.pilot == null or not is_instance_valid(o.pilot):
			continue
		var tp: Vector3 = o.global_position
		var d: float = tp.distance_to(pl.global_position)
		if d > 1500.0 or cam.is_position_behind(tp):
			continue
		var sp := cam.unproject_position(tp)
		var col := Color(1.0, 0.3, 0.25, 0.9)
		var s := clampf(1200.0 / maxf(d, 1.0), 10.0, 40.0)
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			draw_line(sp + c * s, sp + c * s - Vector2(c.x * s * 0.5, 0), col, 2.0, true)
			draw_line(sp + c * s, sp + c * s - Vector2(0, c.y * s * 0.5), col, 2.0, true)
		draw_string(font, sp + Vector2(s + 4, -s), "%d m" % int(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		if d < 900.0:
			# pocisk dziedziczy moją prędkość: liczę w układzie względnym
			var rel_v: Vector3 = o.velocity - pl.velocity
			var tof := d / v0
			for i in 2:
				tof = (tp + rel_v * tof).distance_to(pl.global_position) / v0
			var lead: Vector3 = tp + rel_v * tof + Vector3.UP * 0.5 * 9.81 * tof * tof
			if not cam.is_position_behind(lead):
				var lp := cam.unproject_position(lead)
				draw_arc(lp, 7.0, 0.0, TAU, 16, Color(1, 0.9, 0.3, 0.95), 2.0, true)
				draw_line(sp, lp, Color(1, 0.9, 0.3, 0.35), 1.0, true)


# ---------------------------------------------------------------- trafienia i zabójstwa (styl Battlefront II)

const HIT_COLORS := [Color(1, 1, 1), Color(1.0, 0.24, 0.16), Color(0.95, 0.06, 0.05)]  # lekkie, krytyczne, eliminacja


## Znacznik trafienia: cztery skośne kreski; biały / żółty / czerwony (eliminacja — większy,
## grubszy, rozszerza się i gaśnie).
func _draw_hit_marker(c: Vector2) -> void:
	var hm: float = player.hit_marker
	if hm <= 0.0:
		return
	var kind: int = player.hit_kind
	var col: Color = HIT_COLORS[kind]
	col.a = clampf(hm * 1.4, 0.0, 1.0)
	var grow := (1.0 - hm) * (10.0 if kind == 2 else 4.0)
	var r0 := (8.0 if kind == 2 else 6.0) + grow
	var r1 := r0 + (11.0 if kind == 2 else 7.0)
	var w := 3.0 if kind == 2 else 2.0
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var dn := d.normalized()
		draw_line(c + dn * r0 + Vector2(1, 1), c + dn * r1 + Vector2(1, 1), Color(0, 0, 0, col.a * 0.5), w + 1.0, true)
		draw_line(c + dn * r0, c + dn * r1, col, w, true)


## Czaszka (ikona eliminacji) w punkcie p, rozmiar s.
func _skull(p: Vector2, s: float, col: Color) -> void:
	var dark := Color(0.08, 0.0, 0.0, col.a)
	draw_circle(p + Vector2(0, -s * 0.12), s * 0.5, col, true, -1.0, true)
	draw_rect(Rect2(p + Vector2(-s * 0.3, s * 0.15), Vector2(s * 0.6, s * 0.38)), col)
	draw_circle(p + Vector2(-s * 0.19, -s * 0.08), s * 0.15, dark, true, -1.0, true)
	draw_circle(p + Vector2(s * 0.19, -s * 0.08), s * 0.15, dark, true, -1.0, true)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, s * 0.08), p + Vector2(-s * 0.07, s * 0.22), p + Vector2(s * 0.07, s * 0.22)]), dark)
	for i in 3:
		var x := -s * 0.15 + i * s * 0.15
		draw_line(p + Vector2(x, s * 0.36), p + Vector2(x, s * 0.53), dark, maxf(s * 0.05, 1.0))


## Napisy przy ranach: krytyczne czerwone (większe), lekkie białe, pancerz szary; unoszą się i gasną.
func _draw_hit_popups(font: Font, cam: Camera3D) -> void:
	for pp: Dictionary in player.hit_popups:
		var wp: Vector3 = pp["pos"]
		if cam.is_position_behind(wp):
			continue
		var t: float = 1.3 - float(pp["t"])
		var a := clampf(float(pp["t"]) / 0.4, 0.0, 1.0)
		var sp := cam.unproject_position(wp) + (pp["off"] as Vector2) - Vector2(0, 18.0 + t * 26.0)
		var crit: bool = pp["crit"]
		var col := Color(1.0, 0.22, 0.14, a) if crit else Color(1, 1, 1, a * 0.9)
		if pp["armor"]:
			col = Color(0.75, 0.78, 0.82, a * 0.85)
		var size := 22 if pp["head"] else (18 if crit else 14)
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - t / 0.12)
		size = int(size * pop)
		draw_string(font, sp + Vector2(1.5, 1.5), pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, a * 0.7))
		draw_string(font, sp, pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_kills(font: Font, vs: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	var red := Color(1.0, 0.16, 0.12)
	if cam:
		_draw_hit_popups(font, cam)
	# czaszki nad zabitymi: wyskakują, unoszą się i gasną
	if cam:
		for m: Dictionary in player.kill_marks:
			var wp: Vector3 = (m["pos"] as Vector3) + Vector3(0, 0.6, 0)
			if cam.is_position_behind(wp):
				continue
			var t: float = player.KILL_MARK_TIME - float(m["t"])
			var a := clampf(float(m["t"]) / 0.8, 0.0, 1.0)
			var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - t / 0.18)
			var sp := cam.unproject_position(wp) - Vector2(0, t * 14.0)
			var s := 26.0 * pop
			var col := Color(red, a)
			# romb za czaszką
			var dia := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0)])
			draw_colored_polygon(dia, Color(0, 0, 0, 0.45 * a))
			draw_polyline(dia + PackedVector2Array([sp + Vector2(0, -s)]), col, 2.0, true)
			_skull(sp, s * 0.9, col)
			if m["head"]:
				_center_text(font, "GŁOWA", sp + Vector2(0, s + 16.0), 13, col)
	# komunikat pod celownikiem: ELIMINACJA +100 ...
	var bt: float = player.kill_banner_t
	if bt > 0.0:
		var a := clampf(bt / 0.5, 0.0, 1.0)
		var slide := maxf(0.0, (bt - 2.3) / 0.3) * 30.0
		var y := vs.y * 0.5 + 64.0 + slide
		var lines: Array = player.kill_banner
		for i in lines.size():
			var ln: Dictionary = lines[i]
			var big := i == 0
			var txt: String = ln["text"]
			if int(ln["pts"]) > 0:
				txt += "   +%d" % int(ln["pts"])
			var col := Color(red, a) if big else Color(1, 0.9, 0.75, a * 0.9)
			_center_text(font, txt, Vector2(vs.x * 0.5 + 1, y + 1), 24 if big else 16, Color(0, 0, 0, a * 0.6))
			_center_text(font, txt, Vector2(vs.x * 0.5, y), 24 if big else 16, col)
			y += 30.0 if big else 22.0
	# lista zabójstw i punkty (prawy górny róg)
	draw_string(font, Vector2(vs.x - 230, 58), "Punkty: %d" % player.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.6, 0.9))
	var fy := 90.0
	for k: Dictionary in player.kill_feed:
		var a := clampf(float(k["t"]), 0.0, 1.0)
		var t: String = k["text"]
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var x := vs.x - 24.0 - w - 30.0
		draw_rect(Rect2(x - 8, fy - 17, w + 46, 24), Color(0, 0, 0, 0.45 * a))
		draw_rect(Rect2(x - 8, fy - 17, 3, 24), Color(red, a))
		draw_string(font, Vector2(x, fy), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, a))
		_skull(Vector2(x + w + 18, fy - 5), 14.0, Color(red, a))
		fy += 28.0
