extends Node3D
## Trawa: kępy źdźbeł (trzy skrzyżowane płaty z teksturą rysowaną w kodzie) rozsiane po całej
## mapie poza drogami i budynkami. Wiatr kołysze czubkami, kolor zgadza się z podłożem. Mapa
## podzielona na sektory 24 × 24 m — rysowane tylko te blisko kamery (zanikają płynnie).

const CELL := 24.0
const STEP := 1.15          # średni odstęp kęp [m]
const VIS := 75.0           # zasięg widoczności sektora

const Level = preload("res://scripts/level.gd")

const SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform sampler2D blades : source_color, filter_linear_mipmap;
uniform float wind = 1.0;
varying vec3 wp;
varying float tipk;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	tipk = 1.0 - UV.y;
	// podmuchy: wolna fala przechodząca przez pole + drobne drżenie
	float gust = n2(base.xz * 0.05 + vec2(TIME * 0.35, TIME * 0.2));
	float sway = (sin(TIME * 2.1 + base.x * 0.7 + base.z * 0.4) * 0.5 + 0.5) * 0.35 + gust * 0.9;
	vec3 wdir = vec3(0.8, 0.0, 0.5);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * wdir) * sway * tipk * tipk * 0.28 * wind;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = mix(NORMAL, inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0), 0.7);
}
void fragment() {
	vec4 t = texture(blades, UV);
	if (t.a < 0.45) discard;
	float big = n2(wp.xz * 0.03) * 0.6 + n2(wp.xz * 0.11) * 0.4;
	vec3 grass = mix(vec3(0.15, 0.21, 0.08), vec3(0.29, 0.33, 0.13), big);
	grass = mix(grass, vec3(0.42, 0.38, 0.2), smoothstep(0.6, 0.8, n2(wp.xz * 0.5 + 7.0)) * 0.55);
	vec3 c = grass * (0.5 + 0.42 * tipk) * (0.8 + 0.35 * t.r);
	// zanikanie z odległością (bez nagłego znikania sektorów)
	float d = length(CAMERA_POSITION_WORLD - wp);
	if (h(floor(FRAGCOORD.xy)) > 1.0 - smoothstep(60.0, 72.0, d)) discard;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.25, 0.3, 0.1) * tipk;
}
"""


func build(level) -> void:
	var tex := _blade_texture()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("blades", tex)
	var mesh := _clump_mesh()
	mesh.surface_set_material(0, mat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var space := get_world_3d().direct_space_state
	var half: float = Level.HALF - 3.0
	var img: Image = level.road_img
	var n := int(ceil(half * 2.0 / CELL))
	for cx in n:
		for cz in n:
			var x0 := -half + cx * CELL
			var z0 := -half + cz * CELL
			var xf: Array[Transform3D] = []
			var gx := x0
			while gx < x0 + CELL:
				var gz := z0
				while gz < z0 + CELL:
					var p := Vector2(gx + rng.randf_range(0, STEP), gz + rng.randf_range(0, STEP))
					gz += STEP
					if absf(p.x) > half or absf(p.y) > half:
						continue
					var u := int((p.x + Level.HALF) / (Level.HALF * 2.0) * 256.0)
					var v := int((p.y + Level.HALF) / (Level.HALF * 2.0) * 256.0)
					if img.get_pixel(clampi(u, 0, 255), clampi(v, 0, 255)).r > 0.25:
						continue   # droga
					var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 9.0, p.y), Vector3(p.x, -0.5, p.y), 1)
					var r := space.intersect_ray(q)
					if r.is_empty() or r["collider"] != level.ground_body:
						continue   # budynek, mur, skrzynia
					var s := rng.randf_range(0.7, 1.3)
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.35), s))
					xf.append(Transform3D(b, Vector3(p.x, 0.0, p.y)))
				gx += STEP
			if xf.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xf.size()
			for i in xf.size():
				mm.set_instance_transform(i, xf[i])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = VIS + CELL * 0.75
			mi.custom_aabb = AABB(Vector3(x0, -0.5, z0), Vector3(CELL, 2.0, CELL))
			add_child(mi)


## Kępa: trzy pionowe płaty obrócone co 60°.
func _clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.32
	var hgt := 0.42
	for k in 3:
		var a := PI / 3.0 * k
		var d := Vector3(cos(a), 0, sin(a)) * w
		var nrm := Vector3(-sin(a), 0, cos(a))
		var v := [[-d, Vector2(0, 1)], [d, Vector2(1, 1)], [d + Vector3(0, hgt, 0), Vector2(1, 0)], [-d + Vector3(0, hgt, 0), Vector2(0, 0)]]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nrm)
			st.set_uv(v[i][1])
			st.add_vertex(v[i][0])
	return st.commit()


## Tekstura źdźbeł: zwężające się, lekko wygięte paski (kanał R = jasność źdźbła).
func _blade_texture() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for b in 16:
		var x0 := rng.randf_range(4.0, sz - 4.0)
		var bend := rng.randf_range(-10.0, 10.0)
		var top := rng.randf_range(0.0, sz * 0.45)
		var wd := rng.randf_range(1.6, 3.0)
		var shade := rng.randf_range(0.5, 1.0)
		for y in range(int(top), sz):
			var t := 1.0 - (y - top) / (sz - top)     # 0 u dołu, 1 na czubku
			var x := x0 + bend * t * t
			var hw := wd * (1.0 - t * 0.9)
			for xx in range(int(x - hw - 1), int(x + hw + 2)):
				if xx < 0 or xx >= sz:
					continue
				var a := clampf(hw + 0.5 - absf(xx - x), 0.0, 1.0)
				if a > img.get_pixel(xx, y).a:
					img.set_pixel(xx, y, Color(shade * (0.7 + 0.3 * t), 0, 0, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
