extends RefCounted
class_name PlayerTransportController

const PHASE_IDLE := 0
const PHASE_MARKED := 1
const PHASE_CARRYING := 2
const BOARD_FX_FLASH := 0.25


static func is_water_transporter(owner: Node) -> bool:
	return owner.stats != null and owner.stats.unit_type == UnitStats.UnitType.WATER_TRANSPORT


static func get_cooldown_remaining(owner: Node) -> float:
	return owner.water_transport_cooldown


static func get_phase(owner: Node) -> int:
	return int(owner.water_transport_phase)


static func can_use(owner: Node) -> bool:
	if not is_water_transporter(owner) or owner.is_dying:
		return false
	if int(owner.water_transport_phase) != PHASE_IDLE:
		return true
	return owner.water_transport_cooldown <= 0.0


static func step(owner: Node) -> bool:
	if not can_use(owner):
		return false
	match int(owner.water_transport_phase):
		PHASE_IDLE:
			# One click: mark and board immediately.
			if not mark_allies(owner):
				return false
			return board_marked(owner)
		PHASE_MARKED:
			return board_marked(owner)
		PHASE_CARRYING:
			return disembark(owner)
	return false


static func cancel_mark(owner: Node) -> void:
	if int(owner.water_transport_phase) != PHASE_MARKED:
		return
	clear_marked(owner)


static func capacity(owner: Node) -> int:
	return owner.WATER_TRANSPORT_CAP_BY_LEVEL.get(owner._unit_level(), 5)


static func is_land_unit_transportable(owner: Node, unit: Node) -> bool:
	if not is_instance_valid(unit) or unit == owner:
		return false
	if unit.get("is_dying") and unit.is_dying:
		return false
	if unit.get_meta("water_transport_hidden", false):
		return false
	if unit.get("is_camp_guardian") and unit.is_camp_guardian:
		return false
	if not unit.get("stats") or unit.stats == null:
		return false
	if NodeTeamUtils.team_id(unit) != int(owner.team):
		return false
	var ut: UnitStats.UnitType = unit.stats.unit_type
	return ut == UnitStats.UnitType.INFANTRY \
		or ut == UnitStats.UnitType.ARCHER \
		or ut == UnitStats.UnitType.HEAVY \
		or ut == UnitStats.UnitType.SUPPORT \
		or ut == UnitStats.UnitType.HEAL \
		or ut == UnitStats.UnitType.ANTI_ARMOR \
		or ut == UnitStats.UnitType.MORTAR


static func mark_allies(owner: Node) -> bool:
	var allies := allies_in_radius(owner)
	if allies.is_empty():
		return false
	var cap := capacity(owner)
	allies.sort_custom(func(a, b): return owner.global_position.distance_squared_to(a.global_position) < owner.global_position.distance_squared_to(b.global_position))
	owner.water_transport_marked.clear()
	for unit in allies:
		if owner.water_transport_marked.size() >= cap:
			break
		owner.water_transport_marked.append(unit)
	owner.water_transport_phase = PHASE_MARKED
	return true


