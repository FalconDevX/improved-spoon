extends Node3D
## Fotel w C-17 dla pasażera (drugi pilot): [F] — siadasz (siedzisz i rozglądasz się, samolot
## prowadzi pilot), [F] jeszcze raz — wstajesz. Zajęty fotel nie przyjmie drugiej osoby.

var plane = null
var board_name := "fotel"
var board_text := "[F] — usiądź (drugi pilot)"
var occupant = null


func _ready() -> void:
	add_to_group("launcher")


func can_board(p) -> bool:
	if plane == null or not is_instance_valid(plane) or plane.destroyed or p.get("vehicle") != null:
		return false
	if occupant != null and is_instance_valid(occupant) and not occupant.down:
		return false
	if p.get("seat") != null:
		return false
	return p.global_position.distance_to(global_position) < 1.5


func board(p) -> void:
	occupant = p
	p.sit(self)


func vacate(p) -> void:
	if occupant == p:
		occupant = null
