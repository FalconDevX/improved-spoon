extends CanvasLayer
## Menu główne i menu pauzy: tytuł, przyciski z opisem, strony PvP / ustawienia / sterowanie.
## Tło to żywa scena (kamera krąży nad mapą — ustawia ją main.gd), przyciemniona z lewej strony.

signal solo
signal pvp(online: bool, host: bool, code: String)
signal resume
signal to_menu
signal restart
signal options_changed

const UiTheme = preload("res://scripts/ui_theme.gd")

const TITLE := "BLACK MERIDIAN"
const SUBTITLE := "O P E R A T I O N   2 0 2 7"
const VERSION := "wersja 0.4"

var in_game := false
var code := ""
var can_host := true         # pauza: solo albo host PvP może zmieniać opcje gry
var _pages := {}
var _desc: Label
var _status: Label
var _code: LineEdit


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UiTheme.menu()
	add_child(root)
	# przyciemnienie: od lewej (pod menu) do przezroczystego
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.025, 0.03, 0.93), Color(0.02, 0.025, 0.03, 0.7), Color(0.02, 0.025, 0.03, 0.05 if not in_game else 0.45)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(96, 90)
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_override("font", UiTheme.font(true))
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	col.add_child(title)
	var sub := Label.new()
	sub.text = SUBTITLE
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", UiTheme.ACCENT)
	col.add_child(sub)
	var line := ColorRect.new()
	line.color = UiTheme.ACCENT
	line.custom_minimum_size = Vector2(120, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(line)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 46)
	col.add_child(gap)
	_pages["main"] = _page_main()
	_pages["pvp"] = _page_pvp()
	_pages["settings"] = _page_settings()
	_pages["game"] = _page_game()
	_pages["controls"] = _page_controls()
	for k: String in _pages:
		col.add_child(_pages[k])
	_desc = Label.new()
	_desc.add_theme_font_size_override("font_size", 15)
	_desc.add_theme_color_override("font_color", UiTheme.DIM)
	_desc.custom_minimum_size = Vector2(520, 44)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_desc)
	var foot := Label.new()
	foot.text = VERSION + "   ·   Godot 4.7   ·   F2 — filtr kolorów"
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(96, -48)
	root.add_child(foot)
	show_page("main")


func show_page(name: String) -> void:
	for k: String in _pages:
		(_pages[k] as Control).visible = k == name
	if _desc:
		_desc.text = ""


func set_status(t: String) -> void:
	if _status:
		_status.text = t


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not (_pages["main"] as Control).visible:
			show_page("main")
		elif in_game:
			resume.emit()


func _button(text: String, desc: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 50)
	b.add_theme_font_override("font", UiTheme.font(true))
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): _desc.text = desc)
	b.focus_entered.connect(func(): _desc.text = desc)
	return b


func _box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	return v


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UiTheme.font(true))
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l


func _page_main() -> Control:
	var v := _box()
	if in_game:
		v.add_child(_button("WZNÓW", "Wróć do walki.", func(): resume.emit()))
		if code != "":
			var cb := _button("KOD GRY:  %s" % code, "Kliknij, żeby skopiować kod do schowka i wysłać go drugiemu graczowi.", func(): pass)
			cb.pressed.connect(_copy_code.bind(cb))
			v.add_child(cb)
		if can_host:
			v.add_child(_button("OPCJE GRY", "Liczba botów, poziom trudności, odradzanie botów, restart mapy.", func(): show_page("game")))
		else:
			v.add_child(_button("OPCJE GRY", "Opcje gry (boty, restart mapy) ustawia host.", func(): pass))
	else:
		v.add_child(_button("GRA SOLO", "Misja z oddziałami botów na posterunkach. Na lotnisku czekają myśliwce z bombami.", func(): solo.emit()))
		v.add_child(_button("MULTIPLAYER", "Gra z drugim graczem przez internet albo w sieci lokalnej (z botami).", func(): show_page("pvp")))
		v.add_child(_button("OPCJE GRY", "Liczba botów, poziom trudności i odradzanie botów (solo i jako host w multiplayerze).", func(): show_page("game")))
	v.add_child(_button("USTAWIENIA", "Filtr kolorów, jakość grafiki, czułość myszy, pole widzenia, głośność.", func(): show_page("settings")))
	v.add_child(_button("STEROWANIE", "Klawisze piechoty i samolotu.", func(): show_page("controls")))
	if in_game:
		v.add_child(_button("MENU GŁÓWNE", "Zakończ grę i wróć do menu.", func(): to_menu.emit()))
	v.add_child(_button("WYJDŹ", "Zamknij grę.", func(): get_tree().quit()))
	return v


