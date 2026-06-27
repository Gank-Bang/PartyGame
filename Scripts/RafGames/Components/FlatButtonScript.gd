## Bouton 3D générique réutilisable.
## Exporte le texte, les couleurs et la profondeur.
## Émet le signal "pressed" au clic.
extends Control

signal pressed

## Texte affiché sur le bouton
@export var text: String = "BTN" :
	set(v):
		text = v
		if is_node_ready():
			_label.text = v

## Couleur de la face (dessus)
@export var face_color: Color = Color("4b5a8a") :
	set(v):
		face_color = v
		if is_node_ready():
			_apply_styles()

## Couleur de l'ombre (bas)
@export var shadow_color: Color = Color("2d3655") :
	set(v):
		shadow_color = v
		if is_node_ready():
			_apply_styles()

## Couleur du texte
@export var text_color: Color = Color("f5e6c8") :
	set(v):
		text_color = v
		if is_node_ready():
			_label.add_theme_color_override("font_color", v)

## Profondeur de l'effet 3D (px)
@export var depth: float = 8.0

## Rayon des coins arrondis
@export var corner_radius: int = 10

@onready var _shadow: Panel = $Shadow
@onready var _face: Panel   = $Face
@onready var _label: Label  = $Face/Label

var _tween_press: Tween
var _tween_hover: Tween
var _hovered: bool = false
var _clicking: bool = false
var _original_scale: Vector2

func _ready() -> void:
	_original_scale = scale
	_apply_styles()
	_label.text = text
	_label.add_theme_color_override("font_color", text_color)
	# Les enfants Panel consomment les events par défaut → on les ignore
	_face.mouse_filter   = MOUSE_FILTER_IGNORE
	_shadow.mouse_filter = MOUSE_FILTER_IGNORE
	_label.mouse_filter  = MOUSE_FILTER_IGNORE
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	resized.connect(func(): pivot_offset = size / 2.0)
	await get_tree().process_frame
	pivot_offset = size / 2.0

# ── Styles ────────────────────────────────────────────────────────────────────

func _apply_styles() -> void:
	var face_style := StyleBoxFlat.new()
	face_style.bg_color = face_color
	face_style.set_corner_radius_all(corner_radius)
	_face.add_theme_stylebox_override("panel", face_style)

	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = shadow_color
	shadow_style.set_corner_radius_all(corner_radius)
	_shadow.add_theme_stylebox_override("panel", shadow_style)

# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_clicking = true
			_animate_press()
		else:
			_clicking = false
			_animate_release()
			pressed.emit()

func _on_hover() -> void:
	_hovered = true
	if not _clicking:
		_animate_hover()

func _on_unhover() -> void:
	_hovered = false
	_clicking = false
	_animate_unhover()

# ── Animations ────────────────────────────────────────────────────────────────

func _animate_hover() -> void:
	if _tween_hover:
		_tween_hover.kill()
	_tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween_hover.tween_property(self, "scale:x", _original_scale.x * 1.12, 0.2)
	_tween_hover.parallel().tween_property(self, "scale:y", _original_scale.y * 1.12, 0.25)
	_tween_hover.parallel().tween_property(self, "rotation_degrees", 3.0 * [-1.0, 1.0].pick_random(), 0.1)
	_tween_hover.parallel().tween_property(self, "rotation_degrees", 0.0, 0.1).set_delay(0.1)
	_animate_face_to(depth * 0.35)

func _animate_unhover() -> void:
	if _tween_hover:
		_tween_hover.kill()
	_tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween_hover.tween_property(self, "scale:x", _original_scale.x, 0.18)
	_tween_hover.parallel().tween_property(self, "scale:y", _original_scale.y, 0.18)
	_tween_hover.parallel().tween_property(self, "rotation_degrees", 0.0, 0.15)
	_animate_face_to(0.0)

func _animate_press() -> void:
	if _tween_hover:
		_tween_hover.kill()
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(self, "scale:x", _original_scale.x * 0.95, 0.07)
	t.parallel().tween_property(self, "scale:y", _original_scale.y * 0.95, 0.07)
	_animate_face_to(depth)

func _animate_release() -> void:
	if _hovered:
		_animate_hover()
	else:
		_animate_unhover()

func _animate_face_to(target_y: float) -> void:
	if _tween_press:
		_tween_press.kill()
	_tween_press = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween_press.tween_property(_face, "offset_top", target_y, 0.08)
	_tween_press.parallel().tween_property(_face, "offset_bottom", target_y - depth, 0.08)
