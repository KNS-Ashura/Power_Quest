extends Control

const PADDING := 8.0
const CAMP_RADIUS := 3.5
const UNIT_RADIUS := 1.2
const BOUNDS_PADDING := 128.0
const BOUNDS_LAYER_PRIORITY: Array[String] = ["water", "ground1", "ground2", "road", "chemin"]
const REDRAW_INTERVAL := 0.1

var _world_bounds := Rect2(0, 0, 1920, 1080)
var _map_draw_rect := Rect2()
var _bounds_ready := false
var _redraw_accum := 0.0


func _ready() -> void:
	add_to_group("minimap")
	mouse_filter = Control.MOUSE_FILTER_STOP
	call_deferred("_refresh_world_bounds")


func _process(delta: float) -> void:
	if not _bounds_ready:
		return
	_redraw_accum += delta
	if _redraw_accum < REDRAW_INTERVAL:
		return
	_redraw_accum = 0.0
	queue_redraw()


func _refresh_world_bounds() -> void:
	for _attempt in range(12):
		await get_tree().process_frame
		if not get_tree().get_nodes_in_group("camps").is_empty():
			break
	_world_bounds = _compute_world_bounds()
	_map_draw_rect = _compute_map_draw_rect()
	_bounds_ready = _world_bounds.size.length_squared() > 1.0
	queue_redraw()


func _compute_world_bounds() -> Rect2:
	var camp_bounds := _compute_camp_bounds()
	var slot: Node = get_tree().current_scene.get_node_or_null("MapSlot") if get_tree().current_scene else null
	var tile_bounds := _compute_priority_tilemap_bounds(slot) if slot != null else Rect2()

	if camp_bounds.size.length_squared() > 1.0:
		var bounds := _square_bounds(camp_bounds.grow(BOUNDS_PADDING))
		if tile_bounds.size.length_squared() > 1.0 and _should_merge_tile_bounds(camp_bounds, tile_bounds):
			bounds = _square_bounds(bounds.merge(tile_bounds.grow(BOUNDS_PADDING)))
		return bounds

	if tile_bounds.size.length_squared() > 1.0:
		return tile_bounds.grow(BOUNDS_PADDING)

	if slot != null:
		var nav_bounds := _compute_navigation_bounds(slot)
		if nav_bounds.size.length_squared() > 1.0:
			return nav_bounds.grow(BOUNDS_PADDING)

	return Rect2(0, 0, 1920, 1080)


func _should_merge_tile_bounds(camp_bounds: Rect2, tile_bounds: Rect2) -> bool:
	if camp_bounds.size.x <= 0.0 or camp_bounds.size.y <= 0.0:
		return true
	return tile_bounds.size.x <= camp_bounds.size.x * 1.35 \
		and tile_bounds.size.y <= camp_bounds.size.y * 1.35


func _compute_priority_tilemap_bounds(root: Node) -> Rect2:
	var merged := Rect2()
	var found := false

	for layer_name in BOUNDS_LAYER_PRIORITY:
		var layer := _find_tilemap_layer(root, layer_name)
		if layer == null:
			continue
		var layer_rect := _tilemap_layer_world_rect(layer)
		if layer_rect.size == Vector2.ZERO:
			continue
		merged = layer_rect if not found else merged.merge(layer_rect)
		found = true

	return merged


func _find_tilemap_layer(root: Node, layer_name: String) -> TileMapLayer:
	var target := layer_name.to_lower()
	for layer in _collect_tilemap_layers(root):
		if layer.name.to_lower() == target:
			return layer
	return null


func _square_bounds(rect: Rect2) -> Rect2:
	var side := maxf(rect.size.x, rect.size.y)
	var center := rect.get_center()
	return Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side)


func _compute_navigation_bounds(root: Node) -> Rect2:
	var merged := Rect2()
	var found := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is NavigationRegion2D:
			var nav_rect := _navigation_region_world_rect(node as NavigationRegion2D)
			if nav_rect.size != Vector2.ZERO:
				merged = nav_rect if not found else merged.merge(nav_rect)
				found = true
		for child in node.get_children():
			stack.append(child)
	return merged


