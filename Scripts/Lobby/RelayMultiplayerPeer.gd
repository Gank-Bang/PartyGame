## Client WebSocket vers le serveur relais.
## Tous les joueurs (hôte inclus) se connectent ici — aucun port forwarding requis.
##
## Usage :
##   var c = RelayClient.new()
##   add_child(c)
##   c.create_lobby("wss://relais.example.com", "1234")  # hôte
##   c.join_lobby("wss://relais.example.com", "1234")    # client
class_name RelayClient
extends Node

## Signaux
signal got_id(my_id: int)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal relay_message(from_id: int, data: Dictionary)
signal relay_error(reason: String)

var my_id: int = 0
var _ws := WebSocketPeer.new()
var _pending_handshake: String = ""

# ── API publique ──────────────────────────────────────────────────────────────

func create_lobby(url: String, code: String) -> void:
	_pending_handshake = JSON.stringify({"action": "create", "code": code})
	_ws.connect_to_url(url)

func join_lobby(url: String, code: String) -> void:
	_pending_handshake = JSON.stringify({"action": "join", "code": code})
	_ws.connect_to_url(url)

## Envoie un message JSON au(x) pair(s). target_id = 0 pour broadcast.
func send_to(target_id: int, data: Dictionary) -> void:
	_ws.send_text(JSON.stringify({"type": "game", "to": target_id, "data": data}))

func close() -> void:
	_ws.close()
	my_id = 0

# ── Boucle ────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _pending_handshake != "":
				_ws.send_text(_pending_handshake)
				_pending_handshake = ""
			while _ws.get_available_packet_count() > 0:
				var raw := _ws.get_packet()
				var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
				if parsed is Dictionary:
					_route(parsed)
		WebSocketPeer.STATE_CLOSED:
			if my_id != 0:
				relay_error.emit("Connexion au relais perdue")
				my_id = 0

func _route(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"id":
			my_id = int(msg["id"])
			got_id.emit(my_id)
		"peer_connected":
			peer_joined.emit(int(msg["id"]))
		"peer_disconnected":
			peer_left.emit(int(msg["id"]))
		"game":
			relay_message.emit(int(msg.get("from", 0)), msg.get("data", {}) as Dictionary)
		"error":
			relay_error.emit(str(msg.get("msg", "Erreur inconnue")))
