extends Node2D

@onready var _title: Label = $CanvasLayer/UI/Title
@onready var _subtitle: Label = $CanvasLayer/UI/Subtitle
@onready var _creators: Sprite2D = $CanvasLayer/UI/Creators
@onready var _creator_buttons: Array[Control] = [
	$CanvasLayer/UI/NameRow/Nef as Control,
	$CanvasLayer/UI/NameRow/Yans as Control,
	$CanvasLayer/UI/NameRow/Houc as Control,
	$CanvasLayer/UI/NameRow/Raf as Control,
]

func _ready() -> void:
	await get_tree().process_frame
	_play_intro()
	await get_tree().create_timer(3.2).timeout
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _play_intro() -> void:
	var title_target_y := _title.position.y
	_title.position.y -= 28.0
	_title.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_subtitle.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var title_tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	title_tween.tween_property(_title, "modulate:a", 1.0, 0.55)
	title_tween.parallel().tween_property(_title, "position:y", title_target_y, 0.55)
	create_tween().tween_property(_subtitle, "modulate:a", 1.0, 0.45).set_delay(0.2)

	var creators_target_position := _creators.position
	_creators.position.y += 56.0
	_creators.scale = Vector2(0.72, 0.72)
	_creators.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var creators_tween := create_tween().set_parallel()
	creators_tween.tween_property(_creators, "modulate:a", 1.0, 0.7).set_delay(0.4)
	creators_tween.tween_property(_creators, "scale", Vector2(0.84, 0.84), 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.4)
	creators_tween.tween_property(_creators, "position:y", creators_target_position.y, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.4)

	for index in range(_creator_buttons.size()):
		_animate_control(_creator_buttons[index], 1.0 + index * 0.14)

	var float_tween := create_tween().set_loops()
	float_tween.tween_interval(1.4)
	float_tween.tween_property(_creators, "position:y", creators_target_position.y - 10.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(_creators, "position:y", creators_target_position.y, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _animate_control(control: Control, delay: float) -> void:
	control.modulate = Color(1.0, 1.0, 1.0, 0.0)
	control.scale = Vector2(0.86, 0.86)
	var tween := create_tween().set_parallel()
	tween.tween_property(control, "modulate:a", 1.0, 0.32).set_delay(delay)
	tween.tween_property(control, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)