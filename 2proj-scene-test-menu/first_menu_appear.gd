extends Node2D

@onready var book_anim = $AnimatedSprite2D
@onready var menu_ui = $MenuContent

@onready var scroll_container = $ScrollContainer

func _ready():
	menu_ui.visible = false
	scroll_container.visible = false 
	book_anim.frame = 0
	
	await get_tree().create_timer(0.5).timeout 
	book_anim.play("Open_book")

func _on_animated_sprite_2d_animation_finished():
	if book_anim.animation == "Open_book":
		menu_ui.visible = true
		scroll_container.visible = true 
		
		var tween = create_tween()
		
		menu_ui.modulate.a = 0
		scroll_container.modulate.a = 0
		
		tween.tween_property(menu_ui, "modulate:a", 1.0, 0.5)
		tween.parallel().tween_property(scroll_container, "modulate:a", 1.0, 0.5)
