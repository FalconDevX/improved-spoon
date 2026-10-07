extends Node3D
## Proceduralnie zbudowana postać. Pozę ustawia się punktami stawów
## (przestrzeń lokalna postaci, przód = -Z, prawo = +X).
## Każdy segment to jedna siatka (anatomiczne przekroje + organy wewnątrz),
## osobny hitbox, a po śmierci bryła ragdolla. Kończyny można odcinać:
## shader odrzuca część siatki za płaszczyzną cięcia, a w miejscu cięcia
## pojawia się przekrój (skóra, tłuszcz, mięsień, kość).

const BodyMesh = preload("res://scripts/body_mesh.gd")

const UARM := 0.29
const FARM := 0.27
const THIGH := 0.45
const SHIN := 0.44
const TORSO := 0.52
const HEAD := 0.33

const VIS_LAYER := 2
const HURT_LAYER := 8
const RAGDOLL_LAYER := 16

# segment: [punkt początkowy, punkt końcowy, masa]
const SEGMENTS := {
	"torso": ["pelvis", "neck", 26.0],
	"head": ["neck", "crown", 5.0],
	"uarm_l": ["shoulder_l", "elbow_l", 2.2],
	"farm_l": ["elbow_l", "hand_l", 1.6],
	"uarm_r": ["shoulder_r", "elbow_r", 2.2],
	"farm_r": ["elbow_r", "hand_r", 1.6],
	"thigh_l": ["hip_l", "knee_l", 8.0],
	"shin_l": ["knee_l", "ankle_l", 4.0],
	"thigh_r": ["hip_r", "knee_r", 8.0],
	"shin_r": ["knee_r", "ankle_r", 4.0],
}
const LENGTHS := {
	"torso": TORSO, "head": HEAD,
	"uarm_l": UARM, "farm_l": FARM, "uarm_r": UARM, "farm_r": FARM,
	"thigh_l": THIGH, "shin_l": SHIN, "thigh_r": THIGH, "shin_r": SHIN,
}
# rodzic, dziecko, zakres wychylenia (stopnie), zakres skrętu (stopnie)
const JOINTS := [
	["torso", "head", 30.0, 35.0],
	["torso", "uarm_l", 75.0, 30.0],
	["uarm_l", "farm_l", 65.0, 10.0],
	["torso", "uarm_r", 75.0, 30.0],
	["uarm_r", "farm_r", 65.0, 10.0],
	["torso", "thigh_l", 55.0, 15.0],
	["thigh_l", "shin_l", 60.0, 5.0],
	["torso", "thigh_r", 55.0, 15.0],
	["thigh_r", "shin_r", 60.0, 5.0],
]
const CHILDREN := {"uarm_l": ["farm_l"], "uarm_r": ["farm_r"], "thigh_l": ["shin_l"], "thigh_r": ["shin_r"]}
const SEVERABLE := ["head", "uarm_l", "farm_l", "uarm_r", "farm_r", "thigh_l", "shin_l", "thigh_r", "shin_r"]
const BONE_R := {"head": 0.016, "uarm_l": 0.015, "uarm_r": 0.015, "farm_l": 0.012, "farm_r": 0.012,
	"thigh_l": 0.02, "thigh_r": 0.02, "shin_l": 0.017, "shin_r": 0.017}

# Narządy: indeks = bit w organ_mask i część dziesiętna znacznika materiału (5.xx).
const ORGAN_IDS := ["heart", "lung_l", "lung_r", "liver", "stomach", "kidney_l", "kidney_r", "intestines",
	"spine", "aorta", "brain", "throat", "spine_neck", "femoral", "brachial",
	"spleen", "pancreas", "bladder", "subclavian", "eye", "jaw", "humerus", "biceps", "forearm", "radial",
	"femur", "quadriceps", "hamstring", "tibia", "popliteal", "achilles"]
# Strefy trafień (elipsoidy w przestrzeni segmentu). Dla kończyn x > 0 = strona wewnętrzna.
const ZONES := {
	"torso": [
		["heart", Vector3(-0.024, 0.32, -0.045), Vector3(0.045, 0.058, 0.045)],
		["lung_l", Vector3(-0.068, 0.36, 0.008), Vector3(0.066, 0.105, 0.074)],
		["lung_r", Vector3(0.068, 0.36, 0.008), Vector3(0.066, 0.105, 0.074)],
		["liver", Vector3(0.04, 0.235, -0.01), Vector3(0.085, 0.045, 0.068)],
		["stomach", Vector3(-0.06, 0.235, -0.03), Vector3(0.058, 0.045, 0.05)],
		["kidney_l", Vector3(-0.065, 0.17, 0.055), Vector3(0.028, 0.045, 0.025)],
		["kidney_r", Vector3(0.065, 0.17, 0.055), Vector3(0.028, 0.045, 0.025)],
		["intestines", Vector3(0.0, 0.1, -0.035), Vector3(0.115, 0.09, 0.06)],
		["aorta", Vector3(0.0, 0.2, 0.042), Vector3(0.016, 0.22, 0.016)],
		["spine", Vector3(0.0, 0.25, 0.075), Vector3(0.026, 0.3, 0.026)],
		["spleen", Vector3(-0.085, 0.24, 0.03), Vector3(0.032, 0.046, 0.036)],
		["pancreas", Vector3(0.0, 0.2, 0.015), Vector3(0.06, 0.016, 0.022)],
		["bladder", Vector3(0.0, -0.03, -0.05), Vector3(0.036, 0.034, 0.032)],
		["subclavian", Vector3(-0.07, 0.45, -0.02), Vector3(0.05, 0.018, 0.02)],
		["subclavian", Vector3(0.07, 0.45, -0.02), Vector3(0.05, 0.018, 0.02)],
	],
	"head": [
		["brain", Vector3(0.0, 0.25, 0.008), Vector3(0.068, 0.065, 0.086)],
		["throat", Vector3(0.0, 0.05, -0.025), Vector3(0.04, 0.07, 0.03)],
		["spine_neck", Vector3(0.0, 0.05, 0.025), Vector3(0.02, 0.07, 0.02)],
		["eye", Vector3(-0.034, 0.212, -0.088), Vector3(0.016, 0.016, 0.016)],
		["eye", Vector3(0.034, 0.212, -0.088), Vector3(0.016, 0.016, 0.016)],
		["jaw", Vector3(0.0, 0.11, -0.045), Vector3(0.06, 0.03, 0.05)],
	],
	"thigh": [
		["femoral", Vector3(0.033, 0.17, -0.026), Vector3(0.022, 0.18, 0.022)],
		["femur", Vector3(0.0, 0.22, 0.0), Vector3(0.02, 0.23, 0.02)],
		["quadriceps", Vector3(0.0, 0.18, -0.04), Vector3(0.055, 0.14, 0.035)],
		["hamstring", Vector3(0.0, 0.24, 0.04), Vector3(0.05, 0.14, 0.032)],
	],
	"shin": [
		["popliteal", Vector3(0.0, 0.02, 0.028), Vector3(0.022, 0.05, 0.02)],
		["tibia", Vector3(0.0, 0.21, -0.01), Vector3(0.018, 0.21, 0.018)],
		["achilles", Vector3(0.0, 0.38, 0.025), Vector3(0.016, 0.06, 0.014)],
	],
	"uarm": [
		["brachial", Vector3(0.03, 0.15, -0.012), Vector3(0.02, 0.13, 0.02)],
		["humerus", Vector3(0.0, 0.145, 0.0), Vector3(0.016, 0.15, 0.016)],
		["biceps", Vector3(0.0, 0.14, -0.03), Vector3(0.03, 0.08, 0.022)],
	],
	"farm": [
		["forearm", Vector3(0.0, 0.13, 0.0), Vector3(0.022, 0.12, 0.014)],
		["radial", Vector3(0.01, 0.23, -0.02), Vector3(0.016, 0.05, 0.015)],
	],
}

const FLESH := Color(0.56, 0.08, 0.08)
const FLESH_DARK := Color(0.42, 0.04, 0.05)
const FAT := Color(0.86, 0.76, 0.52)
const BONE := Color(0.9, 0.86, 0.76)
const MARROW := Color(0.6, 0.2, 0.14)

