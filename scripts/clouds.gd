extends Node3D
## Chmury kłębiaste na wysokości lotu samolotów: każda to grupa miękkich kłębów (billboardy
## w jednym MultiMeshu), jaśniejsze u góry, szaroniebieskie od spodu. Blisko kamery kłęby
## przezroczystnieją — przelot przez chmurę to mgiełka, a nie ściana. Chmury powoli dryfują.

const COUNT := 34
const PUFFS := 30
const SPREAD := 1100.0
const DRIFT := Vector3(2.2, 0, 0.9)     # wiatr na wysokości [m/s]

var _mi: MultiMeshInstance3D
var _mm: MultiMesh
var _xf: Array = []          # [środek chmury, przesunięcie kłębu, skala]
var _t := 0.0
var _upd := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 6.0
	m.distance_fade_max_distance = 45.0
	q.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = COUNT * PUFFS
	var i := 0
	for c in COUNT:
		var center := Vector3(rng.randf_range(-SPREAD, SPREAD), rng.randf_range(200.0, 330.0), rng.randf_range(-SPREAD, SPREAD))
		var size := rng.randf_range(45.0, 95.0)
		for k in PUFFS:
			var off := Vector3(rng.randfn(0.0, 0.55), absf(rng.randfn(0.0, 0.3)), rng.randfn(0.0, 0.45)) * size
			var s := rng.randf_range(0.8, 1.4) * size * (1.0 - clampf(off.y / size, 0.0, 0.6) * 0.5)
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), center + off))
			_xf.append([center, off, s])
			var lit := clampf(0.62 + off.y / size * 0.8, 0.62, 1.0)
			mm.set_instance_color(i, Color(lit, lit * 1.01, lit * 1.05, rng.randf_range(0.45, 0.7)))
			i += 1
	_mi = MultiMeshInstance3D.new()
	_mi.multimesh = mm
	_mm = mm
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.custom_aabb = AABB(Vector3(-SPREAD - 200, 100, -SPREAD - 200), Vector3(SPREAD * 2 + 400, 400, SPREAD * 2 + 400))
	add_child(_mi)


## Dryf z wiatrem: chmura, która odpłynie za skraj obszaru, wraca z przeciwnej strony (daleko, w mgle).
func _process(dt: float) -> void:
	_t += dt
	_upd -= dt
	if _upd > 0.0:
		return
	_upd = 0.1
	var shift := DRIFT * _t
	for i in _xf.size():
		var e: Array = _xf[i]
		var c: Vector3 = e[0] + shift
		c.x = wrapf(c.x, -SPREAD, SPREAD)
		c.z = wrapf(c.z, -SPREAD, SPREAD)
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * float(e[2])), c + (e[1] as Vector3)))


## Kłąb: miękka plama z postrzępionym brzegiem (szum fbm), jaśniejsza w środku.
func _puff_texture() -> ImageTexture:
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	for y in sz:
		for x in sz:
			var d := Vector2(x - sz * 0.5, y - sz * 0.5).length() / (sz * 0.5)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.6 - (1.0 - n) * 0.9, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var b := 0.85 + 0.15 * n
			img.set_pixel(x, y, Color(b, b, b, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
