## Mini-jeu : Motus — devine le mot caché !
## La grille et le clavier sont des nœuds de MotusMiniGame.tscn, modifiables dans
## l'éditeur : les cases sont les enfants de Grid (lues de gauche à droite, ligne
## par ligne) et les touches sont nommées Key<Lettre>, KeyEnter et KeyDel.
## Vert = bonne lettre au bon endroit, jaune = lettre présente ailleurs, rien sinon.
## Le premier joueur qui trouve le mot remporte la partie.
extends BaseGame

# ── Constantes ────────────────────────────────────────────────────────────────

const WORDS_PATH: String = "res://Ressources/RafGames/mots.json"
const TARGET_WORDS_PATH: String = "res://Ressources/RafGames/MotsDevinables.json"

const STATE_ABSENT: int  = 0
const STATE_PRESENT: int = 1
const STATE_CORRECT: int = 2

const REVEAL_APPEAR_TIME: float = 0.22   # durée du punch-in d'une case
const REVEAL_GAP: float         = 0.06   # pause entre deux cases
## Laisse le temps à la dernière ligne de se révéler avant l'écran de fin.
const END_DELAY: float          = 2.0

const TYPED_FACE:   Color = Color("415a86")
const TYPED_SHADOW: Color = Color("24334f")
const CORRECT_FACE:   Color = Color("52b788")
const CORRECT_SHADOW: Color = Color("1b5e20")
const PRESENT_FACE:   Color = Color("e9c46a")
const PRESENT_SHADOW: Color = Color("b5860d")
const ABSENT_FACE:   Color = Color("343b4a")
const ABSENT_SHADOW: Color = Color("1e232d")

const NEUTRAL_COLOR: Color = Color("f5e6c8")
const WARN_COLOR:    Color = Color("f4a261")
const WIN_COLOR:     Color = Color("52b788")
const LOSE_COLOR:    Color = Color("e63946")

const MOBILE_WEB_MAX_SIDE: float = 950.0
const MOBILE_WEB_MAX_HEIGHT: float = 760.0
const MOBILE_WEB_BOTTOM_PAD: float = 74.0

## Lettres accentuées présentes dans mots.json → équivalent sans accent.
const ACCENTS: Dictionary = {
	"à": "a", "â": "a", "ç": "c",
	"è": "e", "é": "e", "ê": "e", "ë": "e",
	"î": "i", "ï": "i", "ô": "o", "û": "u",
}

# ── État du jeu ───────────────────────────────────────────────────────────────

var _my_id: int = 0
var _target: String = ""
## Mots normalisés (majuscules, sans accents) tirables par l'hôte
var _words: Array = []
var _target_words: Array = []
## Mot normalisé → true, pour valider les tentatives
var _word_set: Dictionary = {}

## Cases de la grille, déduites de la scène
var _tiles: Array = []
var _word_length: int = 5
var _max_attempts: int = 7
var _tile_face: Color = Color("2b3a55")
var _tile_shadow: Color = Color("18223a")

var _current_row: int = 0
var _current_guess: String = ""
var _input_locked: bool = true
var _game_done: bool = false
## Hôte : résultat déjà arbitré, en attente de l'écran de fin
var _result_pending: bool = false

## Identifiant de touche (A-Z, ENTER, DEL) → bouton du clavier
var _key_buttons: Dictionary = {}
## Lettres déjà tentées et absentes du mot
var _dead_letters: Dictionary = {}

var _sfx_correct: AudioStreamPlayer
var _sfx_error: AudioStreamPlayer
var _sfx_tada: AudioStreamPlayer

## peer_id → nombre d'essais utilisés
var _attempts: Dictionary = {}
var _solved: Array = []
var _out: Array = []
var _responsive_game_area: HBoxContainer

# ── Nœuds ─────────────────────────────────────────────────────────────────────

