extends CharacterBody2D

var target: Node2D = null
var heal_amount: int = 0
const SPEED_DEFAULT := 820.0
var speed: float = SPEED_DEFAULT
var shooter: Node2D = null
var already_hit: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func launch(target_node: Node2D, amount: int, shooter_node: Node2D = null) -> void:
	target = target_node
	heal_amount = amount
	shooter = shooter_node
	_appliquer_couleurs_visibles()
	_set_direction_animation()


func _appliquer_couleurs_visibles() -> void:
	modulate = Color.WHITE
	if is_instance_valid(sprite):
		sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)
		sprite.self_modulate = Color.WHITE


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

	if is_instance_valid(target) and is_instance_valid(shooter):
		if target.get("team") != null and shooter.get("team") != null and target.team == shooter.team:
			if "current_hp" in target and "hp_max" in target and target.current_hp < target.hp_max:
				target.current_hp = min(target.hp_max, target.current_hp + heal_amount)
				if target.has_node("ProgressBar"):
					target.get_node("ProgressBar").value = target.current_hp
	queue_free()


func _set_direction_animation() -> void:
	if not is_instance_valid(sprite):
		return
	var delta_vec = (target.global_position - global_position) if is_instance_valid(target) else Vector2.DOWN
	var dir = _direction_from_vector(delta_vec)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(dir):
		sprite.play(dir)


func _direction_from_vector(delta_vec: Vector2) -> String:
	if abs(delta_vec.y) >= abs(delta_vec.x):
		return "b" if delta_vec.y < 0 else "f"
	return "l" if delta_vec.x < 0 else "r"
