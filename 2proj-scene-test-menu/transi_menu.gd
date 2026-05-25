extends TextureButton

@onready var transition_rect = $"../ColorRect" 

func _on_pressed():
	# 1. Disparition (Fade Out)
	var tween = create_tween()
	tween.tween_property(transition_rect, "modulate:a", 1.0, 2.0)
	await tween.finished
	
	# 2. Chargement de la nouvelle scène
	var next_scene = load("res://book-menu.tscn").instantiate()
	get_tree().root.add_child(next_scene)
	get_tree().current_scene = next_scene
	
	# 3. On donne le rectangle noir au menu et on détruit la victoire
	transition_rect.reparent(next_scene)
	owner.queue_free() # La scène de victoire est définitivement supprimée ici !
	
	# 4. Apparition (Fade In) sur la nouvelle scène
	var tween_in = create_tween()
	tween_in.tween_property(transition_rect, "modulate:a", 0.0, 2.0)
	await tween_in.finished
	
	# 5. Nettoyage du rectangle noir devenu inutile
	transition_rect.queue_free()
