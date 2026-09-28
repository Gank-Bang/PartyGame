## Mini-jeu : Cercle Infernal — un seul bouton, des réflexes en acier !
## Un curseur tourne autour d'un anneau et accélère au fil de la partie.
## Des zones apparaissent au hasard sur l'anneau, à une taille aléatoire,
## puis rétrécissent jusqu'à disparaître.
## Appuie (Espace / clic / tap) pile quand le curseur traverse une zone pour
## la détruire : plus elle est petite, plus ça rapporte. Un appui dans le vide
## casse le combo, sans retirer de point.
## Chaque joueur joue sur son propre anneau en local ; seul le score final est comparé.
extends BaseGame

# ── Réglages de jeu ───────────────────────────────────────────────────────────

const GAME_DURATION: float = 30.0

const RADIUS: float = 300.0
const RING_WIDTH: float = 30.0
const CURSOR_RADIUS: float = 15.0

## Vitesse angulaire du curseur (rad/s) : lente au début, puis ça part en vrille.
const SPEED_START: float = 3.2
const SPEED_ACCEL: float = 0.18
const SPEED_MAX: float = 10.0

## Demi-largeur angulaire d'une zone à sa naissance (radians).
const ZONE_HALF_MIN: float = 0.16
const ZONE_HALF_MAX: float = 0.50
## Proportion de la taille initiale encore présente juste avant disparition.
const ZONE_SHRINK_TO: float = 0.18
const ZONE_LIFE_MIN: float = 2.0
const ZONE_LIFE_MAX: float = 3.4
const ZONE_MAX_ACTIVE: int = 4
## Écart angulaire minimum entre deux zones voisines.
const ZONE_MIN_GAP: float = 0.55
## Marge devant le curseur : une zone n'apparaît jamais sous ses pieds.
const ZONE_SPAWN_AHEAD: float = 0.7

const SPAWN_INTERVAL_START: float = 1.6
const SPAWN_INTERVAL_END: float = 0.65

const MISS_LOCKOUT: float = 0.4
const PRESS_COOLDOWN: float = 0.12
const COMBO_MAX: int = 6
const BULLSEYE_RATIO: float = 0.25
const FINAL_SCORE_RETRY_INTERVAL: float = 0.9
const HOST_REQUERY_INTERVAL: float = 1.8
const RESULTS_WARNING_TIME: float = 3.0
const RESULTS_TIMEOUT: float = 10.0
const ERROR_RETURN_DELAY: float = 2.0

const BURST_LIFE: float = 0.45

# ── Couleurs ──────────────────────────────────────────────────────────────────

const PLAYER_COLORS: Array = [
	Color("e63946"), Color("457b9d"), Color("2a9d8f"), Color("e9c46a"),
]
const BG_COLOR: Color = Color("161d2b")
const DISC_COLOR: Color = Color("111722")
const RING_COLOR: Color = Color("232d42")
const RING_EDGE_COLOR: Color = Color("36455f")
const ZONE_WIDE_COLOR: Color = Color("52b788")
const ZONE_TIGHT_COLOR: Color = Color("e63946")
const CURSOR_COLOR: Color = Color("f5e6c8")

# ── État partagé ──────────────────────────────────────────────────────────────

var _my_id: int = 0
var _elapsed: float = 0.0
var _running: bool = false
var _game_done: bool = false
var _waiting_results: bool = false
var _fatal_error_active: bool = false

var _cursor_angle: float = 0.0

## id de zone → {"angle", "half", "born", "life"}
var _zones: Dictionary = {}
var _scores: Dictionary = {}
var _combos: Dictionary = {}
var _player_order: Array = []
var _final_reports: Dictionary = {}

# ── État local ────────────────────────────────────────────────────────────────

var _next_zone_id: int = 1
var _next_spawn_in: float = 1.2
var _miss_lockout_until: float = 0.0
var _results_wait_time: float = 0.0
var _final_retry_in: float = FINAL_SCORE_RETRY_INTERVAL
var _host_requery_in: float = HOST_REQUERY_INTERVAL
var _warning_shown: bool = false
var _final_score_acknowledged: bool = false
var _reported_score: int = 0

