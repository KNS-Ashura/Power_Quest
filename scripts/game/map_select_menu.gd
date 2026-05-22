extends Control

const MSG_MAP_MISSING := "Map %d is not available yet (missing scene file)."


func _ready() -> void:
	var btn_map3: Button = get_node_or_null("Center/VBox/BtnMap3") as Button
	if btn_map3 == null:
		return
	var available := MapSession.is_map_available(3)
	btn_map3.disabled = not available
	btn_map3.text = "Map 3" if available else "Map 3 (coming soon)"


func _on_map_1_pressed() -> void:
	_start_game(1)


func _on_map_2_pressed() -> void:
	_start_game(2)


func _on_map_3_pressed() -> void:
	_start_game(3)


func _start_game(map_index: int) -> void:
	MapSession.active_map_index = map_index
	if not MapSession.is_map_available(map_index):
		push_warning(MSG_MAP_MISSING % map_index)
		return
	get_tree().change_scene_to_file(MapSession.GAME_SHELL_SCENE)
