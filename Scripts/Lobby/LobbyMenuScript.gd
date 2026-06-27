extends Control

@onready var name_input:  LineEdit      = $Panel/Margin/VBox/NameInput
@onready var host_btn:    Button        = $Panel/Margin/VBox/BtnRow/HostBtn
@onready var join_btn:    Button        = $Panel/Margin/VBox/BtnRow/JoinBtn
@onready var join_panel:  VBoxContainer = $Panel/Margin/VBox/JoinPanel
@onready var code_input:  LineEdit      = $Panel/Margin/VBox/JoinPanel/CodeInput
@onready var confirm_btn: Button        = $Panel/Margin/VBox/JoinPanel/ConfirmBtn
@onready var status_lbl:  Label         = $Panel/Margin/VBox/StatusLabel

func _ready() -> void:
	join_panel.visible = false

	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	confirm_btn.pressed.connect(_on_confirm_pressed)

	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.connection_failed.connect(_on_connection_failed)

# ── Héberger ──────────────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	var player_name := _get_name()
	_set_ui_loading("Connexion au relais…")
	NetworkManager.host_game(player_name)

# ── Rejoindre ─────────────────────────────────────────────────────────────────

func _on_join_pressed() -> void:
	join_panel.visible = not join_panel.visible

func _on_confirm_pressed() -> void:
	var code := code_input.text.strip_edges()
	if code.length() != 4 or not code.is_valid_int():
		status_lbl.text = "Le code doit être 4 chiffres."
		return
	var player_name := _get_name()
	_set_ui_loading("Connexion au lobby %s…" % code)
	NetworkManager.join_game(code, player_name)

# ── Callbacks NetworkManager ──────────────────────────────────────────────────

func _on_lobby_created(_code: String) -> void:
	get_tree().change_scene_to_file("res://Scenes/Lobby/WaitingRoom.tscn")

func _on_lobby_joined() -> void:
	get_tree().change_scene_to_file("res://Scenes/Lobby/WaitingRoom.tscn")

func _on_connection_failed(reason: String) -> void:
	status_lbl.text = "Erreur : " + reason
	_set_ui_loading("", false)

# ── Utilitaires ───────────────────────────────────────────────────────────────

func _get_name() -> String:
	var n := name_input.text.strip_edges()
	return n if n.length() > 0 else "Joueur"

func _set_ui_loading(msg: String, loading: bool = true) -> void:
	host_btn.disabled    = loading
	join_btn.disabled    = loading
	confirm_btn.disabled = loading
	status_lbl.text      = msg
