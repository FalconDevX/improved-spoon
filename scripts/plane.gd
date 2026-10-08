extends CharacterBody3D
## Samolot myśliwski (śmigłowy dolnopłat z podwoziem trójkołowym). Wsiadanie [F] na ziemi,
## start, lot i strzelanie z czterech karabinów maszynowych 12,7 mm w skrzydłach (zbieżność ognia
## przed nosem). Lot: siła nośna zależna od kąta natarcia (przeciągnięcie), opór szkodliwy
## i indukowany, ciąg śmigła, stateczność kierunkowa. Sterowanie myszą: samolot leci tam, gdzie
## patrzysz (instruktor wychyla stery), albo ręcznie strzałkami / A-D. Trafienia niszczą płatowiec
## (dym, ogień, utrata ciągu); zderzenie lub zbyt twarde przyziemienie kończy się wybuchem.
## Wrak dymi, po chwili samolot wraca na lotnisko. Postój przy lotnisku uzupełnia amunicję.
## PvP: samolot symuluje komputer pilota, reszta odtwarza stan; obrażenia liczy strzelający.

const Player = preload("res://scripts/player.gd")
const Weapons = preload("res://scripts/weapons.gd")
const FX = preload("res://scripts/fx.gd")
const Ballistics = preload("res://scripts/ballistics.gd")
const Bomb = preload("res://scripts/bomb.gd")
const BotPilot = preload("res://scripts/bot_pilot.gd")
const Debris = preload("res://scripts/debris.gd")

const LAYER := 32
const GRAVITY := 9.81
var GEAR_H := 1.55                       # od osi kadłuba do spodu kół
var SEAT := Vector3(0, -0.42, 0.6)       # stopy pilota (pozycja gracza) w układzie samolotu
var EYE := Vector3(0, 0.66, 0.3)        # oczy pilota w kabinie
var THRUST := 13.0                       # m/s² przy pełnym gazie
const CD0 := 0.0019
const K_LIFT := 0.012
const K_IND := 0.0017
const K_SIDE := 0.02
const STALL_AOA := 0.28
var PITCH_RATE := 1.1
var ROLL_RATE := 2.3
var YAW_RATE := 0.4
const INERTIA := 3.2                       # jak szybko samolot osiąga zadaną prędkość obrotu [1/s]
const CTRL_RATE := 5.0                     # jak szybko wychylają się stery [1/s]
const AIM_SMOOTH := 4.0                    # wygładzenie punktu, za którym podąża instruktor [1/s]
const K_STAB := 1.6
const K_STAB_Y := 3.0
const GROUND_STEER := 0.9
const CRASH_VY := 9.0
var MAX_HP := 160.0
var AMMO := 1600                         # 4 × 400 naboi
var BOMBS := 12                          # 12 × 50 kg pod skrzydłami, zrzut całą serią (nalot dywanowy)
const BOMB_RELOAD := 8.0                   # bomby bez limitu: po serii pełne przeładowanie w powietrzu [s]
const BOMB_DT := 0.11                      # odstęp między bombami w serii
const GUN_DT := 0.02                       # odstęp między strzałami kolejnych karabinów (4 × 750/min)
const CONVERGE := 280.0
# (zmienne, nie stałe: inne samoloty — np. C-130 — nadpisują je w _init)
# lot zręcznościowy (jak War Thunder): prędkości i szybkość skrętu za celownikiem
var V_MIN := 40.0                          # poniżej nos opada (zamiast przeciągnięcia)
var V_MAX := 150.0                         # przy pełnym gazie w locie poziomym
var TURN_RATE := 1.3                       # maks. obrót nosa za celownikiem [rad/s]
var BOARD := Vector3.ZERO                  # punkt wsiadania (układ samolotu) i jego zasięg
var BOARD_R := 5.0
var EXIT := Vector3(-2.0, 0, 0.9)          # gdzie staje wysiadający
var CAM_DIST := 15.0                       # kamera za samolotem
var CAM_UP := 3.2
var GUNS := [Vector3(-2.1, -0.42, -2.2), Vector3(2.1, -0.42, -2.2), Vector3(-2.55, -0.4, -2.1), Vector3(2.55, -0.4, -2.1)]
const RESPAWN := 25.0
const BOUND := 1400.0
const MOUSE_SENS := 0.0019
const NET_RATE := 1.0 / 30.0
const FLARES := 4                          # salwy flar
const FLARE_RELOAD := 12.0                 # po zużyciu wszystkich: przeładowanie w powietrzu [s]
const FLARE_CD := 0.8
const Flare = preload("res://scripts/flare.gd")
const MODEL = preload("res://assets/vehicles/spitfire.glb")


class MG:
	var cal: Dictionary
	var data: Dictionary


var home: Transform3D
var paint := Color(0.33, 0.38, 0.25)
var pilot = null
var ai = null                  # bot-pilot (bot_pilot.gd)
var ai_aim := Vector3.INF      # bot: punkt z wyprzedzeniem, na który składa karabiny (±20° od osi)
var auth := 0                  # PvP: id komputera, który symuluje samolot (0 = nikt, stoi)
var hp := MAX_HP
var throttle := 0.0
var ammo := AMMO
var bombs := BOMBS
var bomb_reload := 0.0                     # postęp przeładowania bomb [s]
var bomb_kinds: Array = ["frag", "he", "napalm", "cluster"]   # rodzaje do wyboru [B] (C-130 ma też atomową)
var bomb_kind := "frag"
var _salvo := false
var _bomb_t := 0.0
var _bomb_k := 0
var _racks: Array = []          # modele bomb pod skrzydłami (kolejność zrzutu)
var destroyed := false
var on_ground := true
var stall := false
var trigger := false
var cockpit_view := true
var warn := ""
var flares := FLARES
var flare_reload := 0.0
var missile_warn := INF        # za ile sekund doleci rakieta naprowadzana (ustawia missile.gd)
var lock_warn := 0.0           # ktoś namierza (ustawia player.gd / net_locked)
var _flare_cd := 0.0
var _warn_beep := 0.0

