extends Node

func player_died(dead_player):

	var alive_players = []

	for player in get_tree().get_nodes_in_group("players"):
		if player != dead_player:
			alive_players.append(player)

	if alive_players.size() <= 1:
		game_over(alive_players)


func game_over(alive_players):

	get_tree().paused = true

	var ui = get_parent().get_node("UI/GameOver")

	if alive_players.size() == 1:
		ui.show_winner(alive_players[0].name)

	else:
		ui.show_winner("Nobody")
