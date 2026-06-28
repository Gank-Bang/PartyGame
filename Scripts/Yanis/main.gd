extends Node2D

const PLAYER_SCENE := preload("res://Scenes/Yanis/Player.tscn")

@onready var players_node: Node2D = $Players
@onready var spawn_points := $Map/SpawnPoints.get_children()
@onready var cooldown_bar = $UI/HUD/CooldownBar
@onready var game_manager = $GameManager

# peer_id -> Player
var players: Dictionary = {}


func _ready() -> void:

	spawn_players()

	if !NetworkManager.game_message.is_connected(_on_game_message):
		NetworkManager.game_message.connect(_on_game_message)

	if !game_manager.game_over_requested.is_connected(_on_game_over_requested):
		game_manager.game_over_requested.connect(_on_game_over_requested)


func _exit_tree() -> void:

	if NetworkManager.game_message.is_connected(_on_game_message):
		NetworkManager.game_message.disconnect(_on_game_message)

	if game_manager.game_over_requested.is_connected(_on_game_over_requested):
		game_manager.game_over_requested.disconnect(_on_game_over_requested)


func spawn_players() -> void:

	if NetworkManager.players.size() > spawn_points.size():
		push_error("Pas assez de SpawnPoints pour tous les joueurs.")
		return

	var spawn_positions: Dictionary = {}
	var index := 0

	for peer_id in NetworkManager.players.keys():
		spawn_positions[peer_id] = spawn_points[index].global_position
		index += 1

	_spawn_players(spawn_positions)


func _spawn_players(spawn_positions: Dictionary) -> void:

	for peer_id in spawn_positions.keys():

		var player = PLAYER_SCENE.instantiate()

		player.game_manager = game_manager
		player.setup(peer_id)
		player.global_position = spawn_positions[peer_id]

		players_node.add_child(player)
		players[peer_id] = player

		if player.is_local_player:
			player.cooldown_changed.connect(cooldown_bar.update_cooldown)


func _on_game_over_requested(winner_peer_id: int) -> void:

	if !NetworkManager.is_host:
		return

	NetworkManager.send_game_message(0, {
		"action": "game_over",
		"winner": winner_peer_id
	})

	# L'hôte applique immédiatement
	game_manager.finish_game(winner_peer_id)


func _on_game_message(from_id: int, data: Dictionary) -> void:

	match data.get("action", ""):

		"player_move":

			if !players.has(from_id):
				return

			var player = players[from_id]

			if !is_instance_valid(player):
				players.erase(from_id)
				return

			player.set_network_transform(
				Vector2(
					float(data["x"]),
					float(data["y"])
				),
				float(data["rotation"])
			)

		"game_over":

			game_manager.finish_game(
				int(data["winner"])
			)

		"restart":

			get_tree().paused = false
			get_tree().reload_current_scene()

		"host_left":

			get_tree().paused = false
			NetworkManager.disconnect_from_lobby()
			get_tree().change_scene_to_file("res://Scenes/Main.tscn")

		"player_hit":

			# Seul l'hôte traite les dégâts
			if !NetworkManager.is_host:
				return

			var target_id := int(data["target"])

			if !players.has(target_id):
				return

			var target = players[target_id]

			if !is_instance_valid(target):
				return

			target.take_damage(
				int(data["damage"])
			)
