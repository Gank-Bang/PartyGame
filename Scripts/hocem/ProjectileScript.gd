extends Area2D                                                                                                                      

var velocity : Vector2 = Vector2.ZERO                                                                                               
var speed : float = 300.0                                                                                                           

func _ready() -> void:
	add_to_group("projectile")

func init(direction: Vector2, spd: float = 300.0) -> void:                                                                          
	speed = spd
	velocity = direction.normalized() * speed
	
func _process(delta: float) -> void:
	position += velocity * delta                                                                                                  
	# Détruire le projectile s'il sort de l'écran
	if position.x < -100 or position.x > 2020 or position.y < -100 or position.y > 1180:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if is_instance_valid(body) and body.has_method("take_damage"):
		body.take_damage()
	queue_free()