const BODY_SHADER := """
shader_type spatial;
render_mode cull_disabled;

instance uniform vec4 clip_plane = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform int organ_mask = 0;
global uniform float xray;

varying vec3 lp;
varying vec2 info;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX;
	info = UV;
	COLOR.rgb = pow(COLOR.rgb, vec3(2.2));
}

void fragment() {
	if (dot(lp, clip_plane.xyz) > clip_plane.w) {
		discard;
	}
	int m = int(info.y + 0.001);
	int organ = int(round((info.y - float(m)) * 100.0));
	vec3 alb = COLOR.rgb;
	float rough = COLOR.a;
	float metal = 0.0;
	if (m == 1) {
		// tkanina: przebarwienia, splot, delikatny meszek na krawędziach
		float n = noise(lp * 70.0) * 0.55 + noise(lp * 260.0) * 0.45;
		float fw = length(fwidth(lp));
		float weave = sin(lp.x * 1400.0 + lp.z * 1400.0) * sin(lp.y * 1400.0);
		weave *= 1.0 - smoothstep(0.0004, 0.0015, fw);
		alb *= 0.84 + 0.26 * n + 0.06 * weave;
		RIM = 0.35;
		RIM_TINT = 0.6;
	} else if (m == 2) {
		// skóra wyprawiona: plamy, przetarcia, zmienny połysk
		float n = noise(lp * 40.0) * 0.6 + noise(lp * 240.0) * 0.4;
		alb *= 0.72 + 0.45 * n;
		rough = clamp(rough - 0.18 + 0.32 * n, 0.2, 0.9);
	} else if (m == 3) {
		// włosy: pasma
		float st = noise(vec3(lp.x * 500.0, lp.y * 25.0, lp.z * 500.0));
		alb *= 0.65 + 0.55 * st;
		rough = 0.4 + 0.25 * st;
	} else if (m == 4) {
		metal = 0.9;
		rough = 0.3 + 0.1 * noise(lp * 300.0);
	} else if (m == 0) {
		// skóra: lekkie zaczerwienienia i pory
		float n = noise(lp * 30.0);
		alb *= vec3(1.0 + 0.07 * (n - 0.5), 1.0 - 0.05 * n, 1.0 - 0.05 * n);
		rough = clamp(rough + 0.1 * (noise(lp * 500.0) - 0.5), 0.2, 0.8);
	}
	if (xray > 0.5) {
		if (m < 5) {
			// rentgen: ciało półprzezroczyste (rastrowo), chłodna poświata konturu
			vec2 fc = floor(FRAGCOORD.xy);
			if (mod(fc.x + fc.y * 2.0, 4.0) > 0.5) {
				discard;
			}
			float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
			ALBEDO = vec3(0.02, 0.05, 0.08);
			EMISSION = vec3(0.15, 0.45, 0.8) * (0.3 + fres * 2.0);
			ROUGHNESS = 1.0;
		} else {
			ALBEDO = alb;
			EMISSION = alb * (m == 6 ? 0.7 : 1.3);
			if (m == 5 && ((organ_mask >> organ) & 1) == 1) {
				// trafiony narząd pulsuje
				EMISSION = mix(vec3(1.0, 0.08, 0.04), vec3(1.0, 0.85, 0.7), 0.5 + 0.5 * sin(TIME * 8.0)) * 2.5;
			}
			ROUGHNESS = 0.5;
		}
		SSS_STRENGTH = 0.0;
	} else if (FRONT_FACING) {
		ALBEDO = alb;
		ROUGHNESS = rough;
		METALLIC = metal;
		SSS_STRENGTH = info.x;
	} else {
		bool cut_open = dot(clip_plane.xyz, clip_plane.xyz) > 0.5;
		if (cut_open || m == 0) {
			// wnętrze ciała widoczne przez przecięcie
			ALBEDO = vec3(0.16, 0.012, 0.015);
			ROUGHNESS = 0.3;
		} else {
			// wewnętrzna strona ubrania (np. pod rąbkiem)
			ALBEDO = alb * 0.4;
			ROUGHNESS = 0.95;
		}
		SSS_STRENGTH = 0.0;
	}
}
"""

static var _body_mat: ShaderMaterial
static var _cap_mat: StandardMaterial3D

var segs: Dictionary = {}
var meshes: Dictionary = {}
var profiles: Dictionary = {}
var cap_skin: Dictionary = {}
var rag_bodies: Dictionary = {}
var cut: Dictionary = {}
var detached: Dictionary = {}
var ragdolled := false

var _areas: Dictionary = {}
var _joints: Dictionary = {}
var _skin := Color()
var _tags: Dictionary = {}
var _organ_masks: Dictionary = {}


# ---------------------------------------------------------------- matematyka

## Baza z osią Y wzdłuż kości; Z możliwie zgodne z ref_z (kontrola skrętu).
static func basis_from_y(y: Vector3, ref_z: Vector3) -> Basis:
	var yn := y.normalized()
	var z := ref_z - yn * ref_z.dot(yn)
	if z.length_squared() < 0.0004:
		var alt := Vector3.RIGHT if absf(yn.x) < 0.9 else Vector3.FORWARD
		z = alt.cross(yn)
	z = z.normalized()
	return Basis(yn.cross(z), yn, z)


## Analityczne IK dwóch kości. Zwraca [staw środkowy, koniec].
static func ik(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := target - root
	var dir := d.normalized() if d.length_squared() > 1e-8 else Vector3.DOWN
	var dist := clampf(d.length(), 0.05, l1 + l2 - 0.002)
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pd := pole - dir * pole.dot(dir)
	if pd.length_squared() < 1e-6:
		pd = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP)
	pd = pd.normalized()
	return [root + dir * a + pd * h, root + dir * dist]


## Kształt kolizji segmentu: (środek wzdłuż Y, promień, wysokość kapsuły).
static func shape_params(seg: String) -> Vector3:
	var l: float = LENGTHS[seg]
	if seg == "torso":
		return Vector3(0.25, 0.17, 0.72)
	if seg == "head":
		return Vector3(0.2, 0.115, 0.34)
	if seg.begins_with("uarm"):
		return Vector3(l * 0.5, 0.062, l + 0.06)
	if seg.begins_with("farm"):
		return Vector3(l * 0.5 + 0.04, 0.052, l + 0.14)
	if seg.begins_with("thigh"):
		return Vector3(l * 0.5, 0.085, l + 0.08)
	return Vector3(l * 0.5 + 0.03, 0.07, l + 0.12)


## Zakres kształtu po uwzględnieniu cięcia: [y_od, y_do].
func _shape_range(seg: String, keep_below: bool) -> Vector2:
	var prm := shape_params(seg)
	var lo := prm.x - prm.z * 0.5
	var hi := prm.x + prm.z * 0.5
	if cut.has(seg):
		var cy: float = cut[seg]
		if keep_below:
			hi = cy
		else:
			lo = cy
	return Vector2(lo, hi)


static func _material() -> ShaderMaterial:
	if _body_mat == null:
		var sh := Shader.new()
		sh.code = BODY_SHADER
		_body_mat = ShaderMaterial.new()
		_body_mat.shader = sh
		_cap_mat = StandardMaterial3D.new()
		_cap_mat.vertex_color_use_as_albedo = true
		_cap_mat.vertex_color_is_srgb = true
		_cap_mat.roughness = 0.18
		_cap_mat.subsurf_scatter_enabled = true
		_cap_mat.subsurf_scatter_strength = 0.15
	return _body_mat


# ---------------------------------------------------------------- budowa

func _c(col: Color, rough: float) -> Color:
	return Color(col.r, col.g, col.b, rough)


## Tabela [y, rx, rz, cx, cz, (kolor)] -> pierścienie dla loftu.
func _r(table: Array, col: Color, sx := 1.0, sz := 1.0) -> Array:
	var out: Array = []
	for row: Array in table:
		var cc: Color = row[5] if row.size() > 5 else col
		var sss := 0.35 if cc == _skin else 0.0
		out.append([row[0], float(row[1]) * sx, float(row[2]) * sz, row[3], row[4], cc, sss])
	return out


## Profil (rx, rz, cx, cz) segmentu na wysokości y — do rysowania przekroju.
func profile_at(seg: String, y: float) -> Vector4:
	var t: Array = profiles[seg]
	var i := 0
	while i < t.size() - 2 and float(t[i + 1][0]) < y:
		i += 1
	var a: Array = t[i]
	var b: Array = t[i + 1]
	var u := clampf((y - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-5), 0.0, 1.0)
	return Vector4(lerpf(a[1], b[1], u), lerpf(a[2], b[2], u), lerpf(a[3], b[3], u), lerpf(a[4], b[4], u))


func _tag(col: Color) -> float:
	return float(_tags.get(col, 0))


func _new_mesh() -> BodyMesh:
	var b := BodyMesh.new()
	b.tagger = _tag
	return b


