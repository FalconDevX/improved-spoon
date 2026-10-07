extends RefCounted
## Wspólny wygląd interfejsu: wojskowa czcionka (Bahnschrift z Windows, zapasowo Segoe UI / Arial),
## ciemne półprzezroczyste panele z bursztynowym akcentem.

const ACCENT := Color(0.95, 0.72, 0.28)
const TEXT := Color(0.92, 0.93, 0.9)
const DIM := Color(0.65, 0.68, 0.66)

static var _font: Font
static var _bold: Font


static func font(bold := false) -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
		var b := SystemFont.new()
		b.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		b.font_weight = 700
		b.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_bold = b
	return _bold if bold else _font


static func _box(bg: Color, border := Color(0, 0, 0, 0), left := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = left
	s.content_margin_left = 18
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Motyw HUD-u (tylko czcionka).
static func hud() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	return t


## Motyw menu: przyciski z paskiem akcentu, pola, suwaki, listy.
static func menu() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "Button", _box(Color(0.05, 0.06, 0.06, 0.55)))
	t.set_stylebox("hover", "Button", _box(Color(0.95, 0.72, 0.28, 0.16), ACCENT, 4))
	t.set_stylebox("pressed", "Button", _box(Color(0.95, 0.72, 0.28, 0.3), ACCENT, 4))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT, 2))
	t.set_stylebox("disabled", "Button", _box(Color(0.05, 0.06, 0.06, 0.3)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.9, 0.7))
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", Color(1, 0.9, 0.7))
	t.set_constant("h_separation", "Button", 10)
	var le := _box(Color(0, 0, 0, 0.5), ACCENT, 3)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0.6), ACCENT, 3))
	t.set_color("font_color", "LineEdit", Color(1, 0.92, 0.75))
	t.set_stylebox("normal", "OptionButton", _box(Color(0.05, 0.06, 0.06, 0.6)))
	t.set_stylebox("hover", "OptionButton", _box(Color(0.95, 0.72, 0.28, 0.16), ACCENT, 3))
	t.set_stylebox("pressed", "OptionButton", _box(Color(0.95, 0.72, 0.28, 0.3), ACCENT, 3))
	t.set_stylebox("focus", "OptionButton", _box(Color(0, 0, 0, 0), ACCENT, 2))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.06, 0.07, 0.07, 0.97), ACCENT, 2))
	t.set_stylebox("hover", "PopupMenu", _box(Color(0.95, 0.72, 0.28, 0.25)))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 0.9, 0.7))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return t
