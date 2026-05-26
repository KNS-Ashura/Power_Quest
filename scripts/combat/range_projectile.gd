extends CharacterBody2D

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
	_appliquer_couleurs_visibles()
	_set_direction_animation()


func _appliquer_couleurs_visibles() -> void:
	var teinte := Color(1.2, 1.2, 1.2, 1.0)
	if scene_file_path.contains("water-range"):
		teinte = Color(0.55, 1.35, 1.45, 1.0)
	modulate = Color.WHITE
	if is_instance_valid(sprite):
		sprite.modulate = teinte
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
		_apply_synced_damage(target, damage)
	queue_free()


func _apply_synced_damage(cible: Node, degats: int) -> void:
	if not cible.has_method("take_damage"):
		return
	if MapSession.is_online_match and OnlineGameSync.is_online_active():
		var attacker_id := -1
		if is_instance_valid(shooter) and shooter.get("net_sync_id") != null:
			attacker_id = int(shooter.net_sync_id)
		if MapSession.is_local_team(shooter_team):
			var target_id := int(cible.get("net_sync_id")) if cible.get("net_sync_id") != null else -1
			if target_id >= 0:
				cible.take_damage(degats, shooter, shooter_team)
				if attacker_id >= 0:
					OnlineGameSync.report_damage(attacker_id, target_id, degats, shooter_team)
				return
		if bool(cible.get("net_remote_proxy")):
			return
	cible.take_damage(degats, shooter, shooter_team)


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
