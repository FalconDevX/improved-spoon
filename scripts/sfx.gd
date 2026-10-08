extends RefCounted
## Proceduralna synteza dźwięków (bez plików audio).

const RATE := 22050


static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var g := 0.9 / peak
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## Świst ostrza: szum przez rezonansowy filtr pasmowy z przesuwaną częstotliwością.
static func whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / n
		var fc := lerpf(350.0, 1600.0, sin(pow(t, 0.8) * PI))
		var f := 2.0 * sin(PI * fc / RATE)
		var x := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := x - low - 0.3 * band
		band += f * high
		var env := pow(sin(PI * pow(t, 0.65)), 2.0)
		s[i] = band * env
	return _wav(s)


## Trafienie w ciało: głuche uderzenie + mlaśnięcie + syk krawędzi.
static func flesh(heavy: bool) -> AudioStreamWAV:
	var dur := 0.5 if heavy else 0.34
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21 if heavy else 13
	var phase := 0.0
	var lp := 0.0
	var low := 0.0
	var band := 0.0
	var prev := 0.0
	var base_f := 62.0 if heavy else 85.0
	for i in n:
		var t := float(i) / RATE
		var freq := base_f * (1.0 + 1.6 * exp(-t * 30.0))
		phase += TAU * freq / RATE
		var thump := sin(phase) * exp(-t * (11.0 if heavy else 18.0))
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.25
		var slap := lp * exp(-t * 40.0)
		var fc := 500.0 + 350.0 * sin(t * 45.0)
		var f := 2.0 * sin(PI * fc / RATE)
		low += f * band
		var high := x - low - 0.25 * band
		band += f * high
		var squelch := band * exp(-t * 11.0) * 0.12
		var hp := x - prev
		prev = x
		var cut := hp * exp(-t * 70.0) * 0.25
		s[i] = thump * 1.0 + slap * 1.4 + squelch + cut
	return _wav(s)


