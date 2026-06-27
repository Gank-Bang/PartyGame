extends Node2D

@export var vision_distance := 250.0
@export var vision_angle := 17.0

func _process(_delta: float) -> void:

	var owner = get_parent()

	# Seul le joueur local calcule la vision
	if !owner.is_local_player:
		return

	for player in get_tree().get_nodes_in_group("players"):

		# On ne cache jamais son propre joueur
		if player == owner:
			continue

		var visible_to_me := can_see_player(owner, player)

		player.get_node("Sprite2D").visible = visible_to_me
		player.get_node("PointLight2D").visible = visible_to_me


func can_see_player(owner: CharacterBody2D, target: CharacterBody2D) -> bool:

	var collision := target.get_node("CollisionShape2D")

	if collision == null:
		return false

	var shape := collision.shape as RectangleShape2D

	if shape == null:
		return false

	var extents := shape.size / 2.0

	var points := [
		Vector2.ZERO,
		Vector2(0, -extents.y),
		Vector2(-extents.x, 0),
		Vector2(extents.x, 0),
		Vector2(0, extents.y)
	]

	for offset in points:

		if can_see_point(owner, target.global_position + offset):
			return true

	return false


func can_see_point(owner: CharacterBody2D, point: Vector2) -> bool:

	var origin := owner.global_position

	# Distance
	if origin.distance_to(point) > vision_distance:
		return false

	# Angle
	var forward := Vector2.RIGHT.rotated(owner.rotation)
	var dir := (point - origin).normalized()

	if forward.dot(dir) < cos(deg_to_rad(vision_angle)):
		return false

	# Raycast
	var query := PhysicsRayQueryParameters2D.create(origin, point)

	query.collision_mask = 1
	query.exclude = [owner]

	var result := get_world_2d().direct_space_state.intersect_ray(query)

	return result.is_empty()