@onready var _status_area:  HBoxContainer = $CanvasLayer/UI/MainVBox/Header/StatusArea
@onready var _main_vbox:    VBoxContainer = $CanvasLayer/UI/MainVBox
@onready var _header:       HBoxContainer = $CanvasLayer/UI/MainVBox/Header
@onready var _grid_center:  CenterContainer = $CanvasLayer/UI/MainVBox/GridCenter
@onready var _grid:         GridContainer = $CanvasLayer/UI/MainVBox/GridCenter/Grid
@onready var _feedback_lbl: Label         = $CanvasLayer/UI/MainVBox/FeedbackLabel
@onready var _keyboard_center: CenterContainer = $CanvasLayer/UI/MainVBox/KeyboardCenter
@onready var _keyboard:     VBoxContainer = $CanvasLayer/UI/MainVBox/KeyboardCenter/Keyboard
@onready var _canvas_layer: CanvasLayer   = $CanvasLayer
@onready var _kb_rows: Array = [
	$CanvasLayer/UI/MainVBox/KeyboardCenter/Keyboard/Row1,
	$CanvasLayer/UI/MainVBox/KeyboardCenter/Keyboard/Row2,
	$CanvasLayer/UI/MainVBox/KeyboardCenter/Keyboard/Row3,
]

# ── Surcharge BaseGame ────────────────────────────────────────────────────────

## Pas de CharacterBody2D — tout est UI.
func _spawn_players() -> void:
	pass

func _on_game_ready() -> void:
	_my_id = NetworkManager.local_peer_id()
	_setup_sfx()
	_read_grid()
	_connect_keyboard()
	_load_words()
	_build_status_area()
	_set_feedback("En attente du mot...", NEUTRAL_COLOR)
	if not get_viewport().size_changed.is_connected(_apply_responsive_layout):
		get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	if NetworkManager.is_host:
		_start_game_host()

# ── Son ──────────────────────────────────────────────────────────────────

func _setup_sfx() -> void:
	_sfx_correct = AudioStreamPlayer.new()
	_sfx_correct.stream = load("res://Ressources/RafGames/Correct.mp3")
	_sfx_correct.bus = "Master"
	add_child(_sfx_correct)
	_sfx_error = AudioStreamPlayer.new()
	_sfx_error.stream = load("res://Ressources/RafGames/Error.mp3")
	_sfx_error.bus = "Master"
	add_child(_sfx_error)
	_sfx_tada = AudioStreamPlayer.new()
	_sfx_tada.stream = load("res://Ressources/RafGames/Tada.mp3")
	_sfx_tada.bus = "Master"
	add_child(_sfx_tada)

# ── Dictionnaire ──────────────────────────────────────────────────────────────

func _load_words() -> void:
	_words = _read_word_list(WORDS_PATH)
	for word in _words:
		_word_set[word] = true
	_target_words = _read_word_list(TARGET_WORDS_PATH)

func _read_word_list(path: String) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MotusMiniGame : impossible d'ouvrir %s" % path)
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_ARRAY:
		push_error("MotusMiniGame : %s n'est pas une liste JSON" % path)
		return result
	for raw in parsed:
		var word: String = _normalise(str(raw))
		if word.length() != _word_length or seen.has(word):
			continue
		result.append(word)
		seen[word] = true
	return result

## Retire les accents et passe en majuscules ; renvoie "" si le mot contient
## un caractère hors A-Z (apostrophe, trait d'union, etc.).
func _normalise(word: String) -> String:
	var out := ""
	for i in range(word.length()):
		var ch: String = ACCENTS.get(word[i].to_lower(), word[i].to_lower())
		if ch < "a" or ch > "z":
			return ""
		out += ch
	return out.to_upper()

# ── Lecture de l'UI définie dans la scène ─────────────────────────────────────

## La taille du mot et le nombre d'essais suivent la grille dessinée dans la scène.
func _read_grid() -> void:
	_tiles = _grid.get_children()
	_word_length  = maxi(_grid.columns, 1)
	_max_attempts = maxi(floori(float(_tiles.size()) / float(_word_length)), 1)
	if not _tiles.is_empty():
		_tile_face   = _tiles[0].face_color
		_tile_shadow = _tiles[0].shadow_color

func _connect_keyboard() -> void:
	for row in _kb_rows:
		for child in row.get_children():
			var key: String = str(child.name).trim_prefix("Key").to_upper()
			_key_buttons[key] = child
			child.pressed.connect(_on_key_pressed.bind(key))
	_set_input_locked(true)

