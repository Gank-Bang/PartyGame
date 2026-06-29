extends BaseGame

const SPAWN_POSITIONS = {
	1: Vector2(660, 750), # Host — bas gauche
	2: Vector2(1260, 750), # Client 2 — bas droite
	3: Vector2(660, 350), # Client 3 — haut gauche
	4: Vector2(1260, 350), # Client 4 — haut droite
}

var player_hp : Dictionary = {}
@onready var hud = $HUD

const _CustomPlayerScene = preload("res://Scenes/hocem/UnderHocemPlayer.tscn")

func _on_game_ready() -> void:
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
	player_hp[peer_id] -= 1
	var slot = NetworkManager.players.keys().find(peer_id)
	hud.update_hearts(slot, player_hp[peer_id])
	if player_hp[peer_id] <= 0:
		print("Joueur %d éliminé !" % peer_id)
