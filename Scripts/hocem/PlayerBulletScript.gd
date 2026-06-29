extends Area2D

var velocity : Vector2 = Vector2.ZERO
var speed : float = 400.0

func init(direction: Vector2, spd: float = 400.0) -> void:
    speed = spd
    velocity = direction.normalized() * speed

func _process(delta: float) -> void:
    position += velocity * delta
    if position.x < -100 or position.x > 2020 or position.y < -100 or position.y > 1180:
        queue_free()