extends Control


func _on_button_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menus/main_menu_wireframe_test.tscn")
