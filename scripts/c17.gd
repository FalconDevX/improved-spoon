extends "res://scripts/plane.gd"
## Boeing C-17A Globemaster III w prawdziwej skali (52 m rozpiętości, 55 m długości). Model z paczki
## „C-17A Globemaster III” z pełną ładownią (fotele wzdłuż burt, podłoga z rolkami) i kabiną załogi.
## Po wnętrzu się chodzi — także w locie: ładownia przenosi stojących w niej żołnierzy razem
## z samolotem (player.gd: platform), burty i dach ich trzymają. Do kabiny prowadzą schody z przodu
## ładowni; [F] przy lewym fotelu — za sterami, [F] za sterami — wstajesz, samolot leci dalej
## na autopilocie (wyrównuje i krąży). Rampa z tyłu [R przy rampie albo G za sterami] — otwarta
## na ziemi wjeżdżają po niej pojazdy (w locie są przypięte do podłogi). Z rampy zrzuca bomby
## [Spacja], [B] — rodzaj (w tym MOAB i atomowa).

const DIR := "res://assets/vehicles/c17/"
const OFF := Vector3(0, 5.0, -6.0)            # model -> układ samolotu (spód kół na -GEAR_H)
const HOLD := AABB(Vector3(-2.85, -2.6, -26.2), Vector3(5.7, 5.4, 38.0))   # wnętrze (ładownia, kabina, rampa)
const FLOOR_Y := -2.4                          # podłoga ładowni
const DECK_Y := 0.15                           # podłoga kabiny załogi
const HINGE := Vector3(0, -2.4, 2.0)           # oś rampy
const RAMP_LEN := 9.2
const RAMP_UP := -0.16                         # zamknięta: lekko w górę [rad]
const RAMP_DOWN := 0.19                        # otwarta: koniec na ziemi
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
	GEAR_H = 4.1
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
	SEAT = Vector3(-0.75, DECK_Y, -24.6)
	EYE = Vector3(-0.75, DECK_Y + 1.2, -24.8)
	BOARD = SEAT
	BOARD_R = 1.3
	EXIT = Vector3(-0.2, DECK_Y, -23.4)
	CAM_DIST = 70.0
	CAM_UP = 15.0
	paint = Color(0.47, 0.5, 0.53)


func _ready() -> void:
	super._ready()
	add_to_group("walkable")
	for at: Vector3 in [Vector3(2.3, FLOOR_Y, 0.8), Vector3(3.9, -GEAR_H, 3.0)]:
		var sw := preload("res://scripts/c17_ramp.gd").new()
		sw.plane = self
		sw.position = at
		add_child(sw)
	set_meta("size", Vector3(52.0, 8.0, 55.0))
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
			["quilt", _tex_mat("quilt", Color(1, 1, 1), 0.9)], ["ext", grey], ["int", dark], ["glass", glass]]
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
		bm.size = Vector3(6.0, 6.0, 50.0)
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
		r.position = Vector3((i % 3 - 1) * 1.2, -1.2, 9.0 + (i / 3) * 0.6)
		add_child(r)
		_racks.append(r)


## Pusty kadłub z prostokątów: podłoga, burty, dach, blok pod kabiną, schody, skrzydła, usterzenie.
func _collision_boxes() -> Array:
	var cy := (FLOOR_Y + 2.45) * 0.5
	return [
		[Vector3(5.8, 1.7, 23.2), Vector3(0, -3.25, -9.6)],                 # podłoga ładowni (do ziemi)
		[Vector3(0.5, 5.2, 37.0), Vector3(-3.1, cy, -7.0)],                # burty
		[Vector3(0.5, 5.2, 37.0), Vector3(3.1, cy, -7.0)],
		[Vector3(6.7, 0.6, 37.0), Vector3(0, 2.75, -7.0)],                 # dach
		[Vector3(5.8, 4.25, 5.2), Vector3(0, (-4.1 + DECK_Y) * 0.5, -23.6)],   # pod kabiną
		[Vector3(5.8, 0.4, 3.0), Vector3(0, 2.55, -24.5)],                 # dach kabiny
		[Vector3(5.8, 3.0, 0.5), Vector3(0, DECK_Y + 1.5, -26.6)],         # przód kabiny
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
	var run := 3.6
	sb.size = Vector3(1.3, 0.25, sqrt(rise * rise + run * run))
	st.shape = sb
	st.position = Vector3(1.6, (FLOOR_Y + DECK_Y) * 0.5 - 0.1, -21.0 + run * 0.5)
	st.rotation.x = atan2(rise, run)      # wyżej z przodu (kabina), niżej od strony ładowni
	add_child(st)
	# rampa (obraca się razem z modelem)
	_ramp_body = AnimatableBody3D.new()
	_ramp_body.sync_to_physics = false
	_ramp_body.collision_layer = LAYER
	_ramp_body.collision_mask = 0
	_ramp_body.set_meta("mat", "metal")
	add_child(_ramp_body)
	_ramp_col = CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(5.6, 0.3, RAMP_LEN)
	_ramp_col.shape = rb
	_ramp_body.add_child(_ramp_col)
	add_collision_exception_with(_ramp_body)
	_set_ramp(_ramp_a)


func _set_ramp(a: float) -> void:
	_ramp_a = a
	if _ramp:
		_ramp.rotation.x = a
	if _ramp_col:
		var b := Basis(Vector3.RIGHT, a)
		_ramp_col.transform = Transform3D(b, HINGE + b * Vector3(0, -0.15, RAMP_LEN * 0.5))
	if _door:
		var k := inverse_lerp(RAMP_UP, RAMP_DOWN, a)
		_door.position = Vector3(0, 2.6 * k, 1.5 * k)


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
		if Vector2(global_position.x, global_position.z).length() > 900.0:
			_aim_yaw = lerp_angle(_aim_yaw, to_c, 0.6 * dt)
		else:
			_aim_yaw += 0.15 * dt
		throttle = move_toward(throttle, 0.6, dt * 0.2)
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


