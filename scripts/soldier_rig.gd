extends Node3D
## Model żołnierza (szkielet Mixamo) sterowany warstwami:
##  1. nagrania ruchu (motion capture): stanie, chód, bieg, sprint, kucanie, skok, reakcje na trafienie,
##  2. biodra skręcone w stronę ruchu (chód bokiem / tyłem), tułów i głowa celują niezależnie,
##  3. broń trzymana proceduralnie: kolba w barku, IK obu rąk na chwycie i łożu, odrzut, przeładowanie,
##  4. sprężyny reakcji na trafienia.
## Żywy: kości wyznaczają pozycje części ciała postaci proceduralnej (hitboxy z narządami).
## Martwy / nieprzytomny: kości podążają sztywno za bryłami ragdolla.
## Przestrzeń postaci: przód -Z, prawo +X (węzeł rodzica obraca się w poziomie).

const Humanoid = preload("res://scripts/humanoid.gd")
const SCENE := preload("res://assets/characters/soldier.glb")
const LIB := preload("res://assets/anims/soldier_anims.res")
const PRE := "mixamorig_"

# część ciała ragdolla, za którą idzie kość
const SEG_OF := {
	"Hips": "torso", "Spine": "torso", "Spine1": "torso", "Spine2": "torso",
	"LeftShoulder": "torso", "RightShoulder": "torso", "Neck": "head", "Head": "head",
	"LeftArm": "uarm_l", "LeftForeArm": "farm_l", "LeftHand": "farm_l",
	"RightArm": "uarm_r", "RightForeArm": "farm_r", "RightHand": "farm_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "shin_l", "LeftFoot": "shin_l", "LeftToeBase": "shin_l",
	"RightUpLeg": "thigh_r", "RightLeg": "shin_r", "RightFoot": "shin_r", "RightToeBase": "shin_r",
}
const LOOPS := ["m_idle", "m_walk", "m_run", "walk", "jog", "sprint", "crouch_idle", "crouch_walk", "jump_loop", "idle"]

static var _shared := {}   # dane wspólne dla wszystkich instancji (klipy, długości kroków)

var skel: Skeleton3D
var model: Node3D
var body: Humanoid
var gun: Node3D             # broń (weapons.gd) albo null
var meshes: Array = []

var N := 0
var parent := PackedInt32Array()
var off: Array = []         # przesunięcie kości względem rodzica (m, w układzie rodzica)
var rc: Array = []          # spoczynkowy obrót globalny (przestrzeń postaci)
var rest_q: Array = []      # spoczynkowy obrót lokalny (szkielet)
var Kr := Basis()
var K := Transform3D()
var ks := 0.01
var bi := {}                # krótka nazwa -> indeks

var L: Array = []           # obroty lokalne (dla korzenia: w przestrzeni postaci)
var G: Array = []           # obroty globalne (postać)
var P: Array = []           # pozycje globalne (postać)
var hips_pos := Vector3.ZERO

# --- stan ustawiany przez właściciela co klatkę
var vel := Vector3.ZERO     # prędkość w przestrzeni postaci
var crouch := 0.0
var air := false
var aim_dir := Vector3.FORWARD   # kierunek celowania (postać)
var aim_w := 1.0            # 0 = broń w dół (gotowość), 1 = złożony do strzału
var reload_p := -1.0        # postęp przeładowania 0..1 (<0 = brak)
var reload_kind := "mag"    # "mag", "shell", "bolt", "pump"
var cycle_p := -1.0         # ruch zamka / czółenka po strzale
var sprint := false
var hide_head := false
var kneel := 0.0            # niesprawna noga: przyklęk
var limp_arm := {"_l": false, "_r": false}

