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