var _w := Vector3.ZERO         # prędkość kątowa w układzie samolotu: x pochylenie (nos w górę +), y odchylenie (nos w prawo +), z przechylenie (w prawo +)
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _aim_s := Vector3.FORWARD   # wygładzony kierunek celowania (instruktor)
var _ctrl := Vector3.ZERO       # aktualne wychylenia sterów
var _bank_cmd := 0.0
var _cam_up := Vector3.UP
var _manual_t := 0.0
var _gun_t := 0.0
var _gun_k := 0
var _shot_n := 0
var _wreck_t := 0.0
var _mg := MG.new()
var _parts: Array = []
var _mats: Array = []
var _burnt: StandardMaterial3D
var _prop: Node3D
var _blades: Node3D
var _disc: MeshInstance3D
var _prop_a := 0.0
var _flashes: Array = []
var _flash_t := 0.0
var _cam: Camera3D
var _snd: AudioStreamPlayer3D
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _net_t := 0.0
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_vel := Vector3.ZERO
var _alarm_t := 0.0


func _ready() -> void:
	add_to_group("plane")
	add_to_group("aircraft")
	collision_layer = LAYER
	collision_mask = 1 | LAYER
	set_meta("mat", "metal")
	set_meta("hollow", 0.0015)               # cienkie poszycie: pociski przechodzą (i mogą trafić pilota)
	set_meta("size", Vector3(11.0, 1.5, 9.0))
	_mg.cal = Weapons.CAL["12.7x99"]
	_mg.data = {"v0": 870.0, "zero": CONVERGE, "cal": "12.7x99"}
	_build_model()
	_build_collision()
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = FX._cache["engine"]
	_snd.unit_size = 14.0
	_snd.max_distance = 900.0
	_snd.attenuation_filter_cutoff_hz = 6000.0
	add_child(_snd)
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.fov = 75.0
	_cam.near = 0.05
	_cam.far = 3500.0
	add_child(_cam)
	_smoke = _emitter(Color(0.2, 0.19, 0.18, 0.7), Color(0.35, 0.35, 0.35, 0.0), 2.5, 1.6, false)
	_fire = _emitter(Color(1.0, 0.75, 0.3, 1.0), Color(0.9, 0.2, 0.0, 0.0), 0.5, 0.9, true)
	home = global_transform
	if Player.net_on:
		var gd := _gd()
		for f in [net_plane, net_board, net_exit, net_damage, net_explode, net_bomb, net_flares, net_locked, net_board_bot, net_eject]:
			gd.expose_func(f)
	_reset()


## Kolizja kadłuba, skrzydeł i usterzenia (prostopadłościany: rozmiar, środek).
func _collision_boxes() -> Array:
	return [[Vector3(1.2, 1.45, 9.0), Vector3(0, 0, 1.0)], [Vector3(11.2, 0.35, 2.4), Vector3(0, -0.4, -1.0)],
		[Vector3(3.2, 0.2, 1.0), Vector3(0, 0.2, 5.2)]]


func _build_collision() -> void:
	for s in _collision_boxes():
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s[0]
		cs.shape = bs
		cs.position = s[1]
		add_child(cs)


func _gd() -> Node:
	return get_node("/root/GDSync")


func _my_id() -> int:
	return _gd().get_client_id() if Player.net_on else 0


func _sim_here() -> bool:
	return not Player.net_on or auth == _my_id()


func _local_pilot() -> bool:
	return pilot != null and is_instance_valid(pilot) and not pilot.is_remote and pilot.is_in_group("player")


## Maszyną steruje bot-pilot (liczony na tym komputerze).
func _ai_on() -> bool:
	return ai != null and pilot != null and is_instance_valid(pilot) and not pilot.down 		and pilot.is_in_group("npc") and not pilot.is_remote and _sim_here()


## Bot-pilot wsiada (host / solo); u gościa net_board_bot sadza kukiełkę.
func board_bot(npc) -> void:
	ai = BotPilot.new(self)
	_set_pilot(npc)
	if Player.net_on:
		auth = _my_id()
		_gd().call_func(net_board_bot, String(npc.name))


func net_board_bot(n: String) -> void:
	var p := get_parent().get_node_or_null(n)
	auth = _gd().get_sender_id()
	_net_pos = global_position
	_net_rot = global_basis.get_rotation_quaternion()
	if p and not p.down:
		_set_pilot(p)


func camera() -> Camera3D:
	return _cam


# ---------------------------------------------------------------- model

func _mat(c: Color, metal := 0.3, rough := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	_mats.append(m)
	return m


func _part(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = self, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	_parts.append(mi)
	return mi


func _build_model() -> void:
	var metal := _mat(Color(0.18, 0.18, 0.19), 0.8, 0.35)
	var black := _mat(Color(0.05, 0.05, 0.05), 0.2, 0.7)
	_burnt = StandardMaterial3D.new()
	_burnt.albedo_color = Color(0.06, 0.055, 0.05)
	_burnt.roughness = 0.95
	# Supermarine Spitfire (assets/vehicles/spitfire.glb): kadłub, skrzydła, ogon, osłona kabiny, śmigło
	var m: Node3D = MODEL.instantiate()
	var blades: MeshInstance3D
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		mi.get_parent().remove_child(mi)
		mi.owner = null
		if mi.name == "Prop":
			blades = mi
			continue
		add_child(mi)
		if mi.name != "Canopy":
			_parts.append(mi)
	m.free()
	# podwozie
	for g in [[Vector3(-0.95, -0.5, -1.35), 0.33], [Vector3(0.95, -0.5, -1.35), 0.33], [Vector3(0, -0.75, 5.2), 0.12]]:
		var top: Vector3 = g[0]
		var r: float = g[1]
		var leg := BoxMesh.new()
		leg.size = Vector3(0.08, GEAR_H + top.y - r, 0.1)
		_part(leg, top + Vector3(0, -leg.size.y * 0.5, 0), metal)
		var wh := CylinderMesh.new()
		wh.top_radius = r
		wh.bottom_radius = r
		wh.height = 0.16
		_part(wh, Vector3(top.x, -GEAR_H + r, top.z), black, self, Vector3(0, 0, PI * 0.5))
	# śmigło: łopaty (wolne obroty) albo przezroczysta tarcza (szybkie)
	_prop = Node3D.new()
	_prop.position = Vector3(0, 0.4, -3.3)
	add_child(_prop)
	_blades = Node3D.new()
	_prop.add_child(_blades)
	blades.transform = Transform3D.IDENTITY
	_blades.add_child(blades)
	_parts.append(blades)
	var dm := CylinderMesh.new()
	dm.top_radius = 1.65
	dm.bottom_radius = 1.65
	dm.height = 0.01
	dm.radial_segments = 32
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.18)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc = MeshInstance3D.new()
	_disc.mesh = dm
	_disc.material_override = disc_mat
	_disc.rotation.x = PI * 0.5
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop.add_child(_disc)
	# błyski z luf
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.75, 0.35)
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for g: Vector3 in GUNS:
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.5)
		var fl := MeshInstance3D.new()
		fl.mesh = q
		fl.material_override = fm
		fl.position = g + Vector3(0, 0, -0.6)
		fl.visible = false
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fl)
		_flashes.append(fl)
	# bomby na wyrzutnikach: na zmianę lewe / prawe skrzydło, od kadłuba na zewnątrz
	for k in BOMBS:
		var side := -1.0 if k % 2 == 0 else 1.0
		var slot := k / 2
		var bm := Bomb.make_mesh(self)
		bm.position = Vector3(side * (1.25 + (slot % 3) * 0.55), -0.78, -1.15 + (slot / 3) * 0.95)
		_racks.append(bm)


