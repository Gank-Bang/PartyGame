extends Node2D

const ProjectileScript = preload("res://Scripts/hocem/ProjectileScript.gd")

## Probabilité d'un tir bleu/orange en plus du pattern normal (à partir de la phase 2)
const SPECIAL_CHANCE := 0.25

## État intermédiaire entre la phase 2 et la phase 3 : le boss arrête de tirer,
## vibre sur place et parle, puis la phase 3 explose d'un coup.
const PHASE_PAUSE := 0

## Volume considéré comme silencieux pour les fondus (en décibels)
const SILENCE_DB := -40.0

# ── Synchro musique / phases ──────────────────────────────────────────────────
# Toute la timeline est réglable ici (ou dans l'Inspector). Les phases 3 et 4
# sont calculées à partir du moment où la 2e musique démarre.
#
# Pour changer de musique : glisser le nouveau fichier dans la propriété
# "Stream" du nœud MusicPhase12 / MusicPhase3 (enfants du Boss), puis ajuster
# dialogue_offset et phase3_offset pour coller aux temps forts du morceau.
# Aucun autre code n'a besoin d'être touché.

## Début de la phase 2 (secondes depuis le début de la partie)
@export var phase2_start: float = 20.0
## Moment où la 2e musique démarre — pendant la phase 2, avant la phase 3
@export var music_phase3_start: float = 25.0
## Durée du fondu croisé entre la 1re et la 2e musique (secondes)
@export var music_fade_duration: float = 1.5
## Décalage DANS la 2e musique où le boss arrête de tirer et se met à vibrer
@export var pause_offset: float = 16.0
## Décalage DANS la 2e musique où la phase 3 explose
@export var phase3_offset: float = 23.0
## Durée de la phase 3 avant de passer en phase 4
@export var phase3_duration: float = 20.0

## Répliques du boss. Le BBCode est autorisé, ex. [font_size=96]mot[/font_size].
## La DERNIÈRE réplique déclenche les particules (nœud DialogueParticles).
@export var dialogue_lines: Array[String] = [
	"C'est contre ça que je perds ??",
	"Tu t'es bien débrouillé, machine.",
	"Mais tu as besoin de plus de",
	"[shake rate=25.0 level=12][font_size=96]POUVOIR[/font_size][/shake]",
]
## Instant d'apparition de chaque réplique, en secondes DANS la 2e musique.
## Même ordre que dialogue_lines.
@export var dialogue_times: Array[float] = [16.0, 19.0, 21.0, 22.5]
## Durée d'affichage de la dernière réplique (secondes)
@export var dialogue_hold: float = 4.0

## Amplitude de la vibration du boss pendant la pause (en pixels)
@export var shake_amplitude: float = 6.0
## Nombre de projectiles dans l'explosion qui ouvre la phase 3
@export var burst_count: int = 16

# ── État ──────────────────────────────────────────────────────────────────────

var shoot_timer : float = 0.0
var game_timer : float = 0.0  # temps total écoulé → détermine la phase

var current_phase : int = 1
var spiral_angle : float = 0.0
var _previous_phase : int = -1  # -1 = pas encore initialisé
var _base_position : Vector2
var _music_phase3_started : bool = false
var _dialogue_index : int = -1  # réplique actuellement affichée

# Volume d'origine de la 2e piste, cible du fondu entrant
var _music3_volume : float

# Instants dérivés de la synchro musique (calculés dans _recompute_timeline)
var _pause_time : float
var _phase3_time : float
var _phase4_time : float

@onready var _music12 : AudioStreamPlayer = $MusicPhase12
@onready var _music3 : AudioStreamPlayer = $MusicPhase3
@onready var _dialogue : RichTextLabel = $Dialogue
@onready var _dialogue_particles : CPUParticles2D = $DialogueParticles