func _navigation_region_world_rect(nav: NavigationRegion2D) -> Rect2:
	var polygon: NavigationPolygon = nav.navigation_polygon
	if polygon == null:
		return Rect2()

	var merged := Rect2()
	var found := false
	for outline in polygon.outlines:
		for point in outline:
			var world_point: Vector2 = nav.to_global(point)
			var point_rect := Rect2(world_point, Vector2.ZERO)
			merged = point_rect if not found else merged.merge(point_rect)
			found = true

	return merged


func _compute_camp_bounds() -> Rect2:
	var merged := Rect2()
	var found := false

	for camp in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(camp):
			continue
		var point_rect := Rect2(camp.global_position, Vector2.ZERO).grow(160.0)
		merged = point_rect if not found else merged.merge(point_rect)
		found = true

	return merged


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
	var top_left: Vector2 = layer.to_global(local_rect.position)
	var bottom_right: Vector2 = layer.to_global(local_rect.position + local_rect.size)
	return Rect2(top_left, bottom_right - top_left)


func _content_rect() -> Rect2:
	return Rect2(
		Vector2(PADDING, PADDING),
		size - Vector2(PADDING * 2.0, PADDING * 2.0)
	)


func _compute_map_draw_rect() -> Rect2:
	var content := _content_rect()
	if _world_bounds.size.x <= 0.0 or _world_bounds.size.y <= 0.0:
		return content

	var world_aspect := _world_bounds.size.x / _world_bounds.size.y
	var content_aspect := content.size.x / content.size.y
	if world_aspect > content_aspect:
		var draw_height := content.size.x / world_aspect
		return Rect2(
			Vector2(content.position.x, content.position.y + (content.size.y - draw_height) * 0.5),
			Vector2(content.size.x, draw_height)
		)

	var draw_width := content.size.y * world_aspect
	return Rect2(
		Vector2(content.position.x + (content.size.x - draw_width) * 0.5, content.position.y),
		Vector2(draw_width, content.size.y)
	)


func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var draw_rect := _map_draw_rect if _map_draw_rect.size != Vector2.ZERO else _content_rect()
	if _world_bounds.size.x <= 0.0 or _world_bounds.size.y <= 0.0:
		return draw_rect.position
	var t := (world_pos - _world_bounds.position) / _world_bounds.size
	t = t.clamp(Vector2.ZERO, Vector2.ONE)
	return draw_rect.position + Vector2(t.x * draw_rect.size.x, t.y * draw_rect.size.y)


func _minimap_to_world(local_pos: Vector2) -> Vector2:
	var draw_rect := _map_draw_rect if _map_draw_rect.size != Vector2.ZERO else _content_rect()
	var t := (local_pos - draw_rect.position) / draw_rect.size
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


func _should_show_unit_on_minimap(unit: Node) -> bool:
	return not (unit.get("is_camp_guardian") and unit.is_camp_guardian)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.12, 0.88), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.45, 0.75, 0.95), false, 2.0)

	if not _bounds_ready:
		return

	var content := _content_rect()
	draw_rect(content, Color(0.14, 0.16, 0.22, 0.95), true)

	var map_rect := _map_draw_rect if _map_draw_rect.size != Vector2.ZERO else content
	draw_rect(map_rect, Color(0.18, 0.2, 0.28, 0.95), true)

	for camp in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(camp):
			continue
		if not RegionManager.should_show_camp_on_minimap(camp):
			continue
		var team: int = int(camp.get("team"))
		var p := _world_to_minimap(camp.global_position)
		if not map_rect.has_point(p):
			continue
		draw_circle(p, CAMP_RADIUS, _team_color(team))

	for unit in get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(unit):
			continue
		if not _should_show_unit_on_minimap(unit):
			continue
		var p := _world_to_minimap(unit.global_position)
		if not map_rect.has_point(p):
			continue
		draw_circle(p, UNIT_RADIUS, Color(0.4, 0.85, 1.0, 0.9))

	for unit in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(unit):
			continue
		if not _should_show_unit_on_minimap(unit):
			continue
		var p := _world_to_minimap(unit.global_position)
		if not map_rect.has_point(p):
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