# ── Effets locaux ─────────────────────────────────────────────────────────────

var _bursts: Array = []
var _flash: float = 0.0
var _shake: float = 0.0
var _local_cooldown: float = 0.0
var _status_time: float = 0.0

var _score_labels: Dictionary = {}
var _sfx_hit: AudioStreamPlayer
var _sfx_miss: AudioStreamPlayer

# ── Nœuds ─────────────────────────────────────────────────────────────────────

@onready var _timer_bar: ProgressBar  = $CanvasLayer/UI/Header/HBox/TimerBar
@onready var _combo_label: Label      = $CanvasLayer/UI/ComboLabel
@onready var _status_label: Label     = $CanvasLayer/UI/StatusLabel
@onready var _score_row: HBoxContainer = $CanvasLayer/UI/ScoreRow

# ── Surcharge BaseGame ────────────────────────────────────────────────────────

func _spawn_players() -> void:
	pass   # tout est dessiné à la main

func _on_game_ready() -> void:
	_my_id = NetworkManager.local_peer_id()
	_build_player_order()
	_build_score_row()
	_setup_sfx()
	_status_label.text = ""
	_combo_label.text = ""
	_next_spawn_in = _spawn_interval()
	if not NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.connect(_on_connection_failed)
	if not NetworkManager.player_list_changed.is_connected(_on_player_list_changed):
		NetworkManager.player_list_changed.connect(_on_player_list_changed)
	_running = true

func _process(delta: float) -> void:
	if _game_done:
		queue_redraw()
		return

	_update_effects(delta)

	if _running:
		_elapsed += delta
		_step_local_gameplay(delta)
		_purge_dead_zones()
		_update_hud()
		if _elapsed >= GAME_DURATION:
			_finish_local_game()
	elif _waiting_results and not _game_done:
		_process_results_wait(delta)

	queue_redraw()

# ── Simulation ────────────────────────────────────────────────────────────────

func _cursor_speed() -> float:
	return minf(SPEED_START + SPEED_ACCEL * _elapsed, SPEED_MAX)

func _spawn_interval() -> float:
	var progress: float = clampf(_elapsed / GAME_DURATION, 0.0, 1.0)
	return lerpf(SPAWN_INTERVAL_START, SPAWN_INTERVAL_END, progress)

func _zone_progress(zone: Dictionary) -> float:
	var life: float = maxf(0.01, float(zone["life"]))
	return (_elapsed - float(zone["born"])) / life

## Demi-largeur actuelle de la zone : elle rétrécit du début à la fin de sa vie.
func _zone_half(zone: Dictionary) -> float:
	var start: float = float(zone["half"])
	return lerpf(start, start * ZONE_SHRINK_TO, clampf(_zone_progress(zone), 0.0, 1.0))

func _purge_dead_zones() -> void:
	for id in _zones.keys():
		if _zone_progress(_zones[id]) >= 1.0:
			_zones.erase(id)

func _add_zone(raw: Dictionary) -> void:
	var id: int = int(raw.get("id", 0))
	if id == 0:
		return
	_zones[id] = {
		"angle": float(raw.get("angle", 0.0)),
		"half": float(raw.get("half", ZONE_HALF_MIN)),
		"born": float(raw.get("born", _elapsed)),
		"life": float(raw.get("life", ZONE_LIFE_MIN)),
	}

# ── Boucle locale ─────────────────────────────────────────────────────────────

func _step_local_gameplay(delta: float) -> void:
	var speed: float = _cursor_speed()
	_cursor_angle = wrapf(_cursor_angle + speed * delta, 0.0, TAU)
	_next_spawn_in -= delta
	if _next_spawn_in <= 0.0:
		_next_spawn_in = _spawn_interval()
		_spawn_zone()

