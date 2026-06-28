## Menu principal — Jouer et Quitter.
extends Node2D

@onready var _btn_jouer:   Control = $CanvasLayer/UI/Panel/Margin/VBox/BtnJouer
@onready var _btn_quitter: Control = $CanvasLayer/UI/Panel/Margin/VBox/BtnQuitter

func _ready() -> void:
	_btn_jouer.connect("pressed", _on_jouer_pressed)
	_btn_quitter.connect("pressed", _on_quitter_pressed)

func _on_jouer_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Lobby/LobbyMenu.tscn")

func _on_quitter_pressed() -> void:
	get_tree().quit()
