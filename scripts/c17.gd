extends "res://scripts/plane.gd"
## Boeing C-17A Globemaster III, powiększony K razy względem prawdziwego (52 m rozpiętości, 55 m długości). Model z paczki
## „C-17A Globemaster III” z pełną ładownią (fotele wzdłuż burt, podłoga z rolkami) i kabiną załogi.
## Po wnętrzu się chodzi — także w locie: ładownia przenosi stojących w niej żołnierzy razem
## z samolotem (player.gd: platform), burty i dach ich trzymają. Do kabiny prowadzą schody z przodu
## ładowni; [F] przy lewym fotelu — za sterami, [F] za sterami — wstajesz, samolot leci dalej
## na autopilocie (wyrównuje i krąży). Rampa z tyłu [R przy rampie albo G za sterami] — otwarta
## na ziemi wjeżdżają po niej pojazdy (w locie są przypięte do podłogi). Z rampy zrzuca bomby
## [Spacja], [B] — rodzaj (w tym MOAB i atomowa).

const Terrain = preload("res://scripts/terrain.gd")
const DIR := "res://assets/vehicles/c17/"
const K := 1.6                                 # skala samolotu (model, kolizja, wnętrze); ludzie bez zmian
const OFF := Vector3(0, 5.0, -6.0) * K        # model -> układ samolotu (spód kół na -GEAR_H)
const HOLD := AABB(Vector3(-2.85, -2.6, -26.2) * K, Vector3(5.7, 5.4, 38.0) * K)   # wnętrze (ładownia, kabina, rampa)
const FLOOR_Y := -2.4 * K                      # podłoga ładowni
const DECK_Y := 0.15 * K                       # podłoga kabiny załogi
const HINGE := Vector3(0, -2.4, 2.0) * K       # oś rampy
const RAMP_LEN := 9.2 * K
const STAIR_X := 1.6 * K                       # schody do kabiny: oś, dół, długość
const STAIR_Z := -17.4 * K
const STAIR_RUN := 3.6 * K
const RAMP_UP := -0.17                         # zamknięta: lekko w górę [rad] (tak leży w siatce modelu)
const RAMP_DOWN := 0.2                         # otwarta: koniec na ziemi
const AP_ALT := 650.0                          # autopilot: wysokość krążenia [m]

var board_name := "C-17"
var ramp_open := false
var _ramp_a := RAMP_UP
var _ramp: Node3D
var _door: Node3D
var _ramp_col: CollisionShape3D
var _ramp_body: AnimatableBody3D               # osobne ciało: niesie pieszych i pojazdy, nie pcha samolotu o ziemię
var _carried := {}                             # pojazd -> Transform3D w układzie samolotu


func _init() -> void:
	GEAR_H = 4.1 * K
	THRUST = 6.5
	PITCH_RATE = 0.4
	ROLL_RATE = 0.6
	YAW_RATE = 0.2
	V_MIN = 45.0
	V_MAX = 115.0
	TURN_RATE = 0.32
	MAX_BANK = 0.42                            # łagodne zakręty — da się chodzić po ładowni
	MAX_HP = 900.0
	AMMO = 0
	BOMBS = 12
	GUNS = []
	bomb_kinds = ["he", "moab", "thermo", "bunker", "napalm", "cluster", "frag", "nuke"]
	SEAT = Vector3(-0.75 * K, DECK_Y, -24.6 * K)
	EYE = Vector3(-0.75 * K, DECK_Y + 1.25, -24.75 * K)
	BOARD = SEAT
	BOARD_R = 1.4
	EXIT = Vector3(-0.2 * K, DECK_Y, -23.4 * K)
	CAM_DIST = 70.0 * K
	CAM_UP = 15.0 * K
	paint = Color(0.47, 0.5, 0.53)


func _ready() -> void:
	super._ready()
	add_to_group("walkable")
	for at: Vector3 in [Vector3(2.3 * K, FLOOR_Y, 0.8 * K), Vector3(3.9 * K, -GEAR_H, 3.0 * K)]:
		var sw := preload("res://scripts/c17_ramp.gd").new()
		sw.plane = self
		sw.position = at
		add_child(sw)
	set_meta("size", Vector3(52.0, 8.0, 55.0) * K)
	set_meta("hollow", 0.002)
	process_physics_priority = -10            # rusza się przed żołnierzami, których przenosi