## Pierścienie pikowania (przeszywanica): naprzemiennie szew i wypukły pas.
## puff = 0 i seam == col daje gładki materiał.
func _quilt(seg: String, y0: float, y1: float, step: float, col: Color, seam: Color, base: float, puff: float) -> Array:
	var out: Array = []
	var y := y0
	while y <= y1 + 0.0001:
		var p := profile_at(seg, y)
		out.append([y, p.x + base, p.y + base, p.z, p.w, seam, 0.0])
		var ym := minf(y + step * 0.5, y1)
		if ym > y + 0.001:
			var pm := profile_at(seg, ym)
			out.append([ym, pm.x + base + puff, pm.y + base + puff, pm.z, pm.w, col, 0.0])
		y += step
	return out


func build(look: Dictionary, hurtboxes: bool, owner_node: Node) -> void:
	_material()
	var bulk: float = look.get("bulk", 1.0)
	var garment: String = look.get("garment", "gambeson")
	var quilted := garment == "gambeson"
	_skin = _c(look.get("skin", Color(0.85, 0.66, 0.52)), 0.5)
	var skin := _skin
	var shirt_base: Color = look.get("shirt", Color(0.4, 0.15, 0.12))
	var shirt := _c(shirt_base, 0.92)
	var seam := _c(shirt_base.darkened(0.32), 0.95)
	var trim := _c(look.get("trim", shirt_base.darkened(0.5)), 0.85)
	var pants_base: Color = look.get("pants", Color(0.2, 0.18, 0.16))
	var pants := _c(pants_base, 0.9)
	var pants_d := _c(pants_base.darkened(0.3), 0.92)
	var hair := _c(look.get("hair", Color(0.15, 0.1, 0.07)), 0.7)
	var leather_base: Color = look.get("belt", Color(0.22, 0.14, 0.08))
	var leather := _c(leather_base, 0.5)
	var leather_d := _c(leather_base.darkened(0.35), 0.55)
	var boots_base: Color = look.get("boots", Color(0.14, 0.1, 0.07))
	var boots := _c(boots_base, 0.5)
	var boots_d := _c(boots_base.darkened(0.3), 0.6)
	var sole := _c(Color(0.06, 0.05, 0.045), 0.75)
	var hood_c := _c(look.get("hood_color", shirt_base.darkened(0.15).lerp(Color(0.35, 0.3, 0.24), 0.5)), 0.95)
	var brass := _c(Color(0.62, 0.5, 0.3), 0.3)
	var steel := _c(Color(0.55, 0.56, 0.58), 0.35)
	var eye_w := _c(Color(0.88, 0.86, 0.82), 0.2)
	var iris := _c(look.get("eyes", Color(0.25, 0.17, 0.1)), 0.1)
	var pupil := _c(Color(0.02, 0.02, 0.02), 0.05)
	var lips := _c(Color(skin.r, skin.g, skin.b).darkened(0.12).lerp(Color(0.62, 0.34, 0.32), 0.22), 0.4)
	var glove := leather_d if look.get("gloves", false) else skin
	_tags = {shirt: 1, seam: 1, trim: 1, pants: 1, pants_d: 1, hood_c: 1,
		leather: 2, leather_d: 2, boots: 2, boots_d: 2, sole: 2, hair: 3, brass: 4, steel: 4}
	_tags[eye_w] = 5.0 + ORGAN_IDS.find("eye") * 0.01

	for nm: String in SEGMENTS:
		var s := Node3D.new()
		s.name = nm
		add_child(s)
		segs[nm] = s

	var bx := bulk
	var bz := 0.5 + 0.5 * bulk

	# ---------------- tułów (początek = miednica)
	var torso_tab := [
		[-0.13, 0.0, 0.0, 0.0, 0.0, pants],
		[-0.12, 0.07, 0.06, 0.0, 0.0, pants],
		[-0.07, 0.15, 0.112, 0.0, 0.012, pants],
		[0.0, 0.176, 0.123, 0.0, 0.013, pants],
		[0.07, 0.164, 0.113, 0.0, 0.005, pants],
		[0.1, 0.158, 0.109, 0.0, 0.0, pants],
		[0.1, 0.158, 0.109, 0.0, 0.0, shirt],
		[0.17, 0.148, 0.104, 0.0, -0.006, shirt],
		[0.26, 0.157, 0.113, 0.0, -0.012, shirt],
		[0.34, 0.173, 0.123, 0.0, -0.014, shirt],
		[0.41, 0.186, 0.118, 0.0, -0.006, shirt],
		[0.46, 0.178, 0.1, 0.0, 0.008, shirt],
		[0.5, 0.115, 0.075, 0.0, 0.012, shirt],
		[0.53, 0.07, 0.062, 0.0, 0.012, shirt],
		[0.56, 0.062, 0.058, 0.0, 0.012, skin],
	]
	var tr := _r(torso_tab, shirt, bx, bz)
	profiles["torso"] = tr
	cap_skin["torso"] = shirt
	var tb := _new_mesh()
	var body_rings: Array = []
	for r: Array in tr:
		if float(r[0]) < 0.1:
			body_rings.append(r)
	body_rings.append_array(_quilt("torso", 0.1, 0.46, 0.036 if quilted else 0.06, shirt, seam if quilted else shirt, 0.003, 0.006 if quilted else 0.0))
	for r: Array in tr:
		if float(r[0]) > 0.47:
			body_rings.append(r)
	tb.loft(body_rings, Transform3D.IDENTITY, true, false, 24)

	# poła (przeszywanica dłuższa, tunika krótsza) — rozszerza się w dół
	var hem := -0.24 if quilted else -0.17
	var p0 := profile_at("torso", 0.0)
	var skirt: Array = []
	var ys: Array = []
	var yy := hem
	while yy < 0.075:
		ys.append(yy)
		yy += 0.035 if quilted else 0.05
	ys.append(0.075)
	for i in ys.size():
		var y: float = ys[i]
		var p := profile_at("torso", maxf(y, 0.0))
		var flare := maxf(-y, 0.0)
		var puff := 0.004 if (quilted and i % 2 == 1) else 0.0
		var col := seam if (quilted and i % 2 == 0) else shirt
		if i == 0:
			col = trim
		skirt.append([y, maxf(p.x, p0.x) + 0.01 + flare * 0.28 + puff, maxf(p.y, p0.y) + 0.01 + flare * 0.22 + puff, 0.0, p.w, col, 0.0])
	tb.loft(skirt, Transform3D.IDENTITY, false, false, 24)

	# stójka
	var collar: Array = []
	for row in [[0.49, 0.002], [0.5, 0.009], [0.55, 0.012], [0.59, 0.011], [0.595, 0.006]]:
		var p := profile_at("torso", minf(row[0], 0.56))
		collar.append([row[0], p.x + float(row[1]), p.y + float(row[1]), p.z, p.w, trim, 0.0])
	tb.loft(collar, Transform3D.IDENTITY, false, false, 22)

	# sznurowanie pod szyją
	var lace := PackedVector3Array()
	for q in 9:
		var y := 0.38 + q * 0.014
		var p := profile_at("torso", y)
		lace.append(Vector3(0.011 if q % 2 == 0 else -0.011, y, p.w - p.y - 0.011))
	tb.tube(lace, 0.0028, leather_d, 0.0, 5)

	# pas, klamra, sakiewka, nóż
	var belt: Array = []
	for y in [0.07, 0.075, 0.125, 0.13]:
		var p := profile_at("torso", y)
		var g := 0.006 if (y == 0.07 or y == 0.13) else 0.014
		belt.append([y, p.x + g, p.y + g, p.z, p.w, leather, 0.0])
	tb.loft(belt, Transform3D.IDENTITY, false, false, 24)
	var pb := profile_at("torso", 0.1)
	var front := pb.w - pb.y - 0.016
	tb.ellipsoid(Vector3(0, 0.1, front), Vector3(0.028, 0.024, 0.006), brass, 0.0, Transform3D.IDENTITY, 12, 6)
	tb.ellipsoid(Vector3(0, 0.1, front - 0.004), Vector3(0.018, 0.015, 0.004), leather, 0.0, Transform3D.IDENTITY, 10, 5)
	var px := pb.x * 0.72
	var pz := pb.w - pb.y * 0.72
	tb.ellipsoid(Vector3(px, 0.035, pz - 0.012), Vector3(0.045, 0.052, 0.03), leather, 0.0, Transform3D.IDENTITY, 12, 7)
	tb.ellipsoid(Vector3(px, 0.07, pz - 0.016), Vector3(0.047, 0.018, 0.031), leather_d, 0.0, Transform3D.IDENTITY, 12, 5)
	tb.ellipsoid(Vector3(px, 0.058, pz - 0.046), Vector3(0.006, 0.006, 0.004), brass)
	var sx := -pb.x - 0.012
	tb.tube(PackedVector3Array([Vector3(sx, 0.095, 0.0), Vector3(sx - 0.006, 0.0, 0.012), Vector3(sx - 0.012, -0.12, 0.024), Vector3(sx - 0.013, -0.135, 0.026)]), 0.014, leather_d, 0.0, 8)
	tb.tube(PackedVector3Array([Vector3(sx, 0.095, 0.0), Vector3(sx + 0.002, 0.15, -0.006), Vector3(sx + 0.003, 0.165, -0.008)]), 0.011, leather, 0.0, 8)
	tb.ellipsoid(Vector3(sx + 0.003, 0.172, -0.008), Vector3(0.014, 0.01, 0.014), steel)

	# pas przez pierś
	if look.get("strap", true):
		var strap := PackedVector3Array()
		for q in 33:
			var a := TAU * q / 32.0
			var y := 0.29 + 0.17 * sin(a + PI * 0.25)
			var p := profile_at("torso", y)
			var o := 0.012 if quilted else 0.008
			strap.append(Vector3(p.z + cos(a) * (p.x + o), y, p.w + sin(a) * (p.y + o)))
		tb.tube(strap, 0.02, leather, 0.0, 6, 0.22)

	# kaptur zsunięty na plecy
	if look.get("hood", false):
		var hood: Array = []
		for row in [[0.4, 0.202, 0.14, 0.008], [0.44, 0.198, 0.142, 0.012], [0.48, 0.162, 0.135, 0.022], [0.52, 0.118, 0.115, 0.032], [0.555, 0.09, 0.092, 0.036], [0.56, 0.082, 0.084, 0.036]]:
			hood.append([row[0], float(row[1]) * bx, float(row[2]) * bz, 0.0, row[3], hood_c, 0.0])
		tb.loft(hood, Transform3D.IDENTITY, false, false, 24)
		tb.ellipsoid(Vector3(0, 0.45, 0.125 * bz), Vector3(0.085, 0.08, 0.035), hood_c, 0.0, Transform3D.IDENTITY, 14, 7)
	_organs(tb)
	_finish("torso", tb)

	# ---------------- głowa (początek = podstawa szyi)
	var neck_tab := [
		[-0.03, 0.058, 0.062, 0.0, 0.006],
		[0.04, 0.054, 0.058, 0.0, 0.006],
		[0.1, 0.056, 0.062, 0.0, 0.0],
		[0.13, 0.05, 0.05, 0.0, -0.01],
	]
	var nr := _r(neck_tab, skin)
	profiles["head"] = nr
	cap_skin["head"] = skin
	var hb := _new_mesh()
	hb.loft(nr, Transform3D.IDENTITY, false, false, 18)
	var skull := [
		[0.075, 0.0, 0.0, 0.0, -0.045],
		[0.085, 0.03, 0.025, 0.0, -0.045],
		[0.1, 0.052, 0.06, 0.0, -0.03],
		[0.13, 0.066, 0.085, 0.0, -0.018],
		[0.165, 0.073, 0.098, 0.0, -0.008],
		[0.2, 0.078, 0.104, 0.0, 0.0],
		[0.24, 0.083, 0.106, 0.0, 0.006],
		[0.28, 0.08, 0.1, 0.0, 0.01],
		[0.31, 0.067, 0.085, 0.0, 0.012],
		[0.333, 0.04, 0.052, 0.0, 0.012],
		[0.343, 0.0, 0.0, 0.0, 0.012],
	]
	hb.loft(_r(skull, skin), Transform3D.IDENTITY, false, false, 22)
	var style: String = look.get("hair_style", "short")
	if look.get("bald", false):
		style = "bald"
	if style != "bald":
		hb.ellipsoid(Vector3(0, 0.252, 0.008), Vector3(0.087, 0.1, 0.108), hair, 0.0, Transform3D.IDENTITY, 20, 10)
	if style == "long":
		hb.ellipsoid(Vector3(0, 0.17, 0.05), Vector3(0.088, 0.12, 0.07), hair, 0.0, Transform3D.IDENTITY, 18, 9)
	elif style == "tied":
		hb.tube(PackedVector3Array([Vector3(0, 0.2, 0.105), Vector3(0, 0.15, 0.125), Vector3(0, 0.09, 0.12), Vector3(0, 0.05, 0.11)]), 0.017, hair, 0.0, 8)
		hb.ellipsoid(Vector3(0, 0.2, 0.108), Vector3(0.014, 0.012, 0.012), leather_d)
	for ex in [-1.0, 1.0]:
		var e := Vector3(0.034 * ex, 0.212, 0.0)
		hb.ellipsoid(e + Vector3(0, 0, -0.084), Vector3(0.0125, 0.011, 0.0125), eye_w, 0.0, Transform3D.IDENTITY, 12, 6)
		hb.ellipsoid(e + Vector3(0, 0, -0.0955), Vector3(0.0068, 0.0068, 0.003), iris, 0.0, Transform3D.IDENTITY, 10, 5)
		hb.ellipsoid(e + Vector3(0, 0, -0.0982), Vector3(0.003, 0.003, 0.0012), pupil, 0.0, Transform3D.IDENTITY, 8, 4)
		hb.ellipsoid(e + Vector3(0, 0.0065, -0.0835), Vector3(0.0155, 0.0065, 0.0132), skin, 0.35, Transform3D.IDENTITY, 12, 6)  # powieka górna
		hb.ellipsoid(e + Vector3(0, -0.0085, -0.0835), Vector3(0.0145, 0.0035, 0.0128), skin, 0.35, Transform3D.IDENTITY, 12, 5)  # powieka dolna
		hb.ellipsoid(Vector3(0.036 * ex, 0.234, -0.0885), Vector3(0.02, 0.004, 0.005), hair, 0.0, Transform3D.IDENTITY, 10, 5)
		hb.ellipsoid(Vector3(0.081 * ex, 0.2, 0.012), Vector3(0.011, 0.03, 0.02), skin, 0.35, Transform3D.IDENTITY, 10, 6)
	hb.ellipsoid(Vector3(0, 0.188, -0.102), Vector3(0.011, 0.024, 0.014), skin, 0.35, Transform3D.IDENTITY, 10, 6)
	hb.ellipsoid(Vector3(0, 0.168, -0.11), Vector3(0.014, 0.011, 0.012), skin, 0.35, Transform3D.IDENTITY, 10, 6)
	for ex in [-1.0, 1.0]:
		hb.ellipsoid(Vector3(0.009 * ex, 0.163, -0.107), Vector3(0.006, 0.005, 0.006), skin, 0.35, Transform3D.IDENTITY, 8, 4)  # skrzydełka nosa
	hb.ellipsoid(Vector3(0, 0.137, -0.097), Vector3(0.021, 0.005, 0.009), lips, 0.2, Transform3D.IDENTITY, 10, 4)
	var beard: String = look.get("beard_style", "full" if look.get("beard", false) else "none")
	if beard == "full":
		hb.ellipsoid(Vector3(0, 0.13, -0.018), Vector3(0.07, 0.056, 0.088), hair, 0.0, Transform3D.IDENTITY, 18, 8)
		hb.ellipsoid(Vector3(0, 0.148, -0.1), Vector3(0.03, 0.007, 0.01), hair, 0.0, Transform3D.IDENTITY, 10, 4)
	elif beard == "mustache":
		hb.ellipsoid(Vector3(0, 0.148, -0.101), Vector3(0.03, 0.007, 0.01), hair, 0.0, Transform3D.IDENTITY, 10, 4)
		hb.ellipsoid(Vector3(0, 0.1, -0.075), Vector3(0.016, 0.02, 0.012), hair, 0.0, Transform3D.IDENTITY, 10, 5)
	# kręgosłup szyjny (widoczny po dekapitacji)
	var neck_bone := _oc("spine_neck", BONE, 0.45)
	for k in 3:
		hb.ellipsoid(Vector3(0, 0.01 + k * 0.035, 0.025), Vector3(0.016, 0.014, 0.016), neck_bone)
	hb.tube(PackedVector3Array([Vector3(-0.055, 0.125, 0.0), Vector3(-0.045, 0.095, -0.055), Vector3(0, 0.088, -0.072), Vector3(0.045, 0.095, -0.055), Vector3(0.055, 0.125, 0.0)]), 0.008, _oc("jaw", BONE, 0.45), 0.0, 6)
	hb.ellipsoid(Vector3(0, 0.25, 0.008), Vector3(0.066, 0.062, 0.083), _oc("brain", Color(0.85, 0.62, 0.6), 0.45), 0.2)
	var throat := _oc("throat", Color(0.85, 0.68, 0.62), 0.35)
	var carotid := _oc("throat", Color(0.8, 0.08, 0.08), 0.3)
	hb.tube(PackedVector3Array([Vector3(0, -0.02, -0.03), Vector3(0, 0.06, -0.032), Vector3(0, 0.12, -0.028)]), 0.011, throat, 0.0, 8)
	for cx in [-0.025, 0.025]:
		hb.tube(PackedVector3Array([Vector3(cx, -0.02, -0.016), Vector3(cx, 0.06, -0.018), Vector3(cx * 0.9, 0.13, -0.02)]), 0.005, carotid, 0.0, 6)
	_finish("head", hb)

	# ---------------- kończyny
	var uarm_tab := [
		[-0.04, 0.05, 0.05, 0.0, 0.0], [0.0, 0.066, 0.062, 0.0, 0.0], [0.05, 0.063, 0.06, 0.0, -0.002],
		[0.12, 0.053, 0.057, 0.0, -0.006], [0.2, 0.046, 0.048, 0.0, -0.002], [0.27, 0.043, 0.041, 0.0, 0.0],
		[0.31, 0.04, 0.039, 0.0, 0.0],
	]
	var farm_tab := [
		[-0.03, 0.043, 0.041, 0.0, 0.0, shirt], [0.03, 0.049, 0.046, 0.0, 0.0, shirt], [0.06, 0.049, 0.046, 0.0, 0.0, shirt],
		[0.06, 0.044, 0.042, 0.0, 0.0, skin], [0.12, 0.044, 0.04, 0.0, -0.002, skin], [0.2, 0.035, 0.029, 0.0, 0.0, skin],
		[0.26, 0.029, 0.021, 0.0, 0.0, skin], [0.275, 0.027, 0.02, 0.0, 0.0, skin],
	]
	var thigh_tab := [
		[-0.04, 0.085, 0.085, 0.0, 0.0], [0.02, 0.09, 0.092, 0.0, 0.0], [0.1, 0.085, 0.086, 0.0, -0.008],
		[0.2, 0.075, 0.076, 0.0, -0.006], [0.32, 0.063, 0.063, 0.0, 0.0], [0.41, 0.055, 0.057, 0.0, 0.0],
		[0.47, 0.052, 0.054, 0.0, 0.0],
	]
	var shin_tab := [
		[-0.03, 0.053, 0.056, 0.0, 0.0], [0.03, 0.051, 0.054, 0.0, 0.004], [0.1, 0.053, 0.062, 0.0, 0.012],
		[0.18, 0.048, 0.054, 0.0, 0.009], [0.28, 0.038, 0.04, 0.0, 0.003], [0.38, 0.032, 0.034, 0.0, 0.0],
		[0.44, 0.03, 0.032, 0.0, 0.0],
	]
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var sfx := "_l" if i == 0 else "_r"
		# ramię (rękaw pikowany lub gładki)
		var ub := _new_mesh()
		var ur := _r(uarm_tab, shirt, bulk, bulk)
		profiles["uarm" + sfx] = ur
		cap_skin["uarm" + sfx] = shirt
		var arm_rings: Array = [ur[0]]
		arm_rings.append_array(_quilt("uarm" + sfx, 0.0, 0.28, 0.045 if quilted else 0.07, shirt, seam if quilted else shirt, 0.002, 0.005 if quilted else 0.0))
		arm_rings.append(ur[ur.size() - 1])
		ub.loft(arm_rings, Transform3D.IDENTITY, true, true, 18)
		ub.tube(PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, UARM * 0.5, 0.003), Vector3(0, UARM, 0)]), 0.012, _oc("humerus", BONE, 0.45), 0.0, 6)
		ub.ellipsoid(Vector3(0, 0.14, -0.026), Vector3(0.025, 0.07, 0.02), _oc("biceps", Color(0.55, 0.12, 0.12), 0.4), 0.2, Transform3D.IDENTITY, 10, 6)
		ub.tube(PackedVector3Array([Vector3(s * 0.03, 0.02, -0.012), Vector3(s * 0.033, 0.15, -0.014), Vector3(s * 0.03, 0.27, -0.012)]), 0.005, _oc("brachial", Color(0.8, 0.08, 0.08), 0.3), 0.0, 6)
		if look.get("pauldrons", false):
			ub.ellipsoid(Vector3(0.006 * s, 0.035, 0.0), Vector3(0.085, 0.08, 0.08) * bulk, leather, 0.0, Transform3D.IDENTITY, 16, 8)
			ub.ellipsoid(Vector3(0.006 * s, 0.08, 0.0), Vector3(0.078, 0.03, 0.074) * bulk, leather_d, 0.0, Transform3D.IDENTITY, 16, 6)
			for k in 3:
				var a := -0.9 + k * 0.9
				ub.ellipsoid(Vector3(sin(a) * 0.084 * bulk, 0.045, -cos(a) * 0.079 * bulk), Vector3(0.006, 0.006, 0.006), brass)
		_finish("uarm" + sfx, ub)
		# przedramię + mankiet + karwasz + dłoń
		var fb := _new_mesh()
		var fr := _r(farm_tab, skin, bulk, bulk)
		fb.loft(fr, Transform3D.IDENTITY, true, false, 18)
		profiles["farm" + sfx] = fr
		cap_skin["farm" + sfx] = skin
		for bxo in [-0.01, 0.01]:
			fb.tube(PackedVector3Array([Vector3(bxo, 0.02, 0.0), Vector3(bxo * 0.8, 0.13, 0.0), Vector3(bxo, 0.25, 0.0)]), 0.008, _oc("forearm", BONE, 0.45), 0.0, 6)
		fb.tube(PackedVector3Array([Vector3(s * 0.008, 0.15, -0.02), Vector3(s * 0.01, 0.26, -0.017)]), 0.004, _oc("radial", Color(0.8, 0.08, 0.08), 0.3), 0.0, 6)
		var cuff := []
		for row in [[0.035, 0.05, 0.047], [0.04, 0.056, 0.053], [0.07, 0.055, 0.052], [0.075, 0.046, 0.044]]:
			cuff.append([row[0], row[1] * bulk, row[2] * bulk, 0.0, 0.0, trim, 0.0])
		fb.loft(cuff, Transform3D.IDENTITY, false, false, 18)
		var bracer := []
		for row in [[0.13, 0.046, 0.042], [0.14, 0.048, 0.044], [0.23, 0.039, 0.032], [0.24, 0.036, 0.03]]:
			bracer.append([row[0], row[1] * bulk, row[2] * bulk, 0.0, 0.0, leather, 0.0])
		fb.loft(bracer, Transform3D.IDENTITY, false, false, 18)
		for k in 3:  # rzemienie karwasza
			var y := 0.155 + k * 0.032
			var p := profile_at("farm" + sfx, y)
			var rr := []
			for row in [[y - 0.005, 0.0], [y - 0.004, 0.006], [y + 0.004, 0.006], [y + 0.005, 0.0]]:
				var w := (0.048 - (y - 0.13) * 0.11) * bulk + float(row[1])
				rr.append([row[0], w, w * 0.9, p.z, p.w, leather_d, 0.0])
			fb.loft(rr, Transform3D.IDENTITY, false, false, 16)
		var hand := [
			[0.262, 0.02, 0.028, 0.0, 0.0], [0.29, 0.022, 0.042, 0.0, 0.0], [0.33, 0.021, 0.045, 0.0, -0.002],
			[0.36, 0.019, 0.042, 0.006 * s, -0.002], [0.385, 0.014, 0.032, 0.014 * s, 0.0], [0.395, 0.006, 0.016, 0.019 * s, 0.0],
		]
		fb.loft(_r(hand, glove), Transform3D.IDENTITY, false, true, 14)
		fb.ellipsoid(Vector3(0.007 * s, 0.305, -0.042), Vector3(0.011, 0.027, 0.012), glove, 0.35 if glove == skin else 0.0, Transform3D.IDENTITY, 10, 6)
		for k in 4:  # kostki palców
			fb.ellipsoid(Vector3(0.0, 0.36, -0.03 + k * 0.02), Vector3(0.016, 0.01, 0.009), glove, 0.35 if glove == skin else 0.0, Transform3D.IDENTITY, 8, 4)
		_finish("farm" + sfx, fb)
		# udo (spodnie ze szwem bocznym)
		var thb := _new_mesh()
		var thr := _r(thigh_tab, pants, bulk, bulk)
		thb.loft(thr, Transform3D.IDENTITY, true, true, 18)
		profiles["thigh" + sfx] = thr
		cap_skin["thigh" + sfx] = pants
		thb.tube(PackedVector3Array([Vector3(0, 0.0, 0.005), Vector3(0, 0.22, 0.0), Vector3(0, 0.44, 0.0)]), 0.016, _oc("femur", BONE, 0.45), 0.0, 6)
		thb.ellipsoid(Vector3(0, 0.18, -0.035), Vector3(0.05, 0.13, 0.03), _oc("quadriceps", Color(0.55, 0.12, 0.12), 0.4), 0.2, Transform3D.IDENTITY, 12, 6)
		thb.ellipsoid(Vector3(0, 0.23, 0.035), Vector3(0.045, 0.13, 0.026), _oc("hamstring", Color(0.5, 0.1, 0.11), 0.4), 0.2, Transform3D.IDENTITY, 12, 6)
		thb.tube(PackedVector3Array([Vector3(s * 0.035, 0.0, -0.03), Vector3(s * 0.034, 0.17, -0.027), Vector3(s * 0.03, 0.36, -0.018)]), 0.006, _oc("femoral", Color(0.8, 0.08, 0.08), 0.3), 0.0, 6)
		var side_seam := PackedVector3Array()
		for q in 8:
			var y := q * 0.06
			var p := profile_at("thigh" + sfx, y)
			side_seam.append(Vector3(-(p.x + 0.001), y, p.w))
		thb.tube(side_seam, 0.0025, pants_d, 0.0, 4)
		_finish("thigh" + sfx, thb)
		# goleń: spodnie z fałdami, but z wywiniętą cholewą, podeszwa i obcas
		var shb := _new_mesh()
		var shr := _r(shin_tab, pants, bulk, bulk)
		profiles["shin" + sfx] = shr
		cap_skin["shin" + sfx] = pants
		var leg_rings: Array = []
		for r: Array in shr:
			if float(r[0]) < 0.12:
				leg_rings.append(r)
		leg_rings.append_array(_quilt("shin" + sfx, 0.12, 0.22, 0.033, pants, pants_d, 0.0, 0.006))
		for r: Array in shr:
			if float(r[0]) > 0.22:
				leg_rings.append(r)
		shb.loft(leg_rings, Transform3D.IDENTITY, true, true, 18)
		shb.tube(PackedVector3Array([Vector3(0, 0.01, -0.01), Vector3(0, 0.22, -0.008), Vector3(0, 0.42, -0.005)]), 0.013, _oc("tibia", BONE, 0.45), 0.0, 6)
		shb.tube(PackedVector3Array([Vector3(0, -0.03, 0.025), Vector3(0, 0.08, 0.02)]), 0.005, _oc("popliteal", Color(0.8, 0.08, 0.08), 0.3), 0.0, 6)
		shb.tube(PackedVector3Array([Vector3(0, 0.32, 0.022), Vector3(0, 0.43, 0.022)]), 0.006, _oc("achilles", Color(0.9, 0.86, 0.76), 0.35), 0.0, 6)
		shb.tube(PackedVector3Array([Vector3(-s * 0.025, 0.03, 0.01), Vector3(-s * 0.024, 0.22, 0.01), Vector3(-s * 0.02, 0.4, 0.008)]), 0.007, _bc(), 0.0, 6)
		var boot := []
		for row in [[0.19, 0.06, 0.066, 0.008, boots_d], [0.2, 0.066, 0.072, 0.008, boots_d], [0.245, 0.064, 0.07, 0.008, boots_d],
				[0.245, 0.057, 0.063, 0.008, boots], [0.32, 0.047, 0.05, 0.004, boots], [0.4, 0.042, 0.046, 0.0, boots], [0.45, 0.043, 0.047, 0.0, boots]]:
			boot.append([row[0], float(row[1]) * bulk, float(row[2]) * bulk, 0.0, row[3], row[4], 0.0])
		shb.loft(boot, Transform3D.IDENTITY, true, false, 18)
		var foot := [
			[-0.07, 0.0, 0.0, 0.0, -0.005], [-0.065, 0.028, 0.03, 0.0, -0.005], [-0.04, 0.04, 0.042, 0.0, -0.005],
			[0.02, 0.044, 0.04, 0.0, 0.0], [0.09, 0.048, 0.03, 0.0, 0.01], [0.14, 0.045, 0.022, 0.0, 0.018],
			[0.175, 0.03, 0.016, 0.0, 0.02], [0.19, 0.0, 0.0, 0.0, 0.02],
		]
		var foot_xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, SHIN + 0.035, 0))
		shb.loft(_r(foot, boots), foot_xf, false, false, 16)
		var sole_rings: Array = []
		for row: Array in foot:
			var rz: float = row[2]
			sole_rings.append([row[0], float(row[1]) + 0.003 if float(row[1]) > 0.0 else 0.0, minf(rz, 0.009), 0.0, float(row[4]) + rz - 0.004, sole, 0.0])
		shb.loft(sole_rings, foot_xf, false, false, 16)
		shb.ellipsoid(Vector3(0, SHIN + 0.064, 0.035), Vector3(0.033, 0.012, 0.032), sole, 0.0, Transform3D.IDENTITY, 12, 5)  # obcas
		_finish("shin" + sfx, shb)

	if hurtboxes:
		for nm: String in SEGMENTS:
			var area := Area3D.new()
			area.collision_layer = HURT_LAYER
			area.collision_mask = 0
			area.monitoring = false
			area.set_meta("npc", owner_node)
			area.set_meta("seg", nm)
			var r := _shape_range(nm, true)
			area.add_child(_capsule(r, shape_params(nm).y))
			(segs[nm] as Node3D).add_child(area)
			_areas[nm] = area


