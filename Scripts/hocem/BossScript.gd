extends Node2D

const ProjectileScene = preload("res://Scenes/hocem/Projectile.tscn")

var shoot_timer: float = 0.0
var shoot_interval: float = 1.5 # secondes entre chaque tir

func _process(delta: float) -> void:
	shoot_timer += delta
	if shoot_timer >= shoot_interval:
		shoot_timer = 0.0
		_shoot()

func _shoot() -> void:
	var proj = ProjectileScene.instantiate()
	  # Spawner le projectile à la position du boss                                                                                 
	proj.position = global_position
	# Tirer vers le bas avec légère variation aléatoire                                                                           
	var direction = Vector2(randf_range(-0.3, 0.3), 1.0)
	proj.init(direction, 300.0)
	# Ajouter à la scène principale (pas au Boss)                                                                                 
	get_parent().add_child(proj)
