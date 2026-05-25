extends CharacterBody2D

var target: Node2D = null
var debuff_duration: float = 10.0
var damage_multiplier: float = 2.0
const SPEED_DEFAULT := 120.0
var speed: float = SPEED_DEFAULT
var shooter: Node2D = null
var already_hit: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func launch(target_node: Node2D, duration: float, multiplier: float, shooter_node: Node2D = null, projectile_speed: float = -1.0) -> void:
	target = target_node
	debuff_duration = duration
	damage_multiplier = multiplier
	shooter = shooter_node
	if projectile_speed > 0.0:
		speed = projectile_speed
	_set_direction_animation()


func _process(delta: float) -> void:
	if already_hit:
		return
	if not is_instance_valid(target):
		queue_free()
		return

	var dir := global_position.direction_to(target.global_position)
	global_position += dir * speed * delta
	_set_direction_animation()

	if global_position.distance_to(target.global_position) < 14.0:
		_impact()


func _impact() -> void:
	if already_hit:
		return
	already_hit = true

	if is_instance_valid(target) and target.has_method("receive_anti_armor_spell"):
		target.receive_anti_armor_spell(debuff_duration, damage_multiplier)
	queue_free()


func _set_direction_animation() -> void:
	if not is_instance_valid(sprite):
		return
	var delta_vec := (target.global_position - global_position) if is_instance_valid(target) else Vector2.DOWN
	var dir := _direction_from_vector(delta_vec)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(dir):
		sprite.play(dir)


func _direction_from_vector(delta_vec: Vector2) -> String:
	if abs(delta_vec.y) >= abs(delta_vec.x):
		return "b" if delta_vec.y < 0 else "f"
	return "l" if delta_vec.x < 0 else "r"
