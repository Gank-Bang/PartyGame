## Mini-jeu : Pile ou Face
## Une pièce tourne au centre. Chaque joueur choisit PILE ou FACE avant la fin
## du décompte. +1 pt par bonne réponse. Celui avec le plus de points gagne.
## Pour 1 à 4 joueurs en multijoueur via le relais WebSocket.
extends BaseGame

# ── Constantes ────────────────────────────────────────────────────────────────

const ROUNDS: int = 7
const ROUND_DURATION: float = 5.0
const COIN_SPIN_SPEED: float = 8.0   # radians/sec pour l'animation de la pièce

const PLAYER_FACE_COLORS: Array = [
	Color("e63946"), Color("457b9d"),
	Color("2a9d8f"), Color("e9c46a"),
]
const PLAYER_SHADOW_COLORS: Array = [
	Color("9b2226"), Color("1d3557"),
	Color("1b6a62"), Color("b5860d"),
]

# ── État du jeu ───────────────────────────────────────────────────────────────

var _current_round: int = 0
var _scores: Dictionary = {}
var _correct_side: int = -1   # 0 = PILE, 1 = FACE (hôte uniquement)
var _round_active: bool = false
var _choices: Dictionary = {}  # peer_id → int (hôte uniquement)
var _my_id: int = 0
var _time_left: float = 0.0
var _game_done: bool = false
var _my_choice: int = -1         # -1 = pas encore choisi ce round
var _spin_time: float = 0.0
## Indice de zone (0-3) → peer_id (-1 = inutilisée)
var _area_to_pid: Array = [-1, -1, -1, -1]
## peer_id → indice de zone (0-3)
var _pid_to_area: Dictionary = {}

# ── Nœuds header & pièce ─────────────────────────────────────────────────────

@onready var _round_label: Label      = $CanvasLayer/UI/MainVBox/Header/HBox/RoundLabel
@onready var _timer_bar: ProgressBar  = $CanvasLayer/UI/MainVBox/Header/HBox/TimerBar
@onready var _coin_node: Control      = $CanvasLayer/UI/MainVBox/CoinZone/CoinNode
@onready var _coin_label: Label       = $CanvasLayer/UI/MainVBox/CoinZone/CoinNode/CoinFace/CoinLabel

# ── Surcharge BaseGame ────────────────────────────────────────────────────────

func _spawn_players() -> void:
	pass   # tout en UI

func _on_game_ready() -> void:
	_my_id = NetworkManager.local_peer_id()
	_assign_players_to_areas()
	_configure_areas()
	if NetworkManager.is_host:
		_start_next_round()

func _process(delta: float) -> void:
	if _game_done:
		return

	if not _round_active:
		return

	# Animation de la pièce (s'arrête quand _round_active = false)
	if _coin_node:
		_spin_time += delta
		var angle: float = _spin_time * COIN_SPIN_SPEED
		_coin_node.scale.x = abs(cos(angle))
		if _coin_label:
			var side: int = int(angle / PI) % 2
			_coin_label.text = "PILE" if side == 0 else "FACE"

	_time_left -= delta
	if _timer_bar:
		_timer_bar.value = clampf(_time_left / ROUND_DURATION, 0.0, 1.0)
	if NetworkManager.is_host and _time_left <= 0.0:
		_round_active = false
		_broadcast_round_result()

# ── Assignation joueurs ↔ zones ───────────────────────────────────────────────

func _assign_players_to_areas() -> void:
	var ids: Array = NetworkManager.players.keys()
	var sorted: Array = [_my_id]
	for id in ids:
		if id != _my_id:
			sorted.append(id)
	for i in range(min(sorted.size(), 4)):
		_area_to_pid[i] = sorted[i]
		_pid_to_area[sorted[i]] = i
	for i in range(sorted.size(), 4):
		_get_area_root(i).visible = false
	if sorted.size() <= 2:
		get_node("CanvasLayer/UI/MainVBox/AreaRows/Row2").visible = false

func _configure_areas() -> void:
	for i in range(4):
		var pid: int = _area_to_pid[i]
		if pid == -1:
			continue
		_scores[pid] = 0
		var face: Color = PLAYER_FACE_COLORS[i]
		var shad: Color = PLAYER_SHADOW_COLORS[i]
		var pdata: Dictionary = NetworkManager.players.get(pid, {})
		_get_name_label(i).text = pdata.get("name", "Joueur") + (" ★" if pid == _my_id else "")
		_get_name_label(i).add_theme_color_override("font_color", face.lightened(0.55))
		_get_score_label(i).text = "0 pt"
		_get_choice_row(i).visible = (pid == _my_id)
		if pid == _my_id:
			_connect_choice_buttons(i)
		_set_btn_colors(i, face, shad)

