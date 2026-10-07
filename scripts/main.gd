extends Node3D
## Gra: mapa (wieś, kompleks, farma, sad), gracz-żołnierz. Solo: oddziały botów na posterunkach.
## PvP 1 na 1 przez GD-Sync (online z kluczami API albo w sieci lokalnej / na tym PC bez kluczy).

const Player = preload("res://scripts/player.gd")
const Npc = preload("res://scripts/npc.gd")
const Soldier = preload("res://scripts/soldier.gd")
const FX = preload("res://scripts/fx.gd")
const Ballistics = preload("res://scripts/ballistics.gd")
const Hud = preload("res://scripts/hud.gd")
const Level = preload("res://scripts/level.gd")

const MAX_NPC := 32
const RESPAWN_PVP := 5.0
const MAX_CORPSES := 6

var _level: Level
var _player: Node3D
var _hud
var _xray := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Engine.time_scale = 1.0
	_setup_input()
	_build_environment()
	var fx := FX.new()
	fx.name = "FX"
	add_child(fx)
	var bal := Ballistics.new()
	bal.name = "Ballistics"
	add_child(bal)
	_level = Level.new()
	_level.name = "Level"
	add_child(_level)
	_level.build()
	Npc.level = _level
	Npc.deaths = 0
	Player.net_on = false
	_rng.randomize()
	RenderingServer.global_shader_parameter_set("xray", 0.0)
	# uruchomienie z linii poleceń (testy): -- solo | -- host lan KOD | -- join lan KOD
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0] == "solo":
		_start_solo()
	elif args.size() >= 3 and args[0] in ["host", "join"]:
		_start_pvp(args[1] == "online", args[0] == "host", args[2])
	else:
		_show_menu()


func _process(_dt: float) -> void:
	if is_instance_valid(_player):
		var cam := get_viewport().get_camera_3d()
		_level.update_roofs(_player.global_position, cam.global_position if cam else _player.global_position)


func _physics_process(dt: float) -> void:
	if Player.net_on and _match_started and is_instance_valid(_player) and _player.down:
		_respawn_t += dt
		if _hud:
			_hud.respawn_in = RESPAWN_PVP - _respawn_t
		if _respawn_t >= RESPAWN_PVP:
			_respawn_local()


# ======================================================== solo

func _start_solo() -> void:
	_close_menu()
	var player := Player.new()
	player.name = "Player"
	player.position = _level.spawn_player
	player.rotation.y = 0.0  # na północ (-Z), w stronę wsi
	add_child(player)
	_player = player
	_make_hud(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _level.is_ready():
		_spawn_squads()
	else:
		_level.ready_nav.connect(_spawn_squads, CONNECT_ONE_SHOT)


## Oddziały 1-3 żołnierzy na posterunkach (nie przy starcie gracza).
func _spawn_squads() -> void:
	var n := 0
	for post: Vector3 in _level.posts:
		if post.distance_to(_level.spawn_player) < 45.0:
			continue
		for i in _rng.randi_range(1, 3):
			if n >= MAX_NPC:
				return
			var off := Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
			var p := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, post + off)
			var npc := Npc.new()
			npc.position = Vector3(p.x, 0.0, p.z)
			npc.rotation.y = _rng.randf_range(-PI, PI)
			add_child(npc)
			n += 1


# ======================================================== wspólne

func _make_hud(player: Node) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Hud.new()
	hud.player = player
	layer.add_child(hud)
	_hud = hud


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("xray"):
		_xray = not _xray
		RenderingServer.global_shader_parameter_set("xray", 1.0 if _xray else 0.0)
		if _hud:
			_hud.xray = _xray
		Soldier.xray = _xray  # pokazuje postać proceduralną z narządami zamiast modelu
		get_viewport().set_input_as_handled()


