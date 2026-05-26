extends Area2D

var target: Node2D = null
var damage: int = 0
var speed: float = 450.0
var shooter: Node2D = null
var shooter_team: int = -1


func launch(target_node: Node2D, projectile_damage: int, shooter_node: Node2D = null) -> void:
	target = target_node
	damage = projectile_damage
	shooter = shooter_node
	if is_instance_valid(shooter) and shooter.get("team") != null:
		shooter_team = shooter.team


func _process(delta: float) -> void:
	if is_instance_valid(target):
		var direction = global_position.direction_to(target.global_position)
		look_at(target.global_position)
		global_position += direction * speed * delta

		if global_position.distance_to(target.global_position) < 12:
			_apply_damage()
	else:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body == target:
		_apply_damage()


func _apply_damage() -> void:
	if is_instance_valid(shooter) and "stats" in shooter and shooter.stats != null and shooter.stats.unit_type == 6:
		_mortar_explosion()
	else:
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


func _mortar_explosion() -> void:
	var explosion_radius = 100.0
	var space = get_world_2d().direct_space_state

	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = explosion_radius
	query.shape = circle
	query.transform = Transform2D(0, global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	for res in space.intersect_shape(query):
		var obj = res.collider
		if obj and obj.has_method("take_damage") and not obj.is_in_group("camps"):
			if obj.get("team") != null and obj.get("team") != shooter_team:
				var ratio = max(0.2, 1.0 - clamp(global_position.distance_to(obj.global_position) / explosion_radius, 0.0, 1.0))
				_apply_synced_damage(obj, int(float(damage) * ratio))
