extends Node2D

@export var vision_distance := 250.0
@export var vision_angle := 17.0


func _process(_delta):

	var owner = get_parent()

	for player in get_tree().get_nodes_in_group("players"):

		if player == owner:
			continue

		player.visible = can_see_player(owner, player)



func can_see_player(owner: CharacterBody2D, target: CharacterBody2D) -> bool:

	var collision := target.get_node("CollisionShape2D")

	if collision == null:
		return false

	var shape := collision.shape as RectangleShape2D

	if shape == null:
		return false

	var extents = shape.size / 2.0

	var points = [
		Vector2.ZERO,                              # centre
		Vector2(0, -extents.y),                    # tête
		Vector2(-extents.x, 0),                    # gauche
		Vector2(extents.x, 0),                     # droite
		Vector2(0, extents.y)                      # bas
	]

	for offset in points:

		if can_see_point(owner, target.global_position + offset):
			return true

	return false



func can_see_point(owner, point: Vector2) -> bool:

	var origin = owner.global_position

	# Distance

	if origin.distance_to(point) > vision_distance:
		return false

	# Angle

	var forward = Vector2.RIGHT.rotated(owner.rotation)

	var dir = (point - origin).normalized()

	if forward.dot(dir) < cos(deg_to_rad(vision_angle)):
		return false

	# Raycast

	var query = PhysicsRayQueryParameters2D.create(origin, point)

	query.collision_mask = 1
	query.exclude = [owner]

	var result = get_world_2d().direct_space_state.intersect_ray(query)

	return result.is_empty()
