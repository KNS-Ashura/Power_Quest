extends Node2D

const NOM_NOEUD := "BuffEffectVfx"

@onready var _sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func demarrer(duree: float) -> void:
	if duree <= 0.0:
		queue_free()
		return
	z_index = 10
	var timer := get_tree().create_timer(duree)
	timer.timeout.connect(queue_free, CONNECT_ONE_SHOT)
	_jouer_animation()


func _jouer_animation() -> void:
	if not is_instance_valid(_sprite) or _sprite.sprite_frames == null:
		return
	_sprite.modulate = Color(1.15, 1.15, 1.15, 1.0)
	for nom in ["double effect", "effect", "b", "f", "l", "r"]:
		if _sprite.sprite_frames.has_animation(nom):
			_sprite.sprite_frames.set_animation_loop(nom, true)
			_sprite.play(nom)
			return


func _process(_delta: float) -> void:
	if not is_instance_valid(get_parent()):
		queue_free()
