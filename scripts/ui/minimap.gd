extends Control

const PADDING := 8.0
const CAMP_RADIUS := 3.5
const UNIT_RADIUS := 1.8

var _world_bounds := Rect2(0, 0, 1920, 1080)
var _bounds_ready := false


func _ready() -> void:
	add_to_group("minimap")
	mouse_filter = Control.MOUSE_FILTER_STOP
	call_deferred("_refresh_world_bounds")


func _process(_delta: float) -> void:
	if not _bounds_ready:
		return
	queue_redraw()


func _refresh_world_bounds() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_world_bounds = _compute_world_bounds()
	_bounds_ready = _world_bounds.size.length_squared() > 1.0
	queue_redraw()


func _compute_world_bounds() -> Rect2:
	var merged := Rect2()
	var found := false

	var slot: Node = get_tree().current_scene.get_node_or_null("MapSlot") if get_tree().current_scene else null
	if slot != null:
		for layer in _collect_tilemap_layers(slot):
			var layer_rect := _tilemap_layer_world_rect(layer)
			if layer_rect.size == Vector2.ZERO:
				continue
			merged = layer_rect if not found else merged.merge(layer_rect)
			found = true

	for camp in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(camp):
			continue
		var point_rect := Rect2(camp.global_position, Vector2.ZERO).grow(160.0)
		merged = point_rect if not found else merged.merge(point_rect)
		found = true

	if not found:
		merged = Rect2(0, 0, 1920, 1080)
	return merged.grow(96.0)


func _collect_tilemap_layers(root: Node) -> Array:
	var result: Array = []
	_collect_tilemap_layers_recursive(root, result)
	return result


func _collect_tilemap_layers_recursive(node: Node, result: Array) -> void:
	if node is TileMapLayer:
		result.append(node)
	for child in node.get_children():
		_collect_tilemap_layers_recursive(child, result)


func _tilemap_layer_world_rect(layer: TileMapLayer) -> Rect2:
	var used: Rect2i = layer.get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2()
	var tile_size := Vector2(16, 16)
	if layer.tile_set != null:
		tile_size = Vector2(layer.tile_set.tile_size)
	var local_rect := Rect2(Vector2(used.position) * tile_size, Vector2(used.size) * tile_size)
	var global_pos: Vector2 = layer.to_global(local_rect.position)
	return Rect2(global_pos, local_rect.size)


func _content_rect() -> Rect2:
	return Rect2(
		Vector2(PADDING, PADDING),
		size - Vector2(PADDING * 2.0, PADDING * 2.0)
	)


func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var content := _content_rect()
	if _world_bounds.size.x <= 0.0 or _world_bounds.size.y <= 0.0:
		return content.position
	var t := (world_pos - _world_bounds.position) / _world_bounds.size
	t = t.clamp(Vector2.ZERO, Vector2.ONE)
	return content.position + Vector2(t.x * content.size.x, t.y * content.size.y)


func _minimap_to_world(local_pos: Vector2) -> Vector2:
	var content := _content_rect()
	var t := (local_pos - content.position) / content.size
	t = t.clamp(Vector2.ZERO, Vector2.ONE)
	return _world_bounds.position + Vector2(t.x * _world_bounds.size.x, t.y * _world_bounds.size.y)


func _get_camera_world_rect() -> Rect2:
	var manager := get_tree().get_first_node_in_group("manager_rts")
	if manager == null or not manager.has_method("get_camera"):
		return Rect2()
	var cam: Camera2D = manager.get_camera()
	if cam == null:
		return Rect2()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: float = cam.zoom.x if cam.zoom.x > 0.0 else 1.0
	var half := vp_size / (2.0 * zoom)
	return Rect2(cam.global_position - half, vp_size / zoom)


func _team_color(team_id: int) -> Color:
	if MapSession.is_local_team(team_id):
		return Color(0.35, 0.95, 0.45, 1.0)
	if MapSession.is_neutral_team(team_id):
		return Color(0.75, 0.75, 0.75, 1.0)
	return Color(0.95, 0.35, 0.35, 1.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.12, 0.88), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.45, 0.75, 0.95), false, 2.0)

	if not _bounds_ready:
		return

	var content := _content_rect()
	draw_rect(content, Color(0.14, 0.16, 0.22, 0.95), true)

	for camp in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(camp):
			continue
		var team: int = int(camp.get("team"))
		var p := _world_to_minimap(camp.global_position)
		if not content.has_point(p):
			continue
		draw_circle(p, CAMP_RADIUS, _team_color(team))

	for unit in get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(unit):
			continue
		var p := _world_to_minimap(unit.global_position)
		if not content.has_point(p):
			continue
		draw_circle(p, UNIT_RADIUS, Color(0.4, 0.85, 1.0, 0.9))

	for unit in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(unit):
			continue
		var p := _world_to_minimap(unit.global_position)
		if not content.has_point(p):
			continue
		draw_circle(p, UNIT_RADIUS, Color(1.0, 0.45, 0.45, 0.9))

	var cam_rect := _get_camera_world_rect()
	if cam_rect.size != Vector2.ZERO:
		var top_left := _world_to_minimap(cam_rect.position)
		var bottom_right := _world_to_minimap(cam_rect.position + cam_rect.size)
		var view_rect := Rect2(top_left, bottom_right - top_left)
		draw_rect(view_rect, Color(1.0, 1.0, 1.0, 0.22), true)
		draw_rect(view_rect, Color(1.0, 1.0, 1.0, 0.85), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if not _bounds_ready:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := _minimap_to_world(event.position)
		var manager := get_tree().get_first_node_in_group("manager_rts")
		if manager != null and manager.has_method("focus_camera_on_world"):
			manager.focus_camera_on_world(world_pos)
		accept_event()
