extends CharacterBody2D

const DirectionUtilsRef = preload("res://scripts/common/direction_utils.gd")
const ProjectileDamageUtilsRef = preload("res://scripts/combat/projectile_damage_utils.gd")

var target: Node2D = null
var damage: int = 0
const SPEED_DEFAULT := 820.0
var speed: float = SPEED_DEFAULT
var shooter: Node2D = null
var shooter_team: int = -1
var already_hit: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func launch(target_node: Node2D, projectile_damage: int, shooter_node: Node2D = null, projectile_speed: float = -1.0) -> void:
	target = target_node
	damage = projectile_damage
	shooter = shooter_node
	if projectile_speed > 0.0:
		speed = projectile_speed
	if is_instance_valid(shooter) and shooter.get("team") != null:
		shooter_team = shooter.team
	_apply_visible_colors()
	_set_direction_animation()


func _apply_visible_colors() -> void:
	var tint := Color(1.2, 1.2, 1.2, 1.0)
	if scene_file_path.contains("water-range"):
		tint = Color(0.55, 1.35, 1.45, 1.0)
	modulate = Color.WHITE
	if is_instance_valid(sprite):
		sprite.modulate = tint
		sprite.self_modulate = Color.WHITE
		sprite.z_index = 8


func _process(delta: float) -> void:
	if already_hit:
		return
	if not is_instance_valid(target):
		queue_free()
		return

	var dir = global_position.direction_to(target.global_position)
	global_position += dir * speed * delta
	_set_direction_animation()

	if global_position.distance_to(target.global_position) < 14.0:
		_impact()


func _impact() -> void:
	if already_hit:
		return
	already_hit = true

	if is_instance_valid(target):
		ProjectileDamageUtilsRef.apply_synced_damage(target, damage, shooter, shooter_team)
	queue_free()


func _set_direction_animation() -> void:
	if not is_instance_valid(sprite):
		return
	var delta_vec: Vector2 = (target.global_position - global_position) if is_instance_valid(target) else Vector2.DOWN
	var dir: String = DirectionUtilsRef.direction_from_vector(delta_vec)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(dir):
		sprite.play(dir)
