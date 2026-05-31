extends RefCounted
class_name MapBounds

## Limites caméra mesurées dans l'éditeur Godot (Camera2D → Limit).
const CAMERA_LIMITS_BY_MAP: Dictionary = {
	1: Rect2(-3963, -3093, 8242, 6080),
	2: Rect2(-3963, -3093, 8242, 6080),
	3: Rect2(-3963, -3093, 8242, 6080),
}


static func camera_limit_rect(map_index: int, map_slot: Node) -> Rect2:
	if CAMERA_LIMITS_BY_MAP.has(map_index):
		return CAMERA_LIMITS_BY_MAP[map_index]
	var computed := compute_map_bounds(map_slot)
	if computed.size.length_squared() > 1.0:
		return computed
	return Rect2(0, 0, 1920, 1080)


static func compute_map_bounds(map_root: Node) -> Rect2:
	if map_root == null:
		return Rect2()
	var merged := Rect2()
	var found := false
	for layer in collect_tilemap_layers(map_root):
		var layer_rect := tilemap_layer_world_rect(layer)
		if layer_rect.size == Vector2.ZERO:
			continue
		merged = layer_rect if not found else merged.merge(layer_rect)
		found = true
	return merged


static func collect_tilemap_layers(root: Node) -> Array:
	var result: Array = []
	_collect_tilemap_layers_recursive(root, result)
	return result


static func _collect_tilemap_layers_recursive(node: Node, result: Array) -> void:
	if node is TileMapLayer:
		result.append(node)
	for child in node.get_children():
		_collect_tilemap_layers_recursive(child, result)


static func tilemap_layer_world_rect(layer: TileMapLayer) -> Rect2:
	var used: Rect2i = layer.get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2()
	var tile_size := Vector2i(16, 16)
	if layer.tile_set != null:
		tile_size = layer.tile_set.tile_size
	var merged := Rect2()
	var found := false
	for x in range(used.position.x, used.end.x):
		for y in range(used.position.y, used.end.y):
			var cell := Vector2i(x, y)
			if layer.get_cell_source_id(cell) == -1:
				continue
			var local_origin := layer.map_to_local(cell)
			var local_end := local_origin + Vector2(tile_size)
			var world_tl: Vector2 = layer.to_global(local_origin)
			var world_br: Vector2 = layer.to_global(local_end)
			var cell_rect := Rect2(world_tl, world_br - world_tl)
			merged = cell_rect if not found else merged.merge(cell_rect)
			found = true
	return merged