static func allies_in_radius(owner: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = owner.WATER_TRANSPORT_MARK_RADIUS
	query.shape = circle
	query.transform = Transform2D(0, owner.global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var group_name := "soldiers" if MapSession.is_local_team(int(owner.team)) else "enemies"
	for res in owner.get_world_2d().direct_space_state.intersect_shape(query):
		var obj = res.collider as Node2D
		if obj == null or not obj.is_in_group(group_name):
			continue
		if is_land_unit_transportable(owner, obj):
			result.append(obj)
	return result


static func board_marked(owner: Node) -> bool:
	if owner.water_transport_marked.is_empty():
		clear_marked(owner)
		return false
	return _apply_boarding(owner, owner.water_transport_marked, true)


static func force_board_units(owner: Node, units: Array) -> bool:
	if not is_water_transporter(owner):
		return false
	if int(owner.water_transport_phase) == PHASE_CARRYING and owner.water_transport_boarded.size() > 0:
		return false
	var to_board: Array[Node2D] = []
	for unit in units:
		if not is_instance_valid(unit) or not (unit is Node2D):
			continue
		if not is_land_unit_transportable(owner, unit):
			continue
		to_board.append(unit as Node2D)
		if to_board.size() >= capacity(owner):
			break
	if to_board.is_empty():
		return false
	clear_marked(owner)
	return _apply_boarding(owner, to_board, false)


static func _apply_boarding(owner: Node, units: Array, with_board_fx: bool) -> bool:
	owner.water_transport_boarded.clear()
	owner.water_transport_origin.clear()
	for unit in units:
		if not is_instance_valid(unit):
			continue
		owner.water_transport_origin[unit] = unit.global_position
		owner.water_transport_boarded.append(unit)
		remove_transport_fx(owner, unit)
		if with_board_fx:
			owner._attach_effect_on_target(unit, owner.SCENE_WATER_TRANSPORT_BOARD_FX, BOARD_FX_FLASH)
			hide_unit_after_delay(owner, unit, BOARD_FX_FLASH)
		else:
			hide_unit(owner, unit)
	owner.water_transport_marked.clear()
	if owner.water_transport_boarded.is_empty():
		owner.water_transport_phase = PHASE_IDLE
		return false
	var bonus: float = 1.0 + owner.WATER_TRANSPORT_SCALE_BONUS * float(owner.water_transport_boarded.size())
	owner.scale = owner.water_transport_base_scale * bonus
	owner.water_transport_phase = PHASE_CARRYING
	return true


static func disembark(owner: Node) -> bool:
	if owner.water_transport_boarded.is_empty():
		reset_after_disembark(owner)
		return false
	var land_point := nearest_ground_point(owner, owner.global_position)
	if land_point == Vector2.INF:
		push_warning("Transport: approchez-vous de la cote (sol) pour debarquer.")
		return false
	var count: int = owner.water_transport_boarded.size()
	for i in range(count):
		var unit: Node2D = owner.water_transport_boarded[i]
		if not is_instance_valid(unit):
			continue
		var angle := TAU * float(i) / float(max(count, 1))
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * owner.WATER_TRANSPORT_DISEMBARK_SPREAD
		var spawn_pos := land_point + offset
		if not is_valid_land_point(owner, spawn_pos):
			spawn_pos = land_point
		show_unit(owner, unit, spawn_pos)
	owner.water_transport_boarded.clear()
	owner.water_transport_origin.clear()
	reset_after_disembark(owner)
	owner.water_transport_cooldown = owner.WATER_TRANSPORT_COOLDOWN
	return true


static func reset_after_disembark(owner: Node) -> void:
	owner.water_transport_phase = PHASE_IDLE
	owner.scale = owner.water_transport_base_scale


static func clear_marked(owner: Node) -> void:
	for unit in owner.water_transport_marked:
		if is_instance_valid(unit):
			remove_transport_fx(owner, unit)
	owner.water_transport_marked.clear()
	owner.water_transport_phase = PHASE_IDLE


static func release_boarded_at_origin(owner: Node) -> void:
	for unit in owner.water_transport_boarded:
		if not is_instance_valid(unit):
			continue
		var origin: Vector2 = owner.water_transport_origin.get(unit, owner.global_position)
		show_unit(owner, unit, origin)
	owner.water_transport_boarded.clear()
	owner.water_transport_origin.clear()
	owner.water_transport_marked.clear()
	owner.scale = owner.water_transport_base_scale
	owner.water_transport_phase = PHASE_IDLE


static func hide_unit(owner: Node, unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	stop_unit_combat(unit)
	unit.visible = false
	unit.collision_layer = 0
	unit.collision_mask = 0
	unit.set_process(false)
	unit.set_physics_process(false)
	if unit.has_node("ZoneDetection"):
		unit.get_node("ZoneDetection").monitoring = false
	unit.set_meta("water_transport_hidden", true)
	unit.set_meta("water_transport_carrier", owner)


static func show_unit(owner: Node, unit: Node2D, spawn_pos: Vector2) -> void:
	if not is_instance_valid(unit):
		return
	remove_transport_fx(owner, unit)
	unit.visible = true
	unit.global_position = spawn_pos
	unit.collision_layer = owner.COLLISION_LAYER_PLAYER_UNIT if MapSession.is_local_team(int(unit.get("team"))) else owner.COLLISION_LAYER_ENEMY_UNIT
	unit.collision_mask = owner.COLLISION_LAYER_WORLD | owner.COLLISION_LAYER_PLAYER_UNIT | owner.COLLISION_LAYER_ENEMY_UNIT
	unit.set_process(true)
	unit.set_physics_process(true)
	if unit.has_node("ZoneDetection"):
		var zone: Area2D = unit.get_node("ZoneDetection")
		zone.monitoring = true
	if unit.has_method("_configure_navigation_layers"):
		unit._configure_navigation_layers()
	if unit.has_method("_configure_movement_and_collisions"):
		unit._configure_movement_and_collisions()
	unit.remove_meta("water_transport_hidden")
	if unit.has_meta("water_transport_carrier"):
		unit.remove_meta("water_transport_carrier")


static func stop_unit_combat(unit: Node) -> void:
	if unit.has_method("_stop_combat"):
		unit._stop_combat()
	elif unit.get("attack_target_node") != null:
		unit.attack_target_node = null


static func remove_transport_fx(owner: Node, unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var fx = unit.get_node_or_null(owner.BUFF_EFFECT_NODE_NAME)
	if is_instance_valid(fx):
		fx.queue_free()


static func hide_unit_after_delay(owner: Node, unit: Node2D, delay_seconds: float) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(unit):
		return
	if delay_seconds <= 0.0:
		hide_unit(owner, unit)
		return
	var timer: SceneTreeTimer = owner.get_tree().create_timer(delay_seconds)
	timer.timeout.connect(func():
		if is_instance_valid(unit):
			hide_unit(owner, unit),
		CONNECT_ONE_SHOT
	)


static func nav_regions(owner: Node) -> Array[NavigationRegion2D]:
	var regions: Array[NavigationRegion2D] = []
	var root := owner.get_tree().current_scene
	if is_instance_valid(root):
		collect_nav_regions(root, regions)
	if regions.is_empty():
		var map_slot := owner.get_tree().root.find_child("MapSlot", true, false)
		if map_slot:
			collect_nav_regions(map_slot, regions)
	return regions


static func closest_point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq <= 0.0001:
		return a
	var t: float = clampf((point - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	return a + ab * t


static func closest_point_on_polygon(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	if polygon.size() < 3:
		return Vector2.INF
	var best := Vector2.INF
	var best_d2 := INF
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var candidate := closest_point_on_segment(point, a, b)
		var d2 := point.distance_squared_to(candidate)
		if d2 < best_d2:
			best_d2 = d2
			best = candidate
	return best


static func surface_mask_at(owner: Node, world_pos: Vector2) -> int:
	var surface_mask := 0
	for region in nav_regions(owner):
		if not is_instance_valid(region):
			continue
		var nav_polygon: NavigationPolygon = region.navigation_polygon
		if nav_polygon == null:
			continue
		var vertices: PackedVector2Array = nav_polygon.get_vertices()
		var local_pos := region.to_local(world_pos)
		for polygon_idx in range(nav_polygon.get_polygon_count()):
			var polygon_indices: PackedInt32Array = nav_polygon.get_polygon(polygon_idx)
			if polygon_indices.size() < 3:
				continue
			var polygon_local := PackedVector2Array()
			for vertex_idx in polygon_indices:
				polygon_local.append(vertices[vertex_idx])
			if Geometry2D.is_point_in_polygon(local_pos, polygon_local):
				surface_mask |= region.navigation_layers
				break
	return surface_mask


static func is_valid_land_point(owner: Node, world_pos: Vector2) -> bool:
	var surface_mask := surface_mask_at(owner, world_pos)
	return (surface_mask & owner.NAV_LAYER_GROUND) != 0 and (surface_mask & owner.NAV_LAYER_WATER) == 0


static func closest_on_layers(owner: Node, from: Vector2, layer_mask: int) -> Vector2:
	var best := Vector2.INF
	var best_d2 := INF
	for region in nav_regions(owner):
		if not is_instance_valid(region):
			continue
		if (region.navigation_layers & layer_mask) == 0:
			continue
		var nav_polygon: NavigationPolygon = region.navigation_polygon
		if nav_polygon == null:
			continue
		var vertices: PackedVector2Array = nav_polygon.get_vertices()
		var local_pos := region.to_local(from)
		for polygon_idx in range(nav_polygon.get_polygon_count()):
			var polygon_indices: PackedInt32Array = nav_polygon.get_polygon(polygon_idx)
			if polygon_indices.size() < 3:
				continue
			var polygon_local := PackedVector2Array()
			var polygon_world := PackedVector2Array()
			for vertex_idx in polygon_indices:
				var local_vertex := vertices[vertex_idx]
				polygon_local.append(local_vertex)
				polygon_world.append(region.to_global(local_vertex))
			var candidate := from if Geometry2D.is_point_in_polygon(local_pos, polygon_local) else closest_point_on_polygon(from, polygon_world)
			if candidate == Vector2.INF:
				continue
			var d2 := from.distance_squared_to(candidate)
			if d2 < best_d2:
				best_d2 = d2
				best = candidate
	return best


static func nearest_water_point_near(owner: Node, world_pos: Vector2) -> Vector2:
	return closest_on_layers(owner, world_pos, owner.NAV_LAYER_WATER)


static func nearest_ground_point(owner: Node, from: Vector2) -> Vector2:
	var shore := closest_on_layers(owner, from, owner.NAV_LAYER_GROUND)
	if shore == Vector2.INF:
		return Vector2.INF
	if from.distance_to(shore) > owner.WATER_TRANSPORT_DISEMBARK_TRIGGER_DIST:
		return Vector2.INF

	var toward_shore := shore - from
	if toward_shore.length_squared() < 1.0:
		return shore

	var pushed: Vector2 = shore + toward_shore.normalized() * owner.WATER_TRANSPORT_DISEMBARK_MIN_CLEARANCE
	var land_point := closest_on_layers(owner, pushed, owner.NAV_LAYER_GROUND)
	if land_point == Vector2.INF:
		return shore
	if from.distance_to(land_point) > owner.WATER_TRANSPORT_DISEMBARK_MAX_DIST:
		return shore
	return land_point


static func can_disembark_at(owner: Node, world_pos: Vector2) -> bool:
	return nearest_ground_point(owner, world_pos) != Vector2.INF


static func collect_nav_regions(node: Node, out: Array) -> void:
	if node is NavigationRegion2D:
		out.append(node)
	for child in node.get_children():
		collect_nav_regions(child, out)