## Kolor narządu z unikalnym znacznikiem (do rentgena i podświetlania trafień).
func _oc(organ: String, col: Color, rough: float) -> Color:
	var c := _c(col, rough)
	while _tags.has(c):
		c.a += 0.001
	_tags[c] = 5.0 + ORGAN_IDS.find(organ) * 0.01
	return c


func _bc() -> Color:
	var c := _c(BONE, 0.45)
	_tags[c] = 6.0
	return c


## Narządy przecięte przez ranę: linia od miejsca trafienia w głąb ciała.
func organs_hit(seg: String, p: Vector3, d: Vector3, depth: float) -> Array:
	var key := seg
	var side := 1.0
	if seg.ends_with("_l") or seg.ends_with("_r"):
		key = seg.substr(0, seg.length() - 2)
		side = -1.0 if seg.ends_with("_l") else 1.0
	var out: Array = []
	for z: Array in ZONES.get(key, []):
		var c: Vector3 = z[1]
		c.x *= side
		if cut.has(seg) and c.y > float(cut[seg]):
			continue
		var r: Vector3 = z[2]
		for k in 8:
			var q := (p + d * depth * k / 7.0 - c) / r
			if q.length_squared() <= 1.0:
				out.append(z[0])
				break
	return out


## Narządy na torze pocisku (analitycznie: odcinek kontra elipsoida powiększona o promień jamy rany).
## p, d: punkt wejścia i kierunek w przestrzeni segmentu, length: droga w segmencie.
## Zwraca [[narząd, odległość od wejścia], ...] posortowane wzdłuż toru.
func organs_path(seg: String, p: Vector3, d: Vector3, length: float, cavity: float) -> Array:
	var key := seg
	var side := 1.0
	if seg.ends_with("_l") or seg.ends_with("_r"):
		key = seg.substr(0, seg.length() - 2)
		side = -1.0 if seg.ends_with("_l") else 1.0
	var out: Array = []
	for z: Array in ZONES.get(key, []):
		var c: Vector3 = z[1]
		c.x *= side
		var r: Vector3 = (z[2] as Vector3) + Vector3.ONE * cavity
		var o := (p - c) / r
		var v := d / r
		var a := v.dot(v)
		var b := 2.0 * o.dot(v)
		var cc := o.dot(o) - 1.0
		var disc := b * b - 4.0 * a * cc
		if disc < 0.0 or a < 1e-9:
			continue
		var sq := sqrt(disc)
		var t0 := (-b - sq) / (2.0 * a)
		var t1 := (-b + sq) / (2.0 * a)
		if t1 < 0.0 or t0 > length:
			continue
		out.append([z[0], maxf(t0, 0.0)])
	out.sort_custom(func(x, y): return x[1] < y[1])
	return out


