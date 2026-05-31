extends RefCounted
class_name PlayerMovementController


static func configure_guardian_mode(owner: Node, anchor_position: Vector2, defense_radius: float, chase_radius: float) -> void:
	owner.is_camp_guardian = true
	owner.guard_position = anchor_position
	owner.guard_defense_radius = defense_radius
	owner.guard_chase_radius = chase_radius
	configure_movement_and_collisions(owner)
	if is_instance_valid(owner.agent_navigation):
		owner.agent_navigation.target_position = owner.guard_position


static func is_guardian_scene(owner: Node) -> bool:
	var scene_path: String = owner.scene_file_path
	return scene_path.contains("/guardian/") or scene_path.contains("/port_guardian/")


static func configure_movement_and_collisions(owner: Node) -> void:
	owner.motion_mode = owner.MOTION_MODE_FLOATING
	owner.floor_stop_on_slope = false
	owner.floor_block_on_wall = false
	owner.safe_margin = 0.035
	apply_team_collision_layers(owner)
	configure_detection_zone(owner)
	configure_collision_shape(owner)
	configure_navigation_avoidance(owner)


static func apply_team_collision_layers(owner: Node) -> void:
	# Relative to the local viewer (supports 2–8 players):
	#  - neutral: detected by everyone, no physical push (original behavior)
	#  - my units: PLAYER layer
	#  - any other player: ENEMY layer
	if MapSession.is_neutral_team(int(owner.team)):
		owner.collision_layer = owner.COLLISION_LAYER_PLAYER_UNIT | owner.COLLISION_LAYER_ENEMY_UNIT
		owner.collision_mask = owner.COLLISION_LAYER_WORLD
	elif MapSession.is_local_team(int(owner.team)):
		owner.collision_layer = owner.COLLISION_LAYER_PLAYER_UNIT
		owner.collision_mask = owner.COLLISION_LAYER_WORLD | owner.COLLISION_LAYER_ENEMY_UNIT
	else:
		owner.collision_layer = owner.COLLISION_LAYER_ENEMY_UNIT
		owner.collision_mask = owner.COLLISION_LAYER_WORLD | owner.COLLISION_LAYER_PLAYER_UNIT


static func configure_detection_zone(owner: Node) -> void:
	if not is_instance_valid(owner.zone_detection):
		return
	owner.zone_detection.collision_layer = 0
	owner.zone_detection.monitorable = false
	owner.zone_detection.monitoring = true
	owner.zone_detection.collision_mask = (
		owner.COLLISION_LAYER_PLAYER_UNIT
		| owner.COLLISION_LAYER_ENEMY_UNIT
		| owner.COLLISION_LAYER_WORLD
	)


static func configure_collision_shape(owner: Node) -> void:
	if not owner.has_node("CollisionShape2D"):
		return
	var shape_node: CollisionShape2D = owner.get_node("CollisionShape2D")
	var shape: Shape2D = shape_node.shape
	if shape is CircleShape2D:
		var circle: CircleShape2D = shape.duplicate()
		if owner.is_camp_guardian or is_guardian_scene(owner):
			circle.radius = owner.GUARDIAN_BODY_RADIUS
		else:
			circle.radius = owner.UNIT_BODY_RADIUS
		shape_node.shape = circle


static func configure_navigation_avoidance(owner: Node) -> void:
	if not is_instance_valid(owner.agent_navigation):
		return
	owner.agent_navigation.avoidance_enabled = true
	var radius: float = owner.GUARDIAN_BODY_RADIUS if (owner.is_camp_guardian or is_guardian_scene(owner)) else owner.UNIT_BODY_RADIUS
	owner.agent_navigation.radius = radius * 0.9
	owner.agent_navigation.neighbor_distance = 70.0
	owner.agent_navigation.max_neighbors = 8
	owner.agent_navigation.time_horizon_agents = 0.45
	owner.agent_navigation.max_speed = owner.unit_speed


static func apply_movement_toward(owner: Node, next_point: Vector2) -> void:
	var desired_velocity: Vector2 = compute_desired_velocity(owner, next_point)
	owner.velocity = desired_velocity
	owner.move_and_slide()
	if owner.get_slide_collision_count() > 0 and owner.velocity.length() < owner.unit_speed * 0.35:
		var slide := Vector2.ZERO
		for i in owner.get_slide_collision_count():
			var normal: Vector2 = owner.get_slide_collision(i).get_normal()
			slide += Vector2(-normal.y, normal.x) * signf(desired_velocity.dot(Vector2(-normal.y, normal.x)))
		if slide.length_squared() > 0.01:
			owner.velocity = slide.normalized() * owner.unit_speed * 0.75
			owner.move_and_slide()


static func compute_desired_velocity(owner: Node, next_point: Vector2) -> Vector2:
	var direction: Vector2 = owner.global_position.direction_to(next_point)
	if direction.length_squared() < 0.0001:
		return Vector2.ZERO
	var velocity: Vector2 = direction * owner.unit_speed
	velocity += compute_ally_repulsion(owner)
	if velocity.length() > owner.unit_speed:
		velocity = velocity.normalized() * owner.unit_speed
	return velocity


static func compute_ally_repulsion(owner: Node) -> Vector2:
	var repulsion := Vector2.ZERO
	var group := "soldiers" if MapSession.is_local_team(owner.team) else "enemies"
	for node in owner.get_tree().get_nodes_in_group(group):
		if node == owner or not (node is CharacterBody2D):
			continue
		if not is_instance_valid(node):
			continue
		if "is_dying" in node and node.is_dying:
			continue
		var offset: Vector2 = owner.global_position - node.global_position
		var distance: float = offset.length()
		if distance < 0.001 or distance > owner.SEPARATION_RADIUS:
			continue
		var intensity: float = (owner.SEPARATION_RADIUS - distance) / owner.SEPARATION_RADIUS
		repulsion += offset.normalized() * intensity * owner.SEPARATION_FORCE
	return repulsion