# ── Accesseurs nœuds par indice de zone ──────────────────────────────────────

func _get_area_root(idx: int) -> Control:
	var row := "Row1" if idx < 2 else "Row2"
	return get_node("CanvasLayer/UI/MainVBox/AreaRows/%s/PlayerArea%d" % [row, idx + 1]) as Control

func _get_area_node(idx: int, sub: String) -> Node:
	return _get_area_root(idx).get_node(sub)

func _get_name_label(idx: int) -> Label:
	return _get_area_node(idx, "Margin/VBox/NameRow/NameLabel") as Label

func _get_score_label(idx: int) -> Label:
	return _get_area_node(idx, "Margin/VBox/NameRow/ScoreLabel") as Label

func _get_feedback_label(idx: int) -> Label:
	return _get_area_node(idx, "Margin/VBox/FeedbackLabel") as Label

func _get_choice_row(idx: int) -> HBoxContainer:
	return _get_area_node(idx, "Margin/VBox/ChoiceRow") as HBoxContainer

# ── Connexion et style des boutons ───────────────────────────────────────────

func _connect_choice_buttons(area_idx: int) -> void:
	var cr := _get_choice_row(area_idx)
	cr.get_node("BtnPile").pressed.connect(_on_choice_pressed.bind(0))
	cr.get_node("BtnFace").pressed.connect(_on_choice_pressed.bind(1))

func _set_btn_colors(idx: int, face: Color, shad: Color) -> void:
	var cr := _get_choice_row(idx)
	for btn_name in ["BtnPile", "BtnFace"]:
		var btn := cr.get_node(btn_name)
		btn.set("face_color", face)
		btn.set("shadow_color", shad)

# ── Gestion des rounds ────────────────────────────────────────────────────────

func _start_next_round() -> void:
	_current_round += 1
	if _current_round > ROUNDS:
		_end_game_host()
		return
	_correct_side = randi() % 2
	var msg: Dictionary = {
		"action": "pof_new_round",
		"round": _current_round,
	}
	NetworkManager.send_game_message(0, msg)
	_setup_round(msg)

func _setup_round(data: Dictionary) -> void:
	_current_round = int(data.get("round", _current_round))
	_round_active = true
	_choices.clear()
	_my_choice = -1
	_time_left = ROUND_DURATION
	_spin_time = 0.0
	if _round_label:
		_round_label.text = "Round %d / %d" % [_current_round, ROUNDS]
	if _timer_bar:
		_timer_bar.value = 1.0
	for i in range(4):
		if _area_to_pid[i] != -1:
			var fb := _get_feedback_label(i)
			fb.text = ""
			fb.add_theme_color_override("font_color", Color("f5e6c8"))
	var local_area: int = _pid_to_area.get(_my_id, -1)
	if local_area != -1:
		_set_buttons_disabled(false)

# ── Input joueur ──────────────────────────────────────────────────────────────

func _on_choice_pressed(side: int) -> void:
	if not _round_active or _my_choice != -1:
		return
	_my_choice = side
	_set_buttons_disabled(true)
	var local_area: int = _pid_to_area.get(_my_id, -1)
	if local_area != -1:
		_get_feedback_label(local_area).text = "⏳ " + ("PILE" if side == 0 else "FACE")
		_get_feedback_label(local_area).add_theme_color_override("font_color", Color("a8dadc"))
	if NetworkManager.is_host:
		_record_choice(_my_id, side)
	else:
		NetworkManager.send_game_message(0, {
			"action": "pof_choice",
			"side": side,
			"from": _my_id,
		})

# ── Validation (hôte uniquement) ─────────────────────────────────────────────

func _record_choice(guesser_id: int, side: int) -> void:
	if not _round_active:
		return
	_choices[guesser_id] = side
	# Terminer le round dès que tous les joueurs ont voté
	var all_voted: bool = true
	for pid in _scores.keys():
		if pid not in _choices:
			all_voted = false
			break
	if all_voted:
		_round_active = false
		_broadcast_round_result()

func _broadcast_round_result() -> void:
	# Compter les bonnes réponses et mettre à jour les scores
	for pid in _choices:
		if _choices[pid] == _correct_side:
			_scores[pid] = _scores.get(pid, 0) + 1
	var serialized_choices: Dictionary = {}
	for pid in _choices:
		serialized_choices[str(pid)] = _choices[pid]
	var msg: Dictionary = {
		"action": "pof_round_result",
		"correct": _correct_side,
		"choices": serialized_choices,
		"scores": _serialise_scores(),
	}
	NetworkManager.send_game_message(0, msg)
	_apply_round_result(msg)

