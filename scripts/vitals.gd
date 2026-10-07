extends RefCounted
## Fizjologia rannego: objętość krwi, krwotoki z poszczególnych ran, ból, wstrząs, przytomność.
## Liczby oparte na przybliżonych wartościach medycznych (dorosły ~75 kg, 5 l krwi):
##  - utrata >15% krwi: tachykardia, >30%: spadek sprawności, ~40%: utrata przytomności, ~50%: zgon,
##  - przecięta aorta / serce: utrata przytomności w kilka–kilkanaście sekund,
##  - tętnica udowa: przytomność do ~1–2 min, drobne naczynia krzepną same.

const BLOOD := 5000.0          # mL
const IMPAIRED := 0.25         # ułamek utraconej krwi: spowolnienie, drżenie rąk
const UNCONSCIOUS := 0.40
const DEATH := 0.52

# Narząd -> skutki. bleed [mL/s] przy pełnej jamie rany, clot: czas zatrzymywania się krwawienia [s]
# (0 = nie krzepnie samo), ko: utrata przytomności po tylu sekundach (niezależnie od krwi),
# kill: zgon natychmiast, legs/arm: niesprawna kończyna, pain: ból 0..1.
const ORGANS := {
	"brain": {"name": "Mózg", "kill": true, "pain": 1.0},
	"spine_neck": {"name": "Rdzeń szyjny", "kill": true, "pain": 1.0},
	"heart": {"name": "Serce", "bleed": 140.0, "ko": 7.0, "pain": 1.0},
	"aorta": {"name": "Aorta", "bleed": 150.0, "ko": 12.0, "pain": 0.9},
	"spine": {"name": "Kręgosłup (rdzeń piersiowo-lędźwiowy)", "bleed": 2.0, "legs": "both", "pain": 1.0},
	"throat": {"name": "Tętnica szyjna / tchawica", "bleed": 45.0, "pain": 0.9, "breath": 0.7},
	"subclavian": {"name": "Tętnica podobojczykowa", "bleed": 35.0, "pain": 0.7},
	"lung": {"name": "Płuco (odma, krwiak opłucnej)", "bleed": 7.0, "clot": 300.0, "pain": 0.7, "breath": 0.45},
	"liver": {"name": "Wątroba", "bleed": 14.0, "clot": 400.0, "pain": 0.8},
	"spleen": {"name": "Śledziona", "bleed": 11.0, "clot": 400.0, "pain": 0.7},
	"kidney": {"name": "Nerka", "bleed": 8.0, "clot": 300.0, "pain": 0.8},
	"pancreas": {"name": "Trzustka", "bleed": 4.0, "clot": 200.0, "pain": 0.8},
	"stomach": {"name": "Żołądek", "bleed": 2.5, "clot": 150.0, "pain": 0.7},
	"intestines": {"name": "Jelita", "bleed": 2.5, "clot": 150.0, "pain": 0.6},
	"bladder": {"name": "Pęcherz", "bleed": 1.2, "clot": 120.0, "pain": 0.5},
	"femoral": {"name": "Tętnica udowa", "bleed": 32.0, "pain": 0.6, "limb": true},
	"popliteal": {"name": "Tętnica podkolanowa", "bleed": 14.0, "pain": 0.5, "limb": true},
	"brachial": {"name": "Tętnica ramienna", "bleed": 14.0, "pain": 0.5, "limb": true},
	"radial": {"name": "Tętnica promieniowa", "bleed": 4.0, "clot": 120.0, "pain": 0.4, "limb": true},
	"femur": {"name": "Kość udowa (złamanie)", "bleed": 4.0, "clot": 200.0, "pain": 1.0, "legs": "one"},
	"tibia": {"name": "Piszczel (złamanie)", "bleed": 1.5, "clot": 150.0, "pain": 0.8, "legs": "one"},
	"quadriceps": {"name": "Mięsień czworogłowy", "bleed": 1.2, "clot": 90.0, "pain": 0.4},
	"hamstring": {"name": "Mięśnie kulszowo-goleniowe", "bleed": 1.2, "clot": 90.0, "pain": 0.4},
	"achilles": {"name": "Ścięgno Achillesa", "bleed": 0.4, "clot": 60.0, "pain": 0.5, "legs": "one"},
	"humerus": {"name": "Kość ramienna (złamanie)", "bleed": 1.5, "clot": 150.0, "pain": 0.9, "arm": true},
	"forearm": {"name": "Kości przedramienia (złamanie)", "bleed": 1.0, "clot": 120.0, "pain": 0.8, "arm": true},
	"biceps": {"name": "Biceps", "bleed": 0.8, "clot": 90.0, "pain": 0.35},
	"eye": {"name": "Oko / oczodół", "bleed": 1.0, "clot": 120.0, "pain": 0.9},
	"jaw": {"name": "Żuchwa (złamanie)", "bleed": 2.0, "clot": 120.0, "pain": 0.9},
}
## Trafienie krytyczne: zabija, odcina przytomność, duży krwotok (≥ 7 mL/s: serce, aorta, płuco,
## wątroba, śledziona, nerka, duże tętnice), paraliż, oddech.
## Mięśnie, kości kończyn, drobne naczynia — lekkie.
static func critical_organ(o: String) -> bool:
	var k := organ_key(o)
	if not ORGANS.has(k):
		return false
	var fx: Dictionary = ORGANS[k]
	return fx.get("kill", false) or fx.has("ko") or float(fx.get("bleed", 0.0)) >= 7.0 \
		or fx.get("legs", "") == "both" or fx.has("breath")