func _setup_input() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("run", KEY_SHIFT)
	_key("jump", KEY_SPACE)
	_key("crouch", KEY_CTRL)
	_key("reload", KEY_R)
	_key("fire_mode", KEY_B)
	_key("bandage", KEY_H)
	_key("use", KEY_E)
	_key("walk_toggle", KEY_X)
	_key("xray", KEY_TAB)
	_key("restart", KEY_F5)
	for i in 9:
		_key("weapon_%d" % (i + 1), KEY_1 + i)
	_key("weapon_10", KEY_0)
	_key("view_toggle", KEY_V)
	_key("laser", KEY_L)
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)
	_mouse("next_weapon", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse("prev_weapon", MOUSE_BUTTON_WHEEL_UP)


func _key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var e := InputEventKey.new()
	e.physical_keycode = key
	InputMap.action_add_event(action, e)


func _mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.22, 0.4, 0.66)
	psm.sky_horizon_color = Color(0.66, 0.72, 0.78)
	psm.ground_horizon_color = Color(0.66, 0.72, 0.78)
	psm.ground_bottom_color = Color(0.2, 0.19, 0.16)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 2.0
	env.ssao_detail = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.03
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.68, 0.75)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)


# ======================================================== menu i PvP (GD-Sync)

var _menu: CanvasLayer
var _status: Label
var _code_edit: LineEdit
var _pvp_host := false
var _pvp_code := ""
var _join_tries := 0
var _match_started := false
var _respawn_t := 0.0
var _corpses: Array = []
var _corpse_n := 0


func _show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = CanvasLayer.new()
	add_child(_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.04, 0.84)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.position = Vector2(-210, -230)
	box.add_theme_constant_override("separation", 10)
	bg.add_child(box)
	var title := Label.new()
	title.text = "BLUEPRINT BLADE"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_menu_button("Gra solo (boty)", _start_solo))
	var lbl := Label.new()
	lbl.text = "Kod gry (ten sam u obu graczy):"
	box.add_child(lbl)
	_code_edit = LineEdit.new()
	_code_edit.text = "BB%04d" % _rng.randi_range(0, 9999)
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_code_edit)
	box.add_child(_menu_button("Stwórz grę online (PvP 1 na 1)", func(): _start_pvp(true, true, _code_edit.text)))
	box.add_child(_menu_button("Dołącz online", func(): _start_pvp(true, false, _code_edit.text)))
	box.add_child(_menu_button("Stwórz grę w sieci lokalnej / na tym PC", func(): _start_pvp(false, true, _code_edit.text)))
	box.add_child(_menu_button("Dołącz w sieci lokalnej / na tym PC", func(): _start_pvp(false, false, _code_edit.text)))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420, 60)
	box.add_child(_status)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 40)
	b.pressed.connect(cb)
	return b


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


func _set_status(t: String) -> void:
	print("[PvP] ", t)
	if _status:
		_status.text = t
	if _hud:
		_hud.status = t


func _start_pvp(online: bool, host: bool, code: String) -> void:
	var gd := get_node_or_null("/root/GDSync")
	if gd == null:
		_set_status("Brak wtyczki GD-Sync (addons/GD-Sync).")
		return
	_pvp_host = host
	_pvp_code = code.strip_edges().to_upper()
	if _pvp_code.is_empty():
		_set_status("Wpisz kod gry.")
		return
	if not gd.connected.is_connected(_on_gd_connected):
		gd.connected.connect(_on_gd_connected)
		gd.connection_failed.connect(func(e): _set_status("Nie udało się połączyć z GD-Sync (błąd %d). Online wymaga kluczy API — patrz instrukcja." % e))
		gd.lobby_created.connect(func(n): gd.lobby_join(n))
		gd.lobby_creation_failed.connect(func(n, e): _set_status("Nie udało się stworzyć gry %s (błąd %d) — może kod jest zajęty?" % [n, e]))
		gd.lobby_joined.connect(_on_lobby_joined)
		gd.lobby_join_failed.connect(_on_join_failed)
		gd.client_joined.connect(_on_client_joined)
		gd.client_left.connect(_on_client_left)
		gd.disconnected.connect(func(): _set_status("Rozłączono z GD-Sync."))
	gd.expose_func(net_respawn)
	_set_status("Łączenie (%s)..." % ("online" if online else "lokalnie"))
	if online:
		gd.start_multiplayer()
	else:
		gd.start_local_multiplayer()


func _on_gd_connected() -> void:
	var gd := get_node("/root/GDSync")
	if _pvp_host:
		_set_status("Tworzenie gry %s..." % _pvp_code)
		gd.lobby_create(_pvp_code, "", true, 2)
	else:
		_set_status("Dołączanie do gry %s..." % _pvp_code)
		gd.lobby_join(_pvp_code)