func _ready() -> void:
	_base_position = position
	_dialogue.text = ""
	_recompute_timeline()

	# Les musiques sont assignées dans la scène (nœuds MusicPhase12 / MusicPhase3)
	_music3_volume = _music3.volume_db
	_set_looping(_music12.stream, true)
	_set_looping(_music3.stream, true)

	if _music12.stream != null:
		_music12.play()

func _recompute_timeline() -> void:
	_pause_time = music_phase3_start + pause_offset
	_phase3_time = music_phase3_start + phase3_offset
	_phase4_time = _phase3_time + phase3_duration

## Active ou non la boucle, quel que soit le type de stream (MP3, Ogg, ...).
func _set_looping(stream: AudioStream, enabled: bool) -> void:
	if stream != null and "loop" in stream:
		stream.loop = enabled

## Appelé à la fin de la partie : coupe la musique et remet le boss en place.
func stop_fight() -> void:
	set_process(false)
	_music12.stop()
	_music3.stop()
	position = _base_position
	_dialogue.text = ""

# ── Boucle ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	game_timer += delta
	_update_phase()
	_update_music()
	_update_dialogue()

	if current_phase == PHASE_PAUSE:
		_update_pause()
		return

	# Les phases, la musique et le dialogue tournent partout (présentation),
	# mais seul l'hôte fait tirer le boss.
	if not NetworkManager.is_host:
		return

	shoot_timer += delta
	if shoot_timer >= _get_interval():
		shoot_timer = 0.0
		_shoot()

func _update_phase() -> void:
	if game_timer < phase2_start:
		current_phase = 1
	elif game_timer < _pause_time:
		current_phase = 2
	elif game_timer < _phase3_time:
		current_phase = PHASE_PAUSE
	elif game_timer < _phase4_time:
		current_phase = 3
	else:
		current_phase = 4

	if current_phase != _previous_phase:
		if _previous_phase != -1:
			_on_phase_changed()
		_previous_phase = current_phase

## Démarre la 2e musique pendant la phase 2. Le reste de la timeline étant
## calculé à partir de music_phase3_start, la position dans le morceau
## correspond à (game_timer - music_phase3_start).
func _update_music() -> void:
	if _music_phase3_started or game_timer < music_phase3_start:
		return
	_music_phase3_started = true

	# Fondu sortant sur la 1re musique, puis arrêt une fois le silence atteint
	if _music12.playing:
		var fade_out := create_tween()
		fade_out.tween_property(_music12, "volume_db", SILENCE_DB, music_fade_duration)
		fade_out.tween_callback(_music12.stop)

	# Fondu entrant sur la 2e. Elle démarre *pile* à music_phase3_start (le fondu
	# ne joue que sur le volume) pour que la synchro dialogue/phase 3 reste exacte.
	if _music3.stream != null:
		_music3.volume_db = SILENCE_DB
		_music3.play()
		create_tween().tween_property(_music3, "volume_db", _music3_volume, music_fade_duration)

func _on_phase_changed() -> void:
	if current_phase == PHASE_PAUSE:
		shoot_timer = 0.0
		return

	if _previous_phase == PHASE_PAUSE:
		_end_pause()

	_flash()
	if current_phase == 3:
		_shoot_burst()  # « ça pète d'un coup »

# ── Pause avant la phase 3 ────────────────────────────────────────────────────

## Le boss vibre sur place pendant la pause.
func _update_pause() -> void:
	position = _base_position + Vector2(
		randf_range(-shake_amplitude, shake_amplitude),
		randf_range(-shake_amplitude, shake_amplitude)
	)

func _end_pause() -> void:
	position = _base_position