static func organ_key(o: String) -> String:
	if o.begins_with("lung"):
		return "lung"
	if o.begins_with("kidney"):
		return "kidney"
	return o


static func organ_name(o: String) -> String:
	var k := organ_key(o)
	return String(ORGANS[k]["name"]) if ORGANS.has(k) else o


const TISSUE_BLEED := {"torso": 1.2, "head": 1.5, "uarm": 0.6, "farm": 0.4, "thigh": 1.0, "shin": 0.6}

var blood := BLOOD
var pain := 0.0
var wounds: Array = []         # {name, rate, clot, t, limb, seg, dressed}
var conscious := true
var dead := false
var ko_timer := -1.0           # odliczanie do utraty przytomności (serce, aorta)
var breath := 0.0              # niewydolność oddechowa 0..1 (płuca, tchawica)
var legs := 0                  # niesprawne nogi (0..2)
var arms := {"_l": false, "_r": false}
var cause := ""
var _leg_segs := {}


func lost() -> float:
	return 1.0 - blood / BLOOD


func bleed_rate() -> float:
	var r := 0.0
	for w: Dictionary in wounds:
		r += float(w["rate"])
	return r


## Sprawność 0..1 (celność, szybkość): krew, ból, oddech.
func capacity() -> float:
	if not conscious:
		return 0.0
	var c := 1.0 - smoothstep(0.12, UNCONSCIOUS, lost()) * 0.7
	c -= pain * 0.25 + breath * 0.3
	return clampf(c, 0.1, 1.0)


## Rana od pocisku. organs: lista narządów na drodze (z humanoid.organs_hit), cavity: mnożnik jamy rany.
## Zwraca słownik skutków: {names, kill, ko, legs_now, arm}.
func wound(seg: String, organs: Array, cavity: float) -> Dictionary:
	var res := {"names": PackedStringArray(), "kill": false, "fatal_soon": false, "leg": false, "arm": false}
	if dead:
		return res
	var key := seg
	var side := ""
	if seg.ends_with("_l") or seg.ends_with("_r"):
		side = seg.substr(seg.length() - 2)
		key = seg.substr(0, seg.length() - 2)
	# sama tkanka (mięśnie, skóra)
	_add("Rana " + _seg_name(seg), float(TISSUE_BLEED.get(key, 0.8)) * cavity, 60.0, seg, false)
	pain = minf(pain + 0.25 * cavity, 1.5)
	var seen := {}
	for o: String in organs:
		var k := o
		if o.begins_with("lung"):
			k = "lung"
		elif o.begins_with("kidney"):
			k = "kidney"
		if seen.has(k):
			continue
		seen[k] = true
		if not ORGANS.has(k):
			continue
		var fx: Dictionary = ORGANS[k]
		res["names"].append(fx["name"])
		pain = minf(pain + float(fx.get("pain", 0.3)) * 0.6, 1.5)
		if fx.get("kill", false):
			res["kill"] = true
			cause = fx["name"]
		if fx.has("bleed"):
			_add(fx["name"], float(fx["bleed"]) * clampf(cavity, 0.6, 2.0), float(fx.get("clot", 0.0)), seg, fx.get("limb", false))
		if fx.has("ko"):
			var t := float(fx["ko"]) * randf_range(0.7, 1.4)
			ko_timer = t if ko_timer < 0.0 else minf(ko_timer, t)
			res["fatal_soon"] = true
			if cause == "":
				cause = fx["name"]
		if fx.has("breath"):
			breath = minf(breath + float(fx["breath"]), 1.0)
		if fx.has("legs"):
			if fx["legs"] == "both":
				legs = 2
			elif not _leg_segs.has(seg):
				_leg_segs[seg] = true
				legs = mini(legs + 1, 2)
			res["leg"] = true
		if fx.get("arm", false) and side != "":
			arms[side] = true
			res["arm"] = true
	if res["kill"]:
		_die()
	return res


