extends CanvasLayer

const TEX_NORMAL := preload("res://assets/menu/img-sur-mesure/scene_multi/bouton.tres")
const TEX_ACTIVE := preload("res://assets/menu/img-sur-mesure/scene_multi/bouton_inverse.tres")

@onready var btn_region_1: TextureButton = $Root/BtnRegion1
@onready var btn_region_2: TextureButton = $Root/BtnRegion2
@onready var btn_region_3: TextureButton = $Root/BtnRegion3

var _active_region_id: int = -1


func _ready() -> void:
	add_to_group("region_ui")
	if not RegionManager.regions_ready.is_connected(_refresh_button_states):
		RegionManager.regions_ready.connect(_refresh_button_states)
	if not RegionManager.region_captured.is_connected(_on_region_control_changed):
		RegionManager.region_captured.connect(_on_region_control_changed)
	if RegionManager.has_regions_for_current_map():
		_refresh_button_states()
	else:
		call_deferred("_wait_for_regions_ready")


func _wait_for_regions_ready() -> void:
	for _attempt in range(60):
		if RegionManager.has_regions_for_current_map():
			_refresh_button_states()
			return
		await get_tree().process_frame
	_refresh_button_states()


func _on_region_control_changed(_region_id: int, _team: int, _name: String = "") -> void:
	_refresh_button_states()


func _on_btn_region_1_pressed() -> void:
	_on_region_pressed(1)


func _on_btn_region_2_pressed() -> void:
	_on_region_pressed(2)


func _on_btn_region_3_pressed() -> void:
	_on_region_pressed(3)


func _on_region_pressed(region_id: int) -> void:
	if not RegionManager.has_regions_for_current_map():
		return
	if not RegionManager.has_region(region_id):
		return
	Sound.play_menu1()
	if _active_region_id == region_id:
		RegionManager.hide_region_see(region_id)
		_active_region_id = -1
		Sound.play_menu2()
	else:
		if _active_region_id >= 0:
			RegionManager.hide_region_see(_active_region_id)
		RegionManager.show_region_see(region_id)
		_active_region_id = region_id
	RegionManager.set_minimap_region_filter(_active_region_id)
	_refresh_button_states()


func _refresh_button_states() -> void:
	var has_regions := RegionManager.has_regions_for_current_map()
	visible = has_regions
	if not has_regions:
		return
	for i in range(1, 4):
		var btn: TextureButton = [btn_region_1, btn_region_2, btn_region_3][i - 1]
		var enabled := RegionManager.has_region(i)
		btn.disabled = not enabled
		btn.texture_normal = TEX_ACTIVE if _active_region_id == i else TEX_NORMAL
		btn.modulate = Color.WHITE if enabled else Color(0.55, 0.55, 0.55, 0.85)
		_set_button_text(btn, _region_button_label(i))


func _region_button_label(region_id: int) -> String:
	var name := RegionManager.region_name(region_id)
	if name.is_empty():
		return "Region %d" % region_id
	return name


func _set_button_text(btn: TextureButton, text: String) -> void:
	var label := btn.get_node_or_null("Label") as Label
	if label:
		label.text = text