## Upadek ciała na podłogę.
static func thud() -> AudioStreamWAV:
	var n := int(RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * 52.0 * (1.0 + 0.8 * exp(-t * 25.0)) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		s[i] = sin(phase) * exp(-t * 8.0) + lp * 2.5 * exp(-t * 14.0)
	return _wav(s)


## Strzał z karabinka: ostry trzask (szum z bardzo szybkim zanikiem), niskie uderzenie
## prochu i krótki pogłos.
static func gunshot() -> AudioStreamWAV:
	var n := int(RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 556
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.55
		lp2 += (x - lp2) * 0.04
		phase += TAU * 90.0 * (1.0 + 2.0 * exp(-t * 60.0)) / RATE
		var crack := lp * exp(-t * 90.0) * 1.6
		var boom := sin(phase) * exp(-t * 22.0) * 0.9
		var tail := lp2 * 3.0 * exp(-t * 9.0) * smoothstep(0.0, 0.01, t)
		s[i] = crack + boom + tail
	return _wav(s)


## Kula w ziemi / ścianie: krótkie suche stuknięcie.
static func ricochet() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
		s[i] = lp * exp(-t * 55.0)
	return _wav(s)


## Wystrzał: trzask gazów wylotowych, niskie uderzenie, echo. dur: długość ogona, pitch: barwa
## (mniejsza = cięższy kaliber).
static func shot(dur: float, pitch: float, seed_: int) -> AudioStreamWAV:
	var n := int(RATE * (0.25 + dur))
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	var echo := PackedFloat32Array()
	echo.resize(n)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * clampf(0.6 * pitch, 0.1, 0.9)
		lp2 += (x - lp2) * 0.03 * pitch
		phase += TAU * 70.0 * pitch * (1.0 + 2.5 * exp(-t * 50.0)) / RATE
		var crack := lp * exp(-t * 110.0 * pitch) * 1.8
		var boom := sin(phase) * exp(-t * 18.0 / pitch) * 1.1
		var tail := lp2 * 3.5 * exp(-t * 7.0 / (dur + 0.2)) * smoothstep(0.0, 0.015, t)
		s[i] = crack + boom + tail
	# echo od otoczenia
	for i in n:
		var j := i - int(RATE * 0.11)
		var k := i - int(RATE * 0.23)
		var e := 0.0
		if j > 0:
			e += s[j] * 0.22
		if k > 0:
			e += s[k] * 0.12
		echo[i] = s[i] + e
	return _wav(echo)


## Trzask naddźwiękowego pocisku przelatującego obok (fala uderzeniowa) + świst.
static func crack() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + x - prev)
		prev = x
		var nwave := (1.0 if t < 0.0004 else (-0.9 if t < 0.0009 else 0.0)) * 2.0
		s[i] = nwave + hp * exp(-t * 60.0) * 0.8 + sin(TAU * 3200.0 * t) * exp(-t * 90.0) * 0.2
	return _wav(s)


## Mechaniczne kliknięcie (spust, zatrzask magazynka, zamek): kilka krótkich impulsów.
static func click(dur: float, freq: float, seed_: int) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var hits := [0.0, dur * rng.randf_range(0.3, 0.6)]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for h: float in hits:
			if t >= h:
				var u := t - h
				v += (sin(TAU * freq * u) * 0.6 + rng.randf_range(-1, 1) * 0.5) * exp(-u * 160.0)
		s[i] = v
	return _wav(s)


## Kula w twardej przeszkodzie / drewnie.
static func impact(freq: float, seed_: int) -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var lp := 0.0
	var a := clampf(freq / RATE * 6.0, 0.05, 0.9)
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		s[i] = lp * exp(-t * 40.0) + sin(TAU * freq * 0.3 * t) * exp(-t * 70.0) * 0.4
	return _wav(s)


## Kula w metalu: dzwoniący odgłos.
static func ping() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / RATE
		var v := rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
		v += sin(TAU * 1830.0 * t) * exp(-t * 9.0) * 0.35 + sin(TAU * 2710.0 * t) * exp(-t * 12.0) * 0.25
		v += sin(TAU * 960.0 * t) * exp(-t * 7.0) * 0.2
		s[i] = v
	return _wav(s)


## Jęk rannego: niski, drżący ton z formantem.
static func groan() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var ph := 0.0
	var band := 0.0
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var f0 := 115.0 - 25.0 * t + sin(t * 31.0) * 4.0
		ph += TAU * f0 / RATE
		var src := (fmod(ph, TAU) / TAU - 0.5) + rng.randf_range(-0.15, 0.15)
		var fc := 650.0 - 200.0 * t
		var f := 2.0 * sin(PI * fc / RATE)
		low += f * band
		var high := src - low - 0.25 * band
		band += f * high
		var env := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.55, 0.9, t))
		s[i] = (band * 0.7 + low * 0.3) * env
	return _wav(s)


