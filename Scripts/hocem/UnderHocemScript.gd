extends BaseGame

# Utilisées à 3-4 joueurs : zone joueurs complète, murs intérieurs retirés
const SPAWN_POSITIONS_BIG = {
	1: Vector2(660, 560), # Host — haut gauche
	2: Vector2(1260, 560), # Client 2 — haut droite
	3: Vector2(660, 740), # Client 3 — bas gauche
	4: Vector2(1260, 740), # Client 4 — bas droite
}

# Utilisées à 1-2 joueurs : zone réduite par les murs intérieurs (MurGaucheInterieur/MurDroiteInterieur/MurBasInterieur)
const SPAWN_POSITIONS_SMALL = {
	1: Vector2(760, 560), # Host — gauche
	2: Vector2(1160, 560), # Client 2 — droite
}

const INNER_WALLS = ["MurGaucheInterieur", "MurDroiteInterieur", "MurBasInterieur"]

var player_hp : Dictionary = {}
var elimination_order : Array = []  # peer_ids dans l'ordre d'élimination
var elimination_times : Dictionary = {}  # peer_id → temps de survie en secondes
var game_time : float = 0.0
var game_over : bool = false
var hud
var timer_label : Label

# ── Projectiles répliqués ─────────────────────────────────────────────────────
# L'hôte fait autorité sur les tirs du boss : il crée chaque projectile avec un
# id unique et le réplique. Le déplacement étant déterministe (vitesse
# constante), aucune sync par frame n'est nécessaire — seuls les événements
# (apparition, déflection, destruction) transitent sur le réseau.

var projectiles : Dictionary = {}  # net_id → nœud Projectile
var _next_projectile_id : int = 1

const _CustomPlayerScene = preload("res://Scenes/hocem/UnderHocemPlayer.tscn")
const _ProjectileScene = preload("res://Scenes/hocem/Projectile.tscn")

func _on_game_ready() -> void:
	hud = get_node("HUD")
	timer_label = get_node_or_null("GameTimer")
	# Remplacer les joueurs spawné par BaseGame par nos joueurs custom
	for peer_id in players:
		players[peer_id].queue_free()
	players.clear()

	var ids = NetworkManager.players.keys()
	var my_id = NetworkManager.local_peer_id()

	# Zone réduite à 1-2 joueurs, zone complète à 3-4 joueurs (sinon trop petit)
	var spawn_positions = SPAWN_POSITIONS_SMALL if ids.size() <= 2 else SPAWN_POSITIONS_BIG
	if ids.size() > 2:
		for wall_name in INNER_WALLS:
			var wall = get_node_or_null(wall_name)
			if wall:
				wall.queue_free()

	for i in ids.size():
		var peer_id = ids[i]
		var player = _CustomPlayerScene.instantiate()
		add_child(player)
		var index = i + 1
		player.position = spawn_positions.get(index, Vector2(960, 540))
		var player_name = NetworkManager.players[peer_id].get("name", "Joueur")
		player.setup(peer_id, peer_id == my_id, player_name)
		players[peer_id] = player
		player_hp[peer_id] = 3
		hud.setup_player(i, player_name)

func _process(delta: float) -> void:
	if game_over:
		return
	game_time += delta
	if timer_label:
		timer_label.text = "%02d:%02d" % [int(game_time) / 60, int(game_time) % 60]

# ── Projectiles ───────────────────────────────────────────────────────────────

## Appelé par le boss (hôte uniquement) : crée le projectile ici et le réplique.
func spawn_projectile(pos: Vector2, direction: Vector2, speed: float, type: int) -> void:
	var id := _next_projectile_id
	_next_projectile_id += 1
	_create_projectile(id, pos, direction, speed, type)
	NetworkManager.send_game_message(0, {
		"action": "proj_spawn", "id": id,
		"x": pos.x, "y": pos.y,
		"dx": direction.x, "dy": direction.y,
		"speed": speed, "type": type,
	})

func _create_projectile(id: int, pos: Vector2, direction: Vector2, speed: float, type: int) -> void:
	var proj = _ProjectileScene.instantiate()
	proj.position = pos
	proj.init(direction, speed, type)
	proj.net_id = id
	# Quelle que soit la raison de sa disparition (touché un joueur, sortie
	# d'écran, fin de partie), le projectile se retire seul du registre.
	proj.tree_exited.connect(func(): projectiles.erase(id))
	add_child(proj)
	projectiles[id] = proj

## Appelé par un projectile qui vient de toucher le joueur local. Il se libère
## lui-même : ici on ne fait que prévenir les autres clients.
func despawn_projectile(id: int) -> void:
	NetworkManager.send_game_message(0, {"action": "proj_destroy", "id": id})

func _remove_projectile(id: int) -> void:
	if id in projectiles and is_instance_valid(projectiles[id]):
		projectiles[id].queue_free()

## Réplique une déflection : les autres clients reçoivent la nouvelle trajectoire
## ainsi que la position exacte au moment du renvoi (compense la latence).
func broadcast_reflect(proj, by_peer_id: int) -> void:
	if proj.net_id < 0:
		return
	NetworkManager.send_game_message(0, {
		"action": "proj_reflect", "id": proj.net_id,
		"x": proj.position.x, "y": proj.position.y,
		"vx": proj.velocity.x, "vy": proj.velocity.y,
		"speed": proj.speed, "by": by_peer_id,
	})

func damage_player(peer_id: int) -> void:
	if peer_id not in player_hp:
		return
	if player_hp[peer_id] <= 0:
		return  # déjà éliminé
	player_hp[peer_id] -= 1
	var slot = NetworkManager.players.keys().find(peer_id)
	hud.update_hearts(slot, player_hp[peer_id])
	NetworkManager.send_game_message(0, {"action": "hp_update", "peer_id": peer_id, "hp": player_hp[peer_id]})
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
	game_over = true  # fige le chrono affiché
	# Stopper le boss (tirs + musique) et supprimer les projectiles en cours
	var boss = get_node_or_null("Boss")
	if boss:
		boss.stop_fight()
	for node in get_children():
		if node.is_in_group("projectile"):
			node.queue_free()
	projectiles.clear()

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
		"proj_spawn":
			_create_projectile(
				int(data.get("id", 0)),
				Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))),
				Vector2(float(data.get("dx", 0.0)), float(data.get("dy", 1.0))),
				float(data.get("speed", 300.0)),
				int(data.get("type", 0)))
		"proj_reflect":
			var rid = int(data.get("id", 0))
			if rid in projectiles and is_instance_valid(projectiles[rid]):
				var proj = projectiles[rid]
				proj.position = Vector2(float(data.get("x", proj.position.x)),
										float(data.get("y", proj.position.y)))
				proj.velocity = Vector2(float(data.get("vx", 0.0)), float(data.get("vy", 0.0)))
				proj.speed = float(data.get("speed", proj.speed))
				var by = int(data.get("by", 0))
				if by in players:
					proj.immune_body = players[by]
		"proj_destroy":
			_remove_projectile(int(data.get("id", 0)))
		"hp_update":
			var pid = int(data.get("peer_id", 0))
			var hp = int(data.get("hp", 0))
			if pid in player_hp:
				player_hp[pid] = hp
				hud.update_hearts(NetworkManager.players.keys().find(pid), hp)
		"eliminated":
			var pid = int(data.get("peer_id", 0))
			if pid in players:
				players[pid].eliminate()
				player_hp[pid] = 0
				hud.update_hearts(NetworkManager.players.keys().find(pid), 0)
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
