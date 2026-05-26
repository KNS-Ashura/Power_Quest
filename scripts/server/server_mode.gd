extends Node

## Détecte --server et charge game_server_main au lieu du menu client.

var is_dedicated_server: bool = false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--server":
			is_dedicated_server = true
			return
	for arg in OS.get_cmdline_args():
		if arg == "--server":
			is_dedicated_server = true
			return


func _ready() -> void:
	if not is_dedicated_server:
		return
	call_deferred("_boot_game_server")


func _boot_game_server() -> void:
	var tree := get_tree()
	var current := tree.current_scene
	if current != null and current.scene_file_path == "res://scenes/server/game_server_main.tscn":
		return
	tree.change_scene_to_file("res://scenes/server/game_server_main.tscn")