func _serialise_scores() -> Dictionary:
	var result: Dictionary = {}
	for pid in _scores:
		result[str(pid)] = _scores[pid]
	return result

# ── Réception des messages réseau ─────────────────────────────────────────────

func _on_custom_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"pof_new_round":
			_setup_round(data)
		"pof_choice":
			if NetworkManager.is_host:
				_record_choice(int(data.get("from", from_id)), int(data.get("side", -1)))
		"pof_round_result":
			_apply_round_result(data)

func _apply_round_result(data: Dictionary) -> void:
	_round_active = false
	var correct: int = int(data.get("correct", 0))
	var choices_data: Dictionary = data.get("choices", {})
	var scores_data: Dictionary = data.get("scores", {})
	for key in scores_data:
		_scores[int(key)] = int(scores_data[key])

	# La pièce se stabilise sur le résultat
	if _coin_label:
		_coin_label.text = "PILE" if correct == 0 else "FACE"
	if _coin_node:
		_coin_node.scale.x = 1.0

	# Feedback par zone joueur
	for i in range(4):
		var pid: int = _area_to_pid[i]
		if pid == -1:
			continue
		var player_choice: int = int(choices_data.get(str(pid), -1))
		var fb := _get_feedback_label(i)
		if player_choice == -1:
			fb.text = "⏱ Pas répondu !"
			fb.add_theme_color_override("font_color", Color("f4a261"))
		elif player_choice == correct:
			fb.text = "✓ Bonne réponse !"
			fb.add_theme_color_override("font_color", Color("52b788"))
		else:
			fb.text = "✗ Faux !"
			fb.add_theme_color_override("font_color", Color("e63946"))

	_update_score_displays()
	_set_buttons_disabled(true)
	if NetworkManager.is_host:
		await get_tree().create_timer(3.0).timeout
		_start_next_round()

func _update_score_displays() -> void:
	for i in range(4):
		var pid: int = _area_to_pid[i]
		if pid == -1:
			continue
		var pts: int = _scores.get(pid, 0)
		_get_score_label(i).text = "%d pt%s" % [pts, "s" if pts > 1 else ""]

func _set_buttons_disabled(disabled: bool) -> void:
	var local_area: int = _pid_to_area.get(_my_id, -1)
	if local_area == -1:
		return
	var cr := _get_choice_row(local_area)
	var filter: Control.MouseFilter = Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_STOP
	var alpha: float = 0.4 if disabled else 1.0
	for btn_name in ["BtnPile", "BtnFace"]:
		var btn := cr.get_node(btn_name)
		(btn as Control).mouse_filter = filter
		btn.modulate = Color(alpha, alpha, alpha, 1.0)

# ── Fin de partie ─────────────────────────────────────────────────────────────

func _end_game_host() -> void:
	if _game_done:
		return
	_game_done = true
	var best_id: int = -1
	var best_score: int = -1
	for pid in _scores:
		if _scores[pid] > best_score:
			best_score = _scores[pid]
			best_id = pid
	end_game(best_id)

func _on_game_over(winner_peer_id: int) -> void:
	_game_done = true
	_round_active = false
	_set_buttons_disabled(true)

	var winner_name: String = NetworkManager.players.get(winner_peer_id, {}).get("name", "?")
	var winner_score: int = _scores.get(winner_peer_id, 0)

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	var center_ctrl := Control.new()
	center_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center_ctrl)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.offset_top = -200.0
	panel.offset_bottom = 200.0
	center_ctrl.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Fin de partie !"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("f5e6c8"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var winner_lbl := Label.new()
	winner_lbl.text = "🏆 %s — %d point%s" % [
		winner_name, winner_score, "s" if winner_score > 1 else ""
	]
	winner_lbl.add_theme_font_size_override("font_size", 34)
	winner_lbl.add_theme_color_override("font_color", Color("f4a261"))
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(winner_lbl)

	var sorted_ids: Array = _scores.keys()
	sorted_ids.sort_custom(func(a_id, b_id): return _scores[a_id] > _scores[b_id])
	for rank in range(sorted_ids.size()):
		var pid: int = sorted_ids[rank]
		var pname: String = NetworkManager.players.get(pid, {}).get("name", "?")
		var pts: int = _scores.get(pid, 0)
		var rank_lbl := Label.new()
		rank_lbl.text = "%d. %s — %d pt%s" % [rank + 1, pname, pts, "s" if pts > 1 else ""]
		rank_lbl.add_theme_font_size_override("font_size", 22)
		rank_lbl.add_theme_color_override("font_color", Color.WHITE)
		rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(rank_lbl)

	await get_tree().create_timer(5.0).timeout
	get_tree().change_scene_to_file("res://Scenes/Lobby/SelectGames.tscn")
