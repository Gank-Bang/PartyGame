extends Area2D

@export var speed := 900

var direction := Vector2.ZERO


func _physics_process(delta):
	position += direction * speed * delta

func _ready():
	await get_tree().create_timer(2.0).timeout
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	print("Touché :", body.name)
	if body.has_method("take_damage"):
		body.take_damage(1)
	queue_free()
