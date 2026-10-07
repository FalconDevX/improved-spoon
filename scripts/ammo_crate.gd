extends StaticBody3D
## Skrzynka z amunicją ([F]: pełne magazynki wszystkich broni + granaty + opatrunki) albo apteczka
## (kind = "med": tamuje rany, uzupełnia krew, zdejmuje ból). Po użyciu odnawia się
## (pokrywa szara, na minimapie szary znacznik).

const Weapons = preload("res://scripts/weapons.gd")

const RANGE := 2.6
const COOLDOWN := 45.0
const BANDAGES := 2

var kind := "ammo"            # "ammo" albo "med"
var cooldown := 0.0
var _lid: MeshInstance3D
var _lid_ready: StandardMaterial3D
var _lid_empty: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	add_to_group("ammo_crate")
	collision_layer = 1
	collision_mask = 0
	set_meta("mat", "wood")
	var size := Vector3(1.1, 0.5, 0.62)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y * 0.5
	add_child(cs)
	set_meta("size", size)
	var med := kind == "med"
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.86, 0.86, 0.83) if med else Color(0.27, 0.31, 0.18)
	olive.roughness = 0.8
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y - 0.08, size.z)
	body.mesh = bm
	body.material_override = olive
	body.position.y = (size.y - 0.08) * 0.5
	add_child(body)
	# pokrywa: oliwkowa = pełna, szara = pusta (odnawia się)
	_lid_ready = olive.duplicate()
	_lid_ready.albedo_color = Color(0.92, 0.92, 0.9) if med else Color(0.22, 0.26, 0.15)
	_lid_empty = olive.duplicate()
	_lid_empty.albedo_color = Color(0.3, 0.3, 0.3)
	_lid = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(size.x + 0.04, 0.08, size.z + 0.04)
	_lid.mesh = lm
	_lid.material_override = _lid_ready
	_lid.position.y = size.y - 0.04
	add_child(_lid)
	# żółty pas i napisy na bokach
	var band := MeshInstance3D.new()
	var bandm := BoxMesh.new()
	bandm.size = Vector3(0.08, size.y - 0.1, size.z + 0.01)
	band.mesh = bandm
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.8, 0.08, 0.06) if med else Color(0.85, 0.68, 0.15)
	band.material_override = yellow
	band.position = Vector3(size.x * 0.32, (size.y - 0.08) * 0.5, 0)
	if med:
		# czerwony krzyż na pokrywie zamiast pasa
		band.position = Vector3(0, size.y + 0.002, 0)
		(band.mesh as BoxMesh).size = Vector3(0.38, 0.01, 0.11)
		var bar2 := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(0.11, 0.01, 0.38)
		bar2.mesh = b2
		bar2.material_override = yellow
		bar2.position = band.position
		add_child(bar2)
	add_child(band)
	for side in [1.0, -1.0]:
		var t := Label3D.new()
		t.text = "✚ MEDIC" if med else "AMMO 5.56 / 7.62 / 9MM"
		t.font_size = 22
		t.pixel_size = 0.0022
		t.modulate = Color(0.8, 0.1, 0.08) if med else Color(0.9, 0.8, 0.45)
		t.outline_size = 0
		t.position = Vector3(-0.08, size.y * 0.42, side * (size.z * 0.5 + 0.006))
		t.rotation.y = 0.0 if side > 0.0 else PI
		add_child(t)
	# pływający znacznik nad skrzynką (widać z daleka)
	_label = Label3D.new()
	_label.text = "▼ APTECZKA" if med else "▼ AMUNICJA"
	_label.font_size = 32
	_label.pixel_size = 0.0007
	_label.fixed_size = true        # ta sama wielkość na ekranie z bliska i z daleka
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.modulate = Color(1.0, 0.35, 0.3, 0.95) if med else Color(1.0, 0.85, 0.3, 0.9)
	_label.outline_modulate = Color(0, 0, 0, 0.7)
	_label.outline_size = 8
	_label.position.y = 1.25
	add_child(_label)


func is_ready() -> bool:
	return cooldown <= 0.0


func near(p: Node3D) -> bool:
	return p.global_position.distance_to(global_position) < RANGE


## Uzupełnia amunicję graczowi. Zwraca opis albo "" (pusta).
func resupply(player) -> String:
	if not is_ready():
		return ""
	if kind == "med":
		var before: float = player.vitals.blood
		player.vitals.heal(2500.0)
		player.bandages = mini(player.bandages + 1, 8)
		_use()
		return "Apteczka: rany opatrzone, krew +%d ml" % int(player.vitals.blood - before)
	var got := 0
	for g in player.guns:
		got += g.refill()
	var gr: int = player.MAX_GRENADES - player.grenades
	player.grenades = player.MAX_GRENADES
	var b := mini(BANDAGES, 8 - player.bandages)
	player.bandages += maxi(b, 0)
	_use()
	return "Uzupełniono amunicję (+%d naboi)%s%s" % [got, ", granaty +%d" % gr if gr > 0 else "", ", opatrunki +%d" % b if b > 0 else ""]


func _use() -> void:
	cooldown = COOLDOWN * (1.35 if kind == "med" else 1.0)
	_lid.material_override = _lid_empty
	_label.visible = false


func _process(dt: float) -> void:
	if cooldown > 0.0:
		cooldown -= dt
		if cooldown <= 0.0:
			_lid.material_override = _lid_ready
			_label.visible = true
	# znacznik lekko pulsuje
	if _label.visible:
		_label.position.y = 1.25 + sin(Time.get_ticks_msec() * 0.003) * 0.08
