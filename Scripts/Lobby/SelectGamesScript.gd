## Écran de sélection du mini-jeu.
## L'hôte choisit le jeu ; tous les clients sont redirigés automatiquement.
## La liste des joueurs connectés s'affiche à gauche.
extends Node2D

const _FlatButtonScene := preload("res://Scenes/RafGames/Components/FlatButton.tscn")

@onready var _player_vbox: VBoxContainer = $CanvasLayer/UI/MainHBox/LeftPanel/Margin/VBox/VBoxContainer
@onready var _btn_equation: Control    = $CanvasLayer/UI/MainHBox/RightVBox/FlatButton
@onready var _btn_pileface: Control    = $CanvasLayer/UI/MainHBox/RightVBox/FlatButton2
@onready var _btn_quitter: Control     = $CanvasLayer/UI/MainHBox/RightVBox/QuitRow/FlatButton3
@onready var _btn_miami: Control     = $CanvasLayer/UI/MainHBox/RightVBox/HotlineMiami
@onready var _btn_runes: Control     = $CanvasLayer/UI/MainHBox/RightVBox/RunesMiniGame
@onready var _btn_paires_runes: Control = $CanvasLayer/UI/MainHBox/RightVBox/PairesRunesMiniGame
@onready var _btn_motus: Control     = $CanvasLayer/UI/MainHBox/RightVBox/MotusMiniGame
@onready var _btn_underhocem: Control    = $CanvasLayer/UI/MainHBox/RightVBox/UnderHocem


## Couleurs de survol "hôte" pour les clients (key = scene id)
const _HOVER_FACE:   Dictionary = {"equation": Color("f4a261"), "pileface": Color("f4a261"), "miami": Color("f4a261"), "runes": Color("f4a261"), "pairesrunes": Color("f4a261"), "motus": Color("f4a261")}
const _HOVER_SHADOW: Dictionary = {"equation": Color("b05d1e"), "pileface": Color("b05d1e"), "miami": Color("b05d1e"), "runes": Color("b05d1e"), "pairesrunes": Color("b05d1e"), "motus": Color("b05d1e")}

## Couleurs d'origine mémorisées pour la restauration
var _default_colors: Dictionary = {}
## key = scene id → bouton correspondant
var _game_buttons: Dictionary = {}