func _tex_mat(tex: String, col := Color(1, 1, 1), rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if tex != "":
		m.albedo_texture = load(DIR + tex + "_alb.png")
	m.albedo_color = col
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _part_obj(name: String, mat: Material, parent: Node3D, offset: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = load(DIR + name + ".obj")
	mi.material_override = mat
	mi.position = offset
	mi.scale = Vector3.ONE * K
	parent.add_child(mi)
	_parts.append(mi)
	return mi


func _build_model() -> void:
	_burnt = StandardMaterial3D.new()
	_burnt.albedo_color = Color(0.06, 0.055, 0.05)
	_burnt.roughness = 0.95
	if ResourceLoader.exists(DIR + "body.obj"):
		var grey := _tex_mat("", Color(0.47, 0.5, 0.53), 0.55)
		var dark := _tex_mat("", Color(0.3, 0.31, 0.32), 0.7)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.25, 0.32, 0.38, 0.35)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.metallic = 0.6
		glass.roughness = 0.05
		glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		var parts := [["body", _tex_mat("body")], ["lwing", _tex_mat("lwing")], ["rwing", _tex_mat("rwing")],
			["floor", _tex_mat("floor", Color(1, 1, 1), 0.8)], ["walls", _tex_mat("walls", Color(1, 1, 1), 0.85)],
			["ext", grey], ["int", dark], ["glass", glass]]
		for p: Array in parts:
			_part_obj(p[0], p[1], self, OFF)
		# rampa na osi (obrót wokół X) i tylne drzwi (unoszą się do ogona)
		_ramp = Node3D.new()
		_ramp.position = HINGE
		add_child(_ramp)
		_part_obj("ramp", _tex_mat("floor", Color(1, 1, 1), 0.8), _ramp, OFF - HINGE)
		_door = Node3D.new()
		add_child(_door)
		_part_obj("door", grey, _door, OFF)
	else:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(6.0, 6.0, 50.0) * K
		box.mesh = bm
		add_child(box)
		_parts.append(box)
	# węzły wspólnego kodu (śmigło) — odrzutowiec ich nie pokazuje
	_prop = Node3D.new()
	add_child(_prop)
	_blades = Node3D.new()
	_prop.add_child(_blades)
	_disc = MeshInstance3D.new()
	_prop.add_child(_disc)
	# zrzut bomb z rampy
	for i in BOMBS:
		var r := Node3D.new()
		r.position = Vector3((i % 3 - 1) * 1.2, -1.2 * K, (9.0 + (i / 3) * 0.6) * K)
		add_child(r)
		_racks.append(r)


## Pusty kadłub z prostokątów: podłoga, burty, dach, blok pod kabiną, schody, skrzydła, usterzenie.
func _collision_boxes() -> Array:
	var out: Array = []
	for b: Array in _boxes_raw():
		out.append([(b[0] as Vector3) * K, (b[1] as Vector3) * K])
	return out


## Bryły kolizji w skali prawdziwego samolotu (_collision_boxes mnoży je przez K).
func _boxes_raw() -> Array:
	const FL := -2.4
	const DK := 0.15
	var cy := (FL + 2.45) * 0.5
	return [
		[Vector3(5.8, 1.7, 23.2), Vector3(0, -3.25, -9.6)],                 # podłoga ładowni (do ziemi)
		[Vector3(0.5, 5.2, 37.0), Vector3(-3.1, cy, -7.0)],                # burty
		[Vector3(0.5, 5.2, 37.0), Vector3(3.1, cy, -7.0)],
		[Vector3(6.7, 0.6, 37.0), Vector3(0, 2.75, -7.0)],                 # dach
		[Vector3(5.8, 4.25, 5.2), Vector3(0, (-4.1 + DK) * 0.5, -23.6)],   # pod kabiną
		[Vector3(5.8, 0.4, 3.0), Vector3(0, 2.55, -24.5)],                 # dach kabiny
		[Vector3(5.8, 3.0, 0.5), Vector3(0, DK + 1.5, -26.6)],             # przód kabiny
		[Vector3(23.0, 0.9, 9.0), Vector3(-14.8, 1.0, -7.5)],              # skrzydła (poza kadłubem)
		[Vector3(23.0, 0.9, 9.0), Vector3(14.8, 1.0, -7.5)],
		[Vector3(3.0, 3.0, 10.0), Vector3(-9.0, -1.0, -10.0)],             # silniki
		[Vector3(3.0, 3.0, 10.0), Vector3(9.0, -1.0, -10.0)],
		[Vector3(0.8, 9.0, 12.0), Vector3(0, 8.0, 21.0)],                  # statecznik pionowy
		[Vector3(20.0, 0.6, 5.0), Vector3(0, 11.0, 25.0)],                 # usterzenie poziome
		[Vector3(6.0, 1.2, 10.0), Vector3(0, 2.6, 7.0)],                   # dach nad rampą
	]


func _build_collision() -> void:
	super._build_collision()
	# schody z ładowni do kabiny (prawa strona, pochylnia ~36°)
	var st := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	var rise := DECK_Y - FLOOR_Y
	var run := STAIR_RUN
	sb.size = Vector3(1.3 * K, 0.25, sqrt(rise * rise + run * run))
	st.shape = sb
	st.position = Vector3(STAIR_X, (FLOOR_Y + DECK_Y) * 0.5 - 0.1, STAIR_Z - run * 0.5)
	st.rotation.x = atan2(rise, run)      # wyżej z przodu (kabina), niżej od strony ładowni
	add_child(st)
	_build_stairs(rise, run)
	# rampa (obraca się razem z modelem)
	_ramp_body = AnimatableBody3D.new()
	_ramp_body.sync_to_physics = false
	_ramp_body.collision_layer = LAYER
	_ramp_body.collision_mask = 0
	_ramp_body.set_meta("mat", "metal")
	add_child(_ramp_body)
	_ramp_col = CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(5.6 * K, 0.3, RAMP_LEN)
	_ramp_col.shape = rb
	_ramp_body.add_child(_ramp_col)
	add_collision_exception_with(_ramp_body)
	_set_ramp(_ramp_a)


## Widoczne schody do kabiny: pełne stopnie (stopnica i podstopnica), boczne policzki, poręcze;
## w grodzi ładowni nad schodami jest wycięty otwór drzwiowy (siatka modelu).
func _build_stairs(rise: float, run: float) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.36, 0.38, 0.4)
	steel.metallic = 0.5
	steel.roughness = 0.55
	var tread := StandardMaterial3D.new()
	tread.albedo_color = Color(0.2, 0.21, 0.22)
	tread.roughness = 0.9
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.75, 0.1)
	yellow.roughness = 0.6
	var n := int(round(rise / 0.2))            # ~20 cm na stopień
	var w := 1.3 * K
	var d := run / n
	var h := rise / n
	for i in n:
		# bryła stopnia od podłogi ładowni do stopnicy
		var top := FLOOR_Y + h * (i + 1)
		var blk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, top - FLOOR_Y, d)
		blk.mesh = bm
		blk.material_override = steel
		blk.position = Vector3(STAIR_X, (top + FLOOR_Y) * 0.5, STAIR_Z - d * (i + 0.5))
		add_child(blk)
		var tr := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(w + 0.02, 0.03, d + 0.01)
		tr.mesh = tm
		tr.material_override = tread
		tr.position = Vector3(STAIR_X, top + 0.015, blk.position.z)
		add_child(tr)
		var edge := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(w + 0.02, 0.035, 0.06)
		edge.mesh = em
		edge.material_override = yellow
		edge.position = Vector3(STAIR_X, top + 0.02, blk.position.z + d * 0.5 - 0.03)
		add_child(edge)
	# poręcze na słupkach po obu stronach
	var slope := atan2(rise, run)
	var length := sqrt(rise * rise + run * run)
	for side: float in [-w * 0.5 - 0.04, w * 0.5 + 0.04]:
		var rail := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.025
		rm.bottom_radius = 0.025
		rm.height = length
		rail.mesh = rm
		rail.material_override = yellow
		rail.position = Vector3(STAIR_X + side, (FLOOR_Y + DECK_Y) * 0.5 + 0.95, STAIR_Z - run * 0.5)
		rail.rotation.x = PI * 0.5 + slope
		add_child(rail)
		for k in 4:
			var t := (k + 0.5) / 4.0
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.02
			pm.bottom_radius = 0.02
			pm.height = 0.95
			post.mesh = pm
			post.material_override = steel
			post.position = Vector3(STAIR_X + side, FLOOR_Y + rise * t + 0.48, STAIR_Z - run * t)
			add_child(post)
	var lab := Label3D.new()
	lab.text = "KABINA ↑"
	lab.font_size = 48
	lab.pixel_size = 0.006
	lab.modulate = Color(1.0, 0.85, 0.3)
	lab.outline_size = 10
	lab.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lab.position = Vector3(STAIR_X, FLOOR_Y + 2.6, STAIR_Z + 0.8)
	add_child(lab)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.75)
	lamp.light_energy = 1.2
	lamp.omni_range = 8.0
	lamp.position = Vector3(1.0 * K, DECK_Y + 2.0, -20.0 * K)
	add_child(lamp)
	var deck := OmniLight3D.new()
	deck.light_color = Color(1.0, 0.95, 0.85)
	deck.light_energy = 1.6
	deck.omni_range = 6.0
	deck.position = Vector3(0, DECK_Y + 2.2, -24.0 * K)
	add_child(deck)
	# światła ładowni
	for z in [-14.0 * K, -7.0 * K, 0.0, 6.0 * K]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.92, 0.8)
		l.light_energy = 1.4
		l.omni_range = 9.0 * K
		l.position = Vector3(0, 1.8 * K, z)
		add_child(l)