## Odcinek osi kapsuły trafień segmentu (przestrzeń segmentu) i promień: [y_od, y_do, promień].
func hit_capsule(seg: String) -> Vector3:
	var r := _shape_range(seg, true)
	return Vector3(r.x, r.y, shape_params(seg).y)


## Przecięcie promienia (przestrzeń świata) z kapsułą segmentu. Zwraca Vector2(t_wejścia, t_wyjścia)
## albo Vector2(-1, -1). dir musi być znormalizowany.
func ray_segment(seg: String, from: Vector3, dir: Vector3) -> Vector2:
	if not segs.has(seg) or (detached.has(seg) and not rag_bodies.has(seg)):
		return Vector2(-1, -1)
	var n: Node3D = segs[seg]
	var inv := n.global_transform.affine_inverse()
	var o := inv * from
	var d := (inv.basis * dir)
	var cap := hit_capsule(seg)
	var rad := cap.z
	var y0 := cap.x + rad
	var y1 := maxf(cap.y - rad, y0)
	var t_in := INF
	var t_out := -INF
	# walec (oś Y)
	var a := d.x * d.x + d.z * d.z
	if a > 1e-9:
		var b := 2.0 * (o.x * d.x + o.z * d.z)
		var c := o.x * o.x + o.z * o.z - rad * rad
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			for t in [(-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)]:
				var y: float = o.y + d.y * t
				if y >= y0 and y <= y1:
					t_in = minf(t_in, t)
					t_out = maxf(t_out, t)
	# półkule na końcach
	for cy in [y0, y1]:
		var oc := o - Vector3(0, cy, 0)
		var b := oc.dot(d)
		var c := oc.dot(oc) - rad * rad
		var disc := b * b - c
		if disc >= 0.0:
			var sq := sqrt(disc)
			for t in [-b - sq, -b + sq]:
				var y: float = o.y + d.y * t
				if (cy == y0 and y <= y0) or (cy == y1 and y >= y1):
					t_in = minf(t_in, t)
					t_out = maxf(t_out, t)
	if t_out < 0.0 or t_in == INF:
		return Vector2(-1, -1)
	return Vector2(maxf(t_in, 0.0), t_out)


