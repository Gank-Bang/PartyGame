## Mini-jeu : Blind Test
## L'hôte pioche des extraits Deezer via le relais (routes /blindtest/ de server/main.py).
## Chaque joueur a 25 s pour retrouver le titre : il tape, clique une proposition
## puis valide. Le premier qui trouve marque 1 point et tout le monde passe au titre
## suivant ; si personne ne trouve, le titre s'affiche pendant que l'extrait continue.
## L'hôte arbitre les réponses : les titres ne sont diffusés qu'à la révélation.
extends BaseGame

@export var anime_mode: bool = false

enum Phase { SETUP, WAITING, PLAYING, REVEAL, DONE }

const ROUND_COUNT: int = 5
const ROUND_DURATION: float = 20.0
## Laisse passer les réponses envoyées juste avant la fin du chrono (latence du relais).
const GUESS_GRACE: float = 0.5
const REVEAL_FOUND_DURATION: float = 3.0
const REVEAL_MISSED_DURATION: float = 5.0
## Au-delà, l'hôte lance le titre même si un joueur n'a pas fini de charger l'extrait.
const LOAD_TIMEOUT: float = 10.0
const DOWNLOAD_ATTEMPTS: int = 2
const SEARCH_DEBOUNCE: float = 0.3
const SEARCH_MIN_CHARS: int = 2
const END_SCREEN_DURATION: float = 6.0

const NEUTRAL_COLOR: Color = Color("f5e6c8")
const INFO_COLOR: Color = Color("c6e0f8")
const WIN_COLOR: Color = Color("52b788")
const WARN_COLOR: Color = Color("f4a261")
const LOSE_COLOR: Color = Color("e63946")
const REVEAL_COLOR: Color = Color("ffd166")
const SUGGESTION_FACE: Color = Color("24324a")
const SUGGESTION_HOVER: Color = Color("35507a")

const ACCENTS: Dictionary = {
	"à": "a", "á": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "æ": "ae",
	"ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n",
	"ò": "o", "ó": "o", "ô": "o", "ö": "o", "õ": "o", "ø": "o", "œ": "oe",
	"ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y",
}

## Routes HTTP du relais : même hôte que le WebSocket.
var _api_base: String = NetworkManager.RELAY_URL.replace("wss://", "https://").replace("ws://", "http://")

var _my_id: int = 0
var _phase: Phase = Phase.SETUP
var _round: int = -1
var _round_count: int = 0
var _time_left: float = ROUND_DURATION
var _shown_seconds: int = -1
var _guess_pending: bool = false
## peer_id → nombre de titres trouvés
var _scores: Dictionary = {}

## Hôte : pistes {id, title, artist, preview}. Seules les URLs d'extraits sont diffusées.
var _tracks: Array = []
var _setup_msg: Dictionary = {}
var _anime_answers: Array = []
## Hôte : peer_id → dernier titre dont l'extrait est chargé (téléchargés dans l'ordre)
var _loaded_upto: Dictionary = {}
var _host_deadline: float = 0.0

var _previews: Array = []
## Index du titre → AudioStreamMP3
var _streams: Dictionary = {}
var _download_round: int = 0
var _download_attempt: int = 0

var _music: AudioStreamPlayer
var _sfx_correct: AudioStreamPlayer
var _sfx_error: AudioStreamPlayer
var _sfx_tada: AudioStreamPlayer
var _tracks_request: HTTPRequest
var _preview_request: HTTPRequest
var _search_request: HTTPRequest
var _search_timer: Timer
var _suggestion_style: StyleBoxFlat
var _suggestion_hover_style: StyleBoxFlat

@onready var _round_label: Label = %RoundLabel
@onready var _title_label: Label = %TitleLabel
@onready var _state_label: Label = %StateLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _timer_bar: ProgressBar = %TimerBar
@onready var _replay_btn: Control = %ReplayButton
@onready var _pause_btn: Control = %PauseButton
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _answer_edit: LineEdit = %AnswerEdit
@onready var _validate_btn: Control = %ValidateButton
@onready var _suggestions_scroll: ScrollContainer = %SuggestionsScroll
@onready var _suggestions_list: VBoxContainer = %SuggestionsList
@onready var _scores_list: VBoxContainer = %ScoresList

# ── Surcharge BaseGame ────────────────────────────────────────────────────────

func _spawn_players() -> void:
	pass