var _phase := 0.0
var _idle_t := 0.0
var _leg_yaw := 0.0
var _back := 0.0
var _hit_clip := ""
var _hit_t := 9.0
var _recoil := 0.0
var _recoil_v := 0.0
var _recoil_side := 0.0
var _spring := Vector3.ZERO      # wychylenie tułowia od trafień (wektor obrotu)
var _spring_v := Vector3.ZERO
var _head_spring := Vector3.ZERO
var _head_spring_v := Vector3.ZERO
var _sway_t := 0.0
var _ragdoll := false
var _rag_off := {}
var _air_t := 0.0
var _jump_w := 0.0
var _crouch_s := 0.0
var _gun_xf := Transform3D()     # ostatnie położenie broni (postać)


func setup(tint: Color, b: Humanoid) -> void:
	body = b
	model = SCENE.instantiate() as Node3D
	add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	K = _rel(skel, self)
	Kr = K.basis.orthonormalized()
	ks = K.basis.get_scale().x
	N = skel.get_bone_count()
	parent.resize(N)
	for i in N:
		var nm := skel.get_bone_name(i).trim_prefix(PRE)
		bi[nm] = i
		parent[i] = skel.get_bone_parent(i)
		var r := skel.get_bone_rest(i)
		rest_q.append(r.basis.get_rotation_quaternion())
		off.append(r.origin * ks)
		rc.append((Kr * skel.get_bone_global_rest(i).basis.orthonormalized()).orthonormalized())
		L.append(Basis())
		G.append(Basis())
		P.append(Vector3.ZERO)
	hips_pos = skel.get_bone_rest(bi["Hips"]).origin
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 2
		meshes.append(mi)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is StandardMaterial3D:
				var mm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				mm.albedo_color = mm.albedo_color * tint
				mm.roughness = 0.75
				mi.set_surface_override_material(s, mm)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	for ap in aps:
		ap.queue_free()
	_load_clips()


static func _rel(n: Node, root: Node) -> Transform3D:
	var t := Transform3D()
	var c := n
	while c != root and c is Node3D:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


# ---------------------------------------------------------------- klipy

func _load_clips() -> void:
	if not _shared.is_empty():
		return
	var clips := {}
	for nm: String in LIB.get_animation_list():
		var a := LIB.get_animation(nm)
		var rt := PackedInt32Array()
		rt.resize(N)
		rt.fill(-1)
		var pt := -1
		for t in a.get_track_count():
			var bone := String(a.track_get_path(t).get_concatenated_subnames())
			var i := skel.find_bone(bone)
			if i < 0:
				continue
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				rt[i] = t
			elif a.track_get_type(t) == Animation.TYPE_POSITION_3D and i == bi["Hips"]:
				pt = t
		clips[nm] = {"a": a, "rt": rt, "pt": pt, "len": a.length, "stride": 0.0}
	_shared["clips"] = clips
	# długość kroku: ruch stopy względem bioder w cyklu (stopa w fazie podporu cofa się z prędkością marszu)
	for nm in ["m_walk", "m_run", "walk", "jog", "sprint", "crouch_walk"]:
		if not clips.has(nm):
			continue
		var c: Dictionary = clips[nm]
		var zmin := INF
		var zmax := -INF
		for k in 24:
			_sample_into(nm, float(c["len"]) * k / 24.0, true)
			_fk()
			var z := (P[bi["LeftFoot"]] as Vector3).z - (P[bi["Hips"]] as Vector3).z
			zmin = minf(zmin, z)
			zmax = maxf(zmax, z)
		c["stride"] = maxf((zmax - zmin) * 2.0, 0.6)


func _clips() -> Dictionary:
	return _shared["clips"]


## Próbka klipu: obroty lokalne do tablicy (bez mieszania).
func _sample(nm: String, t: float, loop: bool) -> Array:
	var c: Dictionary = _clips()[nm]
	var a: Animation = c["a"]
	var len: float = c["len"]
	var tt := fposmod(t, len) if loop else clampf(t, 0.0, len)
	var rt: PackedInt32Array = c["rt"]
	var out: Array = []
	out.resize(N + 1)
	for i in N:
		out[i] = a.rotation_track_interpolate(rt[i], tt) if rt[i] >= 0 else rest_q[i]
	var pt: int = c["pt"]
	out[N] = a.position_track_interpolate(pt, tt) if pt >= 0 else hips_pos
	return out


