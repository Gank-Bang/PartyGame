## Mini-jeu : Équation — trouve le chiffre manquant !
## Pour 1 à 4 joueurs en multijoueur via le relais WebSocket.
## Tous les nœuds UI sont définis dans EquationMiniGame.tscn.
extends BaseGame

# ── Constantes ────────────────────────────────────────────────────────────────

const ROUNDS: int = 5
const ROUND_DURATION: float = 8.0
const GUESS_COOLDOWN: float = 1.5

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
var _equation: Dictionary = {}
var _round_active: bool = false
var _cooldowns: Dictionary = {}    # peer_id → float (hôte uniquement)
var _my_id: int = 0
var _time_left: float = 0.0
var _game_done: bool = false
var _numpad_disabled: bool = false
var _input_buffer: String = ""
var _answer_digits: int = 1
## Indice de zone (0-3) → peer_id (-1 = inutilisée)
var _area_to_pid: Array = [-1, -1, -1, -1]
## peer_id → indice de zone (0-3)
var _pid_to_area: Dictionary = {}

# ── Nœuds header ─────────────────────────────────────────────────────────────

@onready var _round_label: Label = $CanvasLayer/UI/MainVBox/Header/HBox/RoundLabel
@onready var _timer_bar: ProgressBar = $CanvasLayer/UI/MainVBox/Header/HBox/TimerBar

# ── Surcharge BaseGame ────────────────────────────────────────────────────────

## Pas de CharacterBody2D — tout est UI défini dans la scène.
func _spawn_players() -> void:
	pass

func _on_game_ready() -> void:
	_my_id = NetworkManager.local_peer_id()
	_assign_players_to_areas()
	_configure_areas()
	if NetworkManager.is_host:
		_start_next_round()

func _process(delta: float) -> void:
	if _game_done or not _round_active:
		return
	if NetworkManager.is_host:
		for pid in _cooldowns.keys():
			_cooldowns[pid] -= delta
			if _cooldowns[pid] <= 0.0:
				_cooldowns.erase(pid)
	_time_left -= delta
	if _timer_bar:
		_timer_bar.value = clampf(_time_left / ROUND_DURATION, 0.0, 1.0)
	if NetworkManager.is_host and _time_left <= 0.0:
		_round_active = false
		_broadcast_round_result(-1)

# ── Assignation joueurs ↔ zones ───────────────────────────────────────────────

func _assign_players_to_areas() -> void:
	var ids: Array = NetworkManager.players.keys()
	# Joueur local en zone 0, les autres à la suite
	var sorted: Array = [_my_id]
	for id in ids:
		if id != _my_id:
			sorted.append(id)
	for i in range(min(sorted.size(), 4)):
		_area_to_pid[i] = sorted[i]
		_pid_to_area[sorted[i]] = i
	# Masquer les zones non utilisées
	for i in range(sorted.size(), 4):
		_get_area_root(i).visible = false
	# Masquer Row2 entier si ≤ 2 joueurs (sinon la rangée vide prend de la place)
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
		#_get_area_bg(i).color = face.darkened(0.72)
		_get_name_label(i).text = pdata.get("name", "Joueur") + (" ★" if pid == _my_id else "")
		_get_name_label(i).add_theme_color_override("font_color", face.lightened(0.55))
		_get_score_label(i).text = "0 pt"
		_get_numpad(i).visible = (pid == _my_id)
		if pid == _my_id:
			_connect_numpad(i)
		_set_eq_btn_colors(i, face, shad)

# ── Accesseurs nœuds par indice de zone ──────────────────────────────────────

func _get_area_root(idx: int) -> Control:
	var row := "Row1" if idx < 2 else "Row2"
	return get_node("CanvasLayer/UI/MainVBox/AreaRows/%s/PlayerArea%d" % [row, idx + 1]) as Control

func _get_area_node(idx: int, sub: String) -> Node:
	return _get_area_root(idx).get_node(sub)

func _get_area_bg(idx: int) -> ColorRect:
	return _get_area_node(idx, "AreaBG") as ColorRect

