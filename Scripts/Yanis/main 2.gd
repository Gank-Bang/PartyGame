extends Node2D

const PLAYER_SCENE = preload("res://Scenes/Yanis/Player.tscn")

@onready var players_node = $Players
@onready var spawn_points = $Map/SpawnPoints.get_children()
@onready var cooldown_bar = $UI/HUD/CooldownBar


func _ready():
	if NetworkManager.players.is_empty():
		return
	spawn_players()


func spawn_players():
	randomize()
	var available_spawns = spawn_points.duplicate()
	available_spawns.shuffle()

	var index := 0

	for peer_id in NetworkManager.players.keys():

		if index >= available_spawns.size():
			push_error("Pas assez de SpawnPoints sur la map !")
			return

		var player = PLAYER_SCENE.instantiate()

		player.setup(peer_id)

		player.global_position = available_spawns[index].global_position

		players_node.add_child(player)

		if player.is_local_player:
			player.cooldown_changed.connect(cooldown_bar.update_cooldown)

		index += 1