func _sample_into(nm: String, t: float, loop: bool) -> void:
	var s := _sample(nm, t, loop)
	_set_locals(s)


func _set_locals(s: Array) -> void:
	var h := bi["Hips"] as int
	for i in N:
		var q: Quaternion = s[i]
		L[i] = Kr * Basis(q) if i == h else Basis(q)
	hips_pos = s[N]


## Mieszanie póz: [[poza, waga], ...] -> poza (normalizowana suma kwaternionów).
static func _blend(list: Array, n: int) -> Array:
	var out: Array = []
	out.resize(n + 1)
	var tw := 0.0
	for e: Array in list:
		tw += float(e[1])
	if tw <= 0.0001:
		return (list[0] as Array)[0]
	var ref: Array = (list[0] as Array)[0]
	for i in n:
		var acc := Quaternion(0, 0, 0, 0)
		var r: Quaternion = ref[i]
		for e: Array in list:
			var w := float(e[1]) / tw
			if w <= 0.0:
				continue
			var q: Quaternion = (e[0] as Array)[i]
			if q.dot(r) < 0.0:
				q = -q
			acc += q * w
		out[i] = acc.normalized()
	var hp := Vector3.ZERO
	for e: Array in list:
		hp += ((e[0] as Array)[n] as Vector3) * float(e[1]) / tw
	out[n] = hp
	return out


## Mieszanie warstwy tylko na wybranych kościach (maska: indeks -> waga).
static func _overlay(base: Array, top: Array, mask: Dictionary, w: float) -> void:
	for i: int in mask:
		var a: Quaternion = base[i]
		var b: Quaternion = top[i]
		base[i] = a.slerp(b, float(mask[i]) * w)


# ---------------------------------------------------------------- kinematyka

func _fk() -> void:
	for i in N:
		var p := parent[i]
		if p < 0:
			G[i] = L[i]
			P[i] = K * hips_pos
		else:
			G[i] = (G[p] as Basis) * (L[i] as Basis)
			P[i] = (P[p] as Vector3) + (G[p] as Basis) * (off[i] as Vector3)


## Ustawia obrót globalny kości (postać) i przelicza poddrzewo.
func _set_global(i: int, g: Basis) -> void:
	var p := parent[i]
	L[i] = g if p < 0 else (G[p] as Basis).inverse() * g
	_fk_sub(i)


func _fk_sub(i: int) -> void:
	var p := parent[i]
	G[i] = L[i] if p < 0 else (G[p] as Basis) * (L[i] as Basis)
	if p >= 0:
		P[i] = (P[p] as Vector3) + (G[p] as Basis) * (off[i] as Vector3)
	for c in skel.get_bone_children(i):
		_fk_sub(c)


## Obrót globalny kości (przed-mnożenie), poddrzewo podąża.
func _rotate(i: int, q: Basis) -> void:
	_set_global(i, (q * (G[i] as Basis)).orthonormalized())


func _b(nm: String) -> int:
	return bi[nm]


func _dir(nm: String) -> Vector3:
	return (G[_b(nm)] as Basis) * (rc[_b(nm)] as Basis).inverse() * Vector3.FORWARD


static func _arc(a: Vector3, b: Vector3) -> Basis:
	var an := a.normalized()
	var bn := b.normalized()
	var d := an.dot(bn)
	if d > 0.99999:
		return Basis()
	if d < -0.9999:
		var ax := an.cross(Vector3.UP if absf(an.y) < 0.9 else Vector3.RIGHT).normalized()
		return Basis(ax, PI)
	return Basis(Quaternion(an, bn))


# ---------------------------------------------------------------- aktualizacja

func hit_react(dir_local: Vector3, seg: String, strength: float) -> void:
	var ax := Vector3.UP.cross(Vector3(dir_local.x, 0, dir_local.z).normalized())
	var k := clampf(strength, 0.1, 2.0)
	if seg == "head":
		_head_spring_v += ax * 9.0 * k
		_spring_v += ax * 2.0 * k
		_hit_clip = "hit_head"
	else:
		_spring_v += ax * 4.5 * k + Vector3(0, randf_range(-2, 2) * k, 0)
		_head_spring_v += ax * -2.5 * k
		_hit_clip = "hit_chest"
	_hit_t = 0.0