func _emitter(c0: Color, c1: Color, life: float, size: float, add: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.position = Vector3(0, 0.3, -3.2)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 60, 120))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 2.0
	m.gravity = Vector3(0, 1.2 if not add else 2.0, 0)
	m.damping_min = 0.5
	m.damping_max = 1.5
	m.scale_min = 0.6
	m.scale_max = 1.5
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = FX._cache["dot"]
	if add:
		mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = mm
	p.draw_pass_1 = q
	add_child(p)
	return p


# ---------------------------------------------------------------- wsiadanie / wysiadanie

func can_board(p) -> bool:
	if destroyed or hp <= 0.0 or pilot != null or not on_ground or velocity.length() > 3.0:
		return false
	return p.global_position.distance_to(global_position + global_basis * BOARD - Vector3(0, GEAR_H, 0)) < BOARD_R


func board(p) -> void:
	_set_pilot(p)
	if Player.net_on:
		auth = _my_id()
		_gd().call_func(net_board, p.net_id)
	var f := -global_basis.z
	_aim_yaw = atan2(-f.x, -f.z)
	_aim_pitch = 0.0
	_aim_s = f
	_ctrl = Vector3.ZERO
	_bank_cmd = 0.0
	cockpit_view = true
	_cam.current = true
	_place_camera(1.0)
	p._msg("Samolot: W/S — gaz, mysz — kierunek lotu, LPM — karabiny, F — wysiądź")


func _set_pilot(p) -> void:
	pilot = p
	trigger = false
	p.enter_vehicle(self)
	_seat_pilot()


## Pilot chce wysiąść (tylko na ziemi, prawie w miejscu).
func request_exit() -> void:
	if not on_ground or velocity.length() > 4.0:
		if not on_ground and global_position.y - GEAR_H > 15.0:
			eject()
		elif _local_pilot():
			pilot._msg("Za nisko na katapultę — wyląduj i zwolnij")
		return
	var p = pilot
	_unseat(true)
	if Player.net_on:
		_gd().call_func(net_exit)
	if p and is_instance_valid(p):
		p.camera().current = true


func _unseat(place: bool) -> void:
	if pilot == null:
		return
	var p = pilot
	pilot = null
	trigger = false
	if is_instance_valid(p) and p.vehicle == self:
		p.leave_vehicle(place)
	if _cam.current:
		_cam.current = false


## Miejsce obok kabiny, gdzie staje wysiadający pilot.
func exit_point() -> Vector3:
	var p := global_transform * EXIT
	p.y = global_position.y - GEAR_H
	return p


## Gracz-pilot padł (trafiony w kabinie): samolot leci dalej bez sterującego.
func pilot_gone(p) -> void:
	if pilot == p:
		pilot = null
		trigger = false


func _seat_pilot() -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	var p = pilot
	p.global_position = global_transform * SEAT
	p.velocity = velocity
	p.visual.global_basis = global_basis
	p.rig.crouch = 1.0
	p.rig.sprint = false
	p.rig.air = false
	p.rig.vel = Vector3.ZERO
	p.rig.aim_w = 0.0


# ---------------------------------------------------------------- wejście (pilot lokalny)

