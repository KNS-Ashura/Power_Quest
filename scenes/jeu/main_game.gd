extends Node2D

func _ready() -> void:
	var idx: int = MapSession.active_map_index
	if idx != 1 and idx != 2:
		idx = 1

	var undead: Node2D = get_node_or_null("Undead-Land") as Node2D
	var cave: Node2D = get_node_or_null("Cave-Land") as Node2D

	if idx == 2:
		if undead:
			undead.free()
	else:
		if cave:
			cave.free()

	# Quand on arrive depuis le menu, l'autoload a deja lance sa premiere
	# initialisation avant que les camps n'existent. On relance ici pour
	# garantir des camps ennemis/alliés sur la map choisie.
	if GameManager.has_method("initialiser_partie"):
		GameManager.initialiser_partie()
