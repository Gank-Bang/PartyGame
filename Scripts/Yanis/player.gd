extends CharacterBody2D

@export var speed = 300
@export var fire_rate := 0.25

var can_shoot := true


func _physics_process(delta):
	handle_movement()
	handle_rotation()


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
