extends Node2D

func _on_option_button_item_selected(index: int) -> void:
	# Passe par UserPrefs : applique la langue, la persiste localement et la
	# resynchronise sur le compte si connecté.
	match index:
		0:
			UserPrefs.set_language("en")
		1:
			UserPrefs.set_language("fr")
		2:
			UserPrefs.set_language("de")
