extends RefCounted
## Budowniczy siatek ciała. Kształty powstają z pierścieni elips (loft), elipsoid
## i rurek. Kolor wierzchołka = albedo (sRGB), alfa koloru = szorstkość, UV.x = SSS.
## Wszystko w jednej powierzchni, w przestrzeni segmentu (Y wzdłuż kości).

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var idx := PackedInt32Array()
## Funkcja Color -> id materiału (0 skóra, 1 tkanina, 2 skóra wyprawiona, 3 włosy, 4 metal), zapisywany w UV.y.
var tagger: Callable


func _vert(p: Vector3, nn: Vector3, col: Color, sss: float) -> int:
	v.append(p)
	n.append(nn)
	c.append(col)
	uv.append(Vector2(sss, float(tagger.call(col)) if tagger.is_valid() else 0.0))
	return v.size() - 1


## Godot traktuje trójkąty zgodne z ruchem wskazówek zegara jako przednie,
## więc kolejność wierzchołków dobieramy względem zamierzonej normalnej.
func _tri(a: int, b: int, cc: int) -> void:
	var gn := (v[b] - v[a]).cross(v[cc] - v[a])
	if gn.dot(n[a] + n[b] + n[cc]) > 0.0:
		idx.append(a)
		idx.append(cc)
		idx.append(b)
	else:
		idx.append(a)
		idx.append(b)
		idx.append(cc)


## rings: [y, rx, rz, cx, cz, Color, sss]
func loft(rings: Array, xf := Transform3D.IDENTITY, cap0 := true, cap1 := true, seg := 18) -> void:
	var nr := rings.size()
	var pts: Array = []
	for r: Array in rings:
		var row := PackedVector3Array()
		for j in seg:
			var a := TAU * j / seg
			row.append(Vector3(float(r[3]) + cos(a) * float(r[1]), r[0], float(r[4]) + sin(a) * float(r[2])))
		pts.append(row)
	var base := v.size()
	for i in nr:
		var r: Array = rings[i]
		var row: PackedVector3Array = pts[i]
		var up_row: PackedVector3Array = pts[mini(i + 1, nr - 1)]
		var dn_row: PackedVector3Array = pts[maxi(i - 1, 0)]
		for j in seg:
			var along := up_row[j] - dn_row[j]
			var around := row[(j + 1) % seg] - row[(j - 1 + seg) % seg]
			var nn := along.cross(around)
			if nn.length_squared() < 1e-14:
				nn = Vector3(0, -1.0 if i == 0 else 1.0, 0)
			_vert(xf * row[j], (xf.basis * nn).normalized(), r[5], r[6])
	for i in nr - 1:
		for j in seg:
			var j2 := (j + 1) % seg
			var a := base + i * seg + j
			var b := base + i * seg + j2
			var d := base + (i + 1) * seg + j
			var e := base + (i + 1) * seg + j2
			_tri(a, b, e)
			_tri(a, e, d)
	if cap0:
		_cap(rings[0], base, seg, xf, -1.0)
	if cap1:
		_cap(rings[nr - 1], base + (nr - 1) * seg, seg, xf, 1.0)


func _cap(r: Array, start: int, seg: int, xf: Transform3D, s: float) -> void:
	var nn := (xf.basis * Vector3(0, s, 0)).normalized()
	var centre := _vert(xf * Vector3(r[3], r[0], r[4]), nn, r[5], r[6])
	var rim := v.size()
	for j in seg:
		_vert(v[start + j], nn, r[5], r[6])
	for j in seg:
		_tri(centre, rim + j, rim + (j + 1) % seg)


func ellipsoid(centre: Vector3, radii: Vector3, col: Color, sss := 0.0, xf := Transform3D.IDENTITY, seg := 14, rings := 8) -> void:
	var rr: Array = []
	for i in rings + 1:
		var th := PI * i / rings
		var s := sin(th)
		rr.append([centre.y - cos(th) * radii.y, radii.x * s, radii.z * s, centre.x, centre.z, col, sss])
	loft(rr, xf, false, false, seg)


## Rurka wzdłuż ścieżki (żebra, jelita, pasy).
func tube(path: PackedVector3Array, radius: float, col: Color, sss := 0.0, seg := 8, flat := 1.0) -> void:
	var np := path.size()
	var base := v.size()
	var nref := Vector3.ZERO
	for i in np:
		var t := (path[mini(i + 1, np - 1)] - path[maxi(i - 1, 0)]).normalized()
		if i == 0:
			nref = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			nref = (nref - t * nref.dot(t)).normalized()
		var b := t.cross(nref)
		for j in seg:
			var a := TAU * j / seg
			var off := nref * cos(a) * radius * flat + b * sin(a) * radius  # spłaszczenie w kierunku od ciała
			_vert(path[i] + off, off.normalized(), col, sss)
	for i in np - 1:
		for j in seg:
			var j2 := (j + 1) % seg
			var a := base + i * seg + j
			var bb := base + i * seg + j2
			var d := base + (i + 1) * seg + j
			var e := base + (i + 1) * seg + j2
			_tri(a, bb, e)
			_tri(a, e, d)


## Płaski przekrój (np. w miejscu cięcia). layers: [[ułamek promienia, Color], ...,
## [1.0, null]] — pas od ułamka i do i+1 ma kolor i. facing: +1 = normalna +Y.
func disc(y: float, rx: float, rz: float, cx: float, cz: float, layers: Array, facing: float, seg := 22) -> void:
	var nn := Vector3(0, facing, 0)
	for li in layers.size() - 1:
		var f0: float = layers[li][0]
		var f1: float = layers[li + 1][0]
		if f1 <= f0:
			continue
		var col: Color = layers[li][1]
		var r0 := v.size()
		for j in seg:
			var a := TAU * j / seg
			_vert(Vector3(cx + cos(a) * rx * f0, y, cz + sin(a) * rz * f0), nn, col, 0.0)
		var r1 := v.size()
		for j in seg:
			var a := TAU * j / seg
			_vert(Vector3(cx + cos(a) * rx * f1, y, cz + sin(a) * rz * f1), nn, col, 0.0)
		for j in seg:
			var j2 := (j + 1) % seg
			_tri(r0 + j, r0 + j2, r1 + j2)
			_tri(r0 + j, r1 + j2, r1 + j)


func commit() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
