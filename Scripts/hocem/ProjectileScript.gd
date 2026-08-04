extends Area2D

enum ColorType { NORMAL, BLUE, ORANGE }

const MOVEMENT_THRESHOLD := 5.0

var velocity : Vector2 = Vector2.ZERO
var speed : float = 300.0
var immune_body: Node2D = null
var color_type : ColorType = ColorType.NORMAL

## Identifiant réseau attribué par l'hôte, identique sur tous les clients.
## -1 = projectile purement local (non répliqué).
var net_id : int = -1

func _ready() -> void:
	add_to_group("projectile")

func init(direction: Vector2, spd: float = 300.0, type: ColorType = ColorType.NORMAL) -> void:
	speed = spd
	color_type = type
	velocity = direction.normalized() * speed
	_update_visual()

func _update_visual() -> void:
	match color_type:
		ColorType.BLUE:
			$Sprite2D.modulate = Color.CORNFLOWER_BLUE
			$CPUParticles2D.color = Color.CORNFLOWER_BLUE
		ColorType.ORANGE:
			$Sprite2D.modulate = Color.ORANGE
			$CPUParticles2D.color = Color.ORANGE

func _process(delta: float) -> void:
	position += velocity * delta
	# Sortie d'écran : chaque client peut nettoyer de son côté, le calcul est
	# déterministe donc tout le monde arrive à la même conclusion.
	if position.x < -100 or position.x > 2020 or position.y < -100 or position.y > 1180:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body == immune_body:
		return
	if not is_instance_valid(body) or not body.has_method("take_damage"):
		return
	# Chaque client ne juge que les collisions de SON joueur : lui seul fait
	# autorité sur sa position (et sur sa velocity, qui n'est pas répliquée).
	# La destruction est ensuite répliquée aux autres via despawn_projectile().
	if "is_local" in body and not body.is_local:
		return

	var should_damage := true
	match color_type:
		ColorType.BLUE:
			should_damage = body.velocity.length() > MOVEMENT_THRESHOLD
		ColorType.ORANGE:
			should_damage = body.velocity.length() <= MOVEMENT_THRESHOLD

	if should_damage:
		body.take_damage()
		_despawn()

## Se retire ici et prévient le jeu, qui réplique la destruction aux autres.
func _despawn() -> void:
	var game := get_parent()
	if net_id >= 0 and game != null and game.has_method("despawn_projectile"):
		game.despawn_projectile(net_id)
	queue_free()
