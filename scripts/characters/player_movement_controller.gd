extends RefCounted
class_name PlayerMovementController


static func configure_guardian_mode(owner: Node, position_ancre: Vector2, rayon_defense: float, rayon_poursuite: float) -> void:
	owner.is_camp_guardian = true
	owner.guard_position = position_ancre
	owner.guard_defense_radius = rayon_defense
	owner.guard_chase_radius = rayon_poursuite
	configurer_mouvement_et_collisions(owner)
	if is_instance_valid(owner.agent_navigation):
		owner.agent_navigation.target_position = owner.guard_position


static func est_scene_gardien(owner: Node) -> bool:
	var chemin: String = owner.scene_file_path
	return chemin.contains("/guardian/") or chemin.contains("/port_guardian/")


static func configurer_mouvement_et_collisions(owner: Node) -> void:
	owner.motion_mode = owner.MOTION_MODE_FLOATING
	owner.floor_stop_on_slope = false
	owner.floor_block_on_wall = false
	owner.safe_margin = 0.035
	appliquer_calques_collision_equipe(owner)
	configurer_zone_detection(owner)
	configurer_forme_collision(owner)
	configurer_evitement_navigation(owner)


static func appliquer_calques_collision_equipe(owner: Node) -> void:
	# Relatif au spectateur local (supporte 2 à 8 joueurs) :
	#  - neutre  : détecté par tous, sans poussée physique (comportement d'origine)
	#  - mes unités : calque PLAYER
	#  - tout autre joueur : calque ENEMY
	if MapSession.is_neutral_team(int(owner.team)):
		owner.collision_layer = owner.COLLISION_LAYER_PLAYER_UNIT | owner.COLLISION_LAYER_ENEMY_UNIT
		owner.collision_mask = owner.COLLISION_LAYER_WORLD
	elif MapSession.is_local_team(int(owner.team)):
		owner.collision_layer = owner.COLLISION_LAYER_PLAYER_UNIT
		owner.collision_mask = owner.COLLISION_LAYER_WORLD | owner.COLLISION_LAYER_ENEMY_UNIT
	else:
		owner.collision_layer = owner.COLLISION_LAYER_ENEMY_UNIT
		owner.collision_mask = owner.COLLISION_LAYER_WORLD | owner.COLLISION_LAYER_PLAYER_UNIT


static func configurer_zone_detection(owner: Node) -> void:
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


static func configurer_forme_collision(owner: Node) -> void:
	if not owner.has_node("CollisionShape2D"):
		return
	var shape_node: CollisionShape2D = owner.get_node("CollisionShape2D")
	var shape: Shape2D = shape_node.shape
	if shape is CircleShape2D:
		var circle: CircleShape2D = shape.duplicate()
		if owner.is_camp_guardian or est_scene_gardien(owner):
			circle.radius = owner.GUARDIAN_BODY_RADIUS
		else:
			circle.radius = owner.UNIT_BODY_RADIUS
		shape_node.shape = circle


static func configurer_evitement_navigation(owner: Node) -> void:
	if not is_instance_valid(owner.agent_navigation):
		return
	owner.agent_navigation.avoidance_enabled = true
	var rayon: float = owner.GUARDIAN_BODY_RADIUS if (owner.is_camp_guardian or est_scene_gardien(owner)) else owner.UNIT_BODY_RADIUS
	owner.agent_navigation.radius = rayon * 0.9
	owner.agent_navigation.neighbor_distance = 70.0
	owner.agent_navigation.max_neighbors = 8
	owner.agent_navigation.time_horizon_agents = 0.45
	owner.agent_navigation.max_speed = owner.unit_speed


static func appliquer_deplacement_vers(owner: Node, prochain_point: Vector2) -> void:
	var vitesse_desiree: Vector2 = calculer_vitesse_desiree(owner, prochain_point)
	owner.velocity = vitesse_desiree
	owner.move_and_slide()
	if owner.get_slide_collision_count() > 0 and owner.velocity.length() < owner.unit_speed * 0.35:
		var glisse := Vector2.ZERO
		for i in owner.get_slide_collision_count():
			var normale: Vector2 = owner.get_slide_collision(i).get_normal()
			glisse += Vector2(-normale.y, normale.x) * signf(vitesse_desiree.dot(Vector2(-normale.y, normale.x)))
		if glisse.length_squared() > 0.01:
			owner.velocity = glisse.normalized() * owner.unit_speed * 0.75
			owner.move_and_slide()


static func calculer_vitesse_desiree(owner: Node, prochain_point: Vector2) -> Vector2:
	var direction: Vector2 = owner.global_position.direction_to(prochain_point)
	if direction.length_squared() < 0.0001:
		return Vector2.ZERO
	var vitesse: Vector2 = direction * owner.unit_speed
	vitesse += calculer_repulsion_allies(owner)
	if vitesse.length() > owner.unit_speed:
		vitesse = vitesse.normalized() * owner.unit_speed
	return vitesse


static func calculer_repulsion_allies(owner: Node) -> Vector2:
	var repulsion := Vector2.ZERO
	var groupe := "soldiers" if MapSession.is_local_team(owner.team) else "enemies"
	for node in owner.get_tree().get_nodes_in_group(groupe):
		if node == owner or not (node is CharacterBody2D):
			continue
		if not is_instance_valid(node):
			continue
		if "is_dying" in node and node.is_dying:
			continue
		var ecart: Vector2 = owner.global_position - node.global_position
		var distance: float = ecart.length()
		if distance < 0.001 or distance > owner.SEPARATION_RADIUS:
			continue
		var intensite: float = (owner.SEPARATION_RADIUS - distance) / owner.SEPARATION_RADIUS
		repulsion += ecart.normalized() * intensite * owner.SEPARATION_FORCE
	return repulsion