func pilot_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_aim_yaw -= e.relative.x * MOUSE_SENS * Settings.sens
		_aim_pitch = clampf(_aim_pitch - e.relative.y * MOUSE_SENS * Settings.sens, -1.45, 1.45)
		return
	if e.is_action_pressed("attack"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		trigger = true
	elif e.is_action_released("attack"):
		trigger = false
	elif e.is_action_pressed("jump"):
		if not on_ground:
			start_salvo()
	elif e.is_action_pressed("use"):
		request_exit()
	elif e.is_action_pressed("flares"):
		release_flares()
	elif e.is_action_pressed("fire_mode"):
		cycle_bomb()
	elif e.is_action_pressed("view_toggle"):
		cockpit_view = not cockpit_view
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func aim_dir() -> Vector3:
	return Basis.from_euler(Vector3(_aim_pitch, _aim_yaw, 0.0)) * Vector3.FORWARD


## Punkt zbieżności karabinów (HUD rysuje tam celownik).
func gun_point() -> Vector3:
	return global_position - global_basis.z * CONVERGE


# ---------------------------------------------------------------- pętla

func _physics_process(dt: float) -> void:
	if destroyed:
		_wreck_t += dt
		if _wreck_t >= RESPAWN:
			_reset()
		return
	if pilot != null and (not is_instance_valid(pilot) or pilot.down):
		pilot = null
	if _sim_here():
		if _ai_on():
			ai.tick(dt)
		_simulate(dt)
		if destroyed:
			return
		if Player.net_on and auth != 0:
			_net_t -= dt
			if _net_t <= 0.0:
				_net_t = NET_RATE
				_gd().call_func_unreliable(net_plane, global_position, global_basis.get_rotation_quaternion(), velocity, throttle, trigger, hp, bombs)
	else:
		_follow(dt)
	_guns(dt)
	if _sim_here():
		_bombing(dt)
	_countermeasures(dt)
	_seat_pilot()


# ---------------------------------------------------------------- flary, ostrzeżenia

## Salwa flar [C]: rakiety lecące na samolot, które są jeszcze dość daleko, idą za flarami.
func release_flares() -> void:
	if flares <= 0 or _flare_cd > 0.0 or destroyed:
		if flares <= 0 and _local_pilot():
			pilot._msg("Flary: przeładowanie %d s" % ceili(FLARE_RELOAD - flare_reload))
		return
	flares -= 1
	_flare_cd = FLARE_CD
	Flare.salvo(self)
	if Player.net_on:
		_gd().call_func(net_flares)


func _countermeasures(dt: float) -> void:
	_flare_cd = maxf(_flare_cd - dt, 0.0)
	if flares < FLARES:
		flare_reload += dt
		if flare_reload >= FLARE_RELOAD:
			flare_reload = 0.0
			flares = FLARES
	lock_warn = maxf(lock_warn - dt, 0.0)
	# missile_warn odświeża rakieta co klatkę; bez niej po chwili gaśnie
	missile_warn = missile_warn + dt if missile_warn < INF else INF
	if missile_warn > 30.0:
		missile_warn = INF
	if _local_pilot():
		_warn_beep -= dt
		var incoming := missile_warn < 15.0 and _missile_near()
		if _warn_beep <= 0.0 and (incoming or lock_warn > 0.0):
			_warn_beep = 0.12 if incoming else 0.45
			FX.I.play("click", _cam.global_position, 0.0 if incoming else -4.0, 0.0, 3.0 if incoming else 1.8, 4.0)


## Czy jakaś rakieta wciąż leci na ten samolot (nie na flarę).
func _missile_near() -> bool:
	for m in get_tree().get_nodes_in_group("missile"):
		if m.target == self:
			return true
	return false


func net_flares() -> void:
	flares = maxi(flares - 1, 0)
	Flare.salvo(self)


func net_locked() -> void:
	lock_warn = 0.5


func _simulate(dt: float) -> void:
	var b := global_basis.orthonormalized()
	var fwd := -b.z
	var up := b.y
	var right := b.x
	var v := velocity.length()
	var lv := b.inverse() * velocity
	var aoa := atan2(-lv.y, -lv.z) if v > 2.0 else 0.0
	var beta := atan2(lv.x, -lv.z) if v > 2.0 else 0.0
	var cl := _cl(aoa)
	stall = not on_ground and absf(aoa) > STALL_AOA and v > 5.0
	var ctrl := _controls(b, aoa, dt)
	var local := _local_pilot()
	if local and not Player.chat_open:
		throttle = clampf(throttle + Input.get_axis("move_back", "move_forward") * 0.6 * dt, 0.0, 1.0)
	elif _ai_on():
		throttle = move_toward(throttle, ai.throttle, 0.6 * dt)
	elif pilot == null and not on_ground:
		throttle = maxf(throttle - 0.15 * dt, 0.0)   # bez pilota: silnik dławi się, samolot szybuje w dół
	if not on_ground and hp > 0.0 and (_local_pilot() or _ai_on()):
		_arcade(dt)
	else:
		# siły (przyspieszenia)
		var eng := 0.0 if hp <= 0.0 else (0.6 if hp < MAX_HP * 0.25 else 1.0)
		eng *= clampf((1400.0 - global_position.y) / 700.0, 0.0, 1.0)
		var acc := Vector3(0, -GRAVITY, 0) + fwd * throttle * THRUST * eng
		if v > 0.5:
			var vd := velocity / v
			acc += right.cross(vd).normalized() * K_LIFT * cl * v * v
			acc -= vd * (CD0 + K_IND * cl * cl) * v * v
			acc -= right * lv.x * v * K_SIDE
		velocity += acc * dt
		# obrót: stery (skuteczność rośnie z prędkością) + stateczność (nos ustawia się do opływu)
		var ak := clampf(v / 40.0, 0.0, 1.25)
		var sk := clampf(v / 30.0, 0.0, 1.5)
		var tw := Vector3(ctrl.x * PITCH_RATE * ak - aoa * K_STAB * sk,
			ctrl.y * YAW_RATE * ak + beta * K_STAB_Y * sk,
			ctrl.z * ROLL_RATE * ak)
		if hp <= 0.0 and not on_ground:
			tw += Vector3(-0.15, 0.1, 0.9) * sk     # płonący samolot wpada w spiralę
		_w = _w.lerp(tw, 1.0 - exp(-INERTIA * dt))
		b = b * Basis(Vector3.RIGHT, _w.x * dt) * Basis(Vector3.UP, -_w.y * dt) * Basis(Vector3.FORWARD, _w.z * dt)
		global_basis = b.orthonormalized()
	var col := move_and_collide(velocity * dt)
	if col and _hit_obstacle(col):
		return
	_ground(dt, ctrl)
	_boundary()
	# postój przy lotnisku: dozbrojenie i naprawa
	if on_ground and velocity.length() < 2.0 and global_position.distance_to(home.origin) < 45.0:
		ammo = mini(ammo + int(ceil(300.0 * dt)), AMMO)
		if bombs < bomb_max() and not _salvo:
			_bomb_t -= dt
			if _bomb_t <= 0.0:
				_bomb_t = 0.4      # podwieszanie bomb jedna po drugiej
				bombs += 1
				_show_racks()
		if hp > 0.0:
			hp = minf(hp + 8.0 * dt, MAX_HP)


## Lot zręcznościowy: nos podąża za celownikiem (ograniczona szybkość skrętu), prędkość z gazu
## (wznoszenie ją zjada, nurkowanie dodaje), automatyczne przechylenie w zakręcie, brak przeciągnięcia.
func _arcade(dt: float) -> void:
	stall = false
	_w = Vector3.ZERO
	var fwd := -global_basis.z
	var spd := velocity.length()
	var eng := 0.6 if hp < MAX_HP * 0.25 else 1.0
	var target := V_MIN + (V_MAX - V_MIN) * throttle * eng
	spd = move_toward(spd, target, THRUST * 0.45 * dt)
	spd = maxf(spd - fwd.y * GRAVITY * 0.55 * dt, 18.0)
	if _local_pilot() and not Player.chat_open:
		_aim_yaw -= Input.get_axis("move_left", "move_right") * 0.7 * dt   # A/D — lekki skręt
	_aim_s = _aim_s.slerp(aim_dir(), 1.0 - exp(-AIM_SMOOTH * 1.5 * dt)).normalized()
	var want := _aim_s
	if spd < V_MIN * 0.85:
		want = (want + Vector3.DOWN * clampf((V_MIN * 0.85 - spd) / 10.0, 0.0, 1.0)).normalized()
	var rate := TURN_RATE * clampf(spd / V_MIN, 0.4, 1.0)
	# kurs i pochylenie osobno: zawracanie to zakręt w poziomie, nie pętla
	var cy := atan2(-fwd.x, -fwd.z)
	var cp := asin(clampf(fwd.y, -1.0, 1.0))
	var ty := atan2(-want.x, -want.z)
	var tp := asin(clampf(want.y, -1.0, 1.0))
	var dyaw := clampf(wrapf(ty - cy, -PI, PI), -rate * dt, rate * dt)
	var np := clampf(cp + clampf(tp - cp, -rate * 0.8 * dt, rate * 0.8 * dt), -1.3, 1.3)
	var nf := Basis.from_euler(Vector3(np, cy + dyaw, 0.0)) * Vector3.FORWARD
	# przechylenie jak w zakręcie skoordynowanym: tg(φ) = v·ω / g (w prawo +)
	var turn := -dyaw / maxf(dt, 0.0001)
	var bank_t := clampf(atan(spd * turn / GRAVITY), -1.3, 1.3)
	_bank_cmd = lerpf(_bank_cmd, bank_t, 1.0 - exp(-3.5 * dt))
	var ref := Basis.looking_at(nf, Vector3.UP if absf(nf.y) < 0.98 else -fwd)
	var up := ref.y * cos(_bank_cmd) + ref.x * sin(_bank_cmd)
	var z := -nf
	global_basis = Basis(up.cross(z).normalized(), up.normalized(), z).orthonormalized()
	velocity = nf * spd


func _cl(a: float) -> float:
	var x := absf(a)
	var c := 5.0 * x if x < STALL_AOA else maxf(1.4 - (x - STALL_AOA) * 3.0, 0.45)
	return 0.1 + c * signf(a)


## Wychylenia sterów [-1..1]: x — wysokości, y — kierunku, z — lotki.
func _controls(b: Basis, aoa: float, dt: float) -> Vector3:
	if not (_local_pilot() or _ai_on()) or hp <= 0.0:
		if pilot != null and is_instance_valid(pilot) and pilot.is_remote:
			return Vector3.ZERO
		return Vector3(0.0, 0.0, -atan2(b.x.y, b.y.y) * 0.5 if not on_ground else 0.0)
	var man := Vector3.ZERO
	if _local_pilot() and not Player.chat_open:
		man = Vector3(Input.get_axis("stick_up", "stick_down"), Input.get_axis("move_left", "move_right"),
			Input.get_axis("stick_left", "stick_right"))
	var right := b.x
	var up := b.y
	var fwd := -b.z
	_aim_s = _aim_s.slerp(aim_dir(), 1.0 - exp(-AIM_SMOOTH * dt)).normalized()
	var aim := _aim_s
	var lt := b.inverse() * aim
	var beta := atan2((b.inverse() * velocity).x, -(b.inverse() * velocity).z) if velocity.length() > 2.0 else 0.0
	var p_err := atan2(lt.y, -lt.z) + aoa   # cel nad wektorem prędkości (+)
	var y_err := atan2(lt.x, -lt.z) - beta  # cel na prawo od toru lotu (+)
	# zakręt: przechylenie względem horyzontu zależne od różnicy kursu (maks. 75°), potem ściąganie drążka
	var head := Vector3(velocity.x, 0.0, velocity.z)
	if head.length() < 5.0:
		head = Vector3(fwd.x, 0.0, fwd.z)
	var ah := Vector3(aim.x, 0.0, aim.z)
	var dh := 0.0
	if ah.length() > 0.05 and head.length() > 0.05:
		dh = head.normalized().signed_angle_to(ah.normalized(), Vector3.DOWN) * clampf(ah.length() * 3.0, 0.0, 1.0)
	if absf(dh) > 2.6 and absf(_bank_cmd) > 0.1 and signf(dh) != signf(_bank_cmd):
		dh = -dh   # cel prawie za plecami: nie zmieniaj kierunku rozpoczętego zakrętu
	var bank := atan2(-right.y, up.y)     # przechylenie w prawo (+)
	var gamma := asin(clampf(velocity.y / maxf(velocity.length(), 1.0), -1.0, 1.0))
	var ve := asin(clampf(aim.y, -1.0, 1.0)) - gamma      # tor lotu poniżej celu (+)
	# zakręt: przechylenie (gdy tor ucieka w górę — mocniejsze), a ściąganie drążka zależne od różnicy kursu
	var bank_t := clampf(dh * 2.2, -1.25, 1.25) - clampf(ve * 2.0, -0.2, 0.2) * signf(dh) * clampf(absf(dh) / 0.3, 0.0, 1.0)
	_bank_cmd = lerpf(_bank_cmd, bank_t, 1.0 - exp(-3.0 * dt))
	var roll_err := wrapf(_bank_cmd - bank, -PI, PI)
	var c_aim := p_err * 3.0
	if c_aim > 0.0:
		c_aim *= clampf(1.0 - absf(roll_err) / 1.4, 0.25, 1.0)
	var c_turn := clampf(absf(dh) * 1.2, 0.0, 0.85) * clampf(1.0 - absf(roll_err) / 0.6, 0.0, 1.0) + clampf(ve * 2.0, -0.5, 0.5) * cos(bank)
	var tw_k := clampf((absf(dh) - 0.15) / 0.35, 0.0, 1.0)
	if lt.z > 0.0:
		tw_k = 1.0
	var c := Vector3(clampf(lerpf(c_aim, c_turn, tw_k) - _w.x * 0.9, -1.0, 1.0), clampf(clampf(y_err, -0.25, 0.25) * 2.0 * (1.0 - tw_k) - clampf(ve * 3.0, -0.6, 0.6) * sin(bank) * tw_k - _w.y * 0.6, -1.0, 1.0),
		clampf(roll_err * 1.5 - _w.z * 0.65, -1.0, 1.0))
	# instruktor nie dopuszcza do przeciągnięcia
	if not on_ground and c.x > 0.0 and aoa > 0.18:
		c.x *= clampf((STALL_AOA - aoa) / 0.1, 0.0, 1.0)
	if absf(man.x) > 0.01:
		c.x = man.x
	if absf(man.y) > 0.01:
		c.y = man.y
	if absf(man.z) > 0.01:
		c.z = man.z
	if absf(man.x) + absf(man.z) > 0.01:
		_manual_t = 0.6
	_manual_t -= dt
	if _manual_t > 0.0:
		# sterowanie ręczne: wzrok podąża za nosem, żeby instruktor nie ściągał samolotu z powrotem
		var f := -b.z
		_aim_yaw = atan2(-f.x, -f.z)
		_aim_pitch = asin(clampf(f.y, -1.0, 1.0))
		_aim_s = f
	if on_ground:
		c.z = 0.0
	# stery nie skaczą: wychylają się płynnie
	_ctrl = _ctrl.lerp(c, 1.0 - exp(-CTRL_RATE * dt))
	return _ctrl


## Podwozie: toczenie, hamulce, skręt kółkiem przednim, twarde przyziemienie.
func _ground(dt: float, ctrl: Vector3) -> void:
	var gy := _ground_y()
	var b := global_basis
	var fwd := -b.z
	if global_position.y - GEAR_H > gy + 0.03 or (on_ground and velocity.y > 0.05):
		on_ground = false
		return
	var v := velocity.length()
	if not on_ground:
		var bad := b.y.y < 0.8 or fwd.y < -0.3
		if velocity.y < -CRASH_VY or (bad and v > 8.0):
			_crash()
			return
		if velocity.y < -4.5:
			_damage((-velocity.y - 4.5) * 22.0)
			FX.I.play("thud", global_position, 4.0, 0.1, 0.7)
		elif velocity.y < -1.0:
			FX.I.play("thud", global_position, -6.0, 0.1, 0.8)
	on_ground = true
	global_position.y = gy + GEAR_H
	velocity.y = maxf(velocity.y, 0.0)
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.05:
		_crash()
		return
	flat = flat.normalized()
	var vf := velocity.dot(flat)
	var side := velocity - flat * vf
	side.y = 0.0
	var brake := _local_pilot() and not Player.chat_open and Input.is_action_pressed("jump")
	vf = move_toward(vf, 0.0, (0.3 + (6.0 if brake else 0.0) + (0.6 if pilot == null else 0.0)) * dt)
	side = side.move_toward(Vector3.ZERO, 18.0 * dt)
	velocity = flat * vf + side + Vector3(0, velocity.y, 0)
	var yaw := atan2(-fwd.x, -fwd.z) - ctrl.y * GROUND_STEER * clampf(absf(vf) / 3.0, 0.0, 1.0) * signf(vf) * dt
	var pitch := clampf(asin(clampf(fwd.y, -1.0, 1.0)), 0.0, 0.17)   # dalej ogon zawadziłby o ziemię
	global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))
	_w.z = 0.0
	if pitch <= 0.0:
		_w.x = maxf(_w.x, 0.0)


