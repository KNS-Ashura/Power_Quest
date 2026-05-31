extends Node2D

@export var animation_name: String = ""
@export var loop_forever: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	z_index = 64
	_start_animation()


func set_team_tint(controlling_team: int) -> void:
	var tint := Color.WHITE
	if controlling_team >= 0 and not MapSession.is_neutral_team(controlling_team):
		if MapSession.is_local_team(controlling_team):
			tint = Color(0.55, 1.35, 0.6)
		else:
			tint = Color(1.35, 0.5, 0.5)
	modulate = tint


func _start_animation() -> void:
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

	_sprite.sprite_frames.set_animation_loop(anim, loop_forever)
	_sprite.play(anim)
	if not loop_forever and not _sprite.animation_finished.is_connected(_on_animation_finished):
		_sprite.animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	queue_free()
