extends Sprite2D

@export var hover_texture: Texture2D
## Scène chargée au clic (laisser vide pour ne rien faire)
@export var scene_to_load: PackedScene
## Si true, quitter le jeu au clic
@export var quit_on_click: bool = false

signal pressed

var tween: Tween
var is_hovered: bool = false
var original_scale: Vector2
var original_texture: Texture2D

func _ready() -> void:
	original_scale = scale
	original_texture = texture

func _process(_delta: float) -> void:
	if texture == null:
		return
	var mouse_pos := get_local_mouse_position()
	var tex_size := texture.get_size()
	var rect := Rect2(-tex_size / 2.0, tex_size)

	if rect.has_point(mouse_pos):
		if not is_hovered:
			is_hovered = true
			_on_hover()
	else:
		if is_hovered:
			is_hovered = false
			_on_unhover()

func _on_hover() -> void:
	if hover_texture:
		texture = hover_texture
	#pivot_offset = texture.get_size() / 2.0

	var scale_target_x := original_scale.x * 1.2
	var scale_target_y := original_scale.y * 1.2

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale:x", scale_target_x, 0.2)
	tween.parallel().tween_property(self, "scale:y", scale_target_y, 0.35)
	tween.parallel().tween_property(self, "rotation_degrees", 5.0 * [-1.0, 1.0].pick_random(), 0.1)
	tween.parallel().tween_property(self, "rotation_degrees", 0.0, 0.1).set_delay(0.1)

func _on_unhover() -> void:
	texture = original_texture
	#pivot_offset = texture.get_size() / 2.0

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale:x", original_scale.x, 0.2)
	tween.parallel().tween_property(self, "scale:y", original_scale.y, 0.2)
	tween.parallel().tween_property(self, "rotation_degrees", 0.0, 0.15)

func _input(event: InputEvent) -> void:
	if not is_hovered:
		return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		pressed.emit()
		if quit_on_click:
			get_tree().quit()
		elif scene_to_load:
			get_tree().change_scene_to_packed(scene_to_load)