func _spawn_zone() -> void:
	if _zones.size() >= ZONE_MAX_ACTIVE:
		return
	var half: float = randf_range(ZONE_HALF_MIN, ZONE_HALF_MAX)
	var angle: float = _find_free_angle(half)
	if angle < 0.0:
		return
	var zone: Dictionary = {
		"id": _next_zone_id,
		"angle": angle,
		"half": half,
		"born": _elapsed,
		"life": randf_range(ZONE_LIFE_MIN, ZONE_LIFE_MAX),
	}
	_next_zone_id += 1
	_add_zone(zone)

## Renvoie un angle libre devant le curseur, ou -1.0 si l'anneau est trop chargé.
func _find_free_angle(half: float) -> float:
	for _attempt in range(24):
		var angle: float = randf() * TAU
		if wrapf(angle - _cursor_angle, 0.0, TAU) < ZONE_SPAWN_AHEAD + half:
			continue
		var free: bool = true
		for zone in _zones.values():
			if absf(angle_difference(angle, float(zone["angle"]))) < half + float(zone["half"]) + ZONE_MIN_GAP:
				free = false
				break
		if free:
			return angle
	return -1.0

# ── Input : un seul bouton ────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _game_done or not _running:
		return
	var pressed: bool = false
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventKey:
		pressed = event.pressed and not event.echo \
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_try_press()

func _try_press() -> void:
	if _local_cooldown > 0.0 or _elapsed < _miss_lockout_until:
		return
	_local_cooldown = PRESS_COOLDOWN
	_flash = 1.0
	_resolve_local_press(_cursor_angle)

func _resolve_local_press(angle: float) -> void:
	var zone_id: int = _find_zone_at(angle)
	if zone_id == -1:
		_combos[_my_id] = 0
		_miss_lockout_until = _elapsed + MISS_LOCKOUT
		_local_cooldown = MISS_LOCKOUT
		_add_burst(_cursor_angle, 0.05, ZONE_TIGHT_COLOR)
		_play(_sfx_miss)
		_set_status("Raté !", ZONE_TIGHT_COLOR)
	else:
		var zone: Dictionary = _zones[zone_id]
		var bullseye: bool = _is_bullseye(angle, zone)
		var combo: int = mini(int(_combos.get(_my_id, 0)) + 1, COMBO_MAX)
		var points: int = _points_for(_zone_half(zone), combo)
		_combos[_my_id] = combo
		_scores[_my_id] = int(_scores.get(_my_id, 0)) + points
		_add_burst(float(zone["angle"]), _zone_half(zone), _color_of(_my_id))
		_zones.erase(zone_id)
		if bullseye:
			_shake = maxf(_shake, 0.55)
		_play(_sfx_hit)
		_set_status(_format_hit_status(points, combo, bullseye), _color_of(_my_id))
	_refresh_scores()

## Zone la plus étroite contenant cet angle, ou -1.
func _find_zone_at(angle: float) -> int:
	var best_id: int = -1
	var best_half: float = 0.0
	for id in _zones:
		var half: float = _zone_half(_zones[id])
		if absf(angle_difference(angle, float(_zones[id]["angle"]))) > half:
			continue
		if best_id == -1 or half < best_half:
			best_id = id
			best_half = half
	return best_id

func _is_bullseye(angle: float, zone: Dictionary) -> bool:
	var half: float = _zone_half(zone)
	if half <= 0.0:
		return false
	var offset: float = absf(angle_difference(angle, float(zone["angle"])))
	return offset <= half * BULLSEYE_RATIO

func _format_hit_status(points: int, combo: int, bullseye: bool) -> String:
	var prefix: String = "Pile-poil !   " if bullseye else ""
	return "%s+%d   ×%d" % [prefix, points, combo]

func _points_for(half: float, combo: int) -> int:
	var tightness: float = 1.0 - clampf(half / ZONE_HALF_MAX, 0.0, 1.0)
	return 1 + int(round(tightness * 4.0)) + (combo - 1)

func _apply_scores(raw: Dictionary) -> void:
	for key in raw:
		_scores[int(key)] = int(raw[key])

