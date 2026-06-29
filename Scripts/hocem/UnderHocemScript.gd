extends BaseGame

const SPAWN_POSITIONS = {
	1: Vector2(660, 750), # Host — bas gauche
	2: Vector2(1260, 750), # Client 2 — bas droite
	3: Vector2(660, 350), # Client 3 — haut gauche
	4: Vector2(1260, 350), # Client 4 — haut droite
}

var player_hp : Dictionary = {}
var elimination_order : Array = []  # peer_ids dans l'ordre d'élimination
var elimination_times : Dictionary = {}  # peer_id → temps de survie en secondes
var game_time : float = 0.0
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

func _process(delta: float) -> void:
	game_time += delta

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
	elimination_times[peer_id] = game_time
	players[peer_id].eliminate()
	# Broadcaster l'élimination à tous les clients
	NetworkManager.send_game_message(0, {"action": "eliminated", "peer_id": peer_id})

	# Compter les joueurs encore vivants
	var alive = []
	for pid in player_hp:
		if player_hp[pid] > 0:
			alive.append(pid)

	if alive.size() == 0:
		# Tout le monde est mort — le dernier éliminé est le gagnant
		var winner_id = elimination_order[elimination_order.size() - 1]
		_show_results(winner_id)
		if NetworkManager.is_host:
			end_game(winner_id)

func _show_results(winner_id: int) -> void:
	# Stopper le boss et supprimer les projectiles en cours
	get_node("Boss").set_process(false)
	for node in get_children():
		if node.is_in_group("projectile"):
			node.queue_free()

	# Construire le classement : gagnant en premier, puis éliminations à l'envers
	var ranking = [winner_id]
	for i in range(elimination_order.size() - 1, -1, -1):
		if elimination_order[i] != winner_id:
			ranking.append(elimination_order[i])

	elimination_times[winner_id] = game_time
	var result_screen = get_node("ResultScreen")
	result_screen.visible = true
	result_screen.show_results(ranking, elimination_times)

func _on_custom_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"eliminated":
			var pid = int(data.get("peer_id", 0))
			if pid in players:
				players[pid].eliminate()
				player_hp[pid] = 0
				elimination_order.append(pid)
				elimination_times[pid] = game_time
				# Vérifier si tout le monde est mort
				var alive = []
				for p in player_hp:
					if player_hp[p] > 0:
						alive.append(p)
				if alive.size() == 0:
					var winner_id = elimination_order[elimination_order.size() - 1]
					_show_results(winner_id)

func _on_game_over(winner_peer_id: int) -> void:
	_show_results(winner_peer_id)
