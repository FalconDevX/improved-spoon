extends Node
## Ustawienia gracza (autoload "Settings"): filtr kolorów, jakość grafiki, czułość myszy, pole
## widzenia, głośność. Zapisywane w user://settings.cfg, wczytywane przy starcie.

signal changed

const PATH := "user://settings.cfg"
const GRADES := ["Filmowy", "Wojenny", "Ciepły zachód", "Chłodny poranek", "Noir", "Bez filtra"]
const QUALITY := ["Niska", "Średnia", "Wysoka"]
const BOT_COUNTS := [0, 4, 8, 12, 16, 24, 32]
const DIFFICULTY := ["Łatwy", "Normalny", "Trudny"]

var grade := 0
var quality := 2
var sens := 1.0
var fov := 70.0
var volume := 0.8
# opcje gry (solo i host PvP)
var bots := 5                # indeks w BOT_COUNTS
var difficulty := 1
var bot_respawn := false
var air_bots := 0             # boty-piloci (samoloty i śmigłowce), 0..AIR_BOTS_MAX
const AIR_BOTS_MAX := 5
# solo: boty w drużynie gracza (piechota idzie za graczem, piloci polują na wrogów)
const ALLY_COUNTS := [0, 2, 4, 6, 8, 12, 16]
var ally_bots := 0            # indeks w ALLY_COUNTS
var ally_air := 0             # sojusznicy-piloci, 0..AIR_BOTS_MAX


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		grade = clampi(int(cf.get_value("video", "grade", grade)), 0, GRADES.size() - 1)
		quality = clampi(int(cf.get_value("video", "quality", quality)), 0, QUALITY.size() - 1)
		fov = clampf(float(cf.get_value("video", "fov", fov)), 60.0, 100.0)
		sens = clampf(float(cf.get_value("input", "sens", sens)), 0.2, 3.0)
		volume = clampf(float(cf.get_value("audio", "volume", volume)), 0.0, 1.0)
		bots = clampi(int(cf.get_value("game", "bots", bots)), 0, BOT_COUNTS.size() - 1)
		difficulty = clampi(int(cf.get_value("game", "difficulty", difficulty)), 0, DIFFICULTY.size() - 1)
		bot_respawn = bool(cf.get_value("game", "bot_respawn", bot_respawn))
		air_bots = clampi(int(cf.get_value("game", "air_bots", air_bots)), 0, AIR_BOTS_MAX)
		ally_bots = clampi(int(cf.get_value("game", "ally_bots", ally_bots)), 0, ALLY_COUNTS.size() - 1)
		ally_air = clampi(int(cf.get_value("game", "ally_air", ally_air)), 0, AIR_BOTS_MAX)
	_apply_audio()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "grade", grade)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "fov", fov)
	cf.set_value("input", "sens", sens)
	cf.set_value("audio", "volume", volume)
	cf.set_value("game", "bots", bots)
	cf.set_value("game", "difficulty", difficulty)
	cf.set_value("game", "bot_respawn", bot_respawn)
	cf.set_value("game", "air_bots", air_bots)
	cf.set_value("game", "ally_bots", ally_bots)
	cf.set_value("game", "ally_air", ally_air)
	cf.save(PATH)
	_apply_audio()
	changed.emit()


func next_grade() -> void:
	grade = (grade + 1) % GRADES.size()
	save()


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
