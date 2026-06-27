extends CharacterBody2D

@export var speed = 300
@export var shoot_cooldown := 2.5
@export var is_local_player := true
@export var max_health := 1
@export var peer_id := -1

const BULLET_SCENE = preload("res://Scenes/Yanis/Bullet.tscn")
var cooldown := 0.0
var health := 1

signal cooldown_changed(progress: float)

func setup(id: int):
	peer_id = id
	is_local_player = (peer_id == NetworkManager.local_peer_id())

func _physics_process(delta):

	if is_local_player:
		cooldown = max(cooldown - delta, 0.0)
		var progress = 1.0 - (cooldown / shoot_cooldown)
		cooldown_changed.emit(progress)

		handle_movement()
		handle_rotation()
		handle_shooting()

	move_and_slide()


func handle_movement():

	var direction = Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
		"ui_down"
	)

	velocity = direction * speed


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
	bullet.global_position = global_position + direction * 40

func get_mouse_direction() -> Vector2:
	return (get_global_mouse_position() - global_position).normalized()

func _ready():
	health = max_health
	
func take_damage(amount: int):

	health -= amount

	if health <= 0:
		die()

func die():

	print("Die() appelée")

	get_parent().get_node("GameManager").player_died(self)

	queue_free()