func _apply_responsive_layout() -> void:
	var viewport: Vector2 = get_viewport_rect().size
	var compact: bool = _use_compact_web_layout(viewport)
	var split: bool = compact and viewport.x > viewport.y
	var side_margin: float = 14.0 if compact else 32.0
	_main_vbox.offset_left = side_margin
	_main_vbox.offset_top = 12.0 if compact else 20.0
	_main_vbox.offset_right = -side_margin
	_main_vbox.offset_bottom = -MOBILE_WEB_BOTTOM_PAD if compact else -20.0
	_main_vbox.add_theme_constant_override("separation", 8 if compact else 12)
	_header.custom_minimum_size.y = 48.0 if compact else 60.0
	_status_area.add_theme_constant_override("separation", 16 if compact else 28)
	_feedback_lbl.add_theme_font_size_override("font_size", 20 if compact else 24)
	for child in _status_area.get_children():
		if child is Label:
			(child as Label).add_theme_font_size_override("font_size", 18 if compact else 22)

	_set_keyboard_layout(split)

	var grid_sep: int = 6 if compact else 10
	_grid.add_theme_constant_override("h_separation", grid_sep)
	_grid.add_theme_constant_override("v_separation", grid_sep)

	if split:
		_apply_split_sizes(viewport, side_margin, grid_sep)
	else:
		_apply_stacked_sizes(viewport, side_margin, grid_sep, compact)

func _use_compact_web_layout(viewport: Vector2) -> bool:
	return OS.has_feature("web") and (
		minf(viewport.x, viewport.y) <= MOBILE_WEB_MAX_SIDE or viewport.y <= MOBILE_WEB_MAX_HEIGHT
	)

func _set_keyboard_layout(split: bool) -> void:
	if split:
		if _responsive_game_area == null:
			_responsive_game_area = HBoxContainer.new()
			_responsive_game_area.name = "ResponsiveGameArea"
			_responsive_game_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_responsive_game_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_responsive_game_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_responsive_game_area.alignment = BoxContainer.ALIGNMENT_CENTER
		_responsive_game_area.add_theme_constant_override("separation", 18)
		if _responsive_game_area.get_parent() == null:
			_main_vbox.add_child(_responsive_game_area)
		_reparent_control(_grid_center, _responsive_game_area)
		_reparent_control(_keyboard_center, _responsive_game_area)
		_responsive_game_area.move_child(_grid_center, 0)
		_responsive_game_area.move_child(_keyboard_center, 1)
		_main_vbox.move_child(_feedback_lbl, 1)
		_main_vbox.move_child(_responsive_game_area, 2)
		_grid_center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_keyboard_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_keyboard_center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return

	if _responsive_game_area != null and _responsive_game_area.get_parent() == _main_vbox:
		_reparent_control(_grid_center, _main_vbox)
		_reparent_control(_keyboard_center, _main_vbox)
		_main_vbox.move_child(_grid_center, 1)
		_main_vbox.move_child(_feedback_lbl, 2)
		_main_vbox.move_child(_keyboard_center, 3)
		_main_vbox.remove_child(_responsive_game_area)
	_grid_center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_keyboard_center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_keyboard_center.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _reparent_control(node: Control, new_parent: Node) -> void:
	if node.get_parent() == new_parent:
		return
	var old_parent: Node = node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	new_parent.add_child(node)

func _apply_split_sizes(viewport: Vector2, side_margin: float, grid_sep: int) -> void:
	var grid_width_budget: float = clampf(viewport.x * 0.32, 220.0, 380.0)
	var tile_size: float = clampf(minf(
		(grid_width_budget - grid_sep * float(_word_length - 1)) / float(_word_length),
		(viewport.y - 110.0 - grid_sep * float(_max_attempts - 1)) / float(_max_attempts)
	), 40.0, 72.0)
	var keyboard_width: float = maxf(320.0, viewport.x - side_margin * 2.0 - grid_width_budget - 18.0)
	var key_sep: int = 6
	var letter_w: float = clampf((keyboard_width - key_sep * 9.0) / 10.0, 44.0, 82.0)
	var key_h: float = clampf(minf(viewport.y * 0.15, letter_w * 1.12), 54.0, 82.0)
	_apply_tile_sizes(tile_size, int(round(tile_size * 0.58)))
	_apply_keyboard_sizes(letter_w, key_h, key_sep)

