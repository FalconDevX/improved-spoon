extends RigidBody3D
## Szczątek maszyny rozerwanej w powietrzu: spada, koziołkuje, dymi i płonie przez kilka sekund,
## po 30 s znika. Tylko obraz (nie rani, nie zasłania pocisków).

const FX = preload("res://scripts/fx.gd")

var _t := 0.0
var _smoke_t := 0.0
var _light: OmniLight3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	gravity_scale = 1.0
	linear_damp = 0.08
	angular_damp = 0.2
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 3.0
	_light.omni_range = 8.0
	add_child(_light)


## Dodaje kształt kolizji z rozmiaru siatki (żeby leżał na ziemi).
func setup(mesh_inst: MeshInstance3D) -> void:
	var aabb := mesh_inst.get_aabb()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (aabb.size * mesh_inst.scale).clamp(Vector3.ONE * 0.2, Vector3.ONE * 8.0)
	cs.shape = bs
	cs.position = mesh_inst.position + aabb.get_center() * mesh_inst.scale
	add_child(cs)
	mass = clampf(bs.size.x * bs.size.y * bs.size.z * 40.0, 20.0, 600.0)


func _physics_process(dt: float) -> void:
	_t += dt
	if _t > 30.0:
		queue_free()
		return
	var burn := _t < 9.0
	_light.visible = burn and randf() > 0.15
	_light.light_energy = 2.0 + randf() * 2.0
	_smoke_t -= dt
	if _smoke_t <= 0.0 and _t < 14.0:
		_smoke_t = 0.06 if burn else 0.25
		FX.I.muzzle_smoke(global_position, Vector3.UP * 0.5 - linear_velocity * 0.02, 3.0 if burn else 2.0)
