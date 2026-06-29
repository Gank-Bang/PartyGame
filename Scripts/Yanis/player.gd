extends CharacterBody2D

@export var speed := 300.0
@export var shoot_cooldown := 2.5
@export var is_local_player := true
@export var max_health := 1
@export var send_rate := 20.0

@onready var muzzle_flash: AnimatedSprite2D = $MuzzleFlash
@onready var flashlight: PointLight2D = $FlashLight
@onready var shoot_glow: Sprite2D = $ShootGlow

const BULLET_SCENE = preload("res://Scenes/Yanis/Bullet.tscn")

var peer_id := 0
var cooldown := 0.0
var health := 1
var game_manager
var _send_timer := 0.0
var _remote_target := Vector2.ZERO
var _lerp_speed := 15.0
var glow_tween: Tween

signal cooldown_changed(progress: float)

func setup(id: int) -> void:
	peer_id = id
	is_local_player = (peer_id == NetworkManager.local_peer_id())
	_remote_target = global_position

	$Camera2D.enabled = is_local_player

func _ready() -> void:
	health = max_health
	muzzle_flash.visible = false

func _physics_process(delta: float) -> void:

	# --------------------------
	# Joueur distant
	# --------------------------
	if !is_local_player:
		global_position = global_position.lerp(
			_remote_target,
			delta * _lerp_speed
		)
		return

	# --------------------------
	# Joueur local
	# --------------------------
	cooldown = max(cooldown - delta, 0.0)

	var progress := 1.0 - (cooldown / shoot_cooldown)
	cooldown_changed.emit(progress)

	handle_movement()
	handle_rotation()
	handle_shooting()

	move_and_slide()

	_send_timer += delta

	if _send_timer >= 1.0 / send_rate:
		_send_timer = 0.0

		NetworkManager.send_game_message(0, {
			"action": "player_move",
			"x": global_position.x,
			"y": global_position.y,
			"rotation": rotation
		})


func handle_movement() -> void:

	var direction := Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
		"ui_down"
	)

	if Input.is_key_pressed(KEY_Q): direction.x -= 1.0
	if Input.is_key_pressed(KEY_D): direction.x += 1.0
	if Input.is_key_pressed(KEY_Z): direction.y -= 1.0
	if Input.is_key_pressed(KEY_S): direction.y += 1.0

	if direction.length() > 1.0:
		direction = direction.normalized()

	velocity = direction * speed


func handle_rotation() -> void:

	var mouse_direction = get_global_mouse_position() - global_position
	rotation = mouse_direction.angle()


func handle_shooting() -> void:

	if cooldown > 0.0:
		return

	if Input.is_action_just_pressed("shoot"):
		shoot()
		cooldown = shoot_cooldown


func shoot() -> void:

	var bullet = BULLET_SCENE.instantiate()

	muzzle_flash.visible = true
	muzzle_flash.play("shoot")
	
	flash_shot()

	get_parent().add_child(bullet)

	var direction = get_mouse_direction()

	bullet.direction = direction
	bullet.global_position = global_position + direction * 40


func get_mouse_direction() -> Vector2:
	return (get_global_mouse_position() - global_position).normalized()


func take_damage(amount: int) -> void:

	health -= amount

	if health <= 0:
		die()


func die() -> void:

	if game_manager:
		game_manager.player_died(self)
	
	queue_free()


func set_network_transform(pos: Vector2, rot: float) -> void:

	_remote_target = pos
	rotation = rot


func _on_muzzle_flash_animation_finished() -> void:
	muzzle_flash.visible = false
	
	
func flash_shot():

	if is_instance_valid(glow_tween):
		glow_tween.kill()

	shoot_glow.scale = Vector2.ONE
	shoot_glow.modulate.a = 0.8

	glow_tween = create_tween()

	glow_tween.parallel().tween_property(
		shoot_glow,
		"scale",
		Vector2.ONE * 3.5,
		0.08
	)

	glow_tween.parallel().tween_property(
		shoot_glow,
		"modulate:a",
		0.0,
		0.08
	)