func _serialise(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for pid in src:
		out[str(pid)] = int(src[pid])
	return out

# ── Réseau ────────────────────────────────────────────────────────────────────

func _on_custom_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"cc_final_score":
			if NetworkManager.is_host:
				var pid: int = int(data.get("from", from_id))
				_register_final_score(pid, int(data.get("score", 0)))
				NetworkManager.send_game_message(pid, {"action": "cc_final_score_ack"})
		"cc_final_score_ack":
			if not NetworkManager.is_host:
				_final_score_acknowledged = true
				if _waiting_results and not _game_done:
					_set_status("Score reçu par l'hôte — attente des autres...", Color("f4a261"))
		"cc_request_final_score":
			if not NetworkManager.is_host and _waiting_results and not _game_done:
				_send_final_score(true)
		"cc_final":
			if not NetworkManager.is_host:
				_apply_scores(data.get("scores", {}))
				_refresh_scores()

# ── Rendu ─────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var viewport: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport * 0.5
	if _shake > 0.0:
		center += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 14.0

	draw_rect(Rect2(Vector2.ZERO, viewport), BG_COLOR)
	draw_circle(center, RADIUS - RING_WIDTH * 0.5, DISC_COLOR)
	draw_arc(center, RADIUS, 0.0, TAU, 160, RING_COLOR, RING_WIDTH, true)
	draw_arc(center, RADIUS, 0.0, TAU, 160, RING_EDGE_COLOR, 2.0, true)

	for zone in _zones.values():
		var angle: float = float(zone["angle"])
		var half: float = _zone_half(zone)
		var openness: float = clampf(half / maxf(0.001, float(zone["half"])), 0.0, 1.0)
		var color: Color = ZONE_TIGHT_COLOR.lerp(ZONE_WIDE_COLOR, openness)
		draw_arc(center, RADIUS, angle - half, angle + half, 40, color.darkened(0.5), RING_WIDTH, true)
		draw_arc(center, RADIUS, angle - half, angle + half, 40, color, RING_WIDTH - 10.0, true)

	for burst in _bursts:
		var t: float = clampf(float(burst["age"]) / BURST_LIFE, 0.0, 1.0)
		var color: Color = burst["color"]
		color.a = 1.0 - t
		var angle: float = float(burst["angle"])
		var spread: float = float(burst["half"]) + t * 0.45
		draw_arc(center, RADIUS + t * 45.0, angle - spread, angle + spread, 40,
			color, maxf(1.0, RING_WIDTH * (1.0 - t)), true)

	var dir: Vector2 = Vector2(cos(_cursor_angle), sin(_cursor_angle))
	var tip: Vector2 = center + dir * RADIUS
	draw_line(center, center + dir * (RADIUS - RING_WIDTH), Color(1, 1, 1, 0.08), 3.0, true)
	draw_circle(tip, CURSOR_RADIUS + 6.0 + _flash * 14.0, Color(1, 1, 1, 0.16 + _flash * 0.4))
	draw_circle(tip, CURSOR_RADIUS, CURSOR_COLOR)

func _add_burst(angle: float, half: float, color: Color) -> void:
	_bursts.append({"angle": angle, "half": half, "age": 0.0, "color": color})

func _update_effects(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 4.0)
	_shake = maxf(0.0, _shake - delta * 2.0)
	_local_cooldown = maxf(0.0, _local_cooldown - delta)
	for i in range(_bursts.size() - 1, -1, -1):
		_bursts[i]["age"] = float(_bursts[i]["age"]) + delta
		if float(_bursts[i]["age"]) >= BURST_LIFE:
			_bursts.remove_at(i)
	_status_time = maxf(0.0, _status_time - delta)
	_status_label.modulate.a = clampf(_status_time / 0.5, 0.0, 1.0)

# ── HUD ───────────────────────────────────────────────────────────────────────

func _update_hud() -> void:
	var left: float = maxf(0.0, GAME_DURATION - _elapsed)
	_timer_bar.value = left / GAME_DURATION
	var combo: int = int(_combos.get(_my_id, 0))
	_combo_label.text = "COMBO ×%d" % combo if combo >= 2 else ""

func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	_status_time = 1.1
	_status_label.modulate.a = 1.0

func _build_player_order() -> void:
	_player_order = NetworkManager.players.keys()
	_player_order.sort()
	if _player_order.is_empty():
		_player_order = [_my_id]
	for pid in _player_order:
		_scores[pid] = 0
		_combos[pid] = 0

func _build_score_row() -> void:
	for pid in _player_order:
		var color: Color = _color_of(pid)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.09, 0.14, 0.85)
		style.border_color = color
		style.set_border_width_all(3)
		style.set_corner_radius_all(14)
		style.set_content_margin_all(12)

		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(220, 0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", style)
		_score_row.add_child(panel)

		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(vbox)

		var name_label := Label.new()
		name_label.text = _name_of(pid) + (" ★" if pid == _my_id else "")
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", color.lightened(0.45))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_label)

		var score_label := Label.new()
		score_label.add_theme_font_size_override("font_size", 32)
		score_label.add_theme_color_override("font_color", Color("f5e6c8"))
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(score_label)
		_score_labels[pid] = score_label

	_refresh_scores()

func _refresh_scores() -> void:
	for pid in _score_labels:
		var points: int = int(_scores.get(pid, 0))
		_score_labels[pid].text = "%d pt%s" % [points, "s" if points > 1 else ""]

func _color_of(pid: int) -> Color:
	var index: int = _player_order.find(pid)
	if index == -1:
		return CURSOR_COLOR
	return PLAYER_COLORS[index % PLAYER_COLORS.size()]

func _name_of(pid: int) -> String:
	return NetworkManager.players.get(pid, {}).get("name", "Joueur")

# ── Son ───────────────────────────────────────────────────────────────────────

func _setup_sfx() -> void:
	_sfx_hit = _make_sfx("res://Ressources/RafGames/Correct.mp3", 0.0)
	_sfx_miss = _make_sfx("res://Ressources/RafGames/Error.mp3", -3.0)

func _make_sfx(path: String, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.bus = "Master"
	player.volume_db = volume_db
	add_child(player)
	return player

func _play(player: AudioStreamPlayer) -> void:
	if player and player.stream:
		player.play()

func _finish_local_game() -> void:
	if _waiting_results or _game_done:
		return
	_running = false
	_waiting_results = true
	_results_wait_time = 0.0
	_final_retry_in = 0.0
	_host_requery_in = HOST_REQUERY_INTERVAL
	_warning_shown = false
	_combo_label.text = ""
	_timer_bar.value = 0.0
	_zones.clear()
	_reported_score = int(_scores.get(_my_id, 0))
	_register_final_score(_my_id, _reported_score)
	if NetworkManager.is_host:
		_final_score_acknowledged = true
		if not _game_done:
			_set_status("En attente des autres joueurs...", Color("f4a261"))
		return
	_final_score_acknowledged = false
	_send_final_score(false)

func _register_final_score(pid: int, score: int) -> void:
	_final_reports[pid] = score
	_scores[pid] = score
	_refresh_scores()
	if NetworkManager.is_host and not _running and not _game_done and _all_final_scores_received():
		_end_game_host()

func _all_final_scores_received() -> bool:
	for pid in NetworkManager.players.keys():
		if not _final_reports.has(pid):
			return false
	return true

func _process_results_wait(delta: float) -> void:
	_results_wait_time += delta
	if NetworkManager.is_host:
		if _all_final_scores_received():
			_end_game_host()
			return
		_host_requery_in -= delta
		if _host_requery_in <= 0.0:
			_host_requery_in = HOST_REQUERY_INTERVAL
			_request_missing_scores()
		if not _warning_shown and _results_wait_time >= RESULTS_WARNING_TIME:
			_warning_shown = true
			_set_status("Un joueur tarde à répondre...", Color("f4a261"))
		if _results_wait_time >= RESULTS_TIMEOUT:
			_fill_missing_scores_with_default()
			_set_status("Fin forcée : score manquant.", Color("f4a261"))
			_end_game_host()
		return

	if not _final_score_acknowledged:
		_final_retry_in -= delta
		if _final_retry_in <= 0.0:
			_send_final_score(true)
		if not _warning_shown and _results_wait_time >= RESULTS_WARNING_TIME:
			_warning_shown = true
			_set_status("Connexion lente — renvoi du score...", Color("f4a261"))
	else:
		if not _warning_shown and _results_wait_time >= RESULTS_WARNING_TIME:
			_warning_shown = true
			_set_status("Score reçu — attente des autres joueurs...", Color("f4a261"))

	if _results_wait_time >= RESULTS_TIMEOUT:
		_fail_and_leave("L'hôte ne répond plus.")

func _send_final_score(is_retry: bool) -> void:
	if NetworkManager.is_host or _game_done:
		return
	_final_retry_in = FINAL_SCORE_RETRY_INTERVAL
	if is_retry:
		_set_status("Renvoi du score...", Color("f4a261"))
	NetworkManager.send_to_host({
		"action": "cc_final_score",
		"from": _my_id,
		"score": _reported_score,
	})

func _request_missing_scores() -> void:
	for pid in NetworkManager.players.keys():
		if pid == _my_id or _final_reports.has(pid):
			continue
		NetworkManager.send_game_message(pid, {"action": "cc_request_final_score"})

func _fill_missing_scores_with_default() -> void:
	for pid in NetworkManager.players.keys():
		if _final_reports.has(pid):
			continue
		_register_final_score(pid, int(_scores.get(pid, 0)))

func _on_player_list_changed() -> void:
	if _game_done:
		return
	if not NetworkManager.players.has(NetworkManager.HOST_ID):
		_fail_and_leave("L'hôte a quitté la partie.")
		return
	if _waiting_results and NetworkManager.is_host and _all_final_scores_received():
		_end_game_host()

func _on_connection_failed(reason: String) -> void:
	if _game_done:
		return
	_fail_and_leave("Connexion perdue : %s" % reason)

func _fail_and_leave(reason: String) -> void:
	if _fatal_error_active:
		return
	_fatal_error_active = true
	_running = false
	_waiting_results = false
	_set_status(reason, ZONE_TIGHT_COLOR)
	_call_return_after_error()

func _call_return_after_error() -> void:
	_handle_return_after_error.call_deferred()

func _handle_return_after_error() -> void:
	await get_tree().create_timer(ERROR_RETURN_DELAY).timeout
	if get_tree().current_scene != self:
		return
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

# ── Fin de partie ─────────────────────────────────────────────────────────────

func _end_game_host() -> void:
	if _game_done:
		return
	if not _all_final_scores_received():
		return
	_running = false
	_waiting_results = false
	var best_id: int = -1
	var best_score: int = -1
	for pid in _scores:
		if int(_scores[pid]) > best_score:
			best_score = int(_scores[pid])
			best_id = pid
	NetworkManager.send_game_message(0, {"action": "cc_final", "scores": _serialise(_scores)})
	end_game(best_id)

func _on_game_over(winner_peer_id: int) -> void:
	if _game_done:
		return
	_game_done = true
	_running = false
	_zones.clear()
	_refresh_scores()

	var winner_name: String = _name_of(winner_peer_id)
	var winner_score: int = int(_scores.get(winner_peer_id, 0))

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

	var winner_label := Label.new()
	winner_label.text = "🏆 %s — %d point%s" % [
		winner_name, winner_score, "s" if winner_score > 1 else ""
	]
	winner_label.add_theme_font_size_override("font_size", 34)
	winner_label.add_theme_color_override("font_color", Color("f4a261"))
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(winner_label)

	var ranking: Array = _scores.keys()
	ranking.sort_custom(func(a, b): return int(_scores[a]) > int(_scores[b]))
	for rank in range(ranking.size()):
		var pid: int = ranking[rank]
		var points: int = int(_scores.get(pid, 0))
		var rank_label := Label.new()
		rank_label.text = "%d. %s — %d pt%s" % [
			rank + 1, _name_of(pid), points, "s" if points > 1 else ""
		]
		rank_label.add_theme_font_size_override("font_size", 22)
		rank_label.add_theme_color_override("font_color", Color.WHITE)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(rank_label)

	await get_tree().create_timer(5.0).timeout
	get_tree().change_scene_to_file("res://Scenes/Lobby/SelectGames.tscn")