func _apply_stacked_sizes(viewport: Vector2, side_margin: float, grid_sep: int, compact: bool) -> void:
	var tile_size: float = clampf(minf(
		(viewport.x - side_margin * 2.0 - grid_sep * float(_word_length - 1)) / float(_word_length),
		(viewport.y * (0.42 if compact else 0.54) - grid_sep * float(_max_attempts - 1)) / float(_max_attempts)
	), 40.0, 80.0)
	var key_sep: int = 4 if compact else 8
	var letter_w: float = clampf(
		(viewport.x - side_margin * 2.0 - key_sep * 9.0) / 10.0,
		36.0 if compact else 72.0,
		72.0,
	)
	var key_h: float = clampf(
		minf(viewport.y * (0.095 if compact else 0.11), letter_w * 1.05),
		42.0 if compact else 66.0,
		72.0,
	)
	_apply_tile_sizes(tile_size, int(round(tile_size * 0.58)))
	_apply_keyboard_sizes(letter_w, key_h, key_sep)

func _apply_tile_sizes(tile_size: float, font_size: int) -> void:
	for tile in _tiles:
		tile.custom_minimum_size = Vector2(tile_size, tile_size)
		tile.set("font_size", font_size)

func _apply_keyboard_sizes(letter_w: float, key_h: float, separation: int) -> void:
	_keyboard.add_theme_constant_override("separation", separation)
	for row in _kb_rows:
		row.add_theme_constant_override("separation", separation)
	for key in _key_buttons:
		var btn = _key_buttons[key]
		var special: bool = key in ["ENTER", "DEL"]
		btn.custom_minimum_size = Vector2(
			letter_w * (1.55 if special else 1.0),
			key_h,
		)
		btn.set("font_size", int(round(key_h * (0.34 if special else 0.48))))

func _build_status_area() -> void:
	for pid in NetworkManager.players.keys():
		_attempts[pid] = 0
		var lbl := Label.new()
		lbl.name = "P_%d" % pid
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", NEUTRAL_COLOR)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_status_area.add_child(lbl)
		_update_status(pid)

func _update_status(pid: int) -> void:
	var lbl: Label = _status_area.get_node_or_null("P_%d" % pid)
	if lbl == null:
		return
	var pname: String = NetworkManager.players.get(pid, {}).get("name", "?")
	var col: Color = NEUTRAL_COLOR
	var suffix := ""
	if pid in _solved:
		col = WIN_COLOR
		suffix = " ✓"
	elif pid in _out:
		col = LOSE_COLOR
		suffix = " ✗"
	lbl.text = "%s%s  %d/%d%s" % [
		"★ " if pid == _my_id else "", pname, _attempts.get(pid, 0), _max_attempts, suffix
	]
	lbl.add_theme_color_override("font_color", col)

# ── Démarrage de la partie ────────────────────────────────────────────────────

func _start_game_host() -> void:
	if _target_words.is_empty():
		push_error("MotusMiniGame : aucun mot tirable de %d lettres disponible" % _word_length)
		return
	var msg: Dictionary = {"action": "motus_start", "word": _target_words[randi() % _target_words.size()]}
	NetworkManager.send_game_message(0, msg)
	_setup_game(msg)

func _setup_game(data: Dictionary) -> void:
	_target        = str(data.get("word", ""))
	_current_row   = 0
	_current_guess = ""
	_game_done     = false
	_set_input_locked(false)
	_set_feedback("Trouvez le mot en %d essais !" % _max_attempts, NEUTRAL_COLOR)

# ── Saisie ────────────────────────────────────────────────────────────────────

func _on_key_pressed(key: String) -> void:
	if _input_locked or _game_done:
		return
	match key:
		"ENTER":
			_submit_guess()
		"DEL":
			if not _current_guess.is_empty():
				_current_guess = _current_guess.left(_current_guess.length() - 1)
				_refresh_current_row()
		_:
			if _current_guess.length() < _word_length:
				_current_guess += key
				_refresh_current_row()

func _unhandled_key_input(event: InputEvent) -> void:
	if _input_locked or _game_done:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_on_key_pressed("ENTER")
		KEY_BACKSPACE:
			_on_key_pressed("DEL")
		_:
			var letter: String = _normalise(String.chr(key_event.unicode))
			if letter.length() == 1:
				_on_key_pressed(letter)

