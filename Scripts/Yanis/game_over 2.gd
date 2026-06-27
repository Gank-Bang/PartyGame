extends Control

@onready var winner_label = $CenterContainer/VBoxContainer/WinnerLabel
@onready var restart_button = $CenterContainer/VBoxContainer/RestartButton
@onready var quit_button = $CenterContainer/VBoxContainer/QuitButton


func _ready():

	visible = false
	modulate.a = 0.0

	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func show_winner(player_name):

	winner_label.text = player_name + " WINS!"

	visible = true
	modulate.a = 0.0

	var tween = create_tween()

	tween.tween_property(self, "modulate:a", 1.0, 0.35)


func _on_restart_pressed():

	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_pressed():

	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