func _ground_y() -> float:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position - Vector3(0, GEAR_H + 4.0, 0), 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return (r["position"] as Vector3).y if not r.is_empty() else -1000.0


func _hit_obstacle(col: KinematicCollision3D) -> bool:
	var n := col.get_normal()
	var imp := -velocity.dot(n)
	if imp > 11.0:
		_crash()
		return true
	if imp > 3.0:
		_damage(imp * 6.0)
		FX.I.play("impact_metal", col.get_position(), 2.0, 0.2, 0.6)
	velocity = velocity.slide(n) * 0.85
	return false


## Poza strefą walki instruktor zawraca samolot w stronę mapy.
func _boundary() -> void:
	var p := global_position
	var r := maxf(absf(p.x), absf(p.z))
	warn = ""
	if r > BOUND - 60.0:
		warn = "GRANICA STREFY — ZAWRÓĆ"
	if r > BOUND and _local_pilot():
		warn = "AUTOPILOT: POWRÓT NAD MAPĘ"
		var to_c := atan2(p.x, p.z)
		_aim_yaw = lerp_angle(_aim_yaw, to_c, 0.04)
		_aim_pitch = lerpf(_aim_pitch, 0.05, 0.04)
		_manual_t = 0.0


# ---------------------------------------------------------------- karabiny

## Zrzut całej serii bomb (nalot dywanowy).
func start_salvo() -> void:
	if bombs <= 0 or _salvo or destroyed or hp <= 0.0:
		return
	_salvo = true
	_bomb_t = 0.0
	if _local_pilot():
		pilot._msg("Zrzut: %d × %s" % [bombs, bomb_name()])


func _bombing(dt: float) -> void:
	# bomby bez limitu: gdy nie ma serii, cały komplet podwiesza się w BOMB_RELOAD sekund
	if not _salvo and bombs < bomb_max() and not destroyed:
		bomb_reload += dt
		if bomb_reload >= bomb_reload_time():
			bomb_reload = 0.0
			bombs = bomb_max()
			_show_racks()
	else:
		bomb_reload = 0.0
	if not _salvo:
		return
	_bomb_t -= dt
	while _salvo and _bomb_t <= 0.0:
		_bomb_t += BOMB_DT
		if bombs <= 0 or on_ground:
			_salvo = false
			_bomb_t = 1.0
			return
		var i := clampi(BOMBS - bombs, 0, _racks.size() - 1)
		var pos: Vector3 = (_racks[i] as Node3D).global_position
		var v := velocity + Vector3.DOWN * 1.5
		bombs -= 1
		_show_racks()
		_drop(pos, v, bomb_kind)
		if Player.net_on:
			_gd().call_func(net_bomb, pos, v, bomb_kind)
		if bombs <= 0:
			_salvo = false
			_bomb_t = 1.0


func _drop(pos: Vector3, v: Vector3, kind := "frag") -> void:
	var b := Bomb.new()
	b.kind = kind
	b.vel = v
	b.shooter = pilot
	b.plane = self
	get_parent().add_child(b)
	b.global_position = pos
	b.global_basis = global_basis
	FX.I.play("click", pos, -2.0, 0.1, 0.5, 10.0)


## Ile bomb wybranego rodzaju mieści jedna seria.
func bomb_max() -> int:
	return Bomb.salvo_size(bomb_kind, BOMBS)


func bomb_reload_time() -> float:
	return float(Bomb.KINDS[bomb_kind]["reload"])


func bomb_name() -> String:
	return Bomb.KINDS[bomb_kind]["name"]


## [B]: następny rodzaj bomb. Wyrzutniki trzeba przezbroić (krótko; atomowa dłużej).
func cycle_bomb() -> void:
	if _salvo:
		return
	var i := bomb_kinds.find(bomb_kind)
	bomb_kind = bomb_kinds[(i + 1) % bomb_kinds.size()]
	bombs = 0
	bomb_reload = maxf(bomb_reload_time() - (20.0 if bomb_kind == "nuke" else 5.0), 0.0)
	_show_racks()
	if _local_pilot():
		pilot._msg("Bomby: %s — podwieszanie..." % bomb_name())


func _show_racks() -> void:
	for k in _racks.size():
		(_racks[k] as Node3D).visible = k >= BOMBS - bombs


## Przewidywany punkt upadku bomby (celownik bombowy w HUD).
func bomb_impact() -> Vector3:
	var p := global_position + Vector3.DOWN * 0.8
	var v := velocity + Vector3.DOWN * 1.5
	var dt := 0.05
	for i in 600:
		v += Vector3(0, -Bomb.GRAVITY, 0) * dt
		v -= v * v.length() * Bomb.DRAG * dt
		var np := p + v * dt
		if np.y <= 0.0:
			var k := p.y / maxf(p.y - np.y, 0.0001)
			return p.lerp(np, k)
		p = np
	return p


