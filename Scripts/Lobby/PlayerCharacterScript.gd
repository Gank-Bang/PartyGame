## Personnage joueur générique.
## - Si is_local = true  : lit l'input clavier/manette et envoie la position via relais.
## - Si is_local = false : reçoit les mises à jour de position et interpole.
##
## Les mini-jeux peuvent étendre cette scène ou remplacer _handle_input().
class_name PlayerCharacter
extends CharacterBody2D

# ── Configuration ─────────────────────────────────────────────────────────────

@export var speed: float = 250.0
## Nombre de mises à jour réseau envoyées par seconde
@export var send_rate: float = 20.0

# ── État ──────────────────────────────────────────────────────────────────────

var peer_id: int = 0
var is_local: bool = false

var _send_timer: float = 0.0
var _remote_target: Vector2 = Vector2.ZERO
var _lerp_speed: float = 15.0

@onready var _label: Label = $Label
@onready var _sprite: ColorRect = $ColorRect

# ── Initialisation ────────────────────────────────────────────────────────────

## Appeler après add_child() pour configurer le personnage.
func setup(p_peer_id: int, p_is_local: bool, player_name: String = "") -> void:
	peer_id = p_peer_id
	is_local = p_is_local
	_remote_target = position

	_label.text = player_name if player_name != "" else "Joueur " + str(peer_id)

	# Couleur différente pour le joueur local
	if is_local:
		_sprite.color = Color(0.2, 0.6, 1.0)   # bleu
	else:
		_sprite.color = Color(1.0, 0.4, 0.2)   # orange

# ── Boucle ────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_local:
		_handle_input()
		move_and_slide()
		_send_timer += delta
		if _send_timer >= 1.0 / send_rate:
			_send_timer = 0.0
			_send_state()
	else:
		# Interpolation vers la position reçue du réseau
		position = position.lerp(_remote_target, _lerp_speed * delta)

# ── Input ─────────────────────────────────────────────────────────────────────

## Surcharger dans les mini-jeux pour des contrôles spécifiques.
func _handle_input() -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = dir * speed

# ── Réseau ────────────────────────────────────────────────────────────────────

func _send_state() -> void:
	NetworkManager.send_game_message(0, {
		"action": "player_state",
		"id": peer_id,
		"x": position.x,
		"y": position.y,
	})

## Appelé par BaseGame quand un message "player_state" arrive pour ce personnage.
func apply_remote_state(data: Dictionary) -> void:
	_remote_target = Vector2(float(data.get("x", _remote_target.x)),
							 float(data.get("y", _remote_target.y)))
