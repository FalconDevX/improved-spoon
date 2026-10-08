extends Node3D
## Gra: mapa (wieś, kompleks, farma, sad), gracz-żołnierz. Solo: oddziały botów na posterunkach.
## PvP 1 na 1 przez GD-Sync (online z kluczami API albo w sieci lokalnej / na tym PC bez kluczy).
## Na lotnisku stoją myśliwce — można do nich wsiąść, latać i strzelać z karabinów maszynowych.

const Player = preload("res://scripts/player.gd")
const Npc = preload("res://scripts/npc.gd")
const Soldier = preload("res://scripts/soldier.gd")
const FX = preload("res://scripts/fx.gd")
const Ballistics = preload("res://scripts/ballistics.gd")
const Hud = preload("res://scripts/hud.gd")
const Level = preload("res://scripts/level.gd")
const Aircraft = preload("res://scripts/plane.gd")
const Heli = preload("res://scripts/heli.gd")
const C130 = preload("res://scripts/c130.gd")
const C17 = preload("res://scripts/c17.gd")
const Car = preload("res://scripts/car.gd")
const Sam = preload("res://scripts/sam.gd")
const Village = preload("res://scripts/village.gd")
const Bunker = preload("res://scripts/bunker.gd")
const Ufo = preload("res://scripts/ufo.gd")
const Civilian = preload("res://scripts/civilian.gd")
const V1Site = preload("res://scripts/v1_site.gd")
const V2Site = preload("res://scripts/v2_site.gd")
const Terrain = preload("res://scripts/terrain.gd")
const Tank = preload("res://scripts/tank.gd")
const AA = preload("res://scripts/aa.gd")
const BigMap = preload("res://scripts/bigmap.gd")
const Chat = preload("res://scripts/chat.gd")
const AmmoCrate = preload("res://scripts/ammo_crate.gd")
const Clouds = preload("res://scripts/clouds.gd")
const Grass = preload("res://scripts/grass.gd")
const Post = preload("res://scripts/post.gd")
const Minimap = preload("res://scripts/minimap.gd")
const Menu = preload("res://scripts/menu.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const PLANE_PAINT := [Color(0.33, 0.38, 0.25), Color(0.36, 0.4, 0.44), Color(0.55, 0.47, 0.33)]

const MAX_NPC := 32
const RESPAWN_PVP := 5.0
const MAX_CORPSES := 6

var _level: Level
var village                      # wioska na południe od bazy (village.gd)
var waypoint := Vector3.INF      # punkt nawigacyjny z mapy [M]
var chat                         # czat [Enter] (chat.gd)
var bigmap                       # pełna mapa [M] (bigmap.gd) — też wybór celu V-2
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
	village = Village.new()
	village.name = "Village"
	add_child(village)
	village.build(_level.terrain.t3d)
	var bunker := Bunker.new()
	bunker.name = "Bunkers"
	add_child(bunker)
	bunker.build(_level.terrain.t3d, _level)
	if _level.is_ready():
		_spawn_crates()
	else:
		_level.ready_nav.connect(_spawn_crates, CONNECT_ONE_SHOT)
	var post := Post.new()
	post.main = self
	add_child(post)
	var clouds := Clouds.new()
	clouds.name = "Clouds"
	add_child(clouds)
	_plant_grass.call_deferred()
	Npc.level = _level
	Npc.deaths = 0
	Civilian.deaths = 0
	Civilian.feed.clear()
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


## Trawa po pierwszych krokach fizyki (promienie muszą widzieć już budynki).
func _plant_grass() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var g := Grass.new()
	g.name = "Grass"
	add_child(g)
	g.build(_level)
	_apply_settings()


func _process(_dt: float) -> void:
	if _menu_cam:
		# kamera menu krąży nad mapą (lotnisko, wieś)
		_menu_a += _dt * 0.035
		_menu_cam.global_position = Vector3(cos(_menu_a) * 120.0 + 20.0, 38.0 + sin(_menu_a * 2.0) * 6.0, sin(_menu_a) * 120.0)
		_menu_cam.look_at(Vector3(20, 6, 0))
	if is_instance_valid(_player):
		var cam := get_viewport().get_camera_3d()
		_level.update_roofs(_player.global_position, cam.global_position if cam else _player.global_position)


func _physics_process(dt: float) -> void:
	_tick_bots(dt)
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
	player.rotation.y = -PI * 0.5  # na wschód: twarzą do samolotów
	add_child(player)
	_player = player
	_spawn_planes()
	if get_tree().get_nodes_in_group("civilian").is_empty():
		village.spawn_people()
		village.spawn_traffic()
	_make_hud(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_when_nav(_spawn_squads)


func _when_nav(f: Callable) -> void:
	if _level.is_ready():
		f.call()
	else:
		_level.ready_nav.connect(f, CONNECT_ONE_SHOT)


# ======================================================== boty
# Liczba, poziom trudności i odradzanie z opcji gry (Settings). W PvP boty liczy host: rozsyła
# ich stan paczkami (limit pakietu GD-Sync ~1200 B), strzały i upadki; u gościa są kukiełkami.

const BOT_RESPAWN := 30.0
const BOT_PACK := 8              # botów w jednej paczce stanu
const BOT_NET_RATE := 0.1
const MAX_BOT_CORPSES := 14

var _bot_n := 0
var _bot_queue: Array = []       # czasy odrodzenia zabitych botów
var _ally_queue: Array = []      # czasy odrodzenia zabitych sojuszników (solo)
var _bot_corpses: Array = []
var _bot_net_t := 0.0
var _got_bots := false
var _air_t := 2.0
var _clock := 0.0


## Miejsca startu graczy (boty nie startują obok nich).
func _player_spawns() -> Array:
	if Player.net_on:
		return [_level.posts[9], _level.posts[11]]
	return [_level.spawn_player]


## Oddziały 1-3 żołnierzy na posterunkach (nie przy starcie graczy), łącznie tylu, ile w opcjach.
func _spawn_squads() -> void:
	if Player.net_on and not _pvp_host:
		return
	Npc.skill = Settings.difficulty
	var want: int = mini(Settings.BOT_COUNTS[Settings.bots], MAX_NPC)
	var posts: Array = []
	for post: Vector3 in _level.posts:
		var ok := true
		for sp: Vector3 in _player_spawns():
			if post.distance_to(sp) < 25.0:
				ok = false
		if ok:
			posts.append(post)
	posts.shuffle()
	var made: Array = []
	var n := 0
	while n < want and not posts.is_empty():
		for post: Vector3 in posts:
			for i in _rng.randi_range(1, 3):
				if n >= want:
					break
				made.append(_spawn_bot(post))
				n += 1
			if n >= want:
				break
	_send_bots(made)
	if not Player.net_on:
		for i in Settings.ALLY_COUNTS[Settings.ally_bots]:
			_spawn_ally()


## Sojusznik (solo): obok gracza, idzie za nim.
func _spawn_ally() -> Node:
	var c: Vector3 = _player.global_position if is_instance_valid(_player) else _level.spawn_player
	var a := _rng.randf() * TAU
	var npc = _spawn_bot(c + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(4.0, 9.0), true)
	npc.leader = _player
	return npc


func _spawn_bot(post: Vector3, ally := false) -> Node:
	var off := Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
	var p := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, post + off)
	var npc := Npc.new()
	npc.ally = ally
	_bot_n += 1
	npc.name = "Bot%d" % _bot_n
	npc.position = Vector3(p.x, 0.0, p.z)
	npc.rotation.y = _rng.randf_range(-PI, PI)
	add_child(npc)
	npc.downed.connect(_on_bot_down)
	return npc


func _on_bot_down(npc: Node) -> void:
	if npc.ally:
		_ally_queue.append(_clock + BOT_RESPAWN)
	else:
		_bot_queue.append(_clock + BOT_RESPAWN)
	_keep_corpse(npc)


func _keep_corpse(npc: Node) -> void:
	_bot_corpses.append(npc)
	while _bot_corpses.size() > MAX_BOT_CORPSES:
		var c = _bot_corpses.pop_front()
		if is_instance_valid(c):
			c.queue_free()


func _tick_bots(dt: float) -> void:
	_clock += dt
	if not is_instance_valid(_player) or (Player.net_on and not _pvp_host):
		return
	_air_t -= dt
	if _air_t <= 0.0:
		_air_t = 4.0
		_staff_aircraft()
	# sojusznicy: wracają obok gracza
	if not _ally_queue.is_empty() and _clock >= float(_ally_queue[0]):
		_ally_queue.pop_front()
		if Settings.bot_respawn and not Player.net_on and not _player.down:
			_spawn_ally()
	# odradzanie: posterunek daleko od graczy
	if not _bot_queue.is_empty() and _clock >= float(_bot_queue[0]):
		_bot_queue.pop_front()
		if Settings.bot_respawn and get_tree().get_nodes_in_group("npc").filter(func(b): return not b.down).size() < MAX_NPC:
			var far: Array = _level.posts.filter(func(p: Vector3):
				for s in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("net_player"):
					if not s.down and p.distance_to(s.global_position) < 45.0:
						return false
				return true)
			if not far.is_empty():
				_send_bots([_spawn_bot(far[_rng.randi() % far.size()])])
	if not Player.net_on or _opponent() == null:
		return
	_bot_net_t -= dt
	if _bot_net_t > 0.0:
		return
	_bot_net_t = BOT_NET_RATE
	var gd := get_node("/root/GDSync")
	var f := PackedFloat32Array()
	var k := 0
	for b in get_tree().get_nodes_in_group("npc"):
		if b.down or b.is_queued_for_deletion():
			continue
		b.net_pack(f, int(String(b.name).trim_prefix("Bot")))
		k += 1
		if k == BOT_PACK:
			gd.call_func_unreliable(net_bots_state, f)
			f = PackedFloat32Array()
			k = 0
	if k > 0:
		gd.call_func_unreliable(net_bots_state, f)


## Boty-piloci: wolne maszyny na lotnisku / lądowiskach dostają pilota, aż będzie ich tyle, ile w opcjach.
func _staff_aircraft() -> void:
	if not _level.is_ready():
		return
	var crafts: Array = get_tree().get_nodes_in_group("aircraft")
	var flying := 0
	var allies := 0
	for a in crafts:
		if a.ai != null and a.pilot != null and is_instance_valid(a.pilot) and not a.pilot.down:
			if a.pilot.get("ally") == true:
				allies += 1
			else:
				flying += 1
	# sojusznicy-piloci tylko w solo; najpierw brakujący wróg, potem brakujący sojusznik
	var ally := false
	if flying >= Settings.air_bots:
		if Player.net_on or allies >= Settings.ally_air:
			return
		ally = true
		flying = allies
	# na zmianę śmigłowce i samoloty, tylko maszyny stojące na swoim miejscu, bez pilota
	crafts.shuffle()
	crafts.sort_custom(func(a, b): return int(a.get("is_heli") == true) > int(b.get("is_heli") == true) if flying % 2 == 0 else int(a.get("is_heli") == true) < int(b.get("is_heli") == true))
	for a in crafts:
		if a.destroyed or a.pilot != null or not a.on_ground or a.global_position.distance_to(a.home.origin) > 3.0:
			continue
		var npc := Npc.new()
		npc.ally = ally
		_bot_n += 1
		npc.name = "Bot%d" % _bot_n
		npc.position = a.global_position
		add_child(npc)
		npc.downed.connect(_on_pilot_down)
		_send_bots([npc])
		a.board_bot(npc)
		return


func _on_pilot_down(npc: Node) -> void:
	_keep_corpse(npc)


func _bot_info(b: Node) -> Array:
	return [String(b.name), b.global_position, b.visual.rotation.y, b.weapon_id, b.tint_i, b.helmet, b.vest]


## Host: nowe boty pojawiają się też u gościa.
func _send_bots(bots: Array, to := -1) -> void:
	if not Player.net_on or not _pvp_host or bots.is_empty():
		return
	var list: Array = []
	for b in bots:
		if is_instance_valid(b) and not b.down:
			list.append(_bot_info(b))
	var gd := get_node("/root/GDSync")
	# paczkami (duża lista w jednym wywołaniu potrafi nie dojść)
	for i in range(0, list.size(), BOT_PACK):
		var part := list.slice(i, i + BOT_PACK)
		if to >= 0:
			gd.call_func_on(to, net_bots_spawn, part)
		else:
			gd.call_func(net_bots_spawn, part)


## (gość) prosi hosta o listę botów, aż jakąś dostanie (host mógł je wysłać, zanim tu doszliśmy).
func _ask_bots() -> void:
	for i in 10:
		await get_tree().create_timer(1.5 if i == 0 else 3.0).timeout
		if _got_bots or not Player.net_on:
			return
		get_node("/root/GDSync").call_func(net_want_bots)


## Czat: moja wiadomość do drugiego gracza.
func send_chat(text: String) -> void:
	if Player.net_on and _match_started:
		get_node("/root/GDSync").call_func(net_chat, text)


## (zdalnie) wiadomość od drugiego gracza.
func net_chat(text: String) -> void:
	if chat:
		chat.add(("Gość" if _pvp_host else "Host") + ": " + text, Color(0.6, 0.85, 1.0))


## (host) gość prosi o listę botów.
func net_want_bots() -> void:
	if _pvp_host:
		_send_bots(get_tree().get_nodes_in_group("npc"), get_node("/root/GDSync").get_sender_id())


## (gość) host stworzył boty.
func net_bots_spawn(list: Array) -> void:
	_got_bots = true
	for it: Array in list:
		if has_node(String(it[0])):
			continue
		var npc := Npc.new()
		npc.is_remote = true
		npc.name = it[0]
		npc.position = it[1]
		npc.rotation.y = it[2]
		npc.weapon_id = it[3]
		npc.tint_i = it[4]
		npc.helmet = it[5]
		npc.vest = it[6]
		add_child(npc)


## (gość) paczka stanu botów.
func net_bots_state(f: PackedFloat32Array) -> void:
	var i := 0
	while i + Npc.NET_STRIDE <= f.size():
		var b := get_node_or_null("Bot%d" % int(f[i]))
		if b and b.is_remote:
			b.net_apply(f, i)
		i += Npc.NET_STRIDE


## Host: bot strzelił (wołane przez npc.gd).
func bot_shot(b: Node, origin: Vector3, dir: Vector3, tracer: bool) -> void:
	if _opponent() != null:
		get_node("/root/GDSync").call_func(net_bot_shot, String(b.name), origin, dir, tracer)


func net_bot_shot(n: String, origin: Vector3, dir: Vector3, tracer: bool) -> void:
	var b := get_node_or_null(n)
	if b and b.is_remote:
		b.net_fire(origin, dir, tracer)


## Host: bot padł — u gościa też; zabójstwo zaliczane temu, kto ostatni trafił.
func bot_down(b: Node, dir: Vector3, at: Vector3, seg: String, energy: float, instant: bool) -> void:
	var by := ""
	if b.last_shooter != null and is_instance_valid(b.last_shooter):
		by = String(b.last_shooter.name)
	get_node("/root/GDSync").call_func(net_bot_down, String(b.name), b.global_position, dir, at, seg, energy, instant, by, b.last_hit_seg)


func net_bot_down(n: String, pos: Vector3, dir: Vector3, at: Vector3, seg: String, energy: float, instant: bool, by: String, hit_seg: String) -> void:
	var b := get_node_or_null(n)
	if b == null or not b.is_remote or b.down:
		return
	b.global_position = pos
	b.last_hit_seg = hit_seg
	b._collapse(dir, at, seg, energy, instant)
	_keep_corpse(b)
	if is_instance_valid(_player) and by == String(_player.name):
		_player.on_kill(b)


## Gość: moja kula trafiła kukiełkę bota — skutki liczy host.
func send_bot_hit(b: Node, h: Dictionary) -> void:
	get_node("/root/GDSync").call_func(net_bot_hit, String(b.name), h)


func net_bot_hit(n: String, h: Dictionary) -> void:
	var b := get_node_or_null(n)
	if b == null or b.is_remote or b.down:
		return
	h["shooter"] = get_node_or_null("P%d" % get_node("/root/GDSync").get_sender_id())
	b.bullet_hit(h)


# ======================================================== restart mapy

## Restart (host albo solo): nowe boty według opcji, gracze na startowych miejscach, wyniki od zera,
## samoloty i skrzynki jak nowe. W PvP gość robi to samo u siebie (net_restart).
func restart_match() -> void:
	if Player.net_on and not _pvp_host:
		return
	if Player.net_on:
		get_node("/root/GDSync").call_func(net_restart)
	_reset_world()
	_when_nav(_spawn_squads)


func net_restart() -> void:
	_reset_world()
	if is_instance_valid(_player):
		_player._msg("Host zrestartował mapę")


func _reset_world() -> void:
	if _menu and _menu.in_game:
		_close_pause()
	for b in get_tree().get_nodes_in_group("npc"):
		b.queue_free()
	_bot_queue.clear()
	_ally_queue.clear()
	_bot_corpses.clear()
	Npc._covers_taken.clear()
	Npc.deaths = 0
	Civilian.deaths = 0
	Civilian.feed.clear()
	Npc.skill = Settings.difficulty
	for c in _corpses:
		if is_instance_valid(c):
			c.queue_free()
	_corpses.clear()
	for g in get_tree().get_nodes_in_group("dropped_gun"):
		g.queue_free()
	# bomby w locie, wybuch atomowy (grzyb, fala), syreny alarmu, płonący napalm
	for o in get_tree().get_nodes_in_group("ordnance"):
		o.queue_free()
	for c in get_tree().get_nodes_in_group("ammo_crate"):
		c.cooldown = 0.01
	var others: Array = []
	for p in get_tree().get_nodes_in_group("net_player"):
		if String(p.name).begins_with("P"):
			others.append(p.net_id)
		_drop_node(p)
	if is_instance_valid(_player):
		_drop_node(_player)
	_spawn_planes()
	village.spawn_people()
	_respawn_t = 0.0
	if _hud:
		_hud.respawn_in = -1.0
	var p: Node
	if Player.net_on:
		var me: int = get_node("/root/GDSync").get_client_id()
		p = _make_net_player(me, false, _level.posts[11] if _pvp_host else _level.posts[9])
		for id: int in others:
			_make_net_player(id, true, _level.posts[9] if _pvp_host else _level.posts[11])
	else:
		p = Player.new()
		p.name = "Player"
		p.position = _level.spawn_player
		p.rotation.y = -PI * 0.5
		add_child(p)
	_player = p
	_hud.player = p


func _drop_node(n: Node) -> void:
	if n.get("vehicle") != null and is_instance_valid(n.vehicle):
		n.vehicle.pilot_gone(n)
	remove_child(n)
	n.queue_free()


## Skrzynki z amunicją (na siatce nawigacyjnej, żeby nie stały w ścianie; te same miejsca u obu graczy).
func _spawn_crates() -> void:
	var map := get_world_3d().navigation_map
	var spots: Array = _level.ammo_spots + _level.med_spots
	for i in spots.size():
		var want: Vector3 = spots[i]
		# siatka nawigacyjna przesuwa skrzynkę z dala od ścian; zanim się zsynchronizuje, zwraca (0, 0, 0)
		# — wtedy wszystkie skrzynki lądowały w jednym miejscu, jedna na drugiej
		var p := NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(p.x - want.x, p.z - want.z).length() > 4.0:
			p = want
		var c := AmmoCrate.new()
		var med: bool = i >= _level.ammo_spots.size()
		c.kind = "med" if med else "ammo"
		c.name = ("MedKit%d" if med else "AmmoCrate%d") % i
		c.position = Vector3(p.x, 0.0, p.z)
		c.rotation.y = float(i) * 0.7
		add_child(c)


# ======================================================== wspólne

## Myśliwce na lotnisku (te same nazwy węzłów u obu graczy — GD-Sync woła funkcje po ścieżce).
func _spawn_planes() -> void:
	for old in get_tree().get_nodes_in_group("plane"):   # z tła menu — PvP potrzebuje nowych (funkcje sieciowe)
		remove_child(old)
		old.queue_free()
	for i in _level.plane_spots.size():
		var pl := Aircraft.new()
		pl.name = "Plane%d" % (i + 1)
		pl.paint = PLANE_PAINT[i % PLANE_PAINT.size()]
		pl.transform = _level.plane_spots[i]
		add_child(pl)
	for old in get_tree().get_nodes_in_group("car"):
		remove_child(old)
		old.queue_free()
	for i in _level.car_spots.size():
		var c := Car.new()
		c.name = "Car%d" % (i + 1)
		c.transform = _level.car_spots[i]
		add_child(c)
	for i in _level.sam_spots.size():
		var sm := Sam.new()
		sm.name = "Sam%d" % (i + 1)
		sm.transform = _level.sam_spots[i]
		add_child(sm)
	for i in _level.tank_spots.size():
		var tk := Tank.new()
		tk.name = "Tank%d" % (i + 1)
		tk.transform = _level.tank_spots[i]
		add_child(tk)
	for old in get_tree().get_nodes_in_group("emplacement"):
		remove_child(old)
		old.queue_free()
	for i in _level.aa_spots.size():
		var s: Array = _level.aa_spots[i]
		var aa := AA.new()
		aa.kind = s[0]
		aa.name = "AA%d" % (i + 1)
		aa.position = s[1]
		aa.rotation.y = s[2]
		add_child(aa)
	for i in _level.transport_spots.size():
		var t := C130.new()
		t.name = "Transport%d" % (i + 1)
		t.transform = _level.transport_spots[i]
		add_child(t)
	# C-17 Globemaster na wschodnim końcu pasa, nosem na zachód (gotowy do startu)
	var g := C17.new()
	g.name = "Globemaster1"
	g.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(740.0, Terrain.height(740.0, 11.0) + g.GEAR_H, 11.0))
	add_child(g)
	for i in _level.heli_spots.size():
		var h := Heli.new()
		h.name = "Heli%d" % (i + 1)
		h.transform = _level.heli_spots[i]
		add_child(h)
	# latający dysk za wschodnim ogrodzeniem bazy, obok C-130 (poza osią startu myśliwców)
	var u := Ufo.new()
	u.name = "UFO1"
	u.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(160.0, 4.6, 92.0))
	add_child(u)
	# trzy wyrzutnie V-1 na wschód od C-130, rampy skierowane na wschód wzdłuż pasa
	for old in get_tree().get_nodes_in_group("launcher"):
		if old.get_parent() == self:      # wyrzutnie V-1 / V-2 (przełączniki rampy C-17 są w samolocie)
			remove_child(old)
			old.queue_free()
	for i in 3:
		var z := 48.0 + 14.0 * i
		var site := V1Site.new()
		site.name = "V1Site%d" % (i + 1)
		site.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(270.0, Terrain.height(270.0, z), z))
		add_child(site)
	# trzy stanowiska V-2 w południowo-zachodniej części bazy
	var v2_spots := [Vector2(-100, -104), Vector2(-80, -82), Vector2(-56, -82)]
	for i in v2_spots.size():
		var sp: Vector2 = v2_spots[i]
		var pad := V2Site.new()
		pad.name = "V2Site%d" % (i + 1)
		pad.position = Vector3(sp.x, Terrain.height(sp.x, sp.y), sp.y)
		add_child(pad)


