extends Area2D

@export var speed := 900.0

var direction := Vector2.ZERO


func _physics_process(delta: float) -> void:
	position += direction * speed * delta


func _ready() -> void:
	await get_tree().create_timer(2.0).timeout
	queue_free()


func _on_body_entered(body: Node2D) -> void:

	if !body.has_method("take_damage"):
		queue_free()
		return

	# L'hôte applique directement les dégâts
	if NetworkManager.is_host:

		body.take_damage(1)

	# Les clients demandent à l'hôte d'appliquer les dégâts
	else:

		NetworkManager.send_game_message(0, {
			"action": "player_hit",
			"target": body.peer_id,
			"damage": 1
		})

	queue_free()
