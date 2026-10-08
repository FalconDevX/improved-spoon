extends Node3D
## Przełącznik rampy C-17 dla pieszych: [F] w pobliżu otwiera / zamyka rampę (jeden w ładowni przy
## rampie, drugi na zewnątrz przy ogonie). Korzysta z tej samej obsługi [F] co wyrzutnie (grupa "launcher").

var plane = null
var board_name := "rampa"
var board_text := "[F] — rampa C-17: otwórz / zamknij"


func _ready() -> void:
	add_to_group("launcher")


func can_board(p) -> bool:
	if plane == null or not is_instance_valid(plane) or plane.destroyed or p.get("vehicle") != null:
		return false
	return p.global_position.distance_to(global_position) < 2.0


func board(_p) -> void:
	plane.toggle_ramp()
