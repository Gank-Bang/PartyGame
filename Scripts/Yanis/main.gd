extends Node2D

@onready var player = $Player
@onready var cooldown_bar = $UI/HUD/CooldownBar

func _ready():
	player.cooldown_changed.connect(cooldown_bar.update_cooldown)