func mark_organ(seg: String, organ: String) -> void:
	var bit := 1 << ORGAN_IDS.find(organ)
	var mask := int(_organ_masks.get(seg, 0)) | bit
	_organ_masks[seg] = mask
	(meshes[seg] as MeshInstance3D).set_instance_shader_parameter("organ_mask", mask)


## Uproszczone organy wewnętrzne tułowia (widoczne po przecięciu).
func _organs(b: BodyMesh) -> void:
	var bone := _bc()
	var spine := _oc("spine", BONE, 0.45)
	for k in 13:
		var y := -0.03 + k * 0.042
		var p := profile_at("torso", y)
		b.ellipsoid(Vector3(0, y, p.w + p.y * 0.68), Vector3(0.022, 0.016, 0.02), spine, 0.0, Transform3D.IDENTITY, 10, 5)
	for k in 6:
		var y0 := 0.25 + k * 0.04
		for s in [-1.0, 1.0]:
			var path := PackedVector3Array()
			for q in 13:
				var u := q / 12.0
				var a := lerpf(PI * 0.5 - 0.25, -PI * 0.5 + 0.5, u)
				var y := y0 - 0.035 * u
				var p := profile_at("torso", y)
				path.append(Vector3(s * cos(a) * p.x * 0.84, y, p.w + sin(a) * p.y * 0.84))
			b.tube(path, 0.007, bone, 0.0, 6)
	b.ellipsoid(Vector3(0, 0.36, -0.1), Vector3(0.016, 0.07, 0.008), bone)  # mostek
	b.ellipsoid(Vector3(-0.068, 0.36, 0.008), Vector3(0.062, 0.1, 0.07), _oc("lung_l", Color(0.8, 0.45, 0.47), 0.4), 0.3)
	b.ellipsoid(Vector3(0.068, 0.36, 0.008), Vector3(0.062, 0.1, 0.07), _oc("lung_r", Color(0.8, 0.45, 0.47), 0.4), 0.3)
	b.ellipsoid(Vector3(-0.024, 0.32, -0.045), Vector3(0.042, 0.055, 0.042), _oc("heart", Color(0.5, 0.05, 0.06), 0.3), 0.2)
	b.ellipsoid(Vector3(0.04, 0.235, -0.01), Vector3(0.082, 0.042, 0.065), _oc("liver", Color(0.38, 0.08, 0.06), 0.25))
	b.ellipsoid(Vector3(-0.06, 0.235, -0.03), Vector3(0.055, 0.042, 0.048), _oc("stomach", Color(0.8, 0.55, 0.5), 0.35), 0.3)
	b.ellipsoid(Vector3(-0.065, 0.17, 0.055), Vector3(0.024, 0.04, 0.02), _oc("kidney_l", Color(0.5, 0.13, 0.1), 0.3))
	b.ellipsoid(Vector3(0.065, 0.17, 0.055), Vector3(0.024, 0.04, 0.02), _oc("kidney_r", Color(0.5, 0.13, 0.1), 0.3))
	b.ellipsoid(Vector3(-0.085, 0.24, 0.03), Vector3(0.028, 0.042, 0.032), _oc("spleen", Color(0.45, 0.08, 0.14), 0.3))
	b.ellipsoid(Vector3(0.0, 0.2, 0.015), Vector3(0.055, 0.013, 0.018), _oc("pancreas", Color(0.88, 0.68, 0.48), 0.4), 0.2)
	b.ellipsoid(Vector3(0.0, -0.03, -0.05), Vector3(0.032, 0.03, 0.028), _oc("bladder", Color(0.86, 0.72, 0.6), 0.3), 0.2)
	var subc := _oc("subclavian", Color(0.8, 0.08, 0.08), 0.3)
	for sx in [-1.0, 1.0]:
		b.tube(PackedVector3Array([Vector3(0.01, 0.37, -0.01), Vector3(sx * 0.06, 0.45, -0.02), Vector3(sx * 0.13, 0.45, -0.02)]), 0.006, subc, 0.0, 6)
	var aorta := PackedVector3Array([Vector3(0, -0.02, 0.042), Vector3(0, 0.15, 0.044), Vector3(0, 0.3, 0.04), Vector3(0.01, 0.36, 0.0), Vector3(0.02, 0.33, -0.03)])
	b.tube(aorta, 0.011, _oc("aorta", Color(0.75, 0.08, 0.08), 0.3), 0.0, 8)
	# jelito grube (rama) i cienkie (zwoje)
	var colon := PackedVector3Array([Vector3(-0.1, 0.02, -0.02), Vector3(-0.105, 0.1, -0.03), Vector3(-0.1, 0.18, -0.04),
		Vector3(0.0, 0.19, -0.05), Vector3(0.1, 0.18, -0.04), Vector3(0.105, 0.1, -0.03), Vector3(0.09, 0.02, -0.02)])
	b.tube(colon, 0.022, _oc("intestines", Color(0.74, 0.47, 0.42), 0.3), 0.3, 8)
	var coil := PackedVector3Array()
	for q in 64:
		var u := q / 63.0
		var row := u * 4.0
		var y := 0.155 - floorf(row) * 0.03
		var dirx := 1.0 if int(floorf(row)) % 2 == 0 else -1.0
		var x := dirx * lerpf(-0.07, 0.07, row - floorf(row))
		coil.append(Vector3(x, y + sin(u * 40.0) * 0.008, -0.045 + cos(u * 25.0) * 0.015))
	b.tube(coil, 0.014, _oc("intestines", Color(0.86, 0.56, 0.52), 0.25), 0.3, 7)


