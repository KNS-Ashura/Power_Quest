extends CanvasLayer

const JOYSTICK_RADIUS := 58.0
const KNOB_RADIUS := 24.0
const PADDING_LEFT := 24.0
const PADDING_BOTTOM := 24.0

var _root: Control = null
var _base: Panel = null
var _knob: Panel = null
var _center: Vector2 = Vector2.ZERO
var _active_touch_id: int = -1
var _input_vector: Vector2 = Vector2.ZERO
var _manager: Node = null


func _ready() -> void:
	if not _is_mobile_runtime():
		queue_free()
		return
	layer = 50
	_manager = get_tree().get_first_node_in_group("manager_rts")
	_build_ui()
	_update_layout()
	get_viewport().size_changed.connect(_update_layout)
	set_process(true)


func _process(_delta: float) -> void:
	if _manager == null or not is_instance_valid(_manager):
		_manager = get_tree().get_first_node_in_group("manager_rts")
	if _manager != null and _manager.has_method("set_virtual_camera_input"):
		_manager.set_virtual_camera_input(_input_vector)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			if _active_touch_id == -1 and _can_capture_touch(touch_event.position):
				_active_touch_id = touch_event.index
				_update_input_from_position(touch_event.position)
				get_viewport().set_input_as_handled()
		elif touch_event.index == _active_touch_id:
			_active_touch_id = -1
			_reset_input()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _active_touch_id:
			_update_input_from_position(drag_event.position)
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "MobileJoystickRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_base = Panel.new()
	_base.name = "JoystickBase"
	_base.custom_minimum_size = Vector2.ONE * (JOYSTICK_RADIUS * 2.0)
	_base.size = _base.custom_minimum_size
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(0.09, 0.09, 0.12, 0.45)
	base_style.border_color = Color(0.95, 0.95, 1.0, 0.35)
	base_style.border_width_left = 2
	base_style.border_width_top = 2
	base_style.border_width_right = 2
	base_style.border_width_bottom = 2
	base_style.corner_radius_top_left = int(JOYSTICK_RADIUS)
	base_style.corner_radius_top_right = int(JOYSTICK_RADIUS)
	base_style.corner_radius_bottom_left = int(JOYSTICK_RADIUS)
	base_style.corner_radius_bottom_right = int(JOYSTICK_RADIUS)
	_base.add_theme_stylebox_override("panel", base_style)
	_root.add_child(_base)

	_knob = Panel.new()
	_knob.name = "JoystickKnob"
	_knob.custom_minimum_size = Vector2.ONE * (KNOB_RADIUS * 2.0)
	_knob.size = _knob.custom_minimum_size
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = Color(0.83, 0.89, 1.0, 0.55)
	knob_style.border_color = Color(1, 1, 1, 0.55)
	knob_style.border_width_left = 2
	knob_style.border_width_top = 2
	knob_style.border_width_right = 2
	knob_style.border_width_bottom = 2
	knob_style.corner_radius_top_left = int(KNOB_RADIUS)
	knob_style.corner_radius_top_right = int(KNOB_RADIUS)
	knob_style.corner_radius_bottom_left = int(KNOB_RADIUS)
	knob_style.corner_radius_bottom_right = int(KNOB_RADIUS)
	_knob.add_theme_stylebox_override("panel", knob_style)
	_root.add_child(_knob)


func _update_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var base_pos := Vector2(PADDING_LEFT, viewport_size.y - PADDING_BOTTOM - JOYSTICK_RADIUS * 2.0)
	_base.position = base_pos
	_center = base_pos + Vector2.ONE * JOYSTICK_RADIUS
	_update_knob_visual(_center)


func _can_capture_touch(screen_pos: Vector2) -> bool:
	return screen_pos.distance_to(_center) <= JOYSTICK_RADIUS * 1.5


func _update_input_from_position(screen_pos: Vector2) -> void:
	var delta := screen_pos - _center
	if delta.length() > JOYSTICK_RADIUS:
		delta = delta.normalized() * JOYSTICK_RADIUS
	_input_vector = delta / JOYSTICK_RADIUS
	_update_knob_visual(_center + delta)


func _update_knob_visual(knob_center: Vector2) -> void:
	if _knob == null:
		return
	_knob.position = knob_center - Vector2.ONE * KNOB_RADIUS


func _reset_input() -> void:
	_input_vector = Vector2.ZERO
	_update_knob_visual(_center)


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
