extends CharacterBody2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if is_instance_valid(sprite):
		sprite.animation_finished.connect(_on_animation_finished)


func play_impact(direction: String) -> void:
	if not is_instance_valid(sprite):
		queue_free()
		return

	var anim = direction
	if anim == "b":
		anim = "d"
	if not sprite.sprite_frames or not sprite.sprite_frames.has_animation(anim):
		anim = "f"
	sprite.play(anim)


func _on_animation_finished() -> void:
	queue_free()
