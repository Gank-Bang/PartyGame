## Singleton (Autoload "NetworkManager") — gère toute la couche réseau.
## Accédez-y depuis n'importe quelle scène : NetworkManager.host_game(...)
extends Node

const _RelayClientClass := preload("res://Scripts/Lobby/RelayMultiplayerPeer.gd")

# ── Configuration ─────────────────────────────────────────────────────────────

## URL de votre serveur relais WebSocket.
## Après déploiement sur Railway/Render, remplacez cette valeur.
## Exemple Railway : "wss://partygame-relay-production.up.railway.app"
## Test local     : "ws://localhost:8765"
## Tes en ligne : "wss://partygame-production-c66e.up.railway.app"
const RELAY_URL := "wss://partygame-production-c66e.up.railway.app"

# ── État ──────────────────────────────────────────────────────────────────────

var _relay: Node = null
## true si le joueur local est l'hôte
var is_host: bool = false
## Code à 4 chiffres du lobby courant
var lobby_code: String = ""
## Dictionnaire des joueurs : {peer_id: {name: String}}
var players: Dictionary = {}
## Nom du joueur local
var local_player_name: String = "Joueur"

# ── Signaux ───────────────────────────────────────────────────────────────────

signal player_list_changed
signal game_started
signal connection_failed(reason: String)
signal lobby_created(code: String)
signal lobby_joined
## Émis pour tout message de jeu (mouvement, événements mini-jeu, etc.)
signal game_message(from_id: int, data: Dictionary)

# ── API publique ──────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
## ID du pair local (0 si non connecté)
func local_peer_id() -> int:
	if _relay == null:
		return 0
	return _relay.my_id

## Envoie un message de jeu via le relais. target_id = 0 pour broadcast.
func send_game_message(target_id: int, data: Dictionary) -> void:
	if _relay == null:
		return
	_relay.send_to(target_id, data)

func host_game(player_name: String) -> void:
	local_player_name = player_name
	lobby_code = _generate_code()
	is_host = true
	_setup_relay()
	_relay.create_lobby(RELAY_URL, lobby_code)

func join_game(code: String, player_name: String) -> void:
	local_player_name = player_name
	lobby_code = code
	is_host = false
	_setup_relay()
	_relay.join_lobby(RELAY_URL, code)

func start_game() -> void:
	if not is_host or _relay == null:
		return
	_relay.send_to(0, {"action": "start_game"})
	game_started.emit()

func disconnect_from_lobby() -> void:
	if _relay:
		_relay.close()
		_relay.queue_free()
		_relay = null
	players.clear()
	lobby_code = ""
	is_host = false

# ── Interne ───────────────────────────────────────────────────────────────────

func _setup_relay() -> void:
	if _relay:
		_relay.close()
		_relay.queue_free()
	players.clear()
	_relay = _RelayClientClass.new()
	add_child(_relay)
	_relay.got_id.connect(_on_got_id)
	_relay.peer_joined.connect(_on_peer_joined)
	_relay.peer_left.connect(_on_peer_left)
	_relay.relay_message.connect(_on_relay_message)
	_relay.relay_error.connect(_on_relay_error)

func _on_got_id(my_id: int) -> void:
	players[my_id] = {"name": local_player_name}
	player_list_changed.emit()
	if is_host:
		lobby_created.emit(lobby_code)
	else:
		_relay.send_to(0, {"action": "register", "name": local_player_name})
		lobby_joined.emit()

func _on_peer_joined(peer_id: int) -> void:
	players[peer_id] = {"name": "Joueur " + str(peer_id)}
	player_list_changed.emit()
	if is_host:
		_relay.send_to(peer_id, {"action": "player_list", "players": _serialise_players()})

func _on_peer_left(peer_id: int) -> void:
	players.erase(peer_id)
	player_list_changed.emit()

func _on_relay_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"register":
			players[from_id] = {"name": str(data.get("name", "Joueur"))}
			player_list_changed.emit()
			if is_host:
				_relay.send_to(0, {"action": "player_list", "players": _serialise_players()})
		"player_list":
			var list: Dictionary = data.get("players", {})
			players.clear()
			for key in list:
				players[int(key)] = list[key]
			player_list_changed.emit()
		"start_game":
			game_started.emit()
		_:
			game_message.emit(from_id, data)

func _on_relay_error(reason: String) -> void:
	connection_failed.emit(reason)

func _serialise_players() -> Dictionary:
	var result: Dictionary = {}
	for k in players:
		result[str(k)] = players[k]
	return result

func _generate_code() -> String:
	return str(randi_range(1000, 9999))
