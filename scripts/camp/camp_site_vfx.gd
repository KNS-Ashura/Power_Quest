extends Node2D

@export var animation_name: String = ""

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	z_index = 64
	_play_once()


func _play_once() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		queue_free()
		return

	var anim: StringName = StringName(animation_name) if animation_name != "" else _sprite.animation
	if anim == StringName("") or not _sprite.sprite_frames.has_animation(anim):
		var names: PackedStringArray = _sprite.sprite_frames.get_animation_names()
		if names.is_empty():
			queue_free()
			return
		anim = StringName(names[0])

	_sprite.sprite_frames.set_animation_loop(anim, false)
	_sprite.play(anim)
	if not _sprite.animation_finished.is_connected(_on_animation_finished):
		_sprite.animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	queue_free()
