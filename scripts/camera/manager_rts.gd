extends Node2D

const MobileCameraJoystickScript = preload("res://scripts/mobile/mobile_camera_joystick.gd")

@onready var selection_box = $BoiteSelection
@onready var camera = $Camera2D

var is_selecting: bool = false
var _is_middle_panning: bool = false
var start_point: Vector2 = Vector2.ZERO
var selected_building: Node2D = null
var _virtual_camera_input: Vector2 = Vector2.ZERO
var _mobile_joystick: CanvasLayer = null

signal selected_building_changed(building)

@export var camera_speed: float = 400.0
@export var zoom_speed: float = 0.1
@export var auto_camera_limits: bool = true
@export var camera_limit_padding: float = 0.0
## Limites manuelles si auto_camera_limits est false.
@export var use_manual_camera_limits: bool = false
@export var manual_limit_rect: Rect2 = Rect2(-3963, -3093, 8242, 6080)

var target_zoom: float = 1.0
var zoom_min: float = 0.5
var zoom_max: float = 2.0
var _world_bounds := Rect2(0, 0, 1920, 1080)
var _camera_limits_ready := false
const BUILDING_CLICK_LAYER := 8


func _ready() -> void:
	selection_box.hide()
	add_to_group("manager_rts")
	if camera:
		camera.make_current()
	_setup_mobile_controls()
	if MapSession.is_online_match:
		if not OnlineMatch.setup_complete.is_connected(_on_online_camps_ready_for_camera):
			OnlineMatch.setup_complete.connect(_on_online_camps_ready_for_camera, CONNECT_ONE_SHOT)
	else:
		call_deferred("_setup_camera_after_map_loaded")


func _on_online_camps_ready_for_camera() -> void:
	await get_tree().process_frame
	_setup_camera_after_map_loaded()


func _setup_camera_after_map_loaded() -> void:
	_refresh_camera_limits()
	focus_on_local_camps()


func focus_on_local_camps() -> void:
	if camera == null:
		return
	var target_camp := _find_primary_local_land_camp()
	if target_camp == null:
		return
	focus_camera_on_world(target_camp.global_position)
	_clamp_camera_to_limits()


func _find_primary_local_land_camp() -> Node2D:
	var fallback_local: Node2D = null
	for camp in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(camp):
			continue
		if not MapSession.is_local_team(int(camp.get("team"))):
			continue
		if fallback_local == null:
			fallback_local = camp as Node2D
		if camp.has_method("is_port") and camp.is_port():
			continue
		return camp as Node2D
	return fallback_local


func get_camera() -> Camera2D:
	return camera


func focus_camera_on_world(world_position: Vector2) -> void:
	if camera == null:
		return
	camera.global_position = world_position
	_clamp_camera_to_limits()


func _refresh_camera_limits() -> void:
	if camera == null:
		return
	if use_manual_camera_limits:
		_world_bounds = manual_limit_rect
	elif auto_camera_limits:
		var slot: Node = get_tree().current_scene.get_node_or_null("MapSlot") if get_tree().current_scene else null
		_world_bounds = MapSession.get_camera_limit_rect(slot)
		if camera_limit_padding > 0.0:
			_world_bounds = _world_bounds.grow(camera_limit_padding)
	else:
		_camera_limits_ready = false
		return
	_camera_limits_ready = _world_bounds.size.length_squared() > 1.0
	if not _camera_limits_ready:
		return
	camera.limit_left = int(_world_bounds.position.x)
	camera.limit_top = int(_world_bounds.position.y)
	camera.limit_right = int(_world_bounds.end.x)
	camera.limit_bottom = int(_world_bounds.end.y)


func _clamp_camera_to_limits() -> void:
	if camera == null or not _camera_limits_ready:
		return
	var viewport_half: Vector2 = get_viewport().get_visible_rect().size * 0.5 / camera.zoom
	var min_pos: Vector2 = _world_bounds.position + viewport_half
	var max_pos: Vector2 = _world_bounds.end - viewport_half
	if min_pos.x > max_pos.x:
		var cx := _world_bounds.get_center().x
		min_pos.x = cx
		max_pos.x = cx
	if min_pos.y > max_pos.y:
		var cy := _world_bounds.get_center().y
		min_pos.y = cy
		max_pos.y = cy
	camera.global_position = camera.global_position.clamp(min_pos, max_pos)


func _process(delta: float) -> void:
	_handle_camera_movement(delta)
	_handle_camera_zoom(delta)