func _make_hud(player: Node) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Hud.new()
	hud.theme = UiTheme.hud()
	hud.player = player
	layer.add_child(hud)
	_hud = hud
	var mm := Minimap.new()
	mm.theme = UiTheme.hud()
	mm.main = self
	mm.level = _level
	layer.add_child(mm)
	chat = Chat.new()
	chat.theme = UiTheme.hud()
	chat.main = self
	layer.add_child(chat)
	var bm := BigMap.new()
	bm.theme = UiTheme.hud()
	bm.main = self
	bm.level = _level
	layer.add_child(bm)
	bigmap = bm



func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("grade"):
		Settings.next_grade()
		if is_instance_valid(_player):
			_player._msg("Filtr kolorów: " + Settings.GRADES[Settings.grade])
		get_viewport().set_input_as_handled()
		return
	# solo: po śmierci Spacja — odrodzenie (ciało zostaje, wynik się nie zeruje)
	if e.is_action_pressed("jump") and not Player.net_on and is_instance_valid(_player) and _player.down and _player._death_t > 1.0:
		_respawn_solo()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ui_cancel") and (_menu == null or not is_instance_valid(_menu)) and is_instance_valid(_player):
		_open_pause()
		get_viewport().set_input_as_handled()
		return
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
	_key("use", KEY_F)
	_key("lean_left", KEY_Q)
	_key("lean_right", KEY_E)
	_key("grenade", KEY_G)
	_key("flares", KEY_C)
	_key("map", KEY_M)
	_key("chat", KEY_ENTER)
	InputMap.action_add_event("chat", _keyev(KEY_KP_ENTER))
	_key("walk_toggle", KEY_X)
	_key("xray", KEY_TAB)
	_key("restart", KEY_F5)
	for i in 9:
		_key("weapon_%d" % (i + 1), KEY_1 + i)
	_key("weapon_10", KEY_0)
	_key("view_toggle", KEY_V)
	_key("laser", KEY_L)
	_key("help", KEY_F1)
	_key("grade", KEY_F2)
	_key("stick_up", KEY_UP)
	_key("stick_down", KEY_DOWN)
	_key("stick_left", KEY_LEFT)
	_key("stick_right", KEY_RIGHT)
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