## Silnik tłokowy samolotu: pętla 1 s (całkowita liczba okresów — zapętla się bez trzasków).
## Harmoniczne zapłonów + szum wydechu modulowany rytmem cylindrów.
static func engine() -> AudioStreamWAV:
	var n := RATE
	var f0 := 40.0
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1940
	var noise := PackedFloat32Array()
	noise.resize(n)
	for i in n:
		noise[i] = rng.randf_range(-1.0, 1.0)
	# filtr dolnoprzepustowy puszczony dwa razy dookoła pętli: stan na końcu = stan na początku
	var lp := 0.0
	for pass_ in 2:
		for i in n:
			lp += (noise[i] - lp) * 0.12
			if pass_ == 1:
				noise[i] = lp
	var ph := []
	for k in 14:
		ph.append(rng.randf() * TAU)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in range(1, 15):
			v += sin(TAU * f0 * k * t + ph[k - 1]) / pow(k, 0.75)
		var pulse := pow(0.5 + 0.5 * sin(TAU * f0 * 4.5 * t), 3.0)
		v += noise[i] * (0.8 + 2.2 * pulse)
		v += sin(TAU * f0 * 0.5 * t) * 0.6   # bicie śmigła
		s[i] = v
	var w := _wav(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## Wybuch: niski grzmot, trzask i długi pogłos.
static func explosion() -> AudioStreamWAV:
	var n := int(RATE * 2.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.5
		lp2 += (x - lp2) * 0.02
		phase += TAU * 38.0 * (1.0 + 1.5 * exp(-t * 12.0)) / RATE
		var crack := lp * exp(-t * 35.0) * 1.5
		var boom := sin(phase) * exp(-t * 3.5) * 1.3
		var rumble := lp2 * 9.0 * exp(-t * 1.6) * smoothstep(0.0, 0.03, t)
		s[i] = crack + boom + rumble
	return _wav(s)


## Syrena alarmu przeciwlotniczego: wycie narastające i opadające (dwa przesunięte tony, wirnik),
## ~6 s na cykl — odtwarzane w pętli.
static func siren() -> AudioStreamWAV:
	var n := int(RATE * 6.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph1 := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / RATE
		# 0–2,5 s w górę, 2,5–3,5 s szczyt, 3,5–6 s w dół (zamknięta pętla: koniec = początek)
		var u := smoothstep(0.0, 2.5, t) * (1.0 - smoothstep(3.5, 6.0, t))
		var f := 260.0 + 380.0 * u
		ph1 += TAU * f / RATE
		ph2 += TAU * f * 1.26 / RATE      # druga tarcza wirnika (tercja wielka)
		var w1 := clampf(sin(ph1) * 1.6, -1.0, 1.0)
		var w2 := clampf(sin(ph2) * 1.6, -1.0, 1.0)
		s[i] = (w1 + w2 * 0.7) * 0.32 * (0.55 + 0.45 * u)
	var w := _wav(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


## Silnik pulsacyjny V-1 (Argus As 014): ~47 zapłonów na sekundę — chrapliwe, terkoczące
## buczenie („buzz bomb”). Każdy cykl: ostre pyknięcie spalania, dudnienie rury i szum wylotu.
## 1 s w pętli (całkowita liczba cykli, więc pętla jest bez szwu).
static func pulsejet() -> AudioStreamWAV:
	var n := RATE
	var f0 := 47.0
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1944
	var lp := 0.0
	var lp2 := 0.0
	var amp := 1.0
	var last_cycle := -1
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(t * f0, 1.0)
		var cyc := int(t * f0)
		if cyc != last_cycle:
			last_cycle = cyc
			amp = rng.randf_range(0.8, 1.15)   # zapłony nierówne — „poszarpane” buczenie
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.35
		lp2 += (noise - lp2) * 0.06
		var pop := exp(-ph * 9.0) * amp                     # wybuch mieszanki na początku cyklu
		var tube := sin(TAU * ph) + 0.5 * sin(TAU * ph * 2.0 + 0.6) + 0.25 * sin(TAU * ph * 3.0 + 1.1)
		var v := tube * (0.55 + 0.6 * pop)
		v += lp * pop * 1.6                                 # trzask zapłonu
		v += lp2 * 0.5                                       # szum strumienia
		s[i] = clampf(v * 1.3, -1.0, 1.0)                   # przester: chrapliwość
	var w := _wav(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## Silnik rakietowy V-2: głęboki ryk (szum o niskim widmie) z trzaskami spalania — 2 s w pętli.
static func rocket() -> AudioStreamWAV:
	var n := RATE * 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1942
	var noise := PackedFloat32Array()
	noise.resize(n)
	for i in n:
		noise[i] = rng.randf_range(-1.0, 1.0)
	# dwa przebiegi filtrów dookoła pętli: stan na końcu = stan na początku (bez szwu)
	var lo := 0.0
	var mid := 0.0
	for pass_ in 2:
		for i in n:
			lo += (noise[i] - lo) * 0.02
			mid += (noise[i] - mid) * 0.18
			if pass_ == 1:
				var crackle := 0.0
				if rng.randf() < 0.004:
					crackle = rng.randf_range(-1.0, 1.0) * 3.0
				s[i] = lo * 9.0 + mid * 0.9 + crackle
	var w := _wav(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w
