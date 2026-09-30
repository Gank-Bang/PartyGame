## Mini-jeu : Paires de runes
## Chaque joueur reçoit une grille 4x4 identique et doit retrouver les 8 paires.
## Le premier à compléter sa grille gagne la manche.
extends BaseGame

const GRID_COLUMNS: int = 4
const GRID_SIZE: int = 16
const PAIR_COUNT: int = 8
const REVEAL_DURATION: float = 1.0
const INTRO_STEP_DELAY: float = 0.045
const INTRO_DROP_DISTANCE: float = 34.0

const CARD_BACK_FACE: Color = Color("405470")
const CARD_BACK_SHADOW: Color = Color("243142")
const CARD_REVEALED_FACE: Color = Color("ead39f")
const CARD_REVEALED_SHADOW: Color = Color("b99158")
const CARD_MATCH_FACE: Color = Color("6fc17d")
const CARD_MATCH_SHADOW: Color = Color("3f8d5b")

const _FlatButtonScene := preload("res://Scenes/RafGames/Components/FlatButton.tscn")

var _my_id: int = 0
var _local_pairs: int = 0
var _game_done: bool = false
var _local_finished: bool = false
var _resolving: bool = false
var _intro_animating: bool = false

var _rune_textures: Array[Texture2D] = []
var _deck: Array[int] = []
var _opened_indexes: Array[int] = []

var _card_buttons: Array = []
var _card_labels: Array = []
var _card_icons: Array = []
var _card_matched: Array[bool] = []
var _card_revealed: Array[bool] = []

var _pair_counts: Dictionary = {}
var _finished_players: Dictionary = {}

var _sfx_correct: AudioStreamPlayer
var _sfx_tada: AudioStreamPlayer

@onready var _pairs_label: Label = $CanvasLayer/UI/Margin/MainVBox/Header/HeaderMargin/HeaderVBox/TitleRow/PairsLabel
@onready var _state_label: Label = $CanvasLayer/UI/Margin/MainVBox/Header/HeaderMargin/HeaderVBox/StateLabel
@onready var _rune_grid: GridContainer = $CanvasLayer/UI/Margin/MainVBox/Body/BoardPanel/BoardMargin/BoardCenter/RuneGrid
@onready var _players_list: VBoxContainer = $CanvasLayer/UI/Margin/MainVBox/Body/SidePanel/SideMargin/SideVBox/PlayersList

func _spawn_players() -> void:
	pass

func _on_game_ready() -> void:
	_my_id = NetworkManager.local_peer_id()
	_load_rune_textures()
	_setup_sfx()
	_reset_progress_state()
	_build_status_list()
	if _rune_textures.size() < PAIR_COUNT:
		_state_label.text = "Pas assez de runes dans RafGames pour lancer la manche."
		push_error("PairesRunesMiniGame: il faut au moins %d runes dans Ressources/RafGames/Runes" % PAIR_COUNT)
		return
	if NetworkManager.is_host:
		_start_new_board()
	else:
		_state_label.text = "L'hôte prépare la grille de runes..."

func _on_custom_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"runes_pairs_setup":
			_apply_board_setup(data)
		"runes_pairs_progress":
			if NetworkManager.is_host:
				_record_progress(int(data.get("pid", from_id)), int(data.get("pairs", 0)), bool(data.get("finished", false)))
		"runes_pairs_progress_sync":
			_apply_progress_sync(data)

func _setup_sfx() -> void:
	_sfx_correct = AudioStreamPlayer.new()
	_sfx_correct.stream = load("res://Ressources/RafGames/Correct.mp3")
	_sfx_correct.bus = "Master"
	add_child(_sfx_correct)

	_sfx_tada = AudioStreamPlayer.new()
	_sfx_tada.stream = load("res://Ressources/RafGames/Tada.mp3")
	_sfx_tada.bus = "Master"
	add_child(_sfx_tada)

func _load_rune_textures() -> void:
	_rune_textures.clear()
	var rune_paths: Array[String] = [
		"res://Ressources/RafGames/Runes/rune.png",
		"res://Ressources/RafGames/Runes/rune copie.png",
	]
	for i in range(2, 20):
		rune_paths.append("res://Ressources/RafGames/Runes/rune copie %d.png" % i)

	for rune_path in rune_paths:
		var texture := load(rune_path) as Texture2D
		if texture != null:
			_rune_textures.append(texture)
		else:
			push_warning("PairesRunesMiniGame: rune introuvable: %s" % rune_path)