func _finish(seg: String, b: BodyMesh) -> void:
	var m := b.commit()
	m.surface_set_material(0, _body_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.layers = VIS_LAYER
	(segs[seg] as Node3D).add_child(mi)
	meshes[seg] = mi


func _capsule(r: Vector2, radius: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(r.y - r.x, radius * 2.0)
	cs.shape = cap
	cs.position = Vector3(0, (r.x + r.y) * 0.5, 0)
	return cs


# ---------------------------------------------------------------- poza

## p: słownik punktów stawów. upper/head: bazy tułowia i głowy (kontrola skrętu).
func apply_pose(p: Dictionary, upper: Basis, head: Basis) -> void:
	if ragdolled:
		return
	for nm: String in SEGMENTS:
		if detached.has(nm):
			continue
		var d: Array = SEGMENTS[nm]
		var a: Vector3 = p[d[0]]
		var b: Vector3 = p[d[1]]
		var ref := upper.z
		if nm == "head":
			ref = head.z
		elif nm.begins_with("thigh") or nm.begins_with("shin"):
			ref = Vector3.BACK
		(segs[nm] as Node3D).transform = Transform3D(basis_from_y(b - a, ref), a)


# ---------------------------------------------------------------- odcinanie

func can_sever(seg: String) -> bool:
	return seg in SEVERABLE and not cut.has(seg) and not detached.has(seg)


## Przekrój w miejscu cięcia. facing +1: kikut (część poniżej cięcia), -1: odcięty kawałek.
func _add_cap(parent: Node3D, seg: String, y: float, facing: float, xf := Transform3D.IDENTITY) -> void:
	var p := profile_at(seg, y)
	var b := BodyMesh.new()
	var yy := y - facing * 0.0008
	var skin_c: Color = cap_skin[seg]
	if seg == "torso":
		b.disc(yy, p.x, p.y, p.z, p.w, [[0.76, FLESH], [0.92, FAT], [0.97, skin_c], [1.0, null]], facing)
		b.disc(yy + facing * 0.0004, 0.026, 0.022, 0.0, p.w + p.y * 0.68, [[0.0, MARROW], [0.45, BONE], [1.0, null]], facing)
	else:
		b.disc(yy, p.x, p.y, p.z, p.w, [[0.0, FLESH_DARK], [0.5, FLESH], [0.86, FAT], [0.93, skin_c], [1.0, null]], facing)
		var br: float = BONE_R[seg]
		var bz := p.w
		if seg == "head":
			bz = 0.025
			b.disc(yy + facing * 0.0004, 0.012, 0.01, 0.0, -0.035, [[0.0, Color(0.08, 0.0, 0.0)], [0.6, Color(0.85, 0.7, 0.65)], [1.0, null]], facing)
		b.disc(yy + facing * 0.0004, br, br, p.z, bz, [[0.0, MARROW], [0.45, BONE], [1.0, null]], facing)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = _cap_mat
	mi.layers = VIS_LAYER
	parent.add_child(mi)
	mi.transform = xf


func _set_area(seg: String, keep_below: bool) -> void:
	var area: Area3D = _areas.get(seg)
	if area == null or not is_instance_valid(area):
		return
	var r := _shape_range(seg, keep_below)
	if r.y - r.x < 0.05:
		area.queue_free()
		_areas.erase(seg)
		return
	for ch in area.get_children():
		ch.queue_free()
	area.add_child(_capsule(r, shape_params(seg).y))


func _free_area(seg: String) -> void:
	var area: Area3D = _areas.get(seg)
	if area and is_instance_valid(area):
		area.queue_free()
	_areas.erase(seg)


func _new_body(container: Node3D, xf: Transform3D, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = RAGDOLL_LAYER
	rb.collision_mask = 1
	rb.mass = mass
	rb.linear_damp = 0.15
	rb.angular_damp = 1.8
	container.add_child(rb)
	rb.global_transform = xf
	return rb


## Odcina segment na wysokości cut_y (w przestrzeni segmentu). Działa na żywej
## postaci i na ragdollu. Zwraca {piece, stump_marker, piece_marker}.
func sever(seg: String, cut_y: float, container: Node3D, impulse: Vector3) -> Dictionary:
	cut[seg] = cut_y
	var seg_node: Node3D = segs[seg]
	var mi: MeshInstance3D = meshes[seg]
	mi.set_instance_shader_parameter("clip_plane", Vector4(0, 1, 0, cut_y))
	_add_cap(seg_node, seg, cut_y, 1.0)
	_set_area(seg, true)

	var src_rb: RigidBody3D = rag_bodies.get(seg)
	if src_rb:
		for ch in src_rb.get_children():
			if ch is CollisionShape3D:
				ch.queue_free()
		src_rb.add_child(_capsule(_shape_range(seg, true), shape_params(seg).y))

	var rb := _new_body(container, seg_node.global_transform, float(SEGMENTS[seg][2]) * 0.6)
	var pm := MeshInstance3D.new()
	pm.mesh = mi.mesh
	pm.layers = VIS_LAYER
	rb.add_child(pm)
	pm.set_instance_shader_parameter("clip_plane", Vector4(0, -1, 0, -cut_y))
	_add_cap(rb, seg, cut_y, -1.0)
	rb.add_child(_capsule(_shape_range(seg, false), shape_params(seg).y))
	var mass := rb.mass
	for ch: String in CHILDREN.get(seg, []):
		detached[ch] = true
		_free_area(ch)
		var cn: Node3D = segs[ch]
		var crb: RigidBody3D = rag_bodies.get(ch)
		if crb:
			var jt: Joint3D = _joints.get(ch)
			if jt:
				jt.node_a = jt.get_path_to(rb)
		else:
			cn.reparent(rb)
			var cs := _capsule(_shape_range(ch, true), shape_params(ch).y)
			cs.transform = cn.transform * cs.transform
			rb.add_child(cs)
			mass += float(SEGMENTS[ch][2])
	rb.mass = mass
	if src_rb:
		rb.linear_velocity = src_rb.linear_velocity
		rb.angular_velocity = src_rb.angular_velocity
	rb.apply_impulse(impulse, rb.global_basis.y * cut_y * 0.5 + Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05)))
	rb.angular_velocity += Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))

	var sm := Node3D.new()
	seg_node.add_child(sm)
	sm.position = Vector3(0, cut_y, 0)
	var pmk := Node3D.new()
	rb.add_child(pmk)
	pmk.position = Vector3(0, cut_y, 0)
	pmk.rotation = Vector3(PI, 0, 0)  # +Y markera = na zewnątrz odciętego kawałka
	return {"piece": rb, "stump_marker": sm, "piece_marker": pmk}


