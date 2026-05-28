extends HBoxContainer

var img_victoire = preload("res://assets/menu/img-sur-mesure/scene_profil/victory.tres")
var img_defaite = preload("res://assets/menu/img-sur-mesure/scene_profil/defeat.tres")

var historique: Array = []

func _ready() -> void:
	NetworkSession.profile_updated.connect(_on_profile_updated)
	NetworkSession.session_closed.connect(_clear_history)
	alignment = BoxContainer.ALIGNMENT_CENTER

	add_theme_constant_override("separation", 3) 
	remplir_l_historique()


func _on_profile_updated(profile: Dictionary) -> void:
	var recent_value: Variant = profile.get("recent", [])
	var recent: Array = []
	if typeof(recent_value) == TYPE_ARRAY:
		recent = recent_value
	elif typeof(recent_value) == TYPE_DICTIONARY:
		recent = recent_value.get("items", [])
	historique.clear()
	for item in recent:
		var value: Variant = item
		if typeof(item) == TYPE_DICTIONARY:
			value = item.get("result", item.get("outcome", ""))
		historique.append("V" if str(value).to_upper() == "W" else "D")
	remplir_l_historique()


func _clear_history() -> void:
	historique.clear()
	remplir_l_historique()


func remplir_l_historique() -> void:
	var slots = get_children()

	var style_bordure = StyleBoxFlat.new()
	style_bordure.draw_center = false       
	style_bordure.border_width_left = 1
	style_bordure.border_width_top = 1
	style_bordure.border_width_right = 1
	style_bordure.border_width_bottom = 1
	style_bordure.border_color = Color("#d4af37") 
	

	for i in range(slots.size()):
		var slot = slots[i]

		if i < historique.size():
			slot.texture = img_victoire if historique[i] == "V" else img_defaite
			slot.custom_minimum_size = Vector2(20, 20) 
			slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot.stretch_mode = TextureRect.STRETCH_SCALE 
			slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if not slot.has_node("Bordure"):
				var bordure = Panel.new()
				bordure.name = "Bordure"
				bordure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				bordure.add_theme_stylebox_override("panel", style_bordure)
				bordure.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot.add_child(bordure)
			slot.show()
		else:
			slot.hide()
