extends Node2D

@onready var selection_box = $BoiteSelection
@onready var camera = $Camera2D

var is_selecting: bool = false
var start_point: Vector2 = Vector2.ZERO
var selected_building: Node2D = null

signal selected_building_changed(building)

@export var camera_speed: float = 400.0
@export var zoom_speed: float = 0.1
var target_zoom: float = 1.0
var zoom_min: float = 0.5
var zoom_max: float = 2.0


func _ready() -> void:
	selection_box.hide()
	add_to_group("manager_rts")
	if camera:
		camera.make_current()


func _process(delta: float) -> void:
	_handle_camera_movement(delta)
	_handle_camera_zoom(delta)


func _handle_camera_movement(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1

	if dir != Vector2.ZERO:
		camera.global_position += dir.normalized() * camera_speed * delta * (1.0 / camera.zoom.x)


func _handle_camera_zoom(delta: float) -> void:
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), 10.0 * delta)


func _unhandled_input(event: InputEvent) -> void:
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
