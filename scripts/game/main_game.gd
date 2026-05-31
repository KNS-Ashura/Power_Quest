extends Node2D

const MAP_SLOT_NAME := "MapSlot"
const MINIMAP_SCENE := preload("res://scenes/ui/minimap.tscn")
const SCOREBOARD_SCENE := preload("res://scenes/ui/InGameScoreboard.tscn")
const LEGACY_MAP_ROOT_NAMES: Array[String] = ["Undead-Land", "Cave-Land"]


func _ready() -> void:
	_remove_legacy_embedded_maps()
	_ensure_minimap_ui()
	_ensure_scoreboard_ui()
	_load_active_map()
	call_deferred("_init_match_systems")


func _ensure_minimap_ui() -> void:
	if get_node_or_null("MinimapUI") != null:
		return
	add_child(MINIMAP_SCENE.instantiate())


func _ensure_scoreboard_ui() -> void:
	if get_node_or_null("InGameScoreboard") != null:
		return
	add_child(SCOREBOARD_SCENE.instantiate())


func _init_match_systems() -> void:
	if GameManager.has_method("init_match"):
		GameManager.init_match()
	if MapSession.is_online_match:
		return
	if AIManager.has_method("init_match"):
		AIManager.init_match()
	call_deferred("_focus_camera_on_local_camps")


func _focus_camera_on_local_camps() -> void:
	var manager := get_tree().get_first_node_in_group("manager_rts")
	if manager != null and manager.has_method("focus_on_local_camps"):
		manager.focus_on_local_camps()


func _remove_legacy_embedded_maps() -> void:
	for node_name in LEGACY_MAP_ROOT_NAMES:
		var legacy: Node = get_node_or_null(node_name)
		if legacy:
			legacy.queue_free()


func _load_active_map() -> void:
	var slot := _ensure_map_slot()
	_clear_map_slot(slot)

	var path := MapSession.get_map_scene_path()
	if not ResourceLoader.exists(path):
		push_error(
			"Map scene missing: %s (map index %d). Add the .scn or pick another map."
			% [path, MapSession.active_map_index]
		)
		return

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Failed to load map scene: %s" % path)
		return

	slot.add_child(packed.instantiate())
	if Music.has_method("play_for_map"):
		Music.play_for_map(MapSession.active_map_index)
	call_deferred("_refresh_minimap")


func _refresh_minimap() -> void:
	for node in get_tree().get_nodes_in_group("minimap"):
		if node.has_method("_refresh_world_bounds"):
			node._refresh_world_bounds()


func _ensure_map_slot() -> Node2D:
	var existing := get_node_or_null(MAP_SLOT_NAME) as Node2D
	if existing != null:
		return existing

	var slot := Node2D.new()
	slot.name = MAP_SLOT_NAME
	add_child(slot)
	move_child(slot, 0)
	return slot


func _clear_map_slot(slot: Node) -> void:
	for child in slot.get_children():
		child.queue_free()