func _ready() -> void:
	_game_buttons = {
		"equation": _btn_equation,
		"pileface": _btn_pileface,
		"miami":    _btn_miami,
		"runes":    _btn_runes,
		"pairesrunes": _btn_paires_runes,
		"motus":    _btn_motus,
	}
	# Mémoriser les couleurs de base des boutons jeu
	for key in _game_buttons:
		_default_colors[key] = {
			"face":   _game_buttons[key].get("face_color"),
			"shadow": _game_buttons[key].get("shadow_color"),
		}
	for btn in _game_buttons.values():
		btn.visible = true
	if NetworkManager.is_host:
		# L'hôte voit et peut cliquer sur les boutons jeu
		_btn_equation.connect("pressed", _on_equation_pressed)
		_btn_pileface.connect("pressed", _on_pileface_pressed)
		_btn_miami.connect("pressed", _on_miami_pressed)
		_btn_runes.connect("pressed", _on_runes_pressed)
		_btn_paires_runes.connect("pressed", _on_paires_runes_pressed)
		_btn_motus.connect("pressed", _on_motus_pressed)
		_btn_underhocem.connect("pressed", _on_underhocem_pressed)
		# Diffuser les survols aux clients
		for key in _game_buttons:
			var hovered_key: String = key
			_game_buttons[key].connect("mouse_entered", func(): _broadcast_hover(hovered_key))
			_game_buttons[key].connect("mouse_exited",  func(): _broadcast_hover(""))
	else:
		# Les clients voient les boutons mais sans interaction
		for btn in _game_buttons.values():
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Bloquer aussi les enfants pour éviter tout hover accidentel
			for child in btn.get_children():
				if child is Control:
					(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	_refresh_player_list()
	NetworkManager.player_list_changed.connect(_refresh_player_list)
	NetworkManager.game_message.connect(_on_game_message)
	_btn_quitter.connect("pressed", _on_quit_pressed)

# ── Hover réseau ──────────────────────────────────────────────────────────────

func _broadcast_hover(game: String) -> void:
	NetworkManager.send_game_message(0, {"action": "game_hover", "game": game})

func _apply_hover(game: String) -> void:
	for key in _game_buttons:
		var btn: Control = _game_buttons[key]
		btn.set("face_color",   _default_colors[key]["face"])
		btn.set("shadow_color", _default_colors[key]["shadow"])
	if game in _game_buttons:
		var hovered: Control = _game_buttons[game]
		hovered.set("face_color",   _HOVER_FACE.get(game,   Color("f4a261")))
		hovered.set("shadow_color", _HOVER_SHADOW.get(game, Color("b05d1e")))

# ── Liste des joueurs ─────────────────────────────────────────────────────────

func _refresh_player_list() -> void:
	for child in _player_vbox.get_children():
		child.queue_free()
	await get_tree().process_frame
	var is_local := NetworkManager.local_peer_id()
	for pid in NetworkManager.players:
		var data: Dictionary = NetworkManager.players[pid]
		var btn = _FlatButtonScene.instantiate()
		var is_me: bool = pid == is_local
		btn.set("text", ("★ " if is_me else "") + data.get("name", "Joueur"))
		# Animations hover/press actives mais signal pressed non connecté
		_player_vbox.add_child(btn)

# ── Sélection du jeu (hôte) ───────────────────────────────────────────────────

func _on_equation_pressed() -> void:
	NetworkManager.send_game_message(0, {"action": "launch_game", "scene": "equation"})
	_launch("equation")

func _on_pileface_pressed() -> void:
	NetworkManager.send_game_message(0, {"action": "launch_game", "scene": "pileface"})
	_launch("pileface")

func _on_miami_pressed() -> void:
	NetworkManager.send_game_message(0, {"action": "launch_game", "scene": "miami"})
	_launch("miami")

func _on_runes_pressed() -> void:
	NetworkManager.send_game_message(0, {"action": "launch_game", "scene": "runes"})
	_launch("runes")

func _on_paires_runes_pressed() -> void:
	NetworkManager.send_game_message(0, {"action": "launch_game", "scene": "pairesrunes"})
	_launch("pairesrunes")

func _on_motus_pressed() -> void:
	NetworkManager.send_game_message(0, {"action": "launch_game", "scene": "motus"})
	_launch("motus")

func _on_underhocem_pressed() -> void:
	NetworkManager.send_game_message(0, {"action": "launch_game", "scene": "underhocem"})
	_launch("underhocem")


func _on_quit_pressed() -> void:
	NetworkManager.disconnect_from_lobby()
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

# ── Réception réseau (clients) ────────────────────────────────────────────────

func _on_game_message(_from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"launch_game":
			_launch(str(data.get("scene", "")))
		"game_hover":
			if not NetworkManager.is_host:
				_apply_hover(str(data.get("game", "")))

func _launch(scene: String) -> void:
	match scene:
		"equation":
			get_tree().change_scene_to_file("res://Scenes/RafGames/EquationMiniGame.tscn")
		"pileface":
			get_tree().change_scene_to_file("res://Scenes/RafGames/PileOuFaceMiniGame.tscn")
		"miami":
			get_tree().change_scene_to_file("res://Scenes/Yanis/Main.tscn")
		"runes":
			get_tree().change_scene_to_file("res://Scenes/RafGames/RunesMiniGame.tscn")
		"pairesrunes":
			get_tree().change_scene_to_file("res://Scenes/RafGames/PairesRunesMiniGame.tscn")
		"motus":
			get_tree().change_scene_to_file("res://Scenes/RafGames/MotusMiniGame.tscn")
		"underhocem":
			get_tree().change_scene_to_file("res://Scenes/hocem/underhocem.tscn")