func _keyev(key: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = key
	return e


func _mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


const SKY_SHADER := """
shader_type sky;
// Niebo: gradient z mgiełką przy horyzoncie, słońce z poświatą, dwie warstwy chmur (fbm) płynące
// z wiatrem i oświetlone od strony słońca.
uniform vec3 zenith : source_color = vec3(0.16, 0.33, 0.62);
uniform vec3 horizon : source_color = vec3(0.68, 0.75, 0.82);
uniform vec3 ground : source_color = vec3(0.6, 0.65, 0.7);
uniform float cover = 0.48;
float h(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
// fbm z obrotem między oktawami (bez widocznej siatki szumu)
float fbm(vec2 p) { float v = 0.0; float a = 0.5; mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 6; i++) { v += a * n2(p); p = r * p * 2.03 + 17.1; a *= 0.5; } return v; }
void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.45));
	col = mix(col, ground, smoothstep(0.0, -0.12, d.y));
	vec3 sun = LIGHT0_DIRECTION;
	float sd = max(dot(d, sun), 0.0);
	col += LIGHT0_COLOR * (pow(sd, 6.0) * 0.18 + pow(sd, 60.0) * 0.35);
	if (!AT_CUBEMAP_PASS) {
		col += LIGHT0_COLOR * smoothstep(0.9995, 0.9998, sd) * 8.0;
	}
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12);
		vec2 wind = vec2(TIME * 0.006, TIME * 0.002);
		float c1 = fbm(uv * 1.3 + wind);
		float c2 = fbm(uv * 3.1 - wind * 1.7 + 4.0);
		float dens = smoothstep(1.0 - cover, 1.0 - cover + 0.45, c1 * 0.75 + c2 * 0.35);
		// strona od słońca ciemniejsza (prosty ślad światła przez chmurę)
		float shade = fbm(uv * 1.3 + wind + sun.xz * 0.06);
		vec3 lit = mix(vec3(1.0, 0.98, 0.95), vec3(0.62, 0.66, 0.74), smoothstep(0.35, 0.8, shade));
		lit += LIGHT0_COLOR * pow(sd, 8.0) * 0.4;
		col = mix(col, lit, dens * smoothstep(0.0, 0.15, d.y) * 0.92);
	}
	COLOR = col;
}
"""


func _build_environment() -> void:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = SKY_SHADER
	sm.shader = ssh
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_detail = 0.8
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.65, 0.7)
	env.fog_density = 0.0004
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.6, 0.75, 1.0)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)