func kick(amount: float) -> void:
	_recoil_v += amount
	_recoil_side = randf_range(-1.0, 1.0)


func update(dt: float) -> void:
	if _ragdoll:
		_follow_ragdoll()
		_write()
		return
	var clips := _clips()
	_idle_t += dt
	_sway_t += dt
	_crouch_s = move_toward(_crouch_s, maxf(crouch, kneel), dt * 4.0)
	var spd := Vector2(vel.x, vel.z).length()
	# --- chód: kierunek ruchu względem przodu postaci
	var mw := clampf(spd / 0.7, 0.0, 1.0)
	var th := atan2(vel.x, -vel.z) if spd > 0.1 else 0.0
	var back_t := 1.0 if absf(th) > deg_to_rad(105.0) and spd > 0.1 else 0.0
	_back = move_toward(_back, back_t, dt * 5.0)
	var yaw_t := 0.0
	if spd > 0.1:
		yaw_t = clampf(wrapf(th - (PI if back_t > 0.5 else 0.0), -PI, PI), -1.2, 1.2)
	if sprint:
		yaw_t = 0.0
	_leg_yaw = lerp_angle(_leg_yaw, yaw_t * mw, 1.0 - exp(-8.0 * dt))
	# klipy wg prędkości
	var gset := []
	if _crouch_s > 0.5:
		gset = [["crouch_walk", 1.0]]
	elif spd > 4.6:
		gset = [["m_run", 1.0 - smoothstep(4.6, 5.8, spd)], ["sprint", smoothstep(4.6, 5.8, spd)]]
	elif spd > 1.9:
		gset = [["m_walk", 1.0 - smoothstep(1.9, 2.8, spd)], ["m_run", smoothstep(1.9, 2.8, spd)]]
	else:
		gset = [["m_walk", 1.0]]
	var stride := 0.0
	for e in gset:
		stride += float(clips[e[0]]["stride"]) * float(e[1])
	_phase = fposmod(_phase + dt * spd / maxf(stride, 0.5), 1.0)
	var loco: Array = []
	for e in gset:
		var c: Dictionary = clips[e[0]]
		var ph := _phase if _back < 0.5 else 1.0 - _phase
		if float(e[1]) > 0.001:
			loco.append([_sample(e[0], ph * float(c["len"]), true), e[1]])
	var stand := _sample("m_idle", _idle_t, true)
	var crouch_p := _sample("crouch_idle", _idle_t, true)
	var idle := _blend([[stand, 1.0 - _crouch_s], [crouch_p, _crouch_s]], N) if _crouch_s > 0.01 else stand
	var pose: Array
	if mw > 0.01 and not loco.is_empty():
		var lp := _blend(loco, N)
		pose = _blend([[idle, 1.0 - mw], [lp, mw]], N)
	else:
		pose = idle
	# skok / spadanie
	_air_t = _air_t + dt if air else 0.0
	_jump_w = move_toward(_jump_w, 1.0 if (air and _air_t > 0.08) else 0.0, dt * 6.0)
	if _jump_w > 0.01:
		pose = _blend([[pose, 1.0 - _jump_w], [_sample("jump_loop", 0.6, true), _jump_w]], N)
	# reakcja na trafienie (nagranie) na tułowiu i głowie
	if _hit_t < 0.5 and _hit_clip != "":
		_hit_t += dt
		var hl: float = clips[_hit_clip]["len"]
		var hw := sin(clampf(_hit_t / hl, 0.0, 1.0) * PI) * 0.6
		_overlay(pose, _sample(_hit_clip, _hit_t, false), _upper_mask(), hw)
	_set_locals(pose)
	# skręt bioder w stronę ruchu (chód bokiem / tyłem)
	var hi := _b("Hips")
	L[hi] = Basis(Vector3.UP, -_leg_yaw) * (L[hi] as Basis)
	_fk()
	_aim_spine(dt)
	_springs(dt)
	if gun:
		_hold_gun(dt)
	else:
		_hands_relaxed()
	_write()
	_sync_body()