func _on_game_ready() -> void:
	_my_id = NetworkManager.local_peer_id()
	_title_label.text = "Blind Test Anime" if anime_mode else "Blind Test"
	_answer_edit.placeholder_text = "Tape le nom de l'anime..." if anime_mode else "Tape le titre de la musique..."
	for pid in NetworkManager.players.keys():
		_scores[pid] = 0
	_setup_nodes()
	_refresh_scores()
	_refresh_timer()
	_refresh_controls()
	if NetworkManager.is_host:
		_set_state("Sélection des animes sur Deezer..." if anime_mode else "Sélection des musiques sur Deezer...", INFO_COLOR)
		var endpoint: String = "/blindtest/anime/tracks" if anime_mode else "/blindtest/tracks"
		if _tracks_request.request("%s%s?count=%d" % [_api_base, endpoint, ROUND_COUNT]) != OK:
			_on_tracks_loaded(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	else:
		_set_state("L'hôte prépare la playlist...", INFO_COLOR)
		# Rattrape un bt_setup diffusé avant que cette scène soit chargée.
		NetworkManager.send_to_host({"action": "bt_hello"})

func _process(delta: float) -> void:
	if _phase == Phase.PLAYING:
		_time_left = maxf(_time_left - delta, 0.0)
		_refresh_timer()
	if NetworkManager.is_host:
		_host_tick()

func _setup_nodes() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.finished.connect(_refresh_controls)
	add_child(_music)
	_sfx_correct = _add_sfx("res://Ressources/RafGames/Correct.mp3")
	_sfx_error = _add_sfx("res://Ressources/RafGames/Error.mp3")
	_sfx_tada = _add_sfx("res://Ressources/RafGames/Tada.mp3")

	_tracks_request = _add_request(20.0, _on_tracks_loaded)
	_preview_request = _add_request(20.0, _on_preview_loaded)
	_search_request = _add_request(8.0, _on_search_loaded)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DEBOUNCE
	_search_timer.timeout.connect(_run_search)
	add_child(_search_timer)

	_suggestion_style = _make_suggestion_style(SUGGESTION_FACE)
	_suggestion_hover_style = _make_suggestion_style(SUGGESTION_HOVER)
	_timer_bar.max_value = ROUND_DURATION

	_replay_btn.pressed.connect(_on_replay_pressed)
	_pause_btn.pressed.connect(_on_pause_pressed)
	_validate_btn.pressed.connect(_submit_answer)
	_answer_edit.text_changed.connect(_on_answer_changed)
	_answer_edit.text_submitted.connect(func(_text: String) -> void: _submit_answer())

func _add_sfx(path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.bus = "Master"
	add_child(player)
	return player

func _add_request(timeout: float, on_completed: Callable) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = timeout
	request.request_completed.connect(on_completed)
	add_child(request)
	return request

func _make_suggestion_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	return style

# ── Réseau ────────────────────────────────────────────────────────────────────

func _on_custom_message(from_id: int, data: Dictionary) -> void:
	match str(data.get("action", "")):
		"bt_hello":
			if NetworkManager.is_host and not _setup_msg.is_empty():
				NetworkManager.send_game_message(from_id, _setup_msg)
		"bt_setup":
			_apply_setup(data)
		"bt_loaded":
			if NetworkManager.is_host:
				_loaded_upto[from_id] = maxi(int(_loaded_upto.get(from_id, -1)), int(data.get("round", -1)))
		"bt_round_start":
			_apply_round_start(data)
		"bt_guess":
			if NetworkManager.is_host:
				_host_check_guess(from_id, int(data.get("round", -1)), str(data.get("guess", data.get("title", ""))))
		"bt_wrong":
			_apply_wrong_guess(int(data.get("round", -1)))
		"bt_round_end":
			_apply_round_end(data)

# ── Hôte : déroulé de la partie ───────────────────────────────────────────────

func _on_tracks_loaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var tracks: Array = []
	var answer_options: Variant = []
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary:
			answer_options = parsed.get("answers", [])
			for track in parsed.get("tracks", []):
				if track is Dictionary and not str(track.get("preview", "")).is_empty():
					tracks.append(track)
	if tracks.is_empty():
		var item_name: String = "animes" if anime_mode else "musiques"
		_set_state("Impossible de récupérer des %s sur Deezer (code %d). Quitte et réessaie." % [item_name, response_code], LOSE_COLOR)
		return

	_tracks = tracks
	var previews: Array = []
	for track in tracks:
		previews.append(str(track["preview"]))
	_setup_msg = {"action": "bt_setup", "previews": previews}
	if anime_mode and answer_options is Array:
		_setup_msg["answers"] = answer_options
	NetworkManager.send_game_message(0, _setup_msg)
	_apply_setup(_setup_msg)
	_host_prepare_round(0)

func _host_tick() -> void:
	match _phase:
		Phase.WAITING:
			if _round >= 0 and (_everyone_loaded(_round) or _now() >= _host_deadline):
				_host_start_round()
		Phase.PLAYING:
			if _now() >= _host_deadline:
				_host_end_round(-1)
		Phase.REVEAL:
			if _now() >= _host_deadline:
				if _round + 1 < _tracks.size():
					_host_prepare_round(_round + 1)
				else:
					_host_finish()

func _host_prepare_round(round_idx: int) -> void:
	_round = round_idx
	_phase = Phase.WAITING
	_host_deadline = _now() + LOAD_TIMEOUT
	if not _everyone_loaded(round_idx):
		_set_state("Chargement de l'extrait chez tout le monde...", INFO_COLOR)

func _everyone_loaded(round_idx: int) -> bool:
	for pid in NetworkManager.players.keys():
		if int(_loaded_upto.get(pid, -1)) < round_idx:
			return false
	return true

func _host_start_round() -> void:
	var msg := {"action": "bt_round_start", "round": _round}
	NetworkManager.send_game_message(0, msg)
	_apply_round_start(msg)
	_host_deadline = _now() + ROUND_DURATION + GUESS_GRACE

func _host_check_guess(pid: int, round_idx: int, guess: String) -> void:
	if _phase != Phase.PLAYING or round_idx != _round:
		return
	var track: Dictionary = _tracks[_round]
	var is_correct: bool = _anime_guess_matches(guess, track) if anime_mode else _normalise_title(guess) == _normalise_title(str(track.get("title", "")))
	if is_correct:
		_host_end_round(pid)
	elif pid == _my_id:
		_apply_wrong_guess(round_idx)
	else:
		NetworkManager.send_game_message(pid, {"action": "bt_wrong", "round": round_idx})

func _host_end_round(winner: int) -> void:
	if winner != -1:
		_scores[winner] = int(_scores.get(winner, 0)) + 1
	var track: Dictionary = _tracks[_round]
	var msg := {
		"action": "bt_round_end",
		"round": _round,
		"winner": winner,
		"title": str(track.get("title", "")),
		"artist": str(track.get("artist", "")),
		"anime": str(track.get("anime", "")),
		"scores": _scores.duplicate(),
	}
	NetworkManager.send_game_message(0, msg)
	_apply_round_end(msg)
	_host_deadline = _now() + (REVEAL_MISSED_DURATION if winner == -1 else REVEAL_FOUND_DURATION)

func _host_finish() -> void:
	_phase = Phase.DONE
	var best_score: int = 0
	var best_ids: Array = []
	for pid in _scores:
		var score: int = int(_scores[pid])
		if score > best_score:
			best_score = score
			best_ids = [pid]
		elif score == best_score and score > 0:
			best_ids.append(pid)
	end_game(best_ids[0] if best_ids.size() == 1 else -1)

# ── Tous : application des messages ───────────────────────────────────────────

func _apply_setup(data: Dictionary) -> void:
	if not _previews.is_empty():
		return
	_previews = data.get("previews", [])
	_round_count = _previews.size()
	_round_label.text = "%d extraits" % _round_count if anime_mode else "%d titres" % _round_count
	var answer_options: Variant = data.get("answers", [])
	if anime_mode and answer_options is Array:
		_anime_answers = answer_options
	if _phase == Phase.SETUP:
		_phase = Phase.WAITING
	_set_state("Chargement des extraits...", INFO_COLOR)
	_request_preview()

func _apply_round_start(data: Dictionary) -> void:
	_round = int(data.get("round", 0))
	_phase = Phase.PLAYING
	_time_left = ROUND_DURATION
	_guess_pending = false
	var round_name: String = "Extrait" if anime_mode else "Titre"
	_round_label.text = "%s %d/%d" % [round_name, _round + 1, _round_count]
	_answer_edit.text = ""
	_clear_suggestions()
	_set_feedback("", NEUTRAL_COLOR)
	_play_round_audio()
	_refresh_timer()
	_refresh_controls()
	_answer_edit.grab_focus()

func _apply_wrong_guess(round_idx: int) -> void:
	if _phase != Phase.PLAYING or round_idx != _round:
		return
	_guess_pending = false
	_sfx_error.play()
	_set_feedback("Mauvaise réponse, essaie encore !", LOSE_COLOR)
	_answer_edit.text = ""
	_refresh_controls()
	_answer_edit.grab_focus()

func _apply_round_end(data: Dictionary) -> void:
	_round = int(data.get("round", _round))
	_phase = Phase.REVEAL
	_guess_pending = false
	_search_timer.stop()
	_search_request.cancel_request()
	_clear_suggestions()
	_answer_edit.release_focus()
	var raw_scores: Dictionary = data.get("scores", {})
	for key in raw_scores:
		_scores[int(key)] = int(raw_scores[key])
	_refresh_scores()

	var winner: int = int(data.get("winner", -1))
	var answer: String
	if anime_mode:
		answer = "l'anime « %s »" % str(data.get("anime", "?"))
		var song_title: String = str(data.get("title", ""))
		if not song_title.is_empty():
			answer += " - « %s »" % song_title
			var artist: String = str(data.get("artist", ""))
			if not artist.is_empty():
				answer += " par %s" % artist
	else:
		answer = "« %s » de %s" % [str(data.get("title", "?")), str(data.get("artist", "?"))]
	if winner == _my_id:
		_sfx_tada.play()
		_set_feedback("Bravo ! C'était %s" % answer, WIN_COLOR)
	elif winner != -1:
		_sfx_correct.play()
		_set_feedback("%s a trouvé : %s" % [_player_name(winner), answer], WARN_COLOR)
	else:
		_set_feedback("Personne n'a trouvé... C'était %s" % answer, REVEAL_COLOR)
		_keep_music_playing()
	if _round + 1 < _round_count:
		_set_state("Titre suivant dans un instant...", INFO_COLOR)
	else:
		_set_state("C'était le dernier titre !", INFO_COLOR)
	_refresh_controls()

# ── Extraits audio ────────────────────────────────────────────────────────────

func _request_preview() -> void:
	if _download_round >= _previews.size():
		return
	_download_attempt += 1
	if _preview_request.request(str(_previews[_download_round])) != OK:
		_on_preview_loaded(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func _on_preview_loaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var stream: AudioStreamMP3 = null
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		stream = AudioStreamMP3.load_from_buffer(body)
	var ok: bool = stream != null and stream.get_length() > 0.0
	if not ok and _download_attempt < DOWNLOAD_ATTEMPTS:
		_request_preview()
		return

	var loaded_round: int = _download_round
	if ok:
		_streams[loaded_round] = stream
	else:
		push_warning("BlindTest : extrait %d indisponible (résultat %d, code %d)" % [loaded_round, result, response_code])
	_download_round += 1
	_download_attempt = 0
	if NetworkManager.is_host:
		_loaded_upto[_my_id] = loaded_round
	else:
		NetworkManager.send_to_host({"action": "bt_loaded", "round": loaded_round})
	if _phase == Phase.PLAYING and loaded_round == _round:
		_play_round_audio()
	_request_preview()

func _play_round_audio() -> void:
	var stream: AudioStreamMP3 = _streams.get(_round)
	_music.stream = stream
	if stream != null:
		_music.play()
		_set_state("Écoute bien et trouve l'anime !" if anime_mode else "Écoute bien et trouve le titre !", INFO_COLOR)
	elif _download_round <= _round:
		_set_state("Chargement de l'extrait...", WARN_COLOR)
	else:
		_set_state("Extrait indisponible chez toi, tente ta chance quand même !", WARN_COLOR)
	_refresh_controls()

## Personne n'a trouvé : l'extrait continue (ou reprend sur sa fin) pendant la révélation.
func _keep_music_playing() -> void:
	if _music.stream == null:
		return
	if _music.stream_paused:
		_music.stream_paused = false
	elif not _music.playing:
		_music.play(maxf(_music.stream.get_length() - REVEAL_MISSED_DURATION, 0.0))

func _on_replay_pressed() -> void:
	if _music.stream == null:
		return
	_music.play()
	_refresh_controls()

func _on_pause_pressed() -> void:
	if _music.stream == null:
		return
	if _music.playing:
		_music.stream_paused = true
	elif _music.stream_paused:
		_music.stream_paused = false
	else:
		_music.play()
	_refresh_controls()

# ── Réponse et propositions ───────────────────────────────────────────────────

func _on_answer_changed(_new_text: String) -> void:
	_search_timer.start()

func _run_search() -> void:
	_search_request.cancel_request()
	var query: String = _answer_edit.text.strip_edges()
	if _phase != Phase.PLAYING or query.length() < SEARCH_MIN_CHARS:
		_clear_suggestions()
		return
	if anime_mode:
		var query_key: String = _normalise_title(query)
		var matches: Array = []
		for option in _anime_answers:
			if not option is Dictionary:
				continue
			var answer_title: String = str(option.get("title", ""))
			var aliases: Variant = option.get("aliases", [answer_title])
			var matched: bool = false
			if aliases is Array:
				for alias in aliases:
					if _normalise_title(str(alias)).contains(query_key):
						matched = true
						break
			if matched:
				matches.append({"title": answer_title})
		_show_suggestions(matches)
		return
	_search_request.request("%s/blindtest/search?q=%s" % [_api_base, query.uri_encode()])

func _on_search_loaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# Le joueur tape encore : une recherche plus récente va partir.
	if _phase != Phase.PLAYING or not _search_timer.is_stopped():
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		_show_suggestions(parsed.get("results", []))

func _show_suggestions(results: Array) -> void:
	_clear_suggestions()
	for item in results:
		if not item is Dictionary or str(item.get("title", "")).is_empty():
			continue
		var title: String = str(item["title"])
		var btn := Button.new()
		btn.text = title if anime_mode else "%s — %s" % [title, str(item.get("artist", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.custom_minimum_size = Vector2(0, 48)
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_theme_color_override("font_color", NEUTRAL_COLOR)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		btn.add_theme_stylebox_override("normal", _suggestion_style)
		btn.add_theme_stylebox_override("hover", _suggestion_hover_style)
		btn.add_theme_stylebox_override("pressed", _suggestion_hover_style)
		btn.pressed.connect(_on_suggestion_pressed.bind(title))
		_suggestions_list.add_child(btn)
	_suggestions_scroll.visible = _suggestions_list.get_child_count() > 0
	_suggestions_scroll.scroll_vertical = 0

func _on_suggestion_pressed(title: String) -> void:
	if _phase != Phase.PLAYING:
		return
	_search_timer.stop()
	_search_request.cancel_request()
	_answer_edit.text = title
	_answer_edit.caret_column = title.length()
	# Différé : on est dans le signal du bouton qui va être supprimé.
	_clear_suggestions.call_deferred()

func _clear_suggestions() -> void:
	for child in _suggestions_list.get_children():
		_suggestions_list.remove_child(child)
		child.queue_free()
	_suggestions_scroll.visible = false

func _submit_answer() -> void:
	if _phase != Phase.PLAYING or _guess_pending or _time_left <= 0.0:
		return
	var guess: String = _answer_edit.text.strip_edges()
	if guess.is_empty():
		_set_feedback("Tape un titre ou choisis une proposition.", WARN_COLOR)
		return
	_guess_pending = true
	_search_timer.stop()
	_search_request.cancel_request()
	_clear_suggestions()
	_refresh_controls()
	if NetworkManager.is_host:
		_host_check_guess(_my_id, _round, guess)
	else:
		NetworkManager.send_to_host({"action": "bt_guess", "round": _round, "guess": guess})

## Titre comparable : minuscules, sans accents, sans « (feat. …) », « [Live] »,
## « - Remastered » ni ponctuation.
func _normalise_title(raw: String) -> String:
	var text: String = raw.to_lower()
	var dash: int = text.find(" - ")
	if dash > 0:
		text = text.left(dash)
	var out: String = ""
	var depth: int = 0
	for ch in text:
		if ch == "(" or ch == "[":
			depth += 1
		elif ch == ")" or ch == "]":
			depth = maxi(depth - 1, 0)
		elif depth == 0:
			var plain: String = ACCENTS.get(ch, ch)
			if (plain >= "a" and plain <= "z") or (plain >= "0" and plain <= "9"):
				out += plain
	return out if not out.is_empty() else raw.strip_edges().to_lower()

func _anime_guess_matches(guess: String, track: Dictionary) -> bool:
	var guess_key: String = _normalise_title(guess)
	var aliases: Variant = track.get("anime_aliases", [track.get("anime", "")])
	if not aliases is Array:
		return false
	for alias in aliases:
		if _normalise_title(str(alias)) == guess_key:
			return true
	return false

# ── Affichage ─────────────────────────────────────────────────────────────────

func _refresh_timer() -> void:
	_timer_bar.value = _time_left
	var seconds: int = ceili(_time_left)
	if seconds == _shown_seconds:
		return
	_shown_seconds = seconds
	_timer_label.text = str(seconds)
	_timer_label.add_theme_color_override("font_color", LOSE_COLOR if seconds <= 5 else NEUTRAL_COLOR)
	if seconds == 0:
		_refresh_controls()

func _refresh_controls() -> void:
	var can_answer: bool = _phase == Phase.PLAYING and _time_left > 0.0
	_answer_edit.editable = can_answer
	_set_button_enabled(_validate_btn, can_answer and not _guess_pending)
	var has_audio: bool = _music.stream != null and (_phase == Phase.PLAYING or _phase == Phase.REVEAL)
	_set_button_enabled(_replay_btn, has_audio)
	_set_button_enabled(_pause_btn, has_audio)
	_pause_btn.text = "Pause" if _music.playing else "Lecture"

func _set_button_enabled(btn: Control, enabled: bool) -> void:
	btn.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	btn.modulate.a = 1.0 if enabled else 0.4

func _refresh_scores() -> void:
	for child in _scores_list.get_children():
		_scores_list.remove_child(child)
		child.queue_free()
	for pid in _ranked_player_ids():
		var prefix: String = "★ " if pid == _my_id else ""
		var line: String = "%s%s — %d" % [prefix, _player_name(pid), int(_scores[pid])]
		_scores_list.add_child(_make_label(line, 24, Color("f6e8ca")))

func _ranked_player_ids() -> Array:
	var ids: Array = _scores.keys()
	ids.sort_custom(func(a, b) -> bool:
		var score_a: int = int(_scores[a])
		var score_b: int = int(_scores[b])
		return score_a > score_b or (score_a == score_b and int(a) < int(b))
	)
	return ids

func _player_name(pid: int) -> String:
	return str(NetworkManager.players.get(pid, {}).get("name", "Joueur"))

func _set_state(message: String, color: Color) -> void:
	_state_label.text = message
	_state_label.add_theme_color_override("font_color", color)

func _set_feedback(message: String, color: Color) -> void:
	_feedback_label.text = message
	_feedback_label.add_theme_color_override("font_color", color)

func _make_label(text: String, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ── Fin de partie ─────────────────────────────────────────────────────────────

func _on_game_over(winner_peer_id: int) -> void:
	_phase = Phase.DONE
	_music.stop()
	_search_timer.stop()
	_search_request.cancel_request()
	_clear_suggestions()
	_refresh_controls()

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.07, 0.82)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.15, 0.23, 0.98)
	style.set_corner_radius_all(20)
	style.set_border_width_all(2)
	style.border_color = Color(0.41, 0.57, 0.77, 1)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var end_title: String = "Fin du Blind Test Anime !" if anime_mode else "Fin du Blind Test !"
	vbox.add_child(_make_label(end_title, 44, NEUTRAL_COLOR, HORIZONTAL_ALIGNMENT_CENTER))
	vbox.add_child(_make_label(_winner_text(winner_peer_id), 28, REVEAL_COLOR, HORIZONTAL_ALIGNMENT_CENTER))
	var rank: int = 1
	for pid in _ranked_player_ids():
		var line: String = "%d. %s — %d" % [rank, _player_name(pid), int(_scores[pid])]
		vbox.add_child(_make_label(line, 24, Color("dff3e3"), HORIZONTAL_ALIGNMENT_CENTER))
		rank += 1

	await get_tree().create_timer(END_SCREEN_DURATION).timeout
	get_tree().change_scene_to_file("res://Scenes/Lobby/SelectGames.tscn")

func _winner_text(winner_peer_id: int) -> String:
	if winner_peer_id != -1:
		var score: int = int(_scores.get(winner_peer_id, 0))
		if anime_mode:
			return "%s gagne avec %d bonne%s réponse%s !" % [_player_name(winner_peer_id), score, "s" if score > 1 else "", "s" if score > 1 else ""]
		return "%s gagne avec %d titre%s !" % [_player_name(winner_peer_id), score, "s" if score > 1 else ""]
	var best: int = 0
	for pid in _scores:
		best = maxi(best, int(_scores[pid]))
	if best == 0:
		return "Personne n'a trouvé le bon anime." if anime_mode else "Personne n'a trouvé de titre."
	var names: PackedStringArray = []
	for pid in _ranked_player_ids():
		if int(_scores[pid]) == best:
			names.append(_player_name(pid))
	return "Égalité entre %s !" % " et ".join(names)
