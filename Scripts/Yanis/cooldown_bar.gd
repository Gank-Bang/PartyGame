extends ProgressBar


func update_cooldown(progress: float):
	value = progress * max_value