func _handle_camera_movement(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1

	if _virtual_camera_input != Vector2.ZERO:
		dir += _virtual_camera_input

	if dir != Vector2.ZERO:
		camera.global_position += dir.normalized() * camera_speed * delta * (1.0 / camera.zoom.x)
		_clamp_camera_to_limits()


func set_virtual_camera_input(direction: Vector2) -> void:
	_virtual_camera_input = direction.limit_length(1.0)


func _setup_mobile_controls() -> void:
	if not _is_mobile_runtime():
		return
	if _mobile_joystick != null and is_instance_valid(_mobile_joystick):
		return
	var joystick_instance := MobileCameraJoystickScript.new()
	if joystick_instance is CanvasLayer:
		_mobile_joystick = joystick_instance as CanvasLayer
		add_child(_mobile_joystick)


func _is_mobile_runtime() -> bool:
	if OS.has_feature("mobile"):
		return true
	if OS.has_feature("web"):
		if DisplayServer.is_touchscreen_available():
			return true
		if ClassDB.class_exists("JavaScriptBridge"):
			var js := (
				"(function(){"
				+ "const ua=(navigator.userAgent||'').toLowerCase();"
				+ "return /android|iphone|ipad|ipod|mobile|windows phone/.test(ua);"
				+ "})()"
			)
			var result: Variant = JavaScriptBridge.eval(js, true)
			if result != null and bool(result):
				return true
	var os_name := OS.get_name()
	return os_name == "Android" or os_name == "iOS"


func _handle_camera_zoom(delta: float) -> void:
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), 10.0 * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_middle_panning = event.pressed
		if _is_middle_panning:
			is_selecting = false
			selection_box.hide()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_selecting = true
			start_point = get_global_mouse_position()
			selection_box.global_position = start_point
			selection_box.size = Vector2.ZERO
			selection_box.show()
		else:
			is_selecting = false
			selection_box.hide()
			select_units()
			if selection_box.size.length() < 5:
				_handle_building_click()

	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_army_selection_hotkey(event as InputEventKey):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.keycode == KEY_E and event.pressed:
		var spell_cast := false
		for soldier in get_tree().get_nodes_in_group("soldiers"):
			if not soldier.get("is_selected"):
				continue
			if soldier.has_method("can_cast_spell") and not soldier.can_cast_spell():
				continue
			if soldier.has_method("cast_spell") and soldier.cast_spell():
				spell_cast = true
		if spell_cast:
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			target_zoom = clamp(target_zoom + zoom_speed, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			target_zoom = clamp(target_zoom - zoom_speed, zoom_min, zoom_max)

	if event is InputEventMouseMotion and is_selecting:
		var pos = get_global_mouse_position()
		selection_box.global_position = Vector2(min(start_point.x, pos.x), min(start_point.y, pos.y))
		selection_box.size = Vector2(abs(pos.x - start_point.x), abs(pos.y - start_point.y))
		if selection_box.size.length() > 10:
			deselect_building()
	elif event is InputEventMouseMotion and _is_middle_panning:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if camera != null:
			camera.global_position -= motion.relative * (1.0 / camera.zoom.x)
			_clamp_camera_to_limits()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var dest = get_global_mouse_position()
		var selection = get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.get("is_selected"))
		var count = selection.size()
		if count == 0:
			return

		var query = PhysicsPointQueryParameters2D.new()
		query.position = dest
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var hits = get_world_2d().direct_space_state.intersect_point(query)
		var target = null

		for res in hits:
			var obj = res.collider
			if obj and obj.has_method("take_damage") and not obj.is_in_group("camps"):
				var t = obj.get("team")
				if t != null and MapSession.is_hostile_team(int(t)):
					target = obj
					break

		if target:
			for soldier in selection:
				if soldier.has_method("attack_target"):
					soldier.attack_target(target)
		else:
			var cols = ceil(sqrt(count))
			var spacing = 24.0
			for i in range(count):
				var offset = Vector2(
					(i % int(cols)) * spacing - (cols - 1) * spacing / 2.0,
					(i / int(cols)) * spacing - (ceil(float(count) / cols) - 1) * spacing / 2.0
				)
				selection[i].move_to(dest + offset)
		_send_network_orders(selection, dest, target)


func _handle_army_selection_hotkey(event: InputEventKey) -> bool:
	if event.keycode == KEY_A:
		_select_all_local_army()
		return true
	if not UnitStats.is_selection_hotkey(event.keycode):
		return false
	_select_units_by_hotkey(event.keycode)
	return true


func _select_all_local_army() -> void:
	deselect_building()
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if not soldier.has_method("set_selection"):
			continue
		var selected := true
		if soldier.has_method("is_selectable_as_local_army"):
			selected = soldier.is_selectable_as_local_army()
		else:
			selected = MapSession.is_local_team(int(soldier.get("team")))
		soldier.set_selection(selected)


func _select_units_by_hotkey(keycode: int) -> void:
	deselect_building()
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if not soldier.has_method("set_selection"):
			continue
		var should_select := false
		if soldier.has_method("matches_selection_hotkey"):
			should_select = soldier.matches_selection_hotkey(keycode)
		soldier.set_selection(should_select)


func select_units() -> void:
	var zone = Rect2(selection_box.global_position, selection_box.size)
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if soldier.has_method("set_selection"):
			var can_select := MapSession.is_local_team(int(soldier.get("team")))
			soldier.set_selection(can_select and zone.has_point(soldier.global_position))


func _send_network_orders(selection: Array, move_to: Vector2, attack_target: Node) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	var sync_ids: Array = []
	for unit in selection:
		if unit.get("net_sync_id") != null and int(unit.net_sync_id) >= 0:
			sync_ids.append(int(unit.net_sync_id))
	if sync_ids.is_empty():
		return
	var attack_sync_id := -1
	if attack_target != null and attack_target.get("net_sync_id") != null:
		attack_sync_id = int(attack_target.net_sync_id)
	OnlineGameSync.report_player_orders(sync_ids, move_to, attack_sync_id)


func _handle_building_click() -> void:
	var query = PhysicsPointQueryParameters2D.new()
	query.position = selection_box.global_position
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = BUILDING_CLICK_LAYER
	var hits = get_world_2d().direct_space_state.intersect_point(query)

	for res in hits:
		if res.collider and res.collider.is_in_group("camps"):
			select_building(res.collider)
			return

	var sel = get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.get("is_selected"))
	if sel.is_empty():
		deselect_building()


func select_building(building) -> void:
	if selected_building:
		deselect_building()
	selected_building = building
	if selected_building.has_method("set_selection"):
		selected_building.set_selection(true)
	selected_building_changed.emit(selected_building)


func deselect_building() -> void:
	if selected_building:
		if selected_building.has_method("set_selection"):
			selected_building.set_selection(false)
		selected_building = null
		selected_building_changed.emit(null)
