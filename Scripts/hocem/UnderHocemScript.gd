extends BaseGame

const SPAWN_POSITIONS = {
	1: Vector2(660, 750), # Host — bas gauche
	2: Vector2(1260, 750), # Client 2 — bas droite
	3: Vector2(660, 350), # Client 3 — haut gauche
	4: Vector2(1260, 350), # Client 4 — haut droite
}

var player_hp : Dictionary = {}
var elimination_order : Array = []  # peer_ids dans l'ordre d'élimination
var hud

const _CustomPlayerScene = preload("res://Scenes/hocem/UnderHocemPlayer.tscn")

func _on_game_ready() -> void:
	hud = get_node("HUD")
	# Remplacer les joueurs spawné par BaseGame par nos joueurs custom
	for peer_id in players:
		players[peer_id].queue_free()
	players.clear()

	var ids = NetworkManager.players.keys()
	var my_id = NetworkManager.local_peer_id()
	for i in ids.size():
		var peer_id = ids[i]
		var player = _CustomPlayerScene.instantiate()
		add_child(player)
		var index = i + 1
		player.position = SPAWN_POSITIONS.get(index, Vector2(960, 540))
		var player_name = NetworkManager.players[peer_id].get("name", "Joueur")
		player.setup(peer_id, peer_id == my_id, player_name)
		players[peer_id] = player
		player_hp[peer_id] = 3
		hud.setup_player(i, player_name)

func damage_player(peer_id: int) -> void:
	if peer_id not in player_hp:
		return
	if player_hp[peer_id] <= 0:
		return  # déjà éliminé
	player_hp[peer_id] -= 1
	var slot = NetworkManager.players.keys().find(peer_id)
	hud.update_hearts(slot, player_hp[peer_id])
	if player_hp[peer_id] <= 0:
		_eliminate_player(peer_id)

func _eliminate_player(peer_id: int) -> void:
	elimination_order.append(peer_id)
	players[peer_id].eliminate()
	# Broadcaster l'élimination à tous les clients
	NetworkManager.send_game_message(0, {"action": "eliminated", "peer_id": peer_id})

	# Compter les joueurs encore vivants
	var alive = []
	for pid in player_hp:
		if player_hp[pid] > 0:
			alive.append(pid)

	if alive.size() <= 1:
		# Fin de partie — le survivant gagne
		var winner_id = alive[0] if alive.size() == 1 else elimination_order[0]
		_show_results(winner_id)
		if NetworkManager.is_host:
			end_game(winner_id)

func _show_results(winner_id: int) -> void:
	# Construire le classement : gagnant en premier, puis éliminations à l'envers
	var ranking = [winner_id]
	for i in range(elimination_order.size() - 1, -1, -1):
		ranking.append(elimination_order[i])

	print("=== RÉSULTATS ===")
	for i in ranking.size():
		var pid = ranking[i]
		var name = NetworkManager.players[pid].get("name", "Joueur")
		print("%d. %s" % [i + 1, name])

func _on_custom_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"eliminated":
			var pid = int(data.get("peer_id", 0))
			if pid in players:
				players[pid].eliminate()

func _on_game_over(winner_peer_id: int) -> void:
	_show_results(winner_peer_id)