func _upper_mask() -> Dictionary:
	var m := {}
	for nm in ["Spine", "Spine1", "Spine2", "Neck", "Head"]:
		m[_b(nm)] = 1.0
	return m


## Tułów w stronę celu (rozłożone na trzy kręgi), głowa dopełnia resztę kąta.
func _aim_spine(dt: float) -> void:
	var a := aim_dir.normalized()
	var flat := Vector3(a.x, 0.0, a.z)
	if flat.length_squared() < 1e-4:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var pitch := asin(clampf(a.y, -1.0, 1.0))
	var w := 0.35 + 0.65 * aim_w
	if sprint:
		w = 0.15
	var chest_pitch := pitch * (0.55 if gun else 0.35) * w
	var want := (flat * cos(chest_pitch) + Vector3.UP * sin(chest_pitch)).normalized()
	var cur := _dir("Spine2")
	cur = Vector3(cur.x, cur.y, cur.z).normalized()
	var d := _arc(cur, want)
	var q := d.get_rotation_quaternion()
	var third := Basis(Quaternion().slerp(q, 1.0 / 3.0))
	for nm in ["Spine", "Spine1", "Spine2"]:
		_rotate(_b(nm), third)
	# głowa: patrzy dokładnie w cel
	var hcur := _dir("Head")
	var hd := _arc(hcur, a).get_rotation_quaternion()
	var lim := 1.0 if hd.get_angle() < 1.2 else 1.2 / hd.get_angle()
	_rotate(_b("Neck"), Basis(Quaternion().slerp(hd, 0.45 * lim)))
	_rotate(_b("Head"), Basis(Quaternion().slerp(hd, 0.55 * lim)))
	if hide_head:
		pass


func _springs(dt: float) -> void:
	_spring_v += (-_spring * 60.0 - _spring_v * 8.0) * dt
	_spring += _spring_v * dt
	_spring = _spring.limit_length(0.7)
	_head_spring_v += (-_head_spring * 90.0 - _head_spring_v * 9.0) * dt
	_head_spring += _head_spring_v * dt
	_head_spring = _head_spring.limit_length(0.8)
	if _spring.length_squared() > 1e-6:
		_rotate(_b("Spine1"), Basis(_spring.normalized(), _spring.length() * 0.5))
		_rotate(_b("Spine2"), Basis(_spring.normalized(), _spring.length() * 0.5))
	if _head_spring.length_squared() > 1e-6:
		_rotate(_b("Head"), Basis(_head_spring.normalized(), _head_spring.length()))


## Ręce bez broni (np. rentgen, testy): opuszczone.
func _hands_relaxed() -> void:
	_curl("Right", 0.5)
	_curl("Left", 0.5)


# ---------------------------------------------------------------- broń

func gun_transform() -> Transform3D:
	return _gun_xf


