extends RefCounted
## Spadochron (gracz i boty): czasza z linkami nad żołnierzem i fizyka opadania.
## Stany: 0 — brak, 1 — swobodny spadek, 2 — otwieranie (czasza rośnie), 3 — otwarty.

const OPEN_TIME := 1.4
const SINK := 5.0              # opadanie pod otwartą czaszą [m/s]
const DRIFT := 6.5             # dryf WASD pod czaszą [m/s]
const FATAL := 22.0            # uderzenie w ziemię szybsze niż tyle zabija [m/s]


## Czasza: kopuła w pasy, linki do uprzęży (początek = barki żołnierza).
static func canopy() -> Node3D:
	var root := Node3D.new()
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.6
	sm.height = 3.6
	sm.is_hemisphere = true
	sm.radial_segments = 16
	sm.rings = 6
	dome.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.45, 0.3)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material_override = m
	dome.position.y = 4.6
	dome.scale = Vector3(1, 0.55, 1)
	root.add_child(dome)
	var line := StandardMaterial3D.new()
	line.albedo_color = Color(0.15, 0.15, 0.13)
	for k in 8:
		var a := TAU * k / 8.0
		var top := Vector3(cos(a) * 3.4, 4.6, sin(a) * 3.4)
		var bot := Vector3(cos(a) * 0.25, 0.0, sin(a) * 0.25)
		var l := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = top.distance_to(bot)
		cm.radial_segments = 3
		cm.rings = 1
		l.mesh = cm
		l.material_override = line
		l.position = (top + bot) * 0.5
		l.basis = Basis(Vector3.UP.cross(top - bot).normalized(), Vector3.UP.angle_to(top - bot)) if Vector3.UP.cross(top - bot).length() > 0.001 else Basis()
		root.add_child(l)
	root.position.y = 1.5
	return root


## Krok fizyki dla żołnierza s (velocity, move_and_slide). wish: kierunek WASD w świecie (0..1).
## Zwraca "" albo "landed" / "dead".
static func step(s: CharacterBody3D, state: int, t: float, wish: Vector3, dt: float) -> String:
	var v := s.velocity
	if state == 1:
		v.y -= 9.81 * dt
		v -= v * minf(v.length() * 0.0035 * dt, 0.5)        # opór: prędkość graniczna ~53 m/s
		v += wish * 3.0 * dt
	elif state == 2:
		var k := clampf(t / OPEN_TIME, 0.0, 1.0)
		v.y = lerpf(v.y, -SINK, 1.0 - exp(-3.0 * k * dt * 4.0))
		v.x = lerpf(v.x, wish.x * DRIFT, 1.0 - exp(-1.5 * k * dt))
		v.z = lerpf(v.z, wish.z * DRIFT, 1.0 - exp(-1.5 * k * dt))
	else:
		v = v.lerp(Vector3(wish.x * DRIFT, -SINK, wish.z * DRIFT), 1.0 - exp(-1.6 * dt))
	var impact := -v.y
	s.velocity = v
	s.move_and_slide()
	if s.is_on_floor() or s.get_slide_collision_count() > 0 and s.velocity.y > -0.5:
		return "dead" if impact > FATAL else "landed"
	return ""