func _get_name_label(idx: int) -> Label:
	return _get_area_node(idx, "Margin/VBox/NameRow/NameLabel") as Label

func _get_score_label(idx: int) -> Label:
	return _get_area_node(idx, "Margin/VBox/NameRow/ScoreLabel") as Label

func _get_feedback_label(idx: int) -> Label:
	return _get_area_node(idx, "Margin/VBox/FeedbackLabel") as Label

func _get_numpad(idx: int) -> GridContainer:
	return _get_area_node(idx, "Margin/VBox/Numpad") as GridContainer

# ── Connexion du pavé numérique ───────────────────────────────────────────────

func _connect_numpad(area_idx: int) -> void:
	var numpad := _get_numpad(area_idx)
	for n in range(0, 10):
		var btn := numpad.get_node_or_null("Btn%d" % n)
		if btn:
			btn.pressed.connect(_on_numpad_pressed.bind(n))

# ── Couleurs et affichage des boutons équation ────────────────────────────────

func _set_eq_btn_colors(idx: int, face: Color, shad: Color) -> void:
	for sub in ["Margin/VBox/EqRow/BtnB", "Margin/VBox/EqRow/BtnResult"]:
		var btn := _get_area_node(idx, sub)
		btn.set("face_color", face)
		btn.set("shadow_color", shad)

func _display_equation_in_area(idx: int, eq: Dictionary) -> void:
	var eq_hidden: String = eq.get("hidden", "a")
	var val_a: String = "?" if eq_hidden == "a" else str(eq["a"])
	var val_b: String = "?" if eq_hidden == "b" else str(eq["b"])
	var val_result: String = "?" if eq_hidden == "result" else str(eq["result"])
	var face: Color = PLAYER_FACE_COLORS[idx]
	var shad: Color = PLAYER_SHADOW_COLORS[idx]
	var btn_a := _get_area_node(idx, "Margin/VBox/EqRow/BtnA")
	var btn_op := _get_area_node(idx, "Margin/VBox/EqRow/BtnOp")
	var btn_b := _get_area_node(idx, "Margin/VBox/EqRow/BtnB")
	var btn_result := _get_area_node(idx, "Margin/VBox/EqRow/BtnResult")
	btn_a.set("text", val_a)
	btn_op.set("text", eq["op"])
	btn_b.set("text", val_b)
	btn_result.set("text", val_result)
	if val_a == "?":
		btn_a.set("face_color", Color("f4a261"))
		btn_a.set("shadow_color", Color("b05d1e"))
	else:
		btn_a.set("face_color", face)
		btn_a.set("shadow_color", shad)
	if val_b == "?":
		btn_b.set("face_color", Color("f4a261"))
		btn_b.set("shadow_color", Color("b05d1e"))
	else:
		btn_b.set("face_color", face)
		btn_b.set("shadow_color", shad)
	if val_result == "?":
		btn_result.set("face_color", Color("f4a261"))
		btn_result.set("shadow_color", Color("b05d1e"))
	else:
		btn_result.set("face_color", face)
		btn_result.set("shadow_color", shad)

# ── Génération d'équations ────────────────────────────────────────────────────

## Génère une équation simple dont la réponse manquante est toujours un chiffre 1-9.
## Format : a [op] b = résultat,  l'un de a ou b est remplacé par '?'.
func _generate_equation() -> Dictionary:
	var ops: Array = ["+", "-", "x"]
	var op: String = ops[randi() % ops.size()]
	var a: int
	var b: int
	var result: int

	match op:
		"+":
			a = randi_range(1, 15)
			b = randi_range(1, 15)
			result = a + b
		"-":
			# b et result 1-15, a = b + result (max 30)
			b = randi_range(1, 15)
			result = randi_range(1, 15)
			a = b + result
		"x":
			# résultat max 81 (≤ 99)
			a = randi_range(2, 9)
			b = randi_range(2, 9)
			result = a * b

	# La réponse cachée peut être a, b ou le résultat (jamais > 99)
	var eq_hidden: String = ["a", "b", "result"][randi() % 3]
	var answer: int
	match eq_hidden:
		"a":    answer = a
		"b":    answer = b
		"result": answer = result
	return {"a": a, "op": op, "b": b, "result": result, "hidden": eq_hidden, "answer": answer}