# ---------------------------------------------------------------- ragdoll

## torso_cut > 0: tułów zostaje przecięty na pół na tej wysokości.
func make_ragdoll(impulse: Vector3, at: Vector3, hit_seg: String, container: Node3D, torso_cut := -1.0) -> Dictionary:
	var result := {}
	if ragdolled:
		return result
	ragdolled = true
	var total_mass := 0.0
	for nm: String in SEGMENTS:
		total_mass += float(SEGMENTS[nm][2])
	for nm: String in SEGMENTS:
		if detached.has(nm):
			continue
		var seg: Node3D = segs[nm]
		var rb := _new_body(container, seg.global_transform, SEGMENTS[nm][2])
		rb.add_child(_capsule(_shape_range(nm, true), shape_params(nm).y))
		seg.reparent(rb)
		rb.linear_velocity = impulse / total_mass * 0.6
		rag_bodies[nm] = rb

	var upper: RigidBody3D = null
	if torso_cut > 0.0:
		upper = _split_torso(torso_cut, container)
		result["upper"] = upper

	for j: Array in JOINTS:
		if detached.has(j[0]) or detached.has(j[1]):
			continue
		var a: RigidBody3D = rag_bodies[j[0]]
		if upper and j[0] == "torso" and j[1] in ["head", "uarm_l", "uarm_r"]:
			a = upper
		var b: RigidBody3D = rag_bodies[j[1]]
		var jt := ConeTwistJoint3D.new()
		container.add_child(jt)
		var bb := b.global_basis
		# oś X złącza wzdłuż kości dziecka
		jt.global_transform = Transform3D(Basis(bb.y, -bb.x, bb.z), b.global_position)
		jt.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(j[2]))
		jt.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(j[3]))
		jt.node_a = jt.get_path_to(a)
		jt.node_b = jt.get_path_to(b)
		_joints[j[1]] = jt

	if rag_bodies.has(hit_seg):
		var hm: float = SEGMENTS[hit_seg][2]
		push(hit_seg, (impulse * 0.4).limit_length(hm * 2.5), at)  # lekkie części nie wystrzeliwują
	var torso: RigidBody3D = rag_bodies["torso"]
	push("torso", impulse * (0.3 if upper else 0.6), torso.global_transform * Vector3(0, 0.3, 0))
	if upper:
		upper.apply_impulse(impulse * 0.45, upper.global_basis.y * 0.4)
	return result


func _split_torso(cy: float, container: Node3D) -> RigidBody3D:
	cut["torso"] = cy
	var lower: RigidBody3D = rag_bodies["torso"]
	var seg_node: Node3D = segs["torso"]
	var mi: MeshInstance3D = meshes["torso"]
	mi.set_instance_shader_parameter("clip_plane", Vector4(0, 1, 0, cy))
	_add_cap(seg_node, "torso", cy, 1.0)
	_set_area("torso", true)
	for ch in lower.get_children():
		if ch is CollisionShape3D:
			ch.queue_free()
	lower.add_child(_capsule(_shape_range("torso", true), 0.16))
	lower.mass = 26.0 * cy / TORSO + 4.0

	var upper := _new_body(container, lower.global_transform, maxf(26.0 - lower.mass, 6.0))
	var pm := MeshInstance3D.new()
	pm.mesh = mi.mesh
	pm.layers = VIS_LAYER
	upper.add_child(pm)
	pm.set_instance_shader_parameter("clip_plane", Vector4(0, -1, 0, -cy))
	_add_cap(upper, "torso", cy, -1.0)
	upper.add_child(_capsule(_shape_range("torso", false), 0.16))
	upper.linear_velocity = lower.linear_velocity
	return upper


func push(seg: String, impulse: Vector3, at: Vector3) -> void:
	var rb: RigidBody3D = rag_bodies.get(seg)
	if rb:
		rb.apply_impulse(impulse, at - rb.global_position)


func torso_position() -> Vector3:
	var node: Node3D = segs["torso"]
	return node.global_transform * Vector3(0, 0.25, 0)