# ======================================================== menu i PvP (GD-Sync)

var _menu: CanvasLayer
var _pvp_host := false
var _pvp_code := ""
var _join_tries := 0
var _match_started := false
var _respawn_t := 0.0
var _corpses: Array = []
var _corpse_n := 0


var _menu_cam: Camera3D
var _menu_a := 0.0
var _env: Environment
var _sun: DirectionalLight3D


func _show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu_cam = Camera3D.new()
	_menu_cam.fov = 60.0
	_menu_cam.far = 3500.0
	add_child(_menu_cam)
	_menu_cam.current = true
	_spawn_planes()      # myśliwce na lotnisku widać w tle menu
	_menu = Menu.new()
	_menu.code = "SN%04d" % _rng.randi_range(0, 9999)
	_menu.solo.connect(_start_solo)
	_menu.pvp.connect(_start_pvp)
	add_child(_menu)


## Pauza (Esc): w solo zatrzymuje grę, w PvP gra toczy się dalej.
func _open_pause() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = Menu.new()
	_menu.in_game = true
	_menu.code = _pvp_code if Player.net_on else ""
	_menu.can_host = not Player.net_on or _pvp_host
	_menu.resume.connect(_close_pause)
	_menu.to_menu.connect(_back_to_menu)
	_menu.restart.connect(restart_match)
	_menu.options_changed.connect(func(): Npc.skill = Settings.difficulty)
	add_child(_menu)
	if _hud:
		_hud.get_parent().visible = false   # HUD i minimapa schowane pod menu pauzy
	if not Player.net_on:
		get_tree().paused = true


