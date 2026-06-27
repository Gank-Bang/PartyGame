extends Area2D

@export var speed := 900

var direction := Vector2.ZERO


func _physics_process(delta):
	position += direction * speed * delta

func _ready():
	await get_tree().create_timer(2.0).timeout
	queue_free()
