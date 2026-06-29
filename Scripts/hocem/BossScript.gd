extends Node2D

const ProjectileScene = preload("res://Scenes/hocem/Projectile.tscn")

var shoot_timer : float = 0.0
var game_timer : float = 0.0  # temps total écoulé → détermine la phase

# Phase 1 : 0-20s  → lignes droites, lent
# Phase 2 : 20-40s → éventail 3 directions
# Phase 3 : 40-60s → spirale
# Phase 4 : 60s+   → mix aléatoire des 3

var current_phase : int = 1
var spiral_angle : float = 0.0

func _process(delta: float) -> void:
	game_timer += delta
	_update_phase()

	shoot_timer += delta
	if shoot_timer >= _get_interval():
		shoot_timer = 0.0
		_shoot()

func _update_phase() -> void:
	if game_timer < 20.0:
		current_phase = 1
	elif game_timer < 40.0:
		current_phase = 2
	elif game_timer < 60.0:
		current_phase = 3
	else:
		current_phase = 4

func _get_interval() -> float:
	match current_phase:
		1: return 1.5
		2: return 1.2
		3: return 0.8
		4: return 0.5
	return 1.5

func _shoot() -> void:
	match current_phase:
		1: _shoot_line()
		2: _shoot_fan()
		3: _shoot_spiral()
		4: _shoot_random()

# Phase 1 — ligne droite vers le bas + légère déviation
func _shoot_line() -> void:
	var dir = Vector2(randf_range(-0.2, 0.2), 1.0)
	_spawn_projectile(dir, 300.0)

# Phase 2 — éventail 3 projectiles
func _shoot_fan() -> void:
	var dirs = [
		Vector2(-0.6, 1.0),
		Vector2(0.0, 1.0),
		Vector2(0.6, 1.0),
	]
	for d in dirs:
		var offset = Vector2(randf_range(-0.1, 0.1), 0.0)
		_spawn_projectile(d + offset, 350.0)

# Phase 3 — spirale (uniquement vers le bas, de gauche à droite)
func _shoot_spiral() -> void:
	spiral_angle += 0.3
	# Contraindre à la moitié basse : angle entre 0 et PI (droite → bas → gauche)
	var clamped = fmod(spiral_angle, PI)
	var dir = Vector2(cos(clamped), sin(clamped))
	_spawn_projectile(dir, 400.0)

# Phase 4 — mix aléatoire
func _shoot_random() -> void:
	match randi() % 3:
		0: _shoot_line()
		1: _shoot_fan()
		2: _shoot_spiral()

func _spawn_projectile(direction: Vector2, speed: float) -> void:
	var proj = ProjectileScene.instantiate()
	proj.position = global_position
	proj.init(direction, speed)
	get_parent().add_child(proj)