func _refresh_current_row() -> void:
	for col in range(_word_length):
		var filled: bool = col < _current_guess.length()
		_set_tile(
			_current_row, col,
			_current_guess[col] if filled else "",
			TYPED_FACE if filled else _tile_face,
			TYPED_SHADOW if filled else _tile_shadow,
		)

func _set_tile(row: int, col: int, letter: String, face: Color, shadow: Color) -> void:
	var tile = _tiles[row * _word_length + col]
	tile.text         = letter
	tile.face_color   = face
	tile.shadow_color = shadow

# ── Tentative ─────────────────────────────────────────────────────────────────

func _submit_guess() -> void:
	if _current_guess.length() < _word_length:
		_set_feedback("Il faut %d lettres !" % _word_length, WARN_COLOR)
		return
	if not _word_set.has(_current_guess):
		_set_feedback("« %s » n'est pas dans le dictionnaire" % _current_guess, WARN_COLOR)
		return

	var guess: String = _current_guess
	var found: bool   = guess == _target
	var row: int      = _current_row
	_current_guess = ""
	_current_row  += 1
	var is_out: bool = not found and _current_row >= _max_attempts

	var msg: Dictionary = {
		"action":   "motus_guess",
		"from":     _my_id,
		"attempts": _current_row,
		"found":    found,
		"out":      is_out,
		"word":     guess if found else "",
	}
	if NetworkManager.is_host:
		_handle_progress_host(msg)
	else:
		NetworkManager.send_game_message(0, msg)

	_set_input_locked(true)
	await _reveal_row(row, guess, _evaluate(guess, _target))
	_mark_dead_letters(guess)
	if _game_done:
		return

	if found:
		_sfx_tada.play()
		_set_feedback("Bravo, c'était « %s » !" % _target, WIN_COLOR)
	elif is_out:
		_set_feedback("Essais épuisés — le mot était « %s »" % _target, LOSE_COLOR)
	else:
		_set_feedback("Essai %d / %d" % [_current_row + 1, _max_attempts], NEUTRAL_COLOR)
		_set_input_locked(false)

## Compare la tentative au mot cible en gérant les lettres en double :
## les positions exactes sont marquées d'abord, le reste pioche dans les
## occurrences non encore consommées.
func _evaluate(guess: String, target: String) -> Array:
	var result: Array = []
	result.resize(_word_length)
	var remaining: Dictionary = {}
	for i in range(_word_length):
		if guess[i] == target[i]:
			result[i] = STATE_CORRECT
		else:
			result[i] = STATE_ABSENT
			remaining[target[i]] = remaining.get(target[i], 0) + 1
	for i in range(_word_length):
		if result[i] == STATE_CORRECT:
			continue
		if remaining.get(guess[i], 0) > 0:
			result[i] = STATE_PRESENT
			remaining[guess[i]] -= 1
	return result

## Assombrit les touches des lettres dont on sait qu'elles ne sont pas dans le mot.
func _mark_dead_letters(guess: String) -> void:
	for i in range(guess.length()):
		var letter: String = guess[i]
		if _dead_letters.has(letter) or _target.contains(letter):
			continue
		_dead_letters[letter] = true
		var btn = _key_buttons.get(letter)
		if btn == null:
			continue
		btn.face_color   = btn.face_color.darkened(0.6)
		btn.shadow_color = btn.shadow_color.darkened(0.6)

## Révèle les cases une à une, avec punch-in, secousse et son par lettre.
func _reveal_row(row: int, guess: String, pattern: Array) -> void:
	for col in range(_word_length):
		if _game_done:
			return
		var state: int = int(pattern[col])
		var face: Color
		var shadow: Color
		match state:
			STATE_CORRECT:
				face = CORRECT_FACE
				shadow = CORRECT_SHADOW
			STATE_PRESENT:
				face = PRESENT_FACE
				shadow = PRESENT_SHADOW
			_:
				face = ABSENT_FACE
				shadow = ABSENT_SHADOW
		_set_tile(row, col, guess[col], face, shadow)
		if state == STATE_ABSENT:
			_sfx_error.play()
		else:
			_sfx_correct.play()
		_shake_canvas()
		var tile: Control = _tiles[row * _word_length + col]
		var tw := create_tween()
		tw.tween_property(tile, "scale", Vector2(1.3, 1.3), REVEAL_APPEAR_TIME * 0.6) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(tile, "scale", Vector2.ONE, REVEAL_APPEAR_TIME * 0.4) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		await tw.finished
		await get_tree().create_timer(REVEAL_GAP).timeout

