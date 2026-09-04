## Classe de base pour tous les mini-jeux.
##
## Pour créer un mini-jeu :
##   1. Crée une scène qui étend BaseGame (ou instancie BaseGame.tscn)
##   2. Crée un script qui extends BaseGame
##   3. Surcharge les méthodes virtuelles :
##        _on_game_ready()       → setup de ton mini-jeu (timers, obstacles, etc.)
##        _on_custom_message()   → messages réseau spécifiques à ton jeu
##        _on_game_over()        → afficher les résultats, retour au lobby
##
## Exemple d'envoi d'un event personnalisé :
##   NetworkManager.send_game_message(0, {"action": "scored", "player": my_id})
##
## Exemple de fin de partie :
##   end_game(winner_peer_id)
class_name BaseGame
extends Node2D

const _HostQuitButtonScene := preload("res://Scenes/RafGames/Components/FlatButton.tscn")
const _PlayerScene := preload("res://Scenes/Lobby/PlayerCharacter.tscn")
const _SELECT_GAMES_SCENE := "res://Scenes/Lobby/SelectGames.tscn"
const _QUIT_FACE_COLOR := Color(0.56, 0.18, 0.2, 1)
const _QUIT_SHADOW_COLOR := Color(0.35, 0.09, 0.11, 1)

## Référence à chaque nœud PlayerCharacter, indexé par peer_id.
var players: Dictionary = {}
var _returning_to_select_games: bool = false

# ── Cycle de vie ──────────────────────────────────────────────────────────────

func _ready() -> void:
	_spawn_players()
	NetworkManager.game_message.connect(_on_network_message)
	NetworkManager.player_list_changed.connect(_on_player_left)
	_setup_host_quit_button()
	_on_game_ready()

## Virtuel — appelé après le spawn de tous les joueurs.
## Initialise ici les éléments spécifiques au mini-jeu.
func _on_game_ready() -> void:
	pass

# ── Spawn ─────────────────────────────────────────────────────────────────────

func _spawn_players() -> void:
	var ids: Array = NetworkManager.players.keys()
	var count: int = ids.size()
	var viewport_size: Vector2 = get_viewport_rect().size
	var my_id: int = NetworkManager.local_peer_id()

	for i in range(count):
		var peer_id: int = ids[i]
		var player: PlayerCharacter = _PlayerScene.instantiate()
		add_child(player)

		# Répartir les spawns horizontalement au bas de l'écran
		var spawn_x: float = (viewport_size.x / (count + 1)) * (i + 1)
		var spawn_y: float = viewport_size.y * 0.75
		player.position = Vector2(spawn_x, spawn_y)

		var player_data: Dictionary = NetworkManager.players[peer_id]
		player.setup(peer_id, peer_id == my_id, player_data.get("name", ""))
		players[peer_id] = player

# ── Réseau ────────────────────────────────────────────────────────────────────

func _on_network_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"player_state":
			var pid: int = int(data.get("id", 0))
			if pid in players and not players[pid].is_local:
				players[pid].apply_remote_state(data)
		"game_over":
			_on_game_over(int(data.get("winner", 0)))
		"return_to_select_games":
			if _begin_return_to_select_games():
				_go_to_select_games()
		_:
			_on_custom_message(from_id, data)

func _on_player_left() -> void:
	# Supprimer les nœuds des joueurs déconnectés
	for pid in players.keys():
		if pid not in NetworkManager.players:
			players[pid].queue_free()
			players.erase(pid)

# ── API mini-jeux ─────────────────────────────────────────────────────────────

## Virtuel — surcharger pour gérer les messages réseau propres au mini-jeu.
func _on_custom_message(_from_id: int, _data: Dictionary) -> void:
	pass

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

	var btn := _HostQuitButtonScene.instantiate() as Control
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
	btn.set("face_color", _QUIT_FACE_COLOR)
	btn.set("shadow_color", _QUIT_SHADOW_COLOR)
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
	get_tree().change_scene_to_file(_SELECT_GAMES_SCENE)

## Appeler quand le mini-jeu se termine.
## Envoie le résultat à tous les joueurs et déclenche _on_game_over().
func end_game(winner_peer_id: int) -> void:
	if NetworkManager.is_host:
		NetworkManager.send_game_message(0, {"action": "game_over", "winner": winner_peer_id})
	_on_game_over(winner_peer_id)

## Virtuel — appelé quand la partie est terminée (sur tous les clients).
## Affiche les résultats ou retourne au lobby ici.
func _on_game_over(winner_peer_id: int) -> void:
	var winner_name: String = "?"
	if winner_peer_id in NetworkManager.players:
		winner_name = NetworkManager.players[winner_peer_id].get("name", "?")
	print("Partie terminée ! Vainqueur : %s (id %d)" % [winner_name, winner_peer_id])
	# TODO : afficher un écran de résultats puis retourner au lobby
	# get_tree().change_scene_to_file("res://Scenes/WaitingRoom.tscn")
