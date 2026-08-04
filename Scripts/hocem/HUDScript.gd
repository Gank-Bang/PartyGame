extends CanvasLayer                                                                                                                 

# Référence aux 4 VBoxContainer des joueurs

@onready var slots = $HBoxContainer.get_children()

func _ready() -> void:
	# Cacher tous les slots au départ
	for slot in slots:
		slot.visible = false

func setup_player(slot_index: int, player_name: String) -> void:                                                                    
	if slot_index >= slots.size():    
		return                                                                                                                
	slots[slot_index].visible = true                                                                                              
	slots[slot_index].get_child(0).text = player_name
																																	  
func update_hearts(slot_index: int, hp: int) -> void:
	if slot_index >= slots.size():
		return
	# Deuxième enfant = HBoxContainer des cœurs
	var hearts = slots[slot_index].get_child(1).get_children()
	for i in hearts.size():
		hearts[i].modulate.a = 1.0 if i < hp else 0.3

	# Portrait placeholder coloré en attendant les vrais sprites (sain/blessé/très blessé)
	var portrait = slots[slot_index].get_node_or_null("Portrait")
	if portrait:
		if hp >= 3:
			portrait.color = Color(0.2, 0.8, 0.2, 1) # sain — vert
		elif hp == 2:
			portrait.color = Color(0.9, 0.6, 0.1, 1) # blessé — orange
		elif hp == 1:
			portrait.color = Color(0.85, 0.15, 0.15, 1) # très blessé — rouge
		else:
			portrait.color = Color(0.3, 0.3, 0.3, 1) # éliminé — gris

