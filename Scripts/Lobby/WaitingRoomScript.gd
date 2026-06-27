extends Control

@onready var code_lbl:     Label         = $Panel/Margin/VBox/CodeLabel
@onready var player_list:  VBoxContainer = $Panel/Margin/VBox/PlayerList
@onready var players_number: Label        = $Panel/Margin/VBox/PlayersTitle
@onready var start_btn:    Button        = $Panel/Margin/VBox/StartBtn
@onready var quit_btn:     Button        = $Panel/Margin/VBox/QuitBtn

func _ready() -> void:
	var is_host: bool = NetworkManager.is_host

	# Le code n'est affiché qu'à l'hôte
	if is_host:
		code_lbl.text = "Code : %s  (partage ce code à tes amis)" % NetworkManager.lobby_code
	else:
		code_lbl.visible = false

	# Le bouton Démarrer est réservé à l'hôte
	start_btn.visible = is_host

	_refresh_list()

	NetworkManager.player_list_changed.connect(_refresh_list)
	NetworkManager.game_started.connect(_on_game_started)

	start_btn.pressed.connect(_on_start_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

# ── Rafraîchir la liste ───────────────────────────────────────────────────────

func _refresh_list() -> void:
	for child in player_list.get_children():
		child.queue_free()
	for id in NetworkManager.players:
		var lbl := Label.new()
		var data: Dictionary = NetworkManager.players[id]
		lbl.text = "• " + data.get("name", "Joueur")
		lbl.add_theme_font_size_override("font_size", 22)
		player_list.add_child(lbl)
	players_number.text = "Joueurs : %d/4" % NetworkManager.players.size()

# ── Boutons ───────────────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	NetworkManager.start_game()

func _on_quit_pressed() -> void:
	NetworkManager.disconnect_from_lobby()
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

# ── Démarrage de la partie ────────────────────────────────────────────────────

func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://Scenes/Lobby/SelectGames.tscn")