func _hold_gun(dt: float) -> void:
	_recoil_v += (-_recoil * 260.0 - _recoil_v * 24.0) * dt
	_recoil += _recoil_v * dt
	var a := aim_dir.normalized()
	var chest := (G[_b("Spine2")] as Basis) * (rc[_b("Spine2")] as Basis).inverse()
	var cx := chest.x.normalized()
	var cu := chest.y.normalized()
	var pistol: bool = gun.is_pistol()
	var aw := aim_w
	if reload_p >= 0.0:
		aw = minf(aw, 0.35)
	if sprint:
		aw = 0.0
	# kierunek lufy: przy gotowości w dół i lekko do środka
	var low := (a * cos(0.85) + Vector3.DOWN * sin(0.85) - cx * 0.25).normalized()
	if pistol:
		low = (a * cos(1.0) + Vector3.DOWN * sin(1.0)).normalized()
	var fwd := low.slerp(a, aw).normalized()
	# drżenie rąk (oddech, zmęczenie)
	var sway := Vector3(sin(_sway_t * 1.3) * 0.004, sin(_sway_t * 1.9) * 0.003, 0.0) * (1.0 + (1.0 - aw) * 2.0)
	fwd = (fwd + cx * sway.x + cu * sway.y).normalized()
	var up := (cu - fwd * cu.dot(fwd)).normalized()
	if reload_p >= 0.0 and reload_kind == "mag":
		var rk := sin(clampf(reload_p, 0.0, 1.0) * PI)
		up = up.rotated(fwd, -0.45 * rk)   # broń przechylona magazynkiem do lewej ręki
	var z := -fwd
	var x := up.cross(z).normalized()
	var gb := Basis(x, up, z)
	# odrzut: podrzut lufy i cofnięcie w bark
	var rec := clampf(_recoil, -0.5, 1.5)
	var rcfg: Array = gun.data["recoil"]
	gb = Basis(x, float(rcfg[0]) * 6.0 * rec) * Basis(up, float(rcfg[1]) * 4.0 * rec * _recoil_side) * gb
	var origin: Vector3
	if pistol:
		var base := (P[_b("Spine2")] as Vector3) + cu * 0.2 + cx * 0.03
		var reach := lerpf(0.28, 0.5, aw)
		origin = base + fwd * reach - fwd * float(rcfg[2]) * rec
	else:
		var shoulder := (P[_b("RightArm")] as Vector3) - cx * 0.045 + chest.z.normalized() * -0.05 + cu * -0.03
		var butt: Vector3 = gun.anchor("butt")
		origin = shoulder - gb * butt - (gb * Vector3(0, 0, -1)) * float(rcfg[2]) * rec * 0.8
		if aw < 0.5:
			origin += (cx * -0.03 + cu * -0.04) * (1.0 - aw * 2.0)
	_gun_xf = Transform3D(gb, origin)
	gun.transform = _gun_xf
	# --- prawa dłoń na chwycie
	var gx := gb.x
	var gy := gb.y
	var gf := -gb.z
	var grip := origin
	var r_dir := (gf * 0.62 - gy * 0.78).normalized()
	var r_palm := -gx
	var r_wrist := grip - r_dir * 0.065 + gx * 0.022 + gy * 0.01
	if cycle_p >= 0.0 and reload_kind == "bolt":
		# zamek: dłoń idzie do rączki zamka i wraca
		var k := sin(clampf(cycle_p, 0.0, 1.0) * PI)
		r_wrist += (gy * 0.07 + gx * 0.05 + gf * 0.02 - gf * 0.07 * smoothstep(0.3, 0.6, cycle_p)) * k
	if limp_arm["_r"]:
		r_wrist = r_wrist.lerp((P[_b("RightArm")] as Vector3) + Vector3(0.05, -0.5, 0.0), 0.7)
	_arm("Right", r_wrist, r_dir, r_palm, cx * 0.6 - cu * 1.0 + chest.z * 0.2)
	_curl("Right", 1.05)
	# --- lewa dłoń: łoże / druga dłoń na pistolecie / magazynek
	var sup: Vector3 = gb * gun.anchor("support") + origin
	var l_dir := (gf * 0.75 + gx * 0.55).normalized()
	var l_palm := (gy * 0.8 + gx * 0.35).normalized()
	var l_wrist := sup - l_dir * 0.06 - gy * 0.035 - gx * 0.03
	if pistol:
		l_dir = (gf * 0.55 + gx * 0.35 - gy * 0.75).normalized()
		l_palm = (gx * 0.9 + gy * 0.2).normalized()
		l_wrist = grip - gx * 0.045 - gy * 0.035 - l_dir * 0.03
	if cycle_p >= 0.0 and reload_kind == "pump":
		l_wrist -= gf * 0.09 * sin(clampf(cycle_p, 0.0, 1.0) * PI)
	if reload_p >= 0.0:
		l_wrist = _reload_hand(l_wrist, origin, gb, chest)
	if limp_arm["_l"]:
		l_wrist = (P[_b("LeftArm")] as Vector3) + Vector3(-0.05, -0.5, 0.0)
	_arm("Left", l_wrist, l_dir, l_palm, -cx * 0.7 - cu * 1.0 + chest.z * 0.1)
	_curl("Left", 0.75 if not pistol else 0.9)