# ── Gestion des rounds ────────────────────────────────────────────────────────

func _start_next_round() -> void:
	_current_round += 1
	if _current_round > ROUNDS:
		_end_game_host()
		return

	_equation = _generate_equation()
	var msg: Dictionary = {
		"action": "eq_new_round",
		"round": _current_round,
		"a": _equation["a"],
		"op": _equation["op"],
		"b": _equation["b"],
		"result": _equation["result"],
		"hidden": _equation["hidden"],
		"answer": _equation["answer"],
	}
	NetworkManager.send_game_message(0, msg)
	_setup_round(msg)


func _setup_round(data: Dictionary) -> void:
	_equation = {
		"a": int(data["a"]), "op": str(data["op"]), "b": int(data["b"]),
		"result": int(data["result"]), "hidden": str(data["hidden"]), "answer": int(data["answer"]),
	}
	_current_round = int(data.get("round", _current_round))
	_round_active = true
	_cooldowns.clear()
	_input_buffer = ""
	_answer_digits = str(int(data.get("answer", 1))).length()
	_time_left = ROUND_DURATION
	_set_numpad_disabled(false)
	if _round_label:
		_round_label.text = "Round %d / %d" % [_current_round, ROUNDS]
	if _timer_bar:
		_timer_bar.value = 1.0
	for i in range(4):
		if _area_to_pid[i] != -1:
			var fb := _get_feedback_label(i)
			fb.text = ""
			fb.add_theme_color_override("font_color", Color("f5e6c8"))
			_display_equation_in_area(i, _equation)

# ── Input joueur ──────────────────────────────────────────────────────────────

func _on_numpad_pressed(value: int) -> void:
	if not _round_active or _numpad_disabled:
		return
	if _input_buffer.length() >= _answer_digits:
		return
	_input_buffer += str(value)
	if _input_buffer.length() == _answer_digits:
		_submit_buffered_guess()
	else:
		var area_idx: int = _pid_to_area.get(_my_id, -1)
		if area_idx != -1:
			_get_feedback_label(area_idx).text = "→ %s" % _input_buffer
			_get_feedback_label(area_idx).add_theme_color_override("font_color", Color("f5e6c8"))


func _submit_buffered_guess() -> void:
	if _input_buffer.is_empty():
		return
	var value: int = int(_input_buffer)
	_input_buffer = ""
	if not _round_active or _numpad_disabled:
		return
	if NetworkManager.is_host:
		_process_guess(_my_id, value)
	else:
		NetworkManager.send_game_message(0, {
			"action": "eq_guess",
			"value": value,
			"from": _my_id,
		})

# ── Validation (hôte uniquement) ──────────────────────────────────────────────

func _process_guess(guesser_id: int, value: int) -> void:
	if not _round_active:
		return
	if guesser_id in _cooldowns and _cooldowns[guesser_id] > 0.0:
		return

	if value == _equation.get("answer", -1):
		_round_active = false
		_broadcast_round_result(guesser_id)
	else:
		_cooldowns[guesser_id] = GUESS_COOLDOWN
		NetworkManager.send_game_message(0, {"action": "eq_wrong", "guesser": guesser_id})
		# Appliquer localement si c'est l'hôte lui-même qui s'est trompé
		if guesser_id == _my_id:
			_on_wrong_answer(_my_id)


