extends HBoxContainer

var img_victory = preload("res://assets/menu/img-sur-mesure/scene_profil/victory.tres")
var img_defeat = preload("res://assets/menu/img-sur-mesure/scene_profil/defeat.tres")

var history: Array = []


func _ready() -> void:
	NetworkSession.profile_updated.connect(_on_profile_updated)
	NetworkSession.session_closed.connect(_clear_history)
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 3)
	populate_history()


func _on_profile_updated(profile: Dictionary) -> void:
	var recent_value: Variant = profile.get("recent", [])
	var recent: Array = []
	if typeof(recent_value) == TYPE_ARRAY:
		recent = recent_value as Array
	elif typeof(recent_value) == TYPE_DICTIONARY:
		recent = (recent_value as Dictionary).get("items", []) as Array
	history.clear()
	for item in recent:
		var value: Variant = item
		if typeof(item) == TYPE_DICTIONARY:
			value = item.get("result", item.get("outcome", ""))
		history.append("V" if str(value).to_upper() == "W" else "D")
	populate_history()


func _clear_history() -> void:
	history.clear()
	populate_history()


func populate_history() -> void:
	var slots = get_children()

	var border_style = StyleBoxFlat.new()
	border_style.draw_center = false
	border_style.border_width_left = 1
	border_style.border_width_top = 1
	border_style.border_width_right = 1
	border_style.border_width_bottom = 1
	border_style.border_color = Color("#d4af37")

	for i in range(slots.size()):
		var slot = slots[i]

		if i < history.size():
			slot.texture = img_victory if history[i] == "V" else img_defeat
			slot.custom_minimum_size = Vector2(20, 20)
			slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot.stretch_mode = TextureRect.STRETCH_SCALE
			slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if not slot.has_node("Bordure"):
				var border = Panel.new()
				border.name = "Bordure"
				border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				border.add_theme_stylebox_override("panel", border_style)
				border.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot.add_child(border)
			slot.show()
		else:
			slot.hide()
