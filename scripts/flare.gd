extends Node3D
## Flara (pułapka termiczna): jasna, płonąca kula wyrzucona z samolotu / śmigłowca. Spada z oporem
## powietrza, pali się ~3 s. Rakiety naprowadzane na podczerwień mogą wziąć ją za cel (missile.gd).

const LIFE := 3.2
const GRAVITY := 9.81

static var _mat: StandardMaterial3D
static var _mesh: SphereMesh

var velocity := Vector3.ZERO     # nazwa jak w CharacterBody3D (rakieta liczy wyprzedzenie)
var _t := 0.0
var _light: OmniLight3D
var _core: MeshInstance3D


func _ready() -> void:
	add_to_group("flare")
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(1.0, 0.92, 0.7)
		_mesh = SphereMesh.new()
		_mesh.radius = 0.18
		_mesh.height = 0.36
		_mesh.radial_segments = 8
		_mesh.rings = 4
	_core = MeshInstance3D.new()
	_core.mesh = _mesh
	_core.material_override = _mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.45)
	_light.light_energy = 6.0
	_light.omni_range = 18.0
	add_child(_light)


func _physics_process(dt: float) -> void:
	_t += dt
	if _t >= LIFE:
		queue_free()
		return
	velocity += Vector3(0, -GRAVITY, 0) * dt
	velocity -= velocity * minf(velocity.length() * 0.004, 0.9) * dt * 10.0
	global_position += velocity * dt
	var k := 1.0 - _t / LIFE
	_light.light_energy = 6.0 * k + randf() * 1.5
	_core.scale = Vector3.ONE * (0.6 + k * 0.6 + randf() * 0.2)
	if int(_t * 30.0) % 2 == 0:
		FX.I.muzzle_smoke(global_position, -velocity * 0.05, 0.5)


## Salwa flar za statkiem powietrznym. Rakiety lecące na niego zdążą się „przestawić” tylko gdy są
## jeszcze daleko (flary trzeba wyrzucić odpowiednio wcześnie).
static func salvo(craft: Node3D, n := 6) -> void:
	var b := craft.global_basis
	var made: Array = []
	for i in n:
		var f = load("res://scripts/flare.gd").new()
		var side := (1.0 if i % 2 == 0 else -1.0)
		f.velocity = craft.velocity * 0.7 + b.x * side * randf_range(8.0, 16.0) - b.y * randf_range(4.0, 10.0) + b.z * randf_range(2.0, 8.0)
		craft.get_parent().add_child(f)
		f.global_position = craft.global_position - b.y * 0.6 + b.z * 1.5
		made.append(f)
	FX.I.play("click", craft.global_position, 2.0, 0.1, 0.45, 40.0)
	for m in craft.get_tree().get_nodes_in_group("missile"):
		if m.target == craft and m.time_to_target() > DECOY_MIN:
			m.target = made[randi() % made.size()]
			m.decoyed = true


const DECOY_MIN := 0.7   # rakieta bliżej niż na tyle sekund już nie da się zwieść
const FX = preload("res://scripts/fx.gd")