func _guns(dt: float) -> void:
	_flash_t -= dt
	if _flash_t <= 0.0:
		for f: Node3D in _flashes:
			f.visible = false
	var can: bool = trigger and pilot != null and is_instance_valid(pilot) and not pilot.down and hp > 0.0 and not GUNS.is_empty()
	if _local_pilot() or not Player.net_on:
		can = can and ammo > 0
	if not can:
		_gun_t = maxf(_gun_t - dt, 0.0)
		return
	_gun_t -= dt
	var guard := 0
	while _gun_t <= 0.0 and guard < 4:
		guard += 1
		_gun_t += GUN_DT
		_fire_gun(_gun_k)
		_gun_k = (_gun_k + 1) % GUNS.size()


func _fire_gun(i: int) -> void:
	var m := global_transform * (GUNS[i] as Vector3) + (-global_basis.z) * 0.45
	var d := (gun_point() - m).normalized()
	if ai_aim != Vector3.INF and _ai_on():
		var to := (ai_aim - m).normalized()
		if (-global_basis.z).angle_to(to) < 0.45:
			d = to
	d = _jitter(d, 0.0018 if ai_aim == Vector3.INF else 0.0035)
	_shot_n += 1
	if _local_pilot() or not Player.net_on:
		ammo -= 1
	Ballistics.I.fire(pilot, _mg, m, d, _shot_n % 3 == 0, velocity, [get_rid()])
	var fl: MeshInstance3D = _flashes[i]
	fl.visible = true
	fl.scale = Vector3.ONE * randf_range(0.7, 1.3)
	_flash_t = 0.035
	if i % 2 == 0:
		FX.I.play("shot_50", m, 3.0, 0.06, 1.0, 30.0)
	if _shot_n % 8 == 0:
		FX.I.muzzle_smoke(m, -global_basis.z, 0.6)
		for s in get_tree().get_nodes_in_group("soldier"):
			if s != pilot and s.has_method("heard_shot"):
				s.heard_shot(global_position, pilot)


func _jitter(d: Vector3, sigma: float) -> Vector3:
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var x := d.cross(up).normalized()
	var y := x.cross(d).normalized()
	return (d + x * randfn(0.0, sigma) + y * randfn(0.0, sigma)).normalized()


# ---------------------------------------------------------------- uszkodzenia

## Pocisk przebił poszycie (wołane z balistyki).
func bullet_struck(shooter, energy: float, _at: Vector3) -> void:
	if destroyed:
		return
	if shooter != null and is_instance_valid(shooter) and shooter.get("is_remote") == true:
		return   # kula odtworzona z cudzego strzału: obrażenia przyśle strzelający
	var was := hp
	_damage(clampf(sqrt(energy) / 6.0, 0.5, 30.0))
	if shooter != null and is_instance_valid(shooter) and shooter.has_method("confirm_hit") and shooter != pilot:
		shooter.confirm_hit(self, was > 0.0 and hp <= 0.0)   # znacznik trafienia, zestrzelenie w kronice


func _damage(d: float) -> void:
	_apply_damage(d)
	if Player.net_on:
		_gd().call_func(net_damage, d)


func _apply_damage(d: float) -> void:
	if destroyed:
		return
	var was := hp
	hp = minf(hp - d, MAX_HP)   # ujemne d = naprawa (gracz z kluczem, [R])
	if not on_ground and d > 0.0 and (hp <= -MAX_HP * 0.8 or d >= MAX_HP * 1.3):   # rozpad tylko przy trafieniu niemal bezpośrednim; zwykle pożar i czas na skok
		_break_apart()
		return
	if hp <= 0.0 and was > 0.0:
		if _local_pilot():
			pilot._msg("SAMOLOT W OGNIU!")
		if on_ground and velocity.length() < 3.0:
			_explode(global_position)


func _crash() -> void:
	var p := global_position
	_explode(p)
	if Player.net_on:
		_gd().call_func(net_explode, p)


func _explode(pos: Vector3) -> void:
	if destroyed:
		return
	destroyed = true
	hp = 0.0
	trigger = false
	FX.I.explosion(pos + Vector3(0, 0.5, 0), 1.6)
	var p = pilot
	_unseat(false)
	if p != null and is_instance_valid(p) and not p.is_remote and not p.down:
		p.vehicle_death()
	# żołnierze tuż obok giną w wybuchu (każdy komputer liczy swoich)
	for s in get_tree().get_nodes_in_group("soldier"):
		if s.down or s.get("is_remote") == true:
			continue
		var d: float = s.global_position.distance_to(pos)
		if d < 7.0:
			s.vitals._die()
			s._collapse((s.global_position - pos).normalized(), s.chest_pos(), "torso", 4000.0, true)
	# wrak na ziemi
	var f := -global_basis.z
	global_basis = Basis.from_euler(Vector3(randf_range(-0.1, 0.1), atan2(-f.x, -f.z), randf_range(-0.35, 0.35)))
	var gy := _ground_y()
	global_position.y = (gy if gy > -999.0 else 0.0) + 0.75
	velocity = Vector3.ZERO
	throttle = 0.0
	for mi: MeshInstance3D in _parts:
		mi.material_override = _burnt
	_disc.visible = false
	for r: Node3D in _racks:
		r.visible = false
	_salvo = false
	_fire.emitting = true
	_smoke.emitting = true
	_snd.stop()
	_wreck_t = 0.0
	if _cam.current:
		_cam.current = false


func _reset() -> void:
	destroyed = false
	visible = true
	collision_layer = LAYER
	global_transform = home
	velocity = Vector3.ZERO
	_w = Vector3.ZERO
	hp = MAX_HP
	ammo = AMMO
	bombs = BOMBS
	flares = FLARES
	flare_reload = 0.0
	_salvo = false
	_show_racks()
	throttle = 0.0
	on_ground = true
	auth = 0
	trigger = false
	for mi: MeshInstance3D in _parts:
		mi.material_override = _part_mat(mi)
	_disc.visible = true
	_fire.emitting = false
	_smoke.emitting = false
	_net_pos = global_position
	_net_rot = global_basis.get_rotation_quaternion()
	_net_vel = Vector3.ZERO


func _part_mat(mi: MeshInstance3D) -> Material:
	if not mi.has_meta("mat0"):
		mi.set_meta("mat0", mi.material_override)
	return mi.get_meta("mat0")


# ---------------------------------------------------------------- obraz, dźwięk