## Ruch lewej dłoni przy przeładowaniu: magazynek -> ładownica -> gniazdo -> łoże.
func _reload_hand(rest: Vector3, origin: Vector3, gb: Basis, chest: Basis) -> Vector3:
	var p := reload_p
	var mag: Vector3 = origin + gb * (gun.anchor("support").lerp(Vector3.ZERO, 0.75) + Vector3(0, -0.1, 0))
	var pouch := (P[_b("Spine1")] as Vector3) + chest.x * -0.12 + chest.z * -0.16 + chest.y * -0.08
	if reload_kind == "shell":
		var port := origin + gb * Vector3(0.03, 0.0, -0.12)
		var k := fposmod(p * 1.0, 1.0)
		if k < 0.4:
			return rest.lerp(pouch, smoothstep(0.0, 0.4, k))
		elif k < 0.8:
			return pouch.lerp(port, smoothstep(0.4, 0.8, k))
		return port.lerp(rest, smoothstep(0.8, 1.0, k))
	if p < 0.18:
		return rest.lerp(mag, smoothstep(0.0, 0.18, p))
	if p < 0.42:
		return mag.lerp(pouch, smoothstep(0.18, 0.42, p))
	if p < 0.7:
		return pouch.lerp(mag, smoothstep(0.42, 0.7, p))
	return mag.lerp(rest, smoothstep(0.75, 1.0, p))


## IK ręki: bark zostaje, ramię i przedramię kierują dłoń w cel; potem orientacja dłoni.
func _arm(side: String, wrist: Vector3, hand_dir: Vector3, palm: Vector3, pole: Vector3) -> void:
	var ua := _b(side + "Arm")
	var fa := _b(side + "ForeArm")
	var hd := _b(side + "Hand")
	var sh := P[ua] as Vector3
	var l1 := (off[fa] as Vector3).length()
	var l2 := (off[hd] as Vector3).length()
	var r := Humanoid.ik(sh, wrist, l1, l2, pole)
	var elbow: Vector3 = r[0]
	var w: Vector3 = r[1]
	var cur := (P[fa] as Vector3) - sh
	_rotate(ua, _arc(cur, elbow - sh))
	var cur2 := (P[hd] as Vector3) - (P[fa] as Vector3)
	_rotate(fa, _arc(cur2, w - (P[fa] as Vector3)))
	# dłoń: kierunek palców i wnętrze dłoni
	var mid := _b(side + "HandMiddle1")
	var fd := ((P[mid] as Vector3) - (P[hd] as Vector3)).normalized()
	var pn := (G[hd] as Basis) * (rc[hd] as Basis).inverse() * Vector3.DOWN
	var cb := _frame(fd, pn)
	var tb := _frame(hand_dir.normalized(), palm.normalized())
	_rotate(hd, (tb * cb.transposed()).orthonormalized())


static func _frame(a: Vector3, b: Vector3) -> Basis:
	var z := (b - a * b.dot(a)).normalized()
	return Basis(a.cross(z).normalized(), a, z)


## Zgięcie palców (0 = proste, ~1 = zaciśnięte na chwycie).
func _curl(side: String, amount: float) -> void:
	var sgn := -1.0 if side == "Right" else 1.0
	for f in ["Index", "Middle", "Ring", "Pinky"]:
		for j in [1, 2, 3]:
			var nm: String = side + "Hand" + f + str(j)
			if not bi.has(nm):
				continue
			var i: int = bi[nm]
			var ax := ((rc[i] as Basis).inverse() * Vector3.BACK).normalized()
			var ang := amount * (0.75 if j == 1 else 0.95) * sgn
			L[i] = (L[i] as Basis) * Basis(ax, ang)
	for j in [1, 2]:
		var nm: String = side + "HandThumb" + str(j)
		if bi.has(nm):
			var i: int = bi[nm]
			var ax := ((rc[i] as Basis).inverse() * Vector3.UP).normalized()
			L[i] = (L[i] as Basis) * Basis(ax, 0.35 * amount * -sgn)
	_fk_sub(_b(side + "Hand"))


