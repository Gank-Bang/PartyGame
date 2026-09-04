extends Control

@onready var winner_label = $CenterContainer/VBoxContainer/WinnerLabel
@onready var restart_button = $CenterContainer/VBoxContainer/RestartButton
@onready var quit_button = $CenterContainer/VBoxContainer/QuitButton
@onready var waiting_label = $CenterContainer/VBoxContainer/WaitingLabel

@onready var game_manager = get_tree().current_scene.get_node("GameManager")


func _ready() -> void:

	visible = false
	modulate.a = 0.0

	waiting_label.visible = false

	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	game_manager.game_over.connect(show_winner)


func show_winner(player_name: String) -> void:

	winner_label.text = player_name + " WINS!"

	if NetworkManager.is_host:

		restart_button.visible = true
		quit_button.visible = true
		waiting_label.visible = false

	else:

		restart_button.visible = false
		quit_button.visible = false
		waiting_label.visible = true

	visible = true
	modulate.a = 0.0

	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35)


func _on_restart_pressed() -> void:

	if !NetworkManager.is_host:
		return

	NetworkManager.send_game_message(0, {
		"action": "restart"
	})

	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:

	if !NetworkManager.is_host:
		return

	get_tree().paused = false
	NetworkManager.send_game_message(0, {
		"action": "return_to_select_games"
	})
	await get_tree().create_timer(0.2, true).timeout
	get_tree().change_scene_to_file("res://Scenes/Lobby/SelectGames.tscn")