## Affiche la réplique dont l'horodatage est atteint, en se calant sur la
## position dans la 2e musique. Appelé en continu : la dernière réplique peut
## donc rester affichée après la fin de la pause (ex. celle calée sur la phase 3).
func _update_dialogue() -> void:
	var music_pos := game_timer - music_phase3_start
	var index := -1
	for i in mini(dialogue_lines.size(), dialogue_times.size()):
		if music_pos >= dialogue_times[i]:
			index = i

	if index < 0 or music_pos > dialogue_times[index] + dialogue_hold:
		_dialogue.text = ""
		return

	if index != _dialogue_index:
		_dialogue_index = index
		# La dernière réplique arrive avec ses particules
		if index == dialogue_lines.size() - 1:
			_dialogue_particles.restart()

	_dialogue.text = "[center]%s[/center]" % dialogue_lines[index]

# ── Animation ─────────────────────────────────────────────────────────────────

func _flash() -> void:
	var original_color : Color = $ColorRect.color
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.15)
	tween.parallel().tween_property($ColorRect, "color", Color(1, 1, 1, 1), 0.15)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)
	tween.parallel().tween_property($ColorRect, "color", original_color, 0.15)

# ── Tirs ──────────────────────────────────────────────────────────────────────

func _get_interval() -> float:
	match current_phase:
		1: return 1.5
		2: return 0.6  # beaucoup plus de projectiles qu'avant (était 1.2)
		3: return 0.25 # aussi dense que la phase 4 dès l'explosion d'entrée
		4: return 0.25
	return 1.5

func _shoot() -> void:
	match current_phase:
		1: _shoot_line()
		2: _shoot_fan()
		3: _shoot_spiral()
		4: _shoot_random()

	if current_phase >= 2 and randf() < SPECIAL_CHANCE:
		_shoot_special()

# Phase 1 — ligne droite vers le bas + légère déviation
func _shoot_line() -> void:
	var dir = Vector2(randf_range(-0.2, 0.2), 1.0)
	_spawn_projectile(dir, 340.0)

# Phase 2 — éventail 5 projectiles
func _shoot_fan() -> void:
	var dirs = [
		Vector2(-0.8, 1.0),
		Vector2(-0.4, 1.0),
		Vector2(0.0, 1.0),
		Vector2(0.4, 1.0),
		Vector2(0.8, 1.0),
	]
	for d in dirs:
		var offset = Vector2(randf_range(-0.1, 0.1), 0.0)
		_spawn_projectile(d + offset, 400.0)

# Phase 3 — spirale (uniquement vers le bas, de gauche à droite)
func _shoot_spiral() -> void:
	spiral_angle += 0.3
	# Contraindre à la moitié basse : angle entre 0 et PI (droite → bas → gauche)
	var clamped = fmod(spiral_angle, PI)
	var dir = Vector2(cos(clamped), sin(clamped))
	_spawn_projectile(dir, 450.0)

# Phase 4 — mix aléatoire
func _shoot_random() -> void:
	match randi() % 3:
		0: _shoot_line()
		1: _shoot_fan()
		2: _shoot_spiral()

# Explosion qui ouvre la phase 3 : un éventail large sur toute la moitié basse
func _shoot_burst() -> void:
	if burst_count < 2:
		return
	for i in burst_count:
		var angle := PI * (float(i) / float(burst_count - 1))
		_spawn_projectile(Vector2(cos(angle), sin(angle)), 450.0)

# Tir spécial façon Undertale : bleu (rester immobile pour le traverser) ou orange (rester en mouvement)
func _shoot_special() -> void:
	var dir = Vector2(randf_range(-0.15, 0.15), 1.0)
	var type = ProjectileScript.ColorType.BLUE if randf() < 0.5 else ProjectileScript.ColorType.ORANGE
	_spawn_projectile(dir, 250.0, type)

## Seul l'hôte décide des tirs : il crée le projectile via le jeu, qui lui
## attribue un id réseau et le réplique chez tous les clients.
func _spawn_projectile(direction: Vector2, speed: float, type: int = ProjectileScript.ColorType.NORMAL) -> void:
	if not NetworkManager.is_host:
		return
	var game := get_parent()
	if game != null and game.has_method("spawn_projectile"):
		game.spawn_projectile(global_position, direction, speed, type)