# ---------------------------------------------------------------- zapis i ciało

func _write() -> void:
	var kinv := K.affine_inverse()
	var hi := _b("Hips")
	for i in N:
		if i == hi:
			skel.set_bone_pose_rotation(i, (Kr.inverse() * (G[i] as Basis)).orthonormalized().get_rotation_quaternion())
			skel.set_bone_pose_position(i, kinv * (P[i] as Vector3))
		else:
			skel.set_bone_pose_rotation(i, (L[i] as Basis).orthonormalized().get_rotation_quaternion())
	if _ragdoll:
		# rozciągnięcia w stawach ragdolla: pozycje lokalne z położeń globalnych
		for i in N:
			var p := parent[i]
			if p < 0:
				continue
			var lp := (G[p] as Basis).inverse() * ((P[i] as Vector3) - (P[p] as Vector3)) / ks
			skel.set_bone_pose_position(i, lp)
	var head := _b("Head")
	skel.set_bone_pose_scale(head, Vector3.ONE * (0.01 if hide_head else 1.0))


## Postać proceduralna (hitboxy, narządy, ragdoll) w pozie modelu.
func _sync_body() -> void:
	if body == null or body.ragdolled:
		return
	var p := {}
	var hb := (G[_b("Head")] as Basis) * (rc[_b("Head")] as Basis).inverse()
	var ub := (G[_b("Spine2")] as Basis) * (rc[_b("Spine2")] as Basis).inverse()
	p["pelvis"] = (P[_b("Hips")] as Vector3) + Vector3(0, -0.06, 0)
	p["neck"] = P[_b("Neck")]
	p["crown"] = (P[_b("Neck")] as Vector3) + hb.y * Humanoid.HEAD
	for s in [["_l", "Left"], ["_r", "Right"]]:
		var sfx: String = s[0]
		var pre: String = s[1]
		p["shoulder" + sfx] = P[_b(pre + "Arm")]
		p["elbow" + sfx] = P[_b(pre + "ForeArm")]
		var hand := P[_b(pre + "Hand")] as Vector3
		p["hand" + sfx] = hand
		p["hip" + sfx] = P[_b(pre + "UpLeg")]
		p["knee" + sfx] = P[_b(pre + "Leg")]
		p["ankle" + sfx] = P[_b(pre + "Foot")]
	body.apply_pose(p, ub.orthonormalized(), hb.orthonormalized())


## Od teraz kości podążają za bryłami ragdolla (wywołać tuż po make_ragdoll).
func start_ragdoll() -> void:
	_ragdoll = true
	hide_head = false
	var me := global_transform
	for nm: String in SEG_OF:
		var i: int = bi[nm]
		var seg: Node3D = body.segs[SEG_OF[nm]]
		var bw := me * Transform3D(G[i] as Basis, P[i] as Vector3)
		_rag_off[i] = seg.global_transform.affine_inverse() * bw


func _follow_ragdoll() -> void:
	var inv := global_transform.affine_inverse()
	for i in N:
		var p := parent[i]
		if _rag_off.has(i):
			var nm := skel.get_bone_name(i).trim_prefix(PRE)
			var seg: Node3D = body.segs[SEG_OF[nm]]
			var t := inv * seg.global_transform * (_rag_off[i] as Transform3D)
			G[i] = t.basis.orthonormalized()
			P[i] = t.origin
		elif p >= 0:
			G[i] = (G[p] as Basis) * (L[i] as Basis)
			P[i] = (P[p] as Vector3) + (G[p] as Basis) * (off[i] as Vector3)
		if p >= 0:
			L[i] = (G[p] as Basis).inverse() * (G[i] as Basis)
		else:
			L[i] = G[i]


func set_visible_model(on: bool) -> void:
	model.visible = on