func _on_join_failed(n: String, e: int) -> void:
	# lobby lokalne ogłasza się co chwilę — próbujemy kilka razy
	_join_tries += 1
	if _join_tries < 15:
		_set_status("Szukanie gry %s... (%d)" % [n, _join_tries])
		await get_tree().create_timer(1.0).timeout
		get_node("/root/GDSync").lobby_join(_pvp_code)
	else:
		_set_status("Nie znaleziono gry %s (błąd %d). Sprawdź kod i czy host już stworzył grę." % [n, e])


func _on_lobby_joined(_n: String) -> void:
	if _match_started:
		return
	_match_started = true
	var gd := get_node("/root/GDSync")
	Player.net_on = true
	_close_menu()
	var me: int = gd.get_client_id()
	var host_side: bool = gd.is_host()
	var p := _make_net_player(me, false, _pvp_spawn(_level.posts[11] if host_side else _level.posts[9]))
	_player = p
	_make_hud(p)
	_hud.pvp = true
	_hud.code = _pvp_code
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for id in gd.lobby_get_all_clients():
		if int(id) != me:
			_on_client_joined(int(id))
	_set_status("W grze %s" % _pvp_code)


## Miejsce odrodzenia: posterunek we wsi daleko od przeciwnika (albo podany).
func _pvp_spawn(prefer := Vector3.INF) -> Vector3:
	var village: Array = _level.posts.slice(0, 13)
	if prefer != Vector3.INF:
		return prefer
	var opp := _opponent()
	if opp == null:
		return village[_rng.randi() % village.size()]
	var by_d := village.duplicate()
	by_d.sort_custom(func(a, b): return a.distance_to(opp.global_position) > b.distance_to(opp.global_position))
	return by_d[_rng.randi() % 3]


func _opponent() -> Node3D:
	for n in get_tree().get_nodes_in_group("net_player"):
		if not n.down and not String(n.name).begins_with("Dead"):
			return n
	return null


func _make_net_player(id: int, remote: bool, pos: Vector3, deaths := 0) -> Node:
	var p := Player.new()
	p.name = "P%d" % id
	p.net_id = id
	p.is_remote = remote
	p.deaths = deaths
	p.position = pos
	var look_at := Vector3(-10, 0, -5) - pos   # twarzą do środka wsi
	p.rotation.y = atan2(-look_at.x, -look_at.z)
	add_child(p)
	return p


## Odrodzenie mojego żołnierza; ciało zostaje, przeciwnik dostaje nowe miejsce.
func _respawn_local() -> void:
	_respawn_t = 0.0
	if _hud:
		_hud.respawn_in = -1.0
	var gd := get_node("/root/GDSync")
	var me: int = gd.get_client_id()
	var old := _player
	_retire(old)
	old.set_process_unhandled_input(false)
	old.camera().current = false
	var pos := _pvp_spawn()
	var p := _make_net_player(me, false, pos, old.deaths)
	p.kills = old.kills
	_player = p
	_hud.player = p
	gd.call_func(net_respawn, me, pos, old.deaths)


## (zdalnie) przeciwnik się odrodził.
func net_respawn(id: int, pos: Vector3, deaths: int) -> void:
	var old := get_node_or_null("P%d" % id)
	if old:
		_retire(old)
	_make_net_player(id, true, pos, deaths)


func _retire(n: Node) -> void:
	_corpse_n += 1
	n.name = "Dead%d" % _corpse_n
	_corpses.append(n)
	while _corpses.size() > MAX_CORPSES:
		var c = _corpses.pop_front()
		if is_instance_valid(c) and c != _player:
			c.queue_free()


func _on_client_joined(id: int) -> void:
	if not _match_started or has_node("P%d" % id) or id == get_node("/root/GDSync").get_client_id():
		return
	# pozycję poprawi pierwszy pakiet stanu
	_make_net_player(id, true, _level.posts[9] if _pvp_host else _level.posts[11])
	_set_status("Przeciwnik dołączył")


func _on_client_left(id: int) -> void:
	var p := get_node_or_null("P%d" % id)
	if p:
		p.queue_free()
	_set_status("Przeciwnik wyszedł.")