func _process(dt: float) -> void:
	var rd := minf(dt, 0.1)
	if destroyed:
		return
	var rpm := 0.0 if hp <= 0.0 else throttle * 0.8 + clampf(velocity.length() / 90.0, 0.0, 0.4)
	if pilot == null and on_ground and throttle < 0.01:
		rpm = 0.0
	_prop_a += rd * (rpm * 60.0)
	_prop.rotation.z = _prop_a
	_blades.visible = rpm < 0.35
	_disc.visible = rpm > 0.2
	if rpm > 0.01:
		if not _snd.playing:
			_snd.play()
		_snd.pitch_scale = 0.55 + rpm * 0.9
		_snd.volume_db = linear_to_db(clampf(0.25 + rpm, 0.0, 1.0)) + 4.0
	elif _snd.playing:
		_snd.stop()
	_smoke.emitting = hp < MAX_HP * 0.5
	_fire.emitting = hp < MAX_HP * 0.25
	if _local_pilot():
		_place_camera(rd)
		if stall:
			_alarm_t -= rd
			if _alarm_t <= 0.0:
				_alarm_t = 0.35
				FX.I.play("click", _cam.global_position, -2.0, 0.0, 0.5, 4.0)


func _place_camera(rd: float) -> void:
	var aim := aim_dir()
	var spd := velocity.length()
	if cockpit_view:
		var eye := global_transform * EYE
		# horyzont przechyla się z samolotem, ale łagodnie (bez drgań)
		_cam_up = _cam_up.lerp(global_basis.y.lerp(Vector3.UP, 0.35), 1.0 - exp(-4.0 * rd)).normalized()
		var up := _cam_up
		if absf(aim.dot(up)) > 0.97:
			up = -global_basis.z
		_cam.global_transform = Transform3D(Basis.looking_at(aim, up), eye)
		_cam.cull_mask = 0xFFFFF & ~Player.OWN_LAYER
		_cam.fov = lerpf(_cam.fov, Settings.fov + 2.0 + clampf(spd / 80.0, 0.0, 1.0) * 6.0, 1.0 - exp(-2.0 * rd))
	else:
		# kamera za samolotem: kierunek od razu za myszą, pozycja płynnie dogania
		var tgt := global_position - aim * CAM_DIST + Vector3.UP * CAM_UP
		var k := 1.0 - exp(-7.0 * rd)
		if _cam.global_position.distance_to(tgt) > 40.0:
			_cam.global_position = tgt
		else:
			_cam.global_position = _cam.global_position.lerp(tgt, k)
		_cam.global_basis = Basis.looking_at(global_position + aim * 60.0 - _cam.global_position, Vector3.UP)
		_cam.cull_mask = 0xFFFFF
		_cam.fov = lerpf(_cam.fov, Settings.fov - 2.0 + clampf(spd / 80.0, 0.0, 1.0) * 8.0, 1.0 - exp(-2.0 * rd))


# ---------------------------------------------------------------- sieć (PvP, GD-Sync)

func _follow(dt: float) -> void:
	if auth == 0:
		return
	_net_pos += _net_vel * dt
	if global_position.distance_to(_net_pos) > 20.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-12.0 * dt))
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(_net_rot, 1.0 - exp(-14.0 * dt)))
	velocity = _net_vel
	on_ground = global_position.y - GEAR_H <= _ground_y() + 0.1


## (zdalnie) stan samolotu z komputera pilota.
func net_plane(p: Vector3, rot: Quaternion, v: Vector3, thr: float, trig: bool, h: float, nb: int) -> void:
	if destroyed:
		return
	auth = _gd().get_sender_id()
	_net_pos = p
	_net_rot = rot
	_net_vel = v
	throttle = thr
	trigger = trig and pilot != null
	if h > 0.0:
		hp = h
	if nb != bombs:
		bombs = nb
		_show_racks()


## (zdalnie) przeciwnik wsiadł.
func net_board(id: int) -> void:
	var p := get_parent().get_node_or_null("P%d" % id)
	auth = _gd().get_sender_id()
	_net_pos = global_position
	_net_rot = global_basis.get_rotation_quaternion()
	if p and not p.down:
		_set_pilot(p)


## (zdalnie) przeciwnik wysiadł.
func net_exit() -> void:
	_unseat(true)


func net_damage(d: float) -> void:
	_apply_damage(d)


func net_explode(pos: Vector3) -> void:
	global_position = pos
	_explode(pos)


## (zdalnie) przeciwnik zrzucił bombę — ta sama bomba spada u mnie (wybuch, odłamki, fala).
func net_bomb(pos: Vector3, v: Vector3, kind := "frag") -> void:
	bombs = maxi(bombs - 1, 0)
	_show_racks()
	_drop(pos, v, kind)


# ---------------------------------------------------------------- katapulta, rozpad w powietrzu

## Pilot opuszcza maszynę w locie (F albo bot przy pożarze): leci dalej sam, z prędkością maszyny.
func eject() -> void:
	var p = pilot
	if p == null or not is_instance_valid(p):
		return
	_unseat(false)
	if Player.net_on and (_local_pilot() or (p.is_in_group("npc") and not p.is_remote)):
		_gd().call_func(net_eject)
	p.start_freefall(global_position + global_basis.y * 2.5 + Vector3.UP, velocity + global_basis.y * 9.0)


func net_eject() -> void:
	var p = pilot
	_unseat(false)
	if p != null and is_instance_valid(p) and p.has_method("start_freefall") and p.is_in_group("npc"):
		p.para = 2      # kukiełka bota: czasza (ruch przychodzi z paczek hosta)


## Bardzo duże obrażenia w locie: maszyna rozpada się na płonące części, pilot ginie.
func _break_apart() -> void:
	var pos := global_position
	var vel := velocity
	FX.I.explosion(pos, 2.2)
	var parts: Array = _parts.duplicate()
	parts.shuffle()
	var n := 0
	for mi: MeshInstance3D in parts:
		if n >= 7 or mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		if aabb.size.length() < 0.8:
			continue
		n += 1
		var d := Debris.new()
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = _burnt
		copy.scale = mi.global_basis.get_scale()
		d.add_child(copy)
		get_parent().add_child(d)
		d.global_transform = Transform3D(mi.global_basis.orthonormalized(), mi.global_position)
		d.setup(copy)
		d.linear_velocity = vel * 0.8 + Vector3(randf_range(-1, 1), randf_range(0, 1.2), randf_range(-1, 1)) * 14.0
		d.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 4.0
	_explode(pos)
	visible = false
	collision_layer = 0
