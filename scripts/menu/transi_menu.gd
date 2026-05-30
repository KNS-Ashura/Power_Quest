extends TextureButton

const _MENU_SCENE := "res://scenes/menu/book-menu.tscn"
const _FADE_DURATION := 1.0


func _on_pressed() -> void:
	disabled = true
	MapSession.reset_online_state()

	var fade := get_node_or_null("../ColorRect") as ColorRect
	if fade != null:
		fade.top_level = true
		fade.visible = true
		fade.global_position = Vector2.ZERO
		fade.size = get_viewport().get_visible_rect().size
		fade.modulate.a = 0.0
		fade.mouse_filter = Control.MOUSE_FILTER_STOP
		var tween := create_tween()
		tween.tween_property(fade, "modulate:a", 1.0, _FADE_DURATION)
		await tween.finished

	GameManager.clear_result_overlay()
	get_tree().change_scene_to_file(_MENU_SCENE)
