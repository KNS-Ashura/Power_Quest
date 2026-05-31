extends Node2D

func _on_option_button_item_selected(index: int) -> void:
	# Via UserPrefs: apply language, persist locally, and sync to account when logged in.
	match index:
		0:
			UserPrefs.set_language("en")
		1:
			UserPrefs.set_language("fr")
		2:
			UserPrefs.set_language("de")