func _shake_canvas() -> void:
	var tw := create_tween()
	tw.tween_property(_canvas_layer, "offset", Vector2( 6, -4), 0.040)
	tw.tween_property(_canvas_layer, "offset", Vector2(-5,  3), 0.040)
	tw.tween_property(_canvas_layer, "offset", Vector2( 3, -2), 0.035)
	tw.tween_property(_canvas_layer, "offset", Vector2.ZERO,    0.040)

# ── Réseau ────────────────────────────────────────────────────────────────────

func _on_custom_message(from_id: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"motus_start":
			_setup_game(data)
		"motus_guess":
			if NetworkManager.is_host:
				var msg: Dictionary = data.duplicate()
				msg["from"] = int(data.get("from", from_id))
				_handle_progress_host(msg)
		"motus_progress":
			_apply_progress(data)

## Hôte : fait autorité sur la progression et la fin de partie.
func _handle_progress_host(data: Dictionary) -> void:
	if _result_pending or _game_done:
		return
	var pid: int      = int(data.get("from", 0))
	var found: bool   = bool(data.get("found", false)) and str(data.get("word", "")) == _target
	var msg: Dictionary = {
		"action":   "motus_progress",
		"from":     pid,
		"attempts": int(data.get("attempts", 0)),
		"found":    found,
		"out":      bool(data.get("out", false)),
	}
	NetworkManager.send_game_message(0, msg)
	_apply_progress(msg)

	if found:
		_result_pending = true
		get_tree().create_timer(END_DELAY).timeout.connect(func(): end_game(pid))
	elif _out.size() >= NetworkManager.players.size():
		_result_pending = true
		get_tree().create_timer(END_DELAY).timeout.connect(func(): end_game(-1))

func _apply_progress(data: Dictionary) -> void:
	var pid: int = int(data.get("from", 0))
	_attempts[pid] = int(data.get("attempts", 0))
	if bool(data.get("found", false)) and pid not in _solved:
		_solved.append(pid)
	elif bool(data.get("out", false)) and pid not in _out:
		_out.append(pid)
	_update_status(pid)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _set_feedback(message: String, color: Color) -> void:
	_feedback_lbl.text = message
	_feedback_lbl.add_theme_color_override("font_color", color)

func _set_input_locked(locked: bool) -> void:
	_input_locked = locked
	var alpha: float = 0.35 if locked else 1.0
	var filter: Control.MouseFilter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	for row in _kb_rows:
		for child in row.get_children():
			child.modulate = Color(alpha, alpha, alpha, 1.0)
			if child is Control:
				(child as Control).mouse_filter = filter

# ── Fin de partie ─────────────────────────────────────────────────────────────

func _on_game_over(winner_peer_id: int) -> void:
	_game_done = true
	_set_input_locked(true)

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
	panel.anchor_left   = 0.5;    panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5;    panel.anchor_bottom = 0.5
	panel.offset_left   = -320.0; panel.offset_right  = 320.0
	panel.offset_top    = -180.0; panel.offset_bottom = 180.0
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Fin de partie !"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", NEUTRAL_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var winner_lbl := Label.new()
	if winner_peer_id == -1:
		winner_lbl.text = "Personne n'a trouvé !"
	else:
		var winner_name: String = NetworkManager.players.get(winner_peer_id, {}).get("name", "?")
		winner_lbl.text = "🏆 %s a trouvé en %d essai%s !" % [
			winner_name,
			_attempts.get(winner_peer_id, 0),
			"s" if _attempts.get(winner_peer_id, 0) > 1 else "",
		]
	winner_lbl.add_theme_font_size_override("font_size", 30)
	winner_lbl.add_theme_color_override("font_color", WARN_COLOR)
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(winner_lbl)

	var word_lbl := Label.new()
	word_lbl.text = "Le mot était : %s" % _target
	word_lbl.add_theme_font_size_override("font_size", 26)
	word_lbl.add_theme_color_override("font_color", WIN_COLOR)
	word_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(word_lbl)

	await get_tree().create_timer(5.0).timeout
	get_tree().change_scene_to_file("res://Scenes/Lobby/SelectGames.tscn")