func _start_new_board() -> void:
	var msg := {
		"action": "runes_pairs_setup",
		"deck": _build_shuffled_deck(),
	}
	NetworkManager.send_game_message(0, msg)
	_apply_board_setup(msg)

func _build_shuffled_deck() -> Array:
	var available_indexes: Array[int] = []
	for i in range(_rune_textures.size()):
		available_indexes.append(i)
	available_indexes.shuffle()

	var deck: Array[int] = []
	for i in range(PAIR_COUNT):
		var rune_idx: int = available_indexes[i]
		deck.append(rune_idx)
		deck.append(rune_idx)
	deck.shuffle()
	return deck

func _apply_board_setup(data: Dictionary) -> void:
	var raw_deck: Array = data.get("deck", [])
	if raw_deck.size() != GRID_SIZE:
		push_warning("PairesRunesMiniGame: deck invalide reçu")
		return

	_deck.clear()
	for value in raw_deck:
		_deck.append(int(value))

	_game_done = false
	_local_finished = false
	_resolving = false
	_intro_animating = true
	_local_pairs = 0
	_opened_indexes.clear()
	_reset_progress_state()
	_build_status_list()
	_state_label.text = "Les runes apparaissent..."
	_build_grid()
	_update_card_interactions()
	_play_intro_animation()

func _reset_progress_state() -> void:
	_pair_counts.clear()
	_finished_players.clear()
	for pid in NetworkManager.players.keys():
		_pair_counts[pid] = 0
		_finished_players[pid] = false

func _build_status_list() -> void:
	for child in _players_list.get_children():
		child.queue_free()
	for pid in _sorted_player_ids():
		var label := Label.new()
		label.name = "Player_%d" % pid
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color("f6e8ca"))
		label.text = _status_text_for_player(pid)
		_players_list.add_child(label)

func _sorted_player_ids() -> Array:
	var result: Array = []
	if NetworkManager.players.has(_my_id):
		result.append(_my_id)
	var others: Array = NetworkManager.players.keys()
	others.sort()
	for pid in others:
		if pid != _my_id:
			result.append(pid)
	return result

func _status_text_for_player(pid: int) -> String:
	var player_name: String = NetworkManager.players.get(pid, {}).get("name", "Joueur")
	var prefix: String = "★ " if pid == _my_id else ""
	var pairs: int = int(_pair_counts.get(pid, 0))
	if bool(_finished_players.get(pid, false)):
		return "%s%s — %d/%d paires ✓" % [prefix, player_name, PAIR_COUNT, PAIR_COUNT]
	return "%s%s — %d/%d paires" % [prefix, player_name, pairs, PAIR_COUNT]

func _refresh_status_list() -> void:
	for pid in _sorted_player_ids():
		var label := _players_list.get_node_or_null("Player_%d" % pid) as Label
		if label == null:
			_build_status_list()
			return
		label.text = _status_text_for_player(pid)

func _build_grid() -> void:
	for child in _rune_grid.get_children():
		child.queue_free()

	_card_buttons.clear()
	_card_labels.clear()
	_card_icons.clear()
	_card_matched.clear()
	_card_revealed.clear()

	for card_idx in range(_deck.size()):
		var card_btn = _make_card_button(card_idx, _deck[card_idx])
		_rune_grid.add_child(card_btn)
		_card_buttons.append(card_btn)
		_card_matched.append(false)
		_card_revealed.append(false)

func _make_card_button(card_idx: int, rune_idx: int):
	var btn := _FlatButtonScene.instantiate()
	btn.custom_minimum_size = Vector2(136, 136)
	btn.face_color = CARD_BACK_FACE
	btn.shadow_color = CARD_BACK_SHADOW
	btn.text = ""
	btn.font_size = 54
	btn.text_color = Color("f6e8ca")
	btn.corner_radius = 18
	btn.depth = 10.0
	btn.pivot_offset = btn.custom_minimum_size / 2.0
	btn.modulate.a = 0.0

	var face_panel := btn.get_node("Face") as Panel
	face_panel.clip_contents = true

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.texture = _rune_textures[rune_idx]
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false
	icon.modulate = Color(1, 1, 1, 1)
	margin.add_child(icon)
	face_panel.add_child(margin)

	var label := btn.get_node("Face/Label") as Label
	label.text = ""
	label.visible = false

	btn.pressed.connect(_on_card_pressed.bind(card_idx))
	_card_labels.append(label)
	_card_icons.append(icon)
	return btn

