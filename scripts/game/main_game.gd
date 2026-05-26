extends Node2D

const MAP_SLOT_NAME := "MapSlot"
const LEGACY_MAP_ROOT_NAMES: Array[String] = ["Undead-Land", "Cave-Land"]


func _ready() -> void:
	_remove_legacy_embedded_maps()
	_load_active_map()
	call_deferred("_init_match_systems")


func _init_match_systems() -> void:
	if GameManager.has_method("init_match"):
		GameManager.init_match()
	if MapSession.is_online_match:
		return
	if AIManager.has_method("init_match"):
		AIManager.init_match()


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
