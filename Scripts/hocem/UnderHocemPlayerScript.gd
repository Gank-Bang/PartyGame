extends PlayerCharacter

const BulletScene = preload("res://Scenes/hocem/PlayerBullet.tscn")

var is_charging : bool = false
var reflect_window : bool = false
var nearby_projectile = null
const FIRE_KEY = KEY_SPACE

func _ready() -> void:
	add_to_group("projectile")
	$ReflectZone.area_entered.connect(_on_reflect_zone_entered)
	$ReflectZone.area_exited.connect(_on_reflect_zone_exited)

func _on_reflect_zone_entered(area: Area2D) -> void:
	if area.is_in_group("projectile"):
		reflect_window = true
		nearby_projectile = area

func _on_reflect_zone_exited(area: Area2D) -> void:
	if area == nearby_projectile:
		reflect_window = false
		nearby_projectile = null

func _process(delta: float) -> void:
	if not is_local:
		return

	if Input.is_key_pressed(FIRE_KEY):
		is_charging = true

	if is_charging and not Input.is_key_pressed(FIRE_KEY):
		is_charging = false
		if reflect_window and nearby_projectile != null:
			_reflect()
		else:
			_shoot()

func _physics_process(delta: float) -> void:
	if is_charging:
		velocity = Vector2.ZERO
	super._physics_process(delta)

func _shoot() -> void:
	var bullet = BulletScene.instantiate()
	bullet.position = global_position
	bullet.init(Vector2(0, -1))
	get_parent().add_child(bullet)

func _reflect() -> void:
	nearby_projectile.velocity = Vector2(0, -1) * nearby_projectile.speed * 1.5
	nearby_projectile.speed *= 1.5
	reflect_window = false
	nearby_projectile = null

func take_damage() -> void:
	if not is_local:
		return
	var game = get_parent()
	if game.has_method("damage_player"):
		game.damage_player(peer_id)
