extends Node2D

const _FlatButtonScene := preload("res://Scenes/RafGames/Components/FlatButton.tscn")
const PLAYER_SCENE := preload("res://Scenes/Yanis/Player.tscn")
const SELECT_GAMES_SCENE := "res://Scenes/Lobby/SelectGames.tscn"
const QUIT_FACE_COLOR := Color(0.56, 0.18, 0.2, 1)
const QUIT_SHADOW_COLOR := Color(0.35, 0.09, 0.11, 1)

@onready var players_node: Node2D = $Players
@onready var spawn_points := $Map/SpawnPoints.get_children()
@onready var cooldown_bar = $UI/HUD/CooldownBar
@onready var game_manager = $GameManager

# peer_id -> Player
var players: Dictionary = {}
var _returning_to_select_games: bool = false


func _ready() -> void:

	spawn_players()
	_setup_host_quit_button()

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
		"return_to_select_games":
			if _begin_return_to_select_games():
				_go_to_select_games()

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

func _setup_host_quit_button() -> void:
	if not NetworkManager.is_host:
		return

	var canvas := CanvasLayer.new()
	canvas.name = "HostQuitCanvas"
	canvas.layer = 90
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	var root := Control.new()
	root.name = "HostQuitRoot"
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)

	var btn := _FlatButtonScene.instantiate() as Control
	btn.name = "HostQuitButton"
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.custom_minimum_size = Vector2(200, 60)
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -220.0
	btn.offset_top = -80.0
	btn.offset_right = -20.0
	btn.offset_bottom = -20.0
	btn.set("text", "Quitter")
	btn.set("face_color", QUIT_FACE_COLOR)
	btn.set("shadow_color", QUIT_SHADOW_COLOR)
	btn.connect("pressed", _on_host_quit_pressed)
	root.add_child(btn)

func _on_host_quit_pressed() -> void:
	if not NetworkManager.is_host:
		return
	if not _begin_return_to_select_games():
		return
	NetworkManager.send_game_message(0, {"action": "return_to_select_games"})
	await get_tree().create_timer(0.2, true).timeout
	_go_to_select_games()

func _begin_return_to_select_games() -> bool:
	if _returning_to_select_games:
		return false
	_returning_to_select_games = true
	get_tree().paused = false
	return true

func _go_to_select_games() -> void:
	if get_tree().current_scene != self:
		return
	get_tree().change_scene_to_file(SELECT_GAMES_SCENE)
