extends Node2D

func _on_option_button_item_selected(index: int) -> void:
	
	match index:
		0:
			TranslationServer.set_locale("en")
		1:
			TranslationServer.set_locale("fr")
		2:
			TranslationServer.set_locale("de")
