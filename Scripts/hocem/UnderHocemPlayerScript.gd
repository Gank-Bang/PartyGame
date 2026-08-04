extends PlayerCharacter

var is_charging : bool = false
var reflect_window : bool = false
var nearby_projectile = null
const DEFLECT_KEY = KEY_SPACE

const DEFLECT_COOLDOWN : float = 1.5
var deflect_cooldown_remaining : float = 0.0

const IFRAME_DURATION : float = 1.5
var iframe_remaining : float = 0.0

var _charge_tween : Tween = null

@onready var _cooldown_bar : ProgressBar = $CooldownBar

func _ready() -> void:
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

	if deflect_cooldown_remaining > 0.0:
		deflect_cooldown_remaining = max(deflect_cooldown_remaining - delta, 0.0)
		_cooldown_bar.value = (1.0 - deflect_cooldown_remaining / DEFLECT_COOLDOWN) * 100.0

	if iframe_remaining > 0.0:
		iframe_remaining -= delta

	if Input.is_key_pressed(DEFLECT_KEY) and deflect_cooldown_remaining <= 0.0 and not is_charging:
		is_charging = true
		_start_charge_animation()

	if is_charging and not Input.is_key_pressed(DEFLECT_KEY):
		is_charging = false
		_stop_charge_animation()
		if reflect_window and nearby_projectile != null:
			_reflect()

func _physics_process(delta: float) -> void:
	if is_charging:
		velocity = Vector2.ZERO
	super._physics_process(delta)

func _start_charge_animation() -> void:
	_charge_tween = create_tween().set_loops(-1)
	_charge_tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.2)
	_charge_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)

func _stop_charge_animation() -> void:
	if _charge_tween:
		_charge_tween.kill()
		_charge_tween = null
	scale = Vector2(1.0, 1.0)

func _flash_damage() -> void:
	var tween = create_tween().set_loops(3)
	tween.tween_property(self, "modulate", Color(1, 0.2, 0.2, 0.5), 0.08)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.08)

func _aim_direction() -> Vector2:
	var to_mouse = get_global_mouse_position() - global_position
	if to_mouse.length() < 0.001:
		return Vector2(0, -1)
	return to_mouse.normalized()

func _reflect() -> void:
	var proj = nearby_projectile
	proj.velocity = _aim_direction() * proj.speed * 1.5
	proj.speed *= 1.5
	proj.immune_body = self

	# Répliquer la déflection : sans ça, seul ce client verrait le changement
	# de trajectoire et les autres continueraient sur l'ancienne.
	var game = get_parent()
	if is_instance_valid(game) and game.has_method("broadcast_reflect"):
		game.broadcast_reflect(proj, peer_id)

	reflect_window = false
	nearby_projectile = null
	deflect_cooldown_remaining = DEFLECT_COOLDOWN

func take_damage() -> void:
	if not is_instance_valid(self):
		return
	if not is_local:
		return
	if iframe_remaining > 0.0:
		return
	iframe_remaining = IFRAME_DURATION
	_flash_damage()
	var game = get_parent()
	if is_instance_valid(game) and game.has_method("damage_player"):
		game.damage_player(peer_id)

func eliminate() -> void:
	visible = false
	$CollisionShape2D.set_deferred("disabled", true)
