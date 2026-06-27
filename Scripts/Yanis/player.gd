extends CharacterBody2D

@export var speed = 300
@export var shoot_cooldown := 2.5

const BULLET_SCENE = preload("res://Scenes/Yanis/Bullet.tscn")
var cooldown := 0.0

signal cooldown_changed(progress: float)

func _physics_process(delta):
	cooldown = max(cooldown - delta, 0.0)
	var progress = 1.0 - (cooldown / shoot_cooldown)
	cooldown_changed.emit(progress)
	handle_movement()
	handle_rotation()
	handle_shooting()


func handle_movement():

	var direction = Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
		"ui_down"
	)

	velocity = direction * speed

	move_and_slide()


func handle_rotation():

	var mouse_direction = get_global_mouse_position() - global_position

	rotation = mouse_direction.angle()
	
func handle_shooting():

	if cooldown > 0.0:
		return

	if Input.is_action_just_pressed("shoot"):
		shoot()
		cooldown = shoot_cooldown
		
func shoot():
	var bullet = BULLET_SCENE.instantiate()
	get_parent().add_child(bullet)
	var direction = get_mouse_direction()

	bullet.direction = direction
	bullet.global_position = global_position + direction * 20

func get_mouse_direction() -> Vector2:
	return (get_global_mouse_position() - global_position).normalized()