func _on_card_pressed(card_idx: int) -> void:
	if _game_done or _local_finished or _resolving:
		return
	if card_idx < 0 or card_idx >= _deck.size():
		return
	if _card_matched[card_idx] or _card_revealed[card_idx]:
		return

	_reveal_card(card_idx)
	_opened_indexes.append(card_idx)
	if _opened_indexes.size() == 2:
		_resolve_current_pair()
	else:
		_state_label.text = "Choisis une deuxième rune."
	_update_card_interactions()

func _reveal_card(card_idx: int) -> void:
	_card_revealed[card_idx] = true
	var btn = _card_buttons[card_idx]
	var label: Label = _card_labels[card_idx]
	var icon: TextureRect = _card_icons[card_idx]
	label.visible = false
	icon.visible = true
	icon.modulate = Color(1, 1, 1, 1)
	btn.face_color = CARD_REVEALED_FACE
	btn.shadow_color = CARD_REVEALED_SHADOW

	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.08)
	tween.tween_property(btn, "scale", Vector2.ONE, 0.10)

func _play_intro_animation() -> void:
	await get_tree().process_frame
	for card_idx in range(_card_buttons.size()):
		if _game_done:
			return
		var btn = _card_buttons[card_idx]
		btn.scale = Vector2(0.7, 0.7)
		btn.position.y -= INTRO_DROP_DISTANCE
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "modulate:a", 1.0, 0.16)
		tween.tween_property(btn, "position:y", btn.position.y + INTRO_DROP_DISTANCE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(btn, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await get_tree().create_timer(INTRO_STEP_DELAY).timeout

	await get_tree().create_timer(0.28).timeout
	if _game_done:
		return
	_intro_animating = false
	_state_label.text = "Trouve les 8 paires de runes avant les autres."
	_update_card_interactions()

func _hide_card(card_idx: int) -> void:
	if _card_matched[card_idx]:
		return
	_card_revealed[card_idx] = false
	var btn = _card_buttons[card_idx]
	var label: Label = _card_labels[card_idx]
	var icon: TextureRect = _card_icons[card_idx]
	label.visible = false
	icon.visible = false
	icon.modulate = Color(1, 1, 1, 1)
	btn.face_color = CARD_BACK_FACE
	btn.shadow_color = CARD_BACK_SHADOW
	btn.scale = Vector2.ONE

func _mark_card_as_matched(card_idx: int) -> void:
	_card_matched[card_idx] = true
	_card_revealed[card_idx] = true
	var btn = _card_buttons[card_idx]
	var label: Label = _card_labels[card_idx]
	var icon: TextureRect = _card_icons[card_idx]
	label.visible = false
	icon.visible = true
	icon.modulate = Color(1, 1, 1, 1)
	btn.face_color = CARD_MATCH_FACE
	btn.shadow_color = CARD_MATCH_SHADOW
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _resolve_current_pair() -> void:
	_resolving = true
	_update_card_interactions()

	var first_idx: int = _opened_indexes[0]
	var second_idx: int = _opened_indexes[1]
	if _deck[first_idx] == _deck[second_idx]:
		_mark_card_as_matched(first_idx)
		_mark_card_as_matched(second_idx)
		if _sfx_correct and _sfx_correct.stream:
			_sfx_correct.play()
		_local_pairs += 1
		_state_label.text = "Bonne paire, continue."
		_opened_indexes.clear()
		_resolving = false
		_report_local_progress(_local_pairs >= PAIR_COUNT)
		if _local_pairs >= PAIR_COUNT:
			_local_finished = true
			_state_label.text = "Toutes les paires sont trouvées."
		_update_card_interactions()
		return

	_state_label.text = "Pas la même rune."
	_opened_indexes.clear()
	_resolving = false
	_update_card_interactions()
	_fade_out_mismatched_pair([first_idx, second_idx])

func _fade_out_mismatched_pair(card_indexes: Array[int]) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	for card_idx in card_indexes:
		if card_idx < 0 or card_idx >= _card_icons.size():
			continue
		var icon: TextureRect = _card_icons[card_idx]
		icon.modulate = Color(1, 1, 1, 1)
		tween.tween_property(icon, "modulate:a", 0.0, REVEAL_DURATION)
	await tween.finished
	for card_idx in card_indexes:
		if card_idx < 0 or card_idx >= _card_matched.size():
			continue
		if not _card_matched[card_idx]:
			_hide_card(card_idx)
	if not _game_done and _opened_indexes.is_empty():
		_state_label.text = "Essaye une autre combinaison."
	_update_card_interactions()

func _update_card_interactions() -> void:
	for card_idx in range(_card_buttons.size()):
		var btn = _card_buttons[card_idx]
		var locked: bool = _game_done or _local_finished or _resolving or _intro_animating or _card_matched[card_idx] or _card_revealed[card_idx]
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP

func _report_local_progress(finished: bool) -> void:
	if NetworkManager.is_host:
		_record_progress(_my_id, _local_pairs, finished)
	else:
		NetworkManager.send_game_message(0, {
			"action": "runes_pairs_progress",
			"pid": _my_id,
			"pairs": _local_pairs,
			"finished": finished,
		})

func _record_progress(pid: int, pairs: int, finished: bool) -> void:
	if _game_done and not bool(_finished_players.get(pid, false)):
		return
	if bool(_finished_players.get(pid, false)):
		return

	var synced_pairs: int = clampi(pairs, 0, PAIR_COUNT)
	var player_finished: bool = finished or synced_pairs >= PAIR_COUNT
	_pair_counts[pid] = synced_pairs
	_finished_players[pid] = player_finished

	var msg := {
		"action": "runes_pairs_progress_sync",
		"pid": pid,
		"pairs": synced_pairs,
		"finished": player_finished,
	}
	NetworkManager.send_game_message(0, msg)
	_apply_progress_sync(msg)
	if player_finished:
		get_tree().create_timer(0.9).timeout.connect(func(): end_game(pid))

func _apply_progress_sync(data: Dictionary) -> void:
	var pid: int = int(data.get("pid", -1))
	if pid == -1:
		return
	_pair_counts[pid] = clampi(int(data.get("pairs", 0)), 0, PAIR_COUNT)
	_finished_players[pid] = bool(data.get("finished", false))
	_refresh_status_list()

	if bool(_finished_players.get(pid, false)):
		_game_done = true
		var winner_name: String = NetworkManager.players.get(pid, {}).get("name", "Joueur")
		_state_label.text = "%s a trouvé toutes les paires." % winner_name
		if pid == _my_id and _sfx_tada and _sfx_tada.stream:
			_sfx_tada.play()
		_update_card_interactions()

func _on_game_over(winner_peer_id: int) -> void:
	_game_done = true
	_local_finished = true
	_update_card_interactions()

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.07, 0.82)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	var center := Control.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -310.0
	panel.offset_right = 310.0
	panel.offset_top = -170.0
	panel.offset_bottom = 170.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.15, 0.23, 0.98)
	style.set_corner_radius_all(20)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.41, 0.57, 0.77, 1)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Fin de partie !"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("f6e8ca"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var winner_lbl := Label.new()
	if winner_peer_id == -1:
		winner_lbl.text = "Personne n'a terminé la grille."
	else:
		var winner_name: String = NetworkManager.players.get(winner_peer_id, {}).get("name", "Joueur")
		winner_lbl.text = "🏆 %s a trouvé les 8 paires." % winner_name
	winner_lbl.add_theme_font_size_override("font_size", 28)
	winner_lbl.add_theme_color_override("font_color", Color("ffd166"))
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(winner_lbl)

	var local_lbl := Label.new()
	local_lbl.text = "Ta progression : %d/%d paires" % [_local_pairs, PAIR_COUNT]
	local_lbl.add_theme_font_size_override("font_size", 24)
	local_lbl.add_theme_color_override("font_color", Color("dff3e3"))
	local_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(local_lbl)

	await get_tree().create_timer(5.0).timeout
	get_tree().change_scene_to_file("res://Scenes/Lobby/SelectGames.tscn")