func _page_pvp() -> Control:
	var v := _box()
	v.add_child(_heading("MULTIPLAYER"))
	var l := Label.new()
	l.text = "Kod gry — ten sam u obu graczy"
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	v.add_child(l)
	_code = LineEdit.new()
	_code.text = code
	_code.custom_minimum_size = Vector2(440, 46)
	_code.add_theme_font_size_override("font_size", 24)
	v.add_child(_code)
	v.add_child(_button("STWÓRZ GRĘ ONLINE", "Wymaga kluczy GD-Sync (patrz instrukcja wtyczki).", func(): pvp.emit(true, true, _code.text)))
	v.add_child(_button("DOŁĄCZ ONLINE", "Wpisz kod gry, którą stworzył przeciwnik.", func(): pvp.emit(true, false, _code.text)))
	v.add_child(_button("STWÓRZ GRĘ W SIECI LOKALNEJ", "Bez kluczy — ta sama sieć albo ten sam komputer.", func(): pvp.emit(false, true, _code.text)))
	v.add_child(_button("DOŁĄCZ W SIECI LOKALNEJ", "Bez kluczy — ta sama sieć albo ten sam komputer.", func(): pvp.emit(false, false, _code.text)))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(440, 30)
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1, 0.85, 0.6))
	v.add_child(_status)
	v.add_child(_button("‹  WSTECZ", "", func(): show_page("main")))
	return v


