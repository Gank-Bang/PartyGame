extends Node

signal game_over_requested(winner_peer_id: int)
signal game_over(winner_name: String)


func player_died(dead_player) -> void:

	# Seul l'hôte décide de la fin de partie
	if !NetworkManager.is_host:
		return

	var alive_players: Array = []

	for player in get_tree().get_nodes_in_group("players"):

		if !is_instance_valid(player):
			continue

		if player != dead_player:
			alive_players.append(player)

	if alive_players.size() > 1:
		return

	if alive_players.is_empty():
		game_over_requested.emit(-1)
	else:
		game_over_requested.emit(alive_players[0].peer_id)


func finish_game(winner_peer_id: int) -> void:

	get_tree().paused = true

	var winner_name := "Nobody"

	if winner_peer_id != -1 and NetworkManager.players.has(winner_peer_id):
		winner_name = NetworkManager.players[winner_peer_id]["name"]

	game_over.emit(winner_name)
