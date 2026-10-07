extends Node
## Ustawienia gracza (autoload "Settings"): filtr kolorów, jakość grafiki, czułość myszy, pole
## widzenia, głośność. Zapisywane w user://settings.cfg, wczytywane przy starcie.

signal changed

const PATH := "user://settings.cfg"
const GRADES := ["Filmowy", "Wojenny", "Ciepły zachód", "Chłodny poranek", "Noir", "Bez filtra"]
const QUALITY := ["Niska", "Średnia", "Wysoka"]

var grade := 0
var quality := 2
var sens := 1.0
var fov := 70.0
var volume := 0.8


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		grade = clampi(int(cf.get_value("video", "grade", grade)), 0, GRADES.size() - 1)
		quality = clampi(int(cf.get_value("video", "quality", quality)), 0, QUALITY.size() - 1)
		fov = clampf(float(cf.get_value("video", "fov", fov)), 60.0, 100.0)
		sens = clampf(float(cf.get_value("input", "sens", sens)), 0.2, 3.0)
		volume = clampf(float(cf.get_value("audio", "volume", volume)), 0.0, 1.0)
	_apply_audio()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "grade", grade)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "fov", fov)
	cf.set_value("input", "sens", sens)
	cf.set_value("audio", "volume", volume)
	cf.save(PATH)
	_apply_audio()
	changed.emit()


func next_grade() -> void:
	grade = (grade + 1) % GRADES.size()
	save()


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