func _close_pause() -> void:
	get_tree().paused = false
	if _hud:
		_hud.get_parent().visible = true
	_close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _back_to_menu() -> void:
	get_tree().paused = false
	var gd := get_node_or_null("/root/GDSync")
	if Player.net_on and gd:
		gd.lobby_leave()
		gd.stop_multiplayer()
	Player.net_on = false
	get_tree().reload_current_scene()


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	if _menu_cam:
		_menu_cam.queue_free()
		_menu_cam = null


## Jakość grafiki z ustawień (wołane przy starcie i po każdej zmianie).
func _apply_settings() -> void:
	if not Settings.changed.is_connected(_apply_settings):
		Settings.changed.connect(_apply_settings)
	var q := Settings.quality
	if _env:
		_env.ssao_enabled = q >= 1
		_env.ssil_enabled = q >= 2
		_env.glow_enabled = true
	if _sun:
		_sun.directional_shadow_max_distance = [80.0, 120.0, 140.0][q]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096][q], true)
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	var g := get_node_or_null("Grass")
	if g:
		g.visible = q >= 1


func _set_status(t: String) -> void:
	print("[PvP] ", t)
	if _menu:
		_menu.set_status(t)
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
		gd.connection_failed.connect(_on_connection_failed)
		gd.lobby_created.connect(func(n): gd.lobby_join(n))
		gd.lobby_creation_failed.connect(func(n, e): _set_status("Nie udało się stworzyć gry %s (błąd %d) — może kod jest zajęty?" % [n, e]))
		gd.lobby_joined.connect(_on_lobby_joined)
		gd.lobby_join_failed.connect(_on_join_failed)
		gd.client_joined.connect(_on_client_joined)
		gd.client_left.connect(_on_client_left)
		gd.disconnected.connect(func(): _set_status("Rozłączono z GD-Sync."))
	for f in [net_chat, net_respawn, net_want_bots, net_bots_spawn, net_bots_state, net_bot_shot, net_bot_down, net_bot_hit, net_restart]:
		gd.expose_func(f)
	_set_status("Łączenie (%s)..." % ("online" if online else "lokalnie"))
	if online:
		gd.start_multiplayer()
	else:
		gd.start_local_multiplayer()


