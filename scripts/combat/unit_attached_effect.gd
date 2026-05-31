extends Node2D

const BUFF_EFFECT_NODE_NAME := "BuffEffectVfx"

@onready var _sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func start(duration: float) -> void:
	if duration <= 0.0:
		queue_free()
		return
	z_index = 10
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(queue_free, CONNECT_ONE_SHOT)
	_play_animation()


func _play_animation() -> void:
	if not is_instance_valid(_sprite) or _sprite.sprite_frames == null:
		return
	_sprite.modulate = Color(1.15, 1.15, 1.15, 1.0)
	for anim_name in ["double effect", "effect", "b", "f", "l", "r"]:
		if _sprite.sprite_frames.has_animation(anim_name):
			_sprite.sprite_frames.set_animation_loop(anim_name, true)
			_sprite.play(anim_name)
			return


func _process(_delta: float) -> void:
	if not is_instance_valid(get_parent()):
		queue_free()
