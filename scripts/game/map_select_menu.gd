extends Control

func _on_map_1_pressed() -> void:
	MapSession.active_map_index = 1
	_start_game()

func _on_map_2_pressed() -> void:
	MapSession.active_map_index = 2
	_start_game()

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/jeu/Main.scn")