## Czytelny powód nieudanego połączenia (kody z GD-Sync ENUMS.CONNECTION_FAILED).
func _on_connection_failed(e: int) -> void:
	match e:
		0:
			_set_status("Brak kluczy API GD-Sync albo są złe. Do gry online skopiuj plik keys.cfg od osoby, która ma klucze, do folderu addons/GD-Sync (obaj gracze te same klucze). Bez kluczy działa gra w sieci lokalnej.")
		1:
			_set_status("Serwer GD-Sync nie odpowiada (przekroczony czas). Sprawdź internet i spróbuj ponownie.")
		2:
			_set_status("Nie udało się otworzyć portu sieci lokalnej — zamknij drugą kopię gry albo zezwól grze w zaporze Windows.")
		_:
			_set_status("Nie udało się połączyć z GD-Sync (błąd %d)." % e)


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
	Npc.net_host = _pvp_host
	_close_menu()
	_spawn_planes()
	var me: int = gd.get_client_id()
	# kto założył grę (nie gd.is_host(): online host jest wyznaczany dopiero po wejściu do lobby,
	# więc obaj dostawali to samo miejsce i stali w sobie)
	var p := _make_net_player(me, false, _pvp_spawn(_level.posts[11] if _pvp_host else _level.posts[9]))
	_player = p
	_make_hud(p)
	_hud.pvp = true
	_hud.code = _pvp_code
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for id in gd.lobby_get_all_clients():
		if int(id) != me:
			_on_client_joined(int(id))
	_set_status("W grze %s" % _pvp_code)
	_when_nav(_spawn_squads)
	if not _pvp_host:
		# host mógł wysłać boty, zanim tu doszliśmy — prosimy o listę jeszcze raz
		_ask_bots()


