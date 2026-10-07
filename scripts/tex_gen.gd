extends RefCounted
## Proceduralne tekstury: plamy krwi (albedo + normal), rany cięte.


static func solid(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


## Zwraca [albedo, normal]. pool = duża, gładka kałuża zamiast rozbryzgu.
static func blood_splat(seed_: int, pool: bool) -> Array:
	var size := 128 if pool else 96
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.frequency = 0.035 if pool else 0.06
	noise.fractal_octaves = 3

	var blobs: Array[Vector3] = []
	blobs.append(Vector3(0.5, 0.5, 0.3 if pool else rng.randf_range(0.19, 0.25)))
	var count := rng.randi_range(3, 5) if pool else rng.randi_range(6, 12)
	for i in count:
		var a := rng.randf() * TAU
		if pool:
			var dist := rng.randf_range(0.08, 0.2)
			blobs.append(Vector3(0.5 + cos(a) * dist, 0.5 + sin(a) * dist, rng.randf_range(0.12, 0.2)))
		else:
			var dist := rng.randf_range(0.2, 0.42)
			blobs.append(Vector3(0.5 + cos(a) * dist, 0.5 + sin(a) * dist, rng.randf_range(0.015, 0.055)))

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			var f := -1.0
			for b in blobs:
				var d := Vector2(u - b.x, v - b.y).length() / b.z
				f = maxf(f, 1.0 - d)
			f += noise.get_noise_2d(x, y) * (0.12 if pool else 0.2)
			var a := smoothstep(0.0, 0.05, f)
			var thick := clampf(f * 2.5, 0.0, 1.0)
			var col := Color(0.42, 0.02, 0.025).lerp(Color(0.13, 0.0, 0.005), thick)
			col.a = a
			img.set_pixel(x, y, col)
			var hh := smoothstep(0.0, 0.3, f)
			hgt.set_pixel(x, y, Color(hh, hh, hh, 1.0))
	img.generate_mipmaps()
	hgt.bump_map_to_normal_map(4.0)
	hgt.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(hgt)]


## Rana cięta: podłużne rozcięcie z ciemnym rdzeniem. Zwraca [albedo, normal].
static func wound(seed_: int) -> Array:
	var w := 128
	var h := 64
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.frequency = 0.07
	noise.fractal_octaves = 3
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var hgt := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var n := noise.get_noise_2d(x, y)
			var prof := pow(maxf(1.0 - u * u, 0.0), 0.6)
			var half := 0.6 * prof + 0.02
			var d := absf(v + n * 0.22) / maxf(half, 0.001)
			var smear := (1.0 - smoothstep(0.55, 1.0, d)) * clampf(0.75 + n, 0.0, 1.0)
			var core := 1.0 - smoothstep(0.1, 0.32, d)
			var col := Color(0.42, 0.03, 0.03).lerp(Color(0.05, 0.0, 0.0), core)
			col.a = clampf(smear + core, 0.0, 1.0)
			img.set_pixel(x, y, col)
			var hh := 0.5 + (smear - core) * 0.35 - core * 0.3
			hgt.set_pixel(x, y, Color(hh, hh, hh, 1.0))
	img.generate_mipmaps()
	hgt.bump_map_to_normal_map(5.0)
	hgt.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(hgt)]


## Miękka okrągła plamka do cząsteczek mgiełki.
static func soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Dziura po kuli: ciemny środek, osmalona obwódka, odpryski.
static func bullet_hole() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var spikes := []
	for i in 9:
		spikes.append([rng.randf() * TAU, rng.randf_range(0.5, 1.0)])
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5) / (n * 0.5)
			var r := p.length()
			var a := atan2(p.y, p.x)
			var sp := 0.0
			for s: Array in spikes:
				var da := absf(wrapf(a - float(s[0]), -PI, PI))
				sp = maxf(sp, float(s[1]) * exp(-da * da * 60.0))
			var rim := 0.45 + 0.4 * sp
			var col := Color(0.05, 0.045, 0.04, 1.0)
			if r < 0.22:
				col = Color(0.02, 0.02, 0.02, 1.0)
			elif r < rim:
				var k := (r - 0.22) / maxf(rim - 0.22, 0.01)
				col = Color(0.12, 0.11, 0.1, 1.0 - k * 0.8)
			else:
				col.a = 0.0
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
