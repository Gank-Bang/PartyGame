## Mini-jeu : Runes — mémorise la séquence croissante !
## L'hôte ajoute 1 rune à chaque round. Les joueurs reproduisent la séquence dans l'ordre.
## Une erreur = élimination. Le dernier joueur debout gagne.
extends BaseGame

# ── Constantes ────────────────────────────────────────────────────────────────

const INPUT_TIMEOUT: float    = 15.0
const MAX_RUNES: int          = 20
const RUNE_APPEAR_TIME: float = 0.27   # durée animation punch-in
const RUNE_GAP: float         = 0.10   # pause entre chaque rune
const RUNE_HOLD: float        = 1.0    # durée avant disparition

const SEQ_FACE_COLOR:   Color = Color("4b2a8a")
const SEQ_SHADOW_COLOR: Color = Color("22104a")
const INPUT_FACE_COLOR:   Color = Color("2a1c5c")
const INPUT_SHADOW_COLOR: Color = Color("140e30")

# ── Assets ────────────────────────────────────────────────────────────────────

const _FlatButtonScene := preload("res://Scenes/RafGames/Components/FlatButton.tscn")
var _rune_textures: Array = []
var _rune_sfx: AudioStreamPlayer
var _pop_sfx: AudioStreamPlayer

# ── État du jeu ───────────────────────────────────────────────────────────────

var _my_id: int           = 0
var _sequence: Array      = []
var _current_round: int   = 0
var _eliminated: Array    = []
var _initial_count: int   = 0
var _game_done: bool      = false

# Input local
var _my_step: int         = 0
var _input_disabled: bool = true

# Timer de phase input seulement
var _phase_timer: float   = 0.0
var _in_input_phase: bool = false

# Hôte : progression par joueur
var _player_steps: Dictionary = {}
var _players_done: Dictionary = {}

# ── Nœuds ────────────────────────────────────────────────────────────────────

@onready var _round_label:  Label         = $CanvasLayer/UI/MainVBox/Header/RoundLabel
@onready var _phase_label:  Label         = $CanvasLayer/UI/MainVBox/Header/PhaseLabel
@onready var _timer_bar:    ProgressBar   = $CanvasLayer/UI/MainVBox/Header/TimerBar
@onready var _seq_hbox:     HBoxContainer = $CanvasLayer/UI/MainVBox/SequencePanel/CenterContainer/SequenceHBox
@onready var _status_area:  HBoxContainer = $CanvasLayer/UI/MainVBox/StatusArea
@onready var _feedback_lbl: Label         = $CanvasLayer/UI/MainVBox/FeedbackLabel
@onready var _rune_grid:    GridContainer = $CanvasLayer/UI/MainVBox/RuneGrid
@onready var _canvas_layer: CanvasLayer   = $CanvasLayer

# ── Surcharge BaseGame ────────────────────────────────────────────────────────

func _spawn_players() -> void:
	pass

func _on_game_ready() -> void:
	_my_id         = NetworkManager.local_peer_id()
	_initial_count = NetworkManager.players.size()
	_load_textures()
	_setup_sfx()
	_build_rune_grid()
	_build_status_area()
	if NetworkManager.is_host:
		_start_next_round()

func _process(delta: float) -> void:
	if _game_done or not _in_input_phase:
		return
	_phase_timer -= delta
	_timer_bar.value = clampf(_phase_timer / INPUT_TIMEOUT, 0.0, 1.0)
	if _phase_timer <= 0.0 and NetworkManager.is_host:
		_handle_timeout()

# ── Son ───────────────────────────────────────────────────────────────────────

func _setup_sfx() -> void:
	_rune_sfx = AudioStreamPlayer.new()
	#_rune_sfx.stream = load("res://Ressources/Menu/Sounds/press.mp3")
	_rune_sfx.bus = "Master"
	_rune_sfx.volume_db = 2.0
	add_child(_rune_sfx)
	_pop_sfx = AudioStreamPlayer.new()
	var pop_stream = load("res://Ressources/RafGames/pop.mp3")
	if pop_stream:
		_pop_sfx.stream = pop_stream
	else:
		push_warning("RunesMiniGame: pop.m4a non chargé — Godot supporte .mp3 .ogg .wav uniquement")
	_pop_sfx.bus = "Master"
	_pop_sfx.volume_db = 4.0
	add_child(_pop_sfx)

# ── Chargement des textures ───────────────────────────────────────────────────

func _load_textures() -> void:
	_rune_textures.append(load("res://Ressources/RafGames/Runes/rune.png"))
	_rune_textures.append(load("res://Ressources/RafGames/Runes/rune copie.png"))
	for i in range(2, MAX_RUNES):
		_rune_textures.append(load("res://Ressources/RafGames/Runes/rune copie %d.png" % i))

# ── Construction UI ───────────────────────────────────────────────────────────

func _make_rune_flat_btn(rune_idx: int, size: float, face: Color, shadow: Color, clickable: bool) -> Control:
	var btn = _FlatButtonScene.instantiate()
	btn.custom_minimum_size = Vector2(size, size)
	btn.face_color   = face
	btn.shadow_color = shadow
	btn.text         = ""
	btn.corner_radius = 14
	btn.depth        = 10.0
	if not clickable:
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face_panel := btn.get_node("Face")
	face_panel.clip_contents = true
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_top",    16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	tex.texture = _rune_textures[rune_idx]
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tex.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(tex)
	face_panel.add_child(margin)
	return btn

func _build_rune_grid() -> void:
	for i in range(_rune_textures.size()):
		var btn := _make_rune_flat_btn(i, 96.0, INPUT_FACE_COLOR, INPUT_SHADOW_COLOR, true)
		btn.pressed.connect(_on_rune_clicked.bind(i))
		_rune_grid.add_child(btn)
	_set_input_disabled(true)

func _build_status_area() -> void:
	for child in _status_area.get_children():
		child.queue_free()
	for pid in NetworkManager.players.keys():
		var pname: String = NetworkManager.players[pid].get("name", "?")
		var lbl := Label.new()
		lbl.name = "P_%d" % pid
		lbl.text = ("★ " if pid == _my_id else "") + pname
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color("f5e6c8"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_status_area.add_child(lbl)

func _update_status(pid: int, alive: bool) -> void:
	var lbl: Label = _status_area.get_node_or_null("P_%d" % pid)
	if not lbl:
		return
	var pname: String = NetworkManager.players.get(pid, {}).get("name", "?")
	lbl.text = ("★ " if pid == _my_id else "") + pname + ("\n✓" if alive else "\n✗")
	lbl.add_theme_color_override("font_color", Color("52b788") if alive else Color("e63946"))

# ── Rounds ────────────────────────────────────────────────────────────────────

func _start_next_round() -> void:
	_current_round += 1
	var used := _sequence.duplicate()
	var candidates: Array = []
	for i in range(MAX_RUNES):
		if i not in used:
			candidates.append(i)
	if candidates.is_empty():
		candidates = range(MAX_RUNES) as Array
	_sequence.append(candidates[randi() % candidates.size()])
	var msg := {
		"action":   "rune_new_round",
		"round":    _current_round,
		"sequence": _sequence,
	}
	NetworkManager.send_game_message(0, msg)
	_setup_round(msg)

func _setup_round(data: Dictionary) -> void:
	_current_round  = int(data.get("round", _current_round))
	var raw: Array  = data.get("sequence", [])
	_sequence       = []
	for v in raw:
		_sequence.append(int(v))
	_my_step        = 0
	_in_input_phase = false
	if NetworkManager.is_host:
		_player_steps.clear()
		_players_done.clear()
		for pid in _get_alive():
			_player_steps[pid] = 0
			_players_done[pid] = false
	_round_label.text  = "Séquence : %d" % _sequence.size()
	_phase_label.text  = "Mémorisez !"
	_timer_bar.value   = 0.0
	_feedback_lbl.text = ""
	_set_input_disabled(true)
	_animate_sequence_reveal()

# ── Animation de révélation ───────────────────────────────────────────────────

func _animate_sequence_reveal() -> void:
	for child in _seq_hbox.get_children():
		child.queue_free()
	await get_tree().process_frame

	var btns: Array = []
	for rune_idx in _sequence:
		var btn := _make_rune_flat_btn(rune_idx, 90.0, SEQ_FACE_COLOR, SEQ_SHADOW_COLOR, false)
		btn.scale = Vector2.ZERO
		btn.pivot_offset = btn.custom_minimum_size / 2.0
		_seq_hbox.add_child(btn)
		btns.append(btn)

	# Révéler une à une avec punch + shake + son
	for btn in btns:
		if _game_done:
			return
		_rune_sfx.play()
		_shake_canvas()
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(1.35, 1.35), RUNE_APPEAR_TIME * 0.6) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn, "scale", Vector2.ONE, RUNE_APPEAR_TIME * 0.4) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		await tw.finished
		_pop_sfx.play()
		await get_tree().create_timer(RUNE_GAP).timeout

	# Tenir 1 seconde
	if not _game_done:
		await get_tree().create_timer(RUNE_HOLD).timeout

	# Disparaître simultanément
	if not _game_done:
		var fade_tw := create_tween()
		fade_tw.set_parallel(true)
		for btn in btns:
			fade_tw.tween_property(btn, "scale", Vector2.ZERO, 0.22) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
		await fade_tw.finished
		for child in _seq_hbox.get_children():
			child.queue_free()
		if not _game_done:
			_end_show_phase()

func _shake_canvas() -> void:
	var tw := create_tween()
	tw.tween_property(_canvas_layer, "offset", Vector2( 10, -7), 0.040)
	tw.tween_property(_canvas_layer, "offset", Vector2( -9,  5), 0.040)
	tw.tween_property(_canvas_layer, "offset", Vector2(  6, -3), 0.035)
	tw.tween_property(_canvas_layer, "offset", Vector2( -4,  2), 0.035)
	tw.tween_property(_canvas_layer, "offset", Vector2.ZERO,     0.040)

func _end_show_phase() -> void:
	_phase_label.text  = "Reproduisez !"
	_timer_bar.value   = 1.0
	_phase_timer       = INPUT_TIMEOUT
	_in_input_phase    = true
	if _my_id not in _eliminated:
		_set_input_disabled(false)
		_feedback_lbl.text = "0 / %d" % _sequence.size()

func _display_sequence_static() -> void:
	for child in _seq_hbox.get_children():
		child.queue_free()
	for rune_idx in _sequence:
		var btn := _make_rune_flat_btn(rune_idx, 90.0, SEQ_FACE_COLOR, SEQ_SHADOW_COLOR, false)
		_seq_hbox.add_child(btn)

func _handle_timeout() -> void:
	_in_input_phase = false
	for pid in _get_alive():
		if not _players_done.get(pid, false):
			_eliminated.append(pid)
			NetworkManager.send_game_message(0, {"action": "rune_eliminated", "pid": pid})
			_update_status(pid, false)
	_resolve_round()

# ── Input ─────────────────────────────────────────────────────────────────────

func _on_rune_clicked(rune_idx: int) -> void:
	if _input_disabled or _my_id in _eliminated or not _in_input_phase:
		return
	var step   := _my_step
	_my_step   += 1
	_feedback_lbl.text = "%d / %d" % [_my_step, _sequence.size()]
	if _my_step >= _sequence.size():
		_set_input_disabled(true)
	if NetworkManager.is_host:
		_process_click(_my_id, rune_idx, step)
	else:
		NetworkManager.send_game_message(0, {
			"action": "rune_click",
			"from":   _my_id,
			"rune":   rune_idx,
			"step":   step,
		})

# ── Validation (hôte) ────────────────────────────────────────────────────────

func _process_click(pid: int, rune_idx: int, step: int) -> void:
	if not _in_input_phase or _game_done:
		return
	if pid in _eliminated or _players_done.get(pid, false):
		return
	var expected: int = _player_steps.get(pid, 0)
	if step != expected:
		return
	if rune_idx == _sequence[expected]:
		_player_steps[pid] = expected + 1
		if _player_steps[pid] >= _sequence.size():
			_players_done[pid] = true
			_resolve_round()
	else:
		_eliminated.append(pid)
		var msg := {"action": "rune_eliminated", "pid": pid}
		NetworkManager.send_game_message(0, msg)
		_on_rune_eliminated(pid)
		_resolve_round()

func _resolve_round() -> void:
	if _game_done:
		return
	var alive := _get_alive()
	var should_end := alive.is_empty() or (alive.size() == 1 and _initial_count > 1)
	if should_end:
		_in_input_phase = false
		_game_done      = true
		var winner: int = alive[0] if alive.size() == 1 else -1
		get_tree().create_timer(1.5).timeout.connect(func(): end_game(winner))
		return
	var all_done := true
	for pid in alive:
		if not _players_done.get(pid, false):
			all_done = false
			break
	if all_done:
		_in_input_phase = false
		get_tree().create_timer(1.5).timeout.connect(_start_next_round)

func _get_alive() -> Array:
	var result: Array = []
	for pid in NetworkManager.players.keys():
		if pid not in _eliminated:
			result.append(pid)
	return result

# ── Réseau ────────────────────────────────────────────────────────────────────

func _on_custom_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"rune_new_round":
			_setup_round(data)
		"rune_click":
			if NetworkManager.is_host:
				_process_click(
					int(data.get("from", from_id)),
					int(data.get("rune", -1)),
					int(data.get("step", 0)),
				)
		"rune_eliminated":
			_on_rune_eliminated(int(data.get("pid", -1)))

func _on_rune_eliminated(pid: int) -> void:
	if pid not in _eliminated:
		_eliminated.append(pid)
	_update_status(pid, false)
	if pid == _my_id:
		_set_input_disabled(true)
		_phase_label.text = "Éliminé !"
		_feedback_lbl.text = "La bonne séquence était :"
		_feedback_lbl.add_theme_color_override("font_color", Color("e63946"))
		_display_sequence_static()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _set_input_disabled(disabled: bool) -> void:
	_input_disabled = disabled
	var alpha  := 0.35 if disabled else 1.0
	var filter := Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_STOP
	for child in _rune_grid.get_children():
		child.modulate = Color(alpha, alpha, alpha, 1.0)
		if child is Control:
			(child as Control).mouse_filter = filter

# ── Fin de partie ─────────────────────────────────────────────────────────────

func _on_game_over(winner_peer_id: int) -> void:
	_game_done      = true
	_in_input_phase = false
	_set_input_disabled(true)

	var winner_name: String = NetworkManager.players.get(winner_peer_id, {}).get("name", "Personne")

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	var center := Control.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5;  panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5;  panel.anchor_bottom = 0.5
	panel.offset_left   = -300.0; panel.offset_right  = 300.0
	panel.offset_top    = -180.0; panel.offset_bottom = 180.0
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Fin de partie !"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("f5e6c8"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var winner_lbl := Label.new()
	if winner_peer_id == -1:
		winner_lbl.text = "Aucun vainqueur !"
	else:
		winner_lbl.text = "🏆 %s — séquence de %d rune%s !" % [
			winner_name, _current_round, "s" if _current_round > 1 else ""
		]
	winner_lbl.add_theme_font_size_override("font_size", 30)
	winner_lbl.add_theme_color_override("font_color", Color("f4a261"))
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(winner_lbl)

	await get_tree().create_timer(5.0).timeout
	get_tree().change_scene_to_file("res://Scenes/Lobby/SelectGames.tscn")
