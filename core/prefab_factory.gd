## R.E.A.L. Prefab Factory - Template
## Define prefabs in code, no .tscn files needed
##
## Principle: Code > Data files
## - AI fully understands code
## - Debuggable, refactorable
## - No uid/id reference issues
##
## Usage:
##   1. Add as autoload: Project > Project Settings > Autoload > Add "PrefabFactory"
##   2. Register prefabs in _ready(): register("enemy", _make_enemy)
##   3. Create instances: var enemy = PrefabFactory.create("enemy", {health: 100})
extends Node

# Dimension mode: "2d" or "3d"
var dimension_mode: String = "3d"

# Prefab factory registry
var _factories: Dictionary = {}


func _ready() -> void:
	# Register your prefabs here
	# Example:
	# register("player", _make_player)
	# register("enemy", _make_enemy)
	# register("item", _make_item)

	print("[PrefabFactory] Registered: %s" % [_factories.keys()])


## Set dimension mode: "2d" or "3d"
func set_dimension_mode(mode: String) -> void:
	dimension_mode = mode


## Register prefab factory function
func register(name: String, factory: Callable) -> void:
	_factories[name] = factory


## Create prefab instance
func create(name: String, props: Dictionary = {}) -> Node:
	if not _factories.has(name):
		push_error("[PrefabFactory] Unknown prefab: %s" % name)
		return null

	var factory: Callable = _factories[name]
	return factory.call(props)


## Get available prefab list
func list() -> Array:
	return _factories.keys()


# ============================================
# Example prefab factory functions (2D)
# ============================================

## Example: Simple 2D enemy
func _make_enemy_2d(props: Dictionary) -> Area2D:
	var node := Area2D.new()

	# Sprite
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	# sprite.texture = preload("res://assets/enemy.png")
	node.add_child(sprite)

	# Collision
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = props.get("radius", 16.0)
	collision.shape = shape
	node.add_child(collision)

	return node


## Example: Simple 2D item
func _make_item_2d(props: Dictionary) -> Area2D:
	var node := Area2D.new()

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	node.add_child(sprite)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(props.get("width", 32), props.get("height", 32))
	collision.shape = shape
	node.add_child(collision)

	return node


# ============================================
# Example prefab factory functions (3D)
# ============================================

## Example: Simple 3D enemy
func _make_enemy_3d(props: Dictionary) -> Area3D:
	var node := Area3D.new()

	# Mesh
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var sphere := SphereMesh.new()
	sphere.radius = props.get("radius", 0.5)
	sphere.height = sphere.radius * 2
	mesh.mesh = sphere

	# Material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.3)
	mesh.material_override = mat
	node.add_child(mesh)

	# Collision
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = props.get("radius", 0.5)
	collision.shape = shape
	node.add_child(collision)

	return node


## Example: Simple 3D item
func _make_item_3d(props: Dictionary) -> Area3D:
	var node := Area3D.new()

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 0.2)
	mat.emission_energy_multiplier = 1.0
	mesh.material_override = mat
	node.add_child(mesh)

	return node