func _row(label: String, ctrl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(190, 0)
	l.add_theme_font_size_override("font_size", 18)
	h.add_child(l)
	ctrl.custom_minimum_size = Vector2(250, 40)
	h.add_child(ctrl)
	return h


func _slider(lo: float, hi: float, step: float, val: float, fmt: String, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(190, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := Label.new()
	vl.text = fmt % val
	vl.custom_minimum_size = Vector2(60, 0)
	vl.add_theme_font_size_override("font_size", 16)
	s.value_changed.connect(func(x: float):
		vl.text = fmt % x
		cb.call(x))
	h.add_child(s)
	h.add_child(vl)
	return h


func _option(items: Array, sel: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it: String in items:
		o.add_item(it)
	o.selected = sel
	o.item_selected.connect(cb)
	return o


func _page_settings() -> Control:
	var v := _box()
	v.add_child(_heading("USTAWIENIA"))
	v.add_child(_row("Filtr kolorów", _option(Settings.GRADES, Settings.grade, func(i: int):
		Settings.grade = i
		Settings.save())))
	v.add_child(_row("Jakość grafiki", _option(Settings.QUALITY, Settings.quality, func(i: int):
		Settings.quality = i
		Settings.save())))
	v.add_child(_row("Czułość myszy", _slider(0.2, 3.0, 0.05, Settings.sens, "%.2f", func(x: float):
		Settings.sens = x
		Settings.save())))
	v.add_child(_row("Pole widzenia", _slider(60.0, 100.0, 1.0, Settings.fov, "%.0f°", func(x: float):
		Settings.fov = x
		Settings.save())))
	v.add_child(_row("Głośność", _slider(0.0, 100.0, 5.0, Settings.volume * 100.0, "%.0f%%", func(x: float):
		Settings.volume = x / 100.0
		Settings.save())))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap)
	v.add_child(_button("‹  WSTECZ", "", func(): show_page("main")))
	return v


func _copy_code(b: Button) -> void:
	DisplayServer.clipboard_set(code)
	b.text = "SKOPIOWANO:  %s" % code
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(b):
		b.text = "KOD GRY:  %s" % code


func _page_game() -> Control:
	var v := _box()
	v.add_child(_heading("OPCJE GRY"))
	var counts: Array = Settings.BOT_COUNTS.map(func(n): return str(n))
	v.add_child(_row("Liczba botów", _option(counts, Settings.bots, func(i: int):
		Settings.bots = i
		Settings.save())))
	v.add_child(_row("Poziom trudności", _option(Settings.DIFFICULTY, Settings.difficulty, func(i: int):
		Settings.difficulty = i
		Settings.save()
		options_changed.emit())))
	v.add_child(_row("Boty-piloci", _option(["Brak", "1", "2", "3", "4", "5"], Settings.air_bots, func(i: int):
		Settings.air_bots = i
		Settings.save())))
	var allies: Array = Settings.ALLY_COUNTS.map(func(n): return str(n))
	v.add_child(_row("Sojusznicy (solo)", _option(allies, Settings.ally_bots, func(i: int):
		Settings.ally_bots = i
		Settings.save())))
	v.add_child(_row("Sojusznicy-piloci (solo)", _option(["Brak", "1", "2", "3", "4", "5"], Settings.ally_air, func(i: int):
		Settings.ally_air = i
		Settings.save())))
	v.add_child(_row("Odradzanie botów", _option(["Wyłączone", "Po 30 s"], 1 if Settings.bot_respawn else 0, func(i: int):
		Settings.bot_respawn = i == 1
		Settings.save())))
	var l := Label.new()
	l.text = "Liczba botów zmienia się po restarcie mapy. Boty-piloci i sojusznicy-piloci zajmują wolne samoloty i śmigłowce na bieżąco. Sojusznicy (niebiescy) idą za tobą i strzelają do wrogów — uważaj, ich też można postrzelić. Restart: wszyscy wracają na start, wyniki od zera."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	v.add_child(l)
	v.add_child(_button("RESTART MAPY", "Nowa runda z obecnymi opcjami (w multiplayerze także u drugiego gracza).", func(): restart.emit()))
	v.add_child(_button("‹  WSTECZ", "", func(): show_page("main")))
	return v


func _page_controls() -> Control:
	var v := _box()
	v.add_child(_heading("STEROWANIE"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	cols.add_child(_keys("PIECHOTA", [
		["WASD", "ruch"], ["Shift", "bieg / wstrzymanie oddechu"], ["Spacja", "skok"], ["Ctrl", "kucanie"],
		["LPM / PPM", "strzał / celowanie"], ["R", "przeładowanie / naprawa (trzymaj)"], ["B", "tryb ognia"], ["1–0, kółko", "broń (8 — Piorun: PPM namierza)"],
		["H", "opatrunek"], ["F", "wsiądź / skrzynka"], ["Q / E", "wychylanie"], ["G", "granat"], ["V", "widok"], ["L", "laser"], ["Tab", "rentgen"]]))
	cols.add_child(_keys("SAMOLOT", [
		["Mysz", "kierunek lotu"], ["W / S", "gaz"], ["A / D", "ster kierunku"], ["Strzałki", "drążek ręcznie"],
		["LPM", "karabiny 12,7 mm"], ["Spacja", "seria bomb / hamulce"], ["C", "flary"], ["V", "kabina / z tyłu"], ["F", "wysiądź (na ziemi)"]]))
	cols.add_child(_keys("ŚMIGŁOWIEC", [
		["Mysz", "kierunek i celowanie"], ["Spacja / Ctrl", "w górę / w dół"], ["W / S", "do przodu / do tyłu"], ["A / D", "w bok"],
		["LPM", "działko 12,7 mm"], ["PPM", "rakiety"], ["C", "flary"], ["V", "kabina / z tyłu"], ["F", "wysiądź (na ziemi)"],
		["", ""], ["M", "mapa, LPM — waypoint"], ["Enter", "czat"], ["F1", "pomoc w grze"], ["F2", "filtr kolorów"], ["Esc", "pauza"]]))
	v.add_child(cols)
	v.add_child(_button("‹  WSTECZ", "", func(): show_page("main")))
	return v


func _keys(title: String, rows: Array) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", UiTheme.DIM)
	v.add_child(t)
	for r: Array in rows:
		var h := HBoxContainer.new()
		var k := Label.new()
		k.text = r[0]
		k.custom_minimum_size = Vector2(110, 0)
		k.add_theme_font_override("font", UiTheme.font(true))
		k.add_theme_font_size_override("font_size", 16)
		k.add_theme_color_override("font_color", Color(1, 0.88, 0.6))
		var d := Label.new()
		d.text = r[1]
		d.add_theme_font_size_override("font_size", 16)
		h.add_child(k)
		h.add_child(d)
		v.add_child(h)
	return v