func _broadcast_round_result(winner_id: int) -> void:
	# Incrémenter le score du gagnant avant de le sérialiser
	if winner_id != -1 and winner_id in _scores:
		_scores[winner_id] += 1
	var msg: Dictionary = {
		"action": "eq_round_result",
		"winner": winner_id,
		"answer": _equation.get("answer", 0),
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
		"eq_new_round":
			_setup_round(data)
		"eq_guess":
			if NetworkManager.is_host:
				_process_guess(int(data.get("from", from_id)), int(data.get("value", -1)))
		"eq_wrong":
			_on_wrong_answer(int(data.get("guesser", -1)))
		"eq_round_result":
			_apply_round_result(data)


func _apply_round_result(data: Dictionary) -> void:
	_round_active = false
	_input_buffer = ""
	var local_area: int = _pid_to_area.get(_my_id, -1)
	if local_area != -1:
		var fb := _get_feedback_label(local_area)
		if fb.text.begins_with("→"):
			fb.text = ""
	var winner_id: int = int(data.get("winner", -1))
	var answer: int = int(data.get("answer", 0))
	var scores_data: Dictionary = data.get("scores", {})
	for key in scores_data:
		_scores[int(key)] = int(scores_data[key])
	_reveal_answer_in_areas(answer)
	_update_score_displays()
	for i in range(4):
		var pid: int = _area_to_pid[i]
		if pid == -1:
			continue
		if pid == winner_id:
			_get_feedback_label(i).text = "✓ Correct !"
			_get_feedback_label(i).add_theme_color_override("font_color", Color("52b788"))
		elif winner_id == -1:
			_get_feedback_label(i).text = "⏱ Temps écoulé ! Réponse : %d" % answer
			_get_feedback_label(i).add_theme_color_override("font_color", Color("f4a261"))
	_set_numpad_disabled(true)
	if NetworkManager.is_host:
		await get_tree().create_timer(3.0).timeout
		_start_next_round()


func _on_wrong_answer(guesser_id: int) -> void:
	if guesser_id <= 0:
		return
	var area_idx: int = _pid_to_area.get(guesser_id, -1)
	if area_idx == -1:
		return
	_get_feedback_label(area_idx).text = "✗ Faux !"
	_get_feedback_label(area_idx).add_theme_color_override("font_color", Color("e63946"))
	if guesser_id == _my_id:
		_set_numpad_disabled(true)
		await get_tree().create_timer(GUESS_COOLDOWN).timeout
		if _round_active:
			_set_numpad_disabled(false)
			_get_feedback_label(area_idx).text = ""


func _reveal_answer_in_areas(answer: int) -> void:
	var eq_hidden: String = _equation.get("hidden", "a")
	var subs: Array = ["Margin/VBox/EqRow/BtnResult"] if eq_hidden == "result" \
		else ["Margin/VBox/EqRow/BtnA", "Margin/VBox/EqRow/BtnB"]
	for i in range(4):
		if _area_to_pid[i] == -1:
			continue
		for sub in subs:
			var btn := _get_area_node(i, sub)
			if btn.get("text") == "?":
				btn.set("text", str(answer))
				btn.set("face_color", Color("52b788"))
				btn.set("shadow_color", Color("1b5e20"))


func _update_score_displays() -> void:
	for i in range(4):
		var pid: int = _area_to_pid[i]
		if pid == -1:
			continue
		var pts: int = _scores.get(pid, 0)
		_get_score_label(i).text = "%d pt%s" % [pts, "s" if pts > 1 else ""]


func _set_numpad_disabled(disabled: bool) -> void:
	_numpad_disabled = disabled
	var local_area: int = _pid_to_area.get(_my_id, -1)
	if local_area == -1:
		return
	var numpad := _get_numpad(local_area)
	var filter: Control.MouseFilter = Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_STOP
	var alpha: float = 0.4 if disabled else 1.0
	for child in numpad.get_children():
		if child is Control:
			(child as Control).mouse_filter = filter
		child.modulate = Color(alpha, alpha, alpha, 1.0)

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
	_set_numpad_disabled(true)

	var winner_name: String = NetworkManager.players.get(winner_peer_id, {}).get("name", "?")
	var winner_score: int = _scores.get(winner_peer_id, 0)

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	# Conteneur pour centrer le panneau
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

	# Classement complet
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
