extends CanvasLayer

@onready var ranking_list = $PanelContainer/VBoxContainer/RankingList
@onready var back_btn = $PanelContainer/VBoxContainer/"Retour au lobby"

const MEDALS = ["🥇", "🥈", "🥉", "💀"]

func _ready() -> void:
	back_btn.pressed.connect(_on_back_pressed)

func show_results(ranking: Array, times: Dictionary) -> void:
	for child in ranking_list.get_children():
		child.queue_free()

	for i in ranking.size():
		var pid = ranking[i]
		var player_name = NetworkManager.players[pid].get("name", "Joueur") if pid in NetworkManager.players else "Joueur"
		var t = times.get(pid, 0.0)
		var minutes = int(t) / 60
		var seconds = int(t) % 60
		var lbl = Label.new()
		lbl.text = "%s  %s  —  %02d:%02d" % [MEDALS[i] if i < MEDALS.size() else "", player_name, minutes, seconds]
		lbl.add_theme_font_size_override("font_size", 28)
		ranking_list.add_child(lbl)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Lobby/WaitingRoom.tscn")
