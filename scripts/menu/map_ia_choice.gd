extends Node2D

const MSG_MAP_MISSING := "Map %d is not available yet (missing scene file)."
const AI_LEVEL_KEYS: Array[String] = ["AI_BEGINNER", "AI_INTERMEDIATE", "AI_EXPERT"]

var current_ai_index: int = 0

var map_list: Array[Dictionary] = [
	{
		"name_key": "MAP_NAME_1",
		"image_map": preload("res://assets/menu/map-img/map1.png"),
		"map_index": 1
	},
	{
		"name_key": "MAP_NAME_2",
		"image_map": preload("res://assets/menu/map-img/map2.png"),
		"map_index": 2
	},
	{
		"name_key": "MAP_NAME_3",
		"image_map": preload("res://assets/objects/map3/Castle.png"),
		"map_index": 3
	}
]
var current_map_index: int = 0

@onready var ai_label: Label = %IntituleIA
@onready var map_name_label: Label = %MapName
@onready var map_texture: TextureRect = %ImgMap
@onready var map_name_large_label: Label = %NomMap
@onready var launch_button: TextureButton = $LaunchGame


func _ready() -> void:
	if launch_button and not launch_button.pressed.is_connected(_on_launch_game_pressed):
		launch_button.pressed.connect(_on_launch_game_pressed)
	current_ai_index = MapSession.get_ai_difficulty()
	update_ai_display()
	update_map_display()


func update_ai_display() -> void:
	ai_label.text = tr(AI_LEVEL_KEYS[current_ai_index])


func _on_arrow_right_pressed() -> void:
	current_ai_index = (current_ai_index + 1) % AI_LEVEL_KEYS.size()
	update_ai_display()


func _on_arrow_left_pressed() -> void:
	current_ai_index = (current_ai_index - 1 + AI_LEVEL_KEYS.size()) % AI_LEVEL_KEYS.size()
	update_ai_display()


func update_map_display() -> void:
	var entry: Dictionary = map_list[current_map_index]
	var map_name := tr(str(entry["name_key"]))
	map_name_label.text = map_name
	map_name_large_label.text = map_name

	if entry["image_map"] is Texture:
		map_texture.texture = entry["image_map"]
	elif entry["image_map"] is SpriteFrames:
		map_texture.texture = entry["image_map"].get_frame_texture("default", 0)


func _on_map_arrow_right_pressed() -> void:
	current_map_index = (current_map_index + 1) % map_list.size()
	update_map_display()


func _on_map_arrow_left_pressed() -> void:
	current_map_index = (current_map_index - 1 + map_list.size()) % map_list.size()
	update_map_display()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		update_ai_display()
		update_map_display()


func _on_launch_game_pressed() -> void:
	var map_index: int = int(map_list[current_map_index].get("map_index", 1))
	MapSession.active_ai_difficulty = current_ai_index
	MapSession.active_map_index = map_index
	if not MapSession.is_map_available(map_index):
		push_warning(MSG_MAP_MISSING % map_index)
		return
	MapSession.reset_online_state()
	get_tree().change_scene_to_file(MapSession.GAME_SHELL_SCENE)
