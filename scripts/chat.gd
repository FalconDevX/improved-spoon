extends Control
## Czat w grze: [Enter] — pisz, [Enter] — wyślij, [Esc] — anuluj. Wiadomości nad paskiem krwi,
## gasną po kilkunastu sekundach (w trakcie pisania widać całą historię). W multiplayerze wiadomość
## trafia do drugiego gracza (main.send_chat → net_chat).

const Player = preload("res://scripts/player.gd")
const SHOW := 12.0
const KEEP := 12

var main
var _edit: LineEdit
var _lines: Array = []        # [tekst, kolor, czas dodania]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit = LineEdit.new()
	_edit.visible = false
	_edit.max_length = 120
	_edit.placeholder_text = "Napisz wiadomość — Enter: wyślij, Esc: anuluj"
	_edit.add_theme_font_size_override("font_size", 16)
	_edit.text_submitted.connect(_send)
	_edit.gui_input.connect(_edit_input)
	add_child(_edit)


func _unhandled_input(e: InputEvent) -> void:
	if not _edit.visible and e.is_action_pressed("chat") and main._player != null:
		_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	var vs := get_viewport_rect().size
	_edit.position = Vector2(20, vs.y - 165)
	_edit.size = Vector2(440, 34)
	_edit.text = ""
	_edit.visible = true
	_edit.grab_focus()
	Player.chat_open = true


func _close() -> void:
	_edit.release_focus()
	_edit.visible = false
	Player.chat_open = false


func _edit_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_close()
		_edit.accept_event()


func _send(t: String) -> void:
	_close()
	t = t.strip_edges()
	if t.is_empty():
		return
	add("Ty: " + t, Color(1, 1, 1))
	main.send_chat(t)


## Nowa wiadomość (też komunikaty systemowe).
func add(text: String, col := Color(1, 1, 1)) -> void:
	_lines.append([text, col, Time.get_ticks_msec() / 1000.0])
	if _lines.size() > KEEP:
		_lines.pop_front()


func _exit_tree() -> void:
	Player.chat_open = false


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var font := get_theme_default_font()
	var now := Time.get_ticks_msec() / 1000.0
	var y := vs.y - 175.0
	var shown := 0
	for i in range(_lines.size() - 1, -1, -1):
		var l: Array = _lines[i]
		var age: float = now - float(l[2])
		var a := 1.0 if _edit.visible else clampf((SHOW - age) / 2.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		var c: Color = l[1]
		var w := font.get_string_size(String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_rect(Rect2(16, y - 17, w + 12, 22), Color(0, 0, 0, 0.4 * a))
		draw_string(font, Vector2(22, y), String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(c, a))
		y -= 24.0
		shown += 1
		if shown >= (KEEP if _edit.visible else 6):
			break
