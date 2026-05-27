extends RefCounted
class_name PlayerNetworkController


static func deal_combat_damage(owner: Node, cible: Node, degats: int) -> void:
	if not cible.has_method("take_damage"):
		return
	if MapSession.is_online_match and OnlineGameSync.is_online_active():
		if MapSession.is_local_team(owner.team):
			var target_sync: int = int(cible.get("net_sync_id")) if cible.get("net_sync_id") != null else -1
			if target_sync >= 0:
				cible.take_damage(degats, owner, owner.team)
				if owner.net_sync_id >= 0:
					OnlineGameSync.report_damage(owner.net_sync_id, target_sync, degats, int(owner.team))
				return
		if bool(cible.get("net_remote_proxy")):
			return
	cible.take_damage(degats, owner, owner.team)


static func take_damage_network_remote(owner: Node, montant: int, auteur_team: int) -> void:
	owner._network_damage = true
	owner.take_damage(montant, null, auteur_team)
	owner._network_damage = false


static func apply_network_order(owner: Node, move_to: Vector2, target: Node) -> void:
	owner.net_remote_proxy = true
	if is_instance_valid(target) and target.has_method("take_damage"):
		owner.attack_target_node = target as Node2D
		owner.agent_navigation.target_position = target.global_position
	else:
		owner.attack_target_node = null
		owner.agent_navigation.target_position = move_to


static func apply_network_state(owner: Node, pos: Vector2, vel: Vector2, hp: int) -> void:
	owner._net_target_position = pos
	owner._net_lerp_active = true
	owner.velocity = vel
	if hp >= 0:
		owner.current_hp = mini(hp, owner.hp_max)
		if owner.has_node("ProgressBar"):
			owner.get_node("ProgressBar").value = owner.current_hp


static func force_network_death(owner: Node) -> void:
	if owner.is_dying:
		return
	owner.die(null, -1)


static func physics_process_network_proxy(owner: Node, delta: float) -> void:
	if owner._net_lerp_active:
		owner.global_position = owner.global_position.lerp(owner._net_target_position, clampf(delta * 9.0, 0.0, 1.0))
		if owner.global_position.distance_to(owner._net_target_position) < 4.0:
			owner._net_lerp_active = false
	if is_instance_valid(owner.attack_target_node):
		owner.agent_navigation.target_position = owner.attack_target_node.global_position
		if owner.attack_target_node in owner.zone_detection.get_overlapping_bodies():
			owner._on_timer_attaque_timeout()
	owner.update_animation()