func _set_ramp(a: float) -> void:
	_ramp_a = a
	if _ramp:
		_ramp.rotation.x = a - RAMP_UP          # siatka rampy jest już w położeniu zamkniętym
	if _ramp_col:
		var b := Basis(Vector3.RIGHT, a)
		_ramp_col.transform = Transform3D(b, HINGE + b * Vector3(0, -0.15, RAMP_LEN * 0.5))
	if _door:
		var k := inverse_lerp(RAMP_UP, RAMP_DOWN, a)
		_door.position = Vector3(0, 3.2 * k, 1.8 * k) * K


## Czy punkt (świat) jest we wnętrzu samolotu.
func inside(p: Vector3) -> bool:
	return HOLD.has_point(global_transform.affine_inverse() * p)


func toggle_ramp() -> void:
	ramp_open = not ramp_open
	FX.I.play("bolt", global_transform * HINGE, 4.0, 0.05, 0.5, 30.0)


# ---------------------------------------------------------------- załoga

## Za stery: przy lewym fotelu w kabinie (także w locie, gdy fotel wolny).
func can_board(p) -> bool:
	if destroyed or hp <= 0.0 or pilot != null or p.get("vehicle") != null:
		return false
	return p.global_position.distance_to(global_transform * SEAT) < BOARD_R


