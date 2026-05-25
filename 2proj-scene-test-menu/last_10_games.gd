extends HBoxContainer


var img_victoire = preload("res://assets/img-sur-mesure/scene_profil/victory.tres")
var img_defaite = preload("res://assets/img-sur-mesure/scene_profil/defeat.tres")


var historique = ["V", "V", "D", "V", "D", "V", "V", "V", "D", "V"]

func _ready():
	
	alignment = BoxContainer.ALIGNMENT_CENTER

	add_theme_constant_override("separation", 3) 
	
	remplir_l_historique()

func remplir_l_historique():
	
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
				bordure.mouse_filter = Control.MOUSE_FILTER_IGNORE # Ne bloque pas la souris
				slot.add_child(bordure)
			
			slot.show()
		else:
			
			slot.hide()

	print("Historique généré avec succès !")