## Miejsce odrodzenia: posterunek we wsi daleko od przeciwnika (albo podany).
func _pvp_spawn(prefer := Vector3.INF) -> Vector3:
	var spots: Array = _level.posts.slice(0, 13)
	if prefer != Vector3.INF:
		return prefer
	var opp := _opponent()
	if opp == null:
		return spots[_rng.randi() % spots.size()]
	var by_d := spots.duplicate()
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
	p.score = old.score
	p.pvp_kills = old.pvp_kills
	p.grenades = maxi(old.grenades, 2)
	_player = p
	_hud.player = p
	gd.call_func(net_respawn, me, pos, old.deaths)


## Solo: nowy żołnierz w bezpiecznym miejscu (lotnisko albo posterunek daleko od wrogów).
func _respawn_solo() -> void:
	var old := _player
	_retire(old)
	old.set_process_unhandled_input(false)
	old.camera().current = false
	var spots: Array = [_level.spawn_player] + _level.posts.slice(0, 13)
	var best: Vector3 = _level.spawn_player
	var best_d := -1.0
	for s: Vector3 in spots:
		var near := INF
		for b in get_tree().get_nodes_in_group("npc"):
			if not b.down and not b.ally:
				near = minf(near, s.distance_to(b.global_position))
		if near > best_d:
			best_d = near
			best = s
	var p := Player.new()
	p.name = "Player"
	p.position = best
	p.rotation.y = -PI * 0.5
	add_child(p)
	p.kills = old.kills
	p.score = old.score
	_player = p
	_hud.player = p


## (zdalnie) przeciwnik się odrodził.
func net_respawn(id: int, pos: Vector3, deaths: int) -> void:
	var old := get_node_or_null("P%d" % id)
	var pk: int = old.pvp_kills if old else 0
	if old:
		_retire(old)
	var np := _make_net_player(id, true, pos, deaths)
	np.pvp_kills = pk


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
	if chat:
		chat.add("Drugi gracz dołączył do gry", Color(1, 0.85, 0.4))
	if _pvp_host:
		_send_bots(get_tree().get_nodes_in_group("npc"), id)


func _on_client_left(id: int) -> void:
	var p := get_node_or_null("P%d" % id)
	if p:
		p.queue_free()
	_set_status("Przeciwnik wyszedł.")