## [F] za sterami: na ziemi i w locie wstajesz z fotela (autopilot przejmuje w powietrzu).
func request_exit() -> void:
	var p = pilot
	_unseat(true)
	if Player.net_on:
		_gd().call_func(net_exit)
	if p and is_instance_valid(p):
		p.camera().current = true
		p.set_platform(self)
		if not on_ground:
			p._msg("Autopilot: C-17 leci dalej, krąży na tej wysokości")


func exit_point() -> Vector3:
	return global_transform * EXIT


func pilot_input(e: InputEvent) -> void:
	if e.is_action_pressed("grenade"):
		toggle_ramp()
		return
	super.pilot_input(e)


# ---------------------------------------------------------------- lot

func _physics_process(dt: float) -> void:
	var before := global_transform
	autopilot = pilot == null and not on_ground and hp > 0.0 and not destroyed
	if autopilot:
		# wznosi się na bezpieczną wysokość (ponad grzbiety doliny) i krąży nad mapą, gaz na przelot
		var want_p := clampf((AP_ALT - global_position.y) / 400.0, -0.08, 0.2)
		_aim_pitch = move_toward(_aim_pitch, want_p, dt * 0.3)
		var to_c := atan2(global_position.x, global_position.z)       # kurs na środek mapy
		if Vector2(global_position.x, global_position.z).length() > 800.0:
			_aim_yaw = lerp_angle(_aim_yaw, to_c, 0.6 * dt)
		else:
			_aim_yaw += 0.15 * dt
		throttle = move_toward(throttle, 0.6, dt * 0.2)
	elif _local_pilot() and hp > 0.0:
		# start: przy prędkości oderwania nos sam idzie w górę; nisko nad ziemią nie da się go
		# wcisnąć w ziemię (chyba że to lądowanie — gaz zdjęty)
		var agl := global_position.y - GEAR_H - Terrain.height(global_position.x, global_position.z)
		if on_ground and velocity.length() > V_MIN * 1.05 and throttle > 0.6:
			_aim_pitch = maxf(_aim_pitch, 0.22)
		elif not on_ground and agl < 120.0 and throttle > 0.35:
			_aim_pitch = maxf(_aim_pitch, lerpf(0.18, 0.0, clampf(agl / 120.0, 0.0, 1.0)))
	super._physics_process(dt)
	_set_ramp(move_toward(_ramp_a, RAMP_DOWN if ramp_open else RAMP_UP, dt * 0.15))
	_carry_vehicles(before)


## Pojazdy w ładowni: w locie (albo gdy samolot się toczy) przypięte do podłogi.
func _carry_vehicles(_before: Transform3D) -> void:
	var still := on_ground and velocity.length() < 0.8
	for c in get_tree().get_nodes_in_group("car"):
		if not is_instance_valid(c):
			continue
		if _carried.has(c):
			if still:
				c.freeze = false
				_carried.erase(c)
				remove_collision_exception_with(c)
			else:
				c.global_transform = global_transform * (_carried[c] as Transform3D)
				c.linear_velocity = velocity
		elif not still and inside(c.global_position):
			_carried[c] = global_transform.affine_inverse() * c.global_transform
			c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			c.freeze = true
			add_collision_exception_with(c)      # przewożony pojazd nie jest przeszkodą dla samolotu


func _process(dt: float) -> void:
	super._process(dt)


func _place_camera(rd: float) -> void:
	super._place_camera(rd)