## Uderzenie w kamizelkę / hełm bez przebicia: ból, siniak, ewentualnie pęknięte żebro.
func blunt(strength: float) -> void:
	pain = minf(pain + 0.35 * strength, 1.5)


func _add(nm: String, rate: float, clot: float, seg: String, limb: bool) -> void:
	wounds.append({"name": nm, "rate": rate, "rate0": rate, "clot": clot, "t": 0.0, "seg": seg, "limb": limb, "dressed": false})


func _seg_name(seg: String) -> String:
	return {"head": "głowy", "torso": "tułowia", "uarm_l": "lewego ramienia", "uarm_r": "prawego ramienia",
		"farm_l": "lewego przedramienia", "farm_r": "prawego przedramienia", "thigh_l": "lewego uda",
		"thigh_r": "prawego uda", "shin_l": "lewej goleni", "shin_r": "prawej goleni"}.get(seg, seg)


## Opatrunek / opaska uciskowa na najgroźniejszą ranę. Zwraca opis albo "".
func treat() -> String:
	var best := -1
	for i in wounds.size():
		var w: Dictionary = wounds[i]
		if w["dressed"]:
			continue
		if best < 0 or float(w["rate"]) > float(wounds[best]["rate"]):
			best = i
	if best < 0 or float(wounds[best]["rate"]) < 0.05:
		return ""
	var w: Dictionary = wounds[best]
	w["dressed"] = true
	if w["limb"]:
		w["rate"] = 0.0   # opaska uciskowa na kończynie zatrzymuje krwotok tętniczy
		return "Opaska uciskowa: " + String(w["name"]).to_lower()
	w["rate"] = float(w["rate"]) * (0.15 if float(w["rate"]) < 20.0 else 0.6)  # ucisk/tamponada
	return "Opatrunek: " + String(w["name"]).to_lower()


## Krok symulacji. Zwraca "" albo zdarzenie: "ko" (utrata przytomności), "dead".
func step(dt: float) -> String:
	if dead:
		return ""
	var ev := ""
	var r := 0.0
	for w: Dictionary in wounds:
		w["t"] = float(w["t"]) + dt
		var c := float(w["clot"])
		if c > 0.0 and not w["dressed"]:
			w["rate"] = float(w["rate0"]) * exp(-float(w["t"]) / c)
		r += float(w["rate"])
	# przy spadku ciśnienia krwawienie słabnie (mniejszy rzut serca)
	r *= clampf(blood / BLOOD, 0.3, 1.0)
	blood = maxf(blood - r * dt, 0.0)
	pain = maxf(pain - dt * 0.05, 0.0)
	if ko_timer >= 0.0:
		ko_timer -= dt
		if ko_timer <= 0.0 and conscious:
			conscious = false
			ev = "ko"
	if conscious and lost() >= UNCONSCIOUS:
		conscious = false
		ev = "ko"
	if lost() >= DEATH:
		if cause == "":
			cause = "wykrwawienie"
		_die()
		ev = "dead"
	return ev


func _die() -> void:
	dead = true
	conscious = false
