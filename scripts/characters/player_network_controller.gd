extends RefCounted
class_name PlayerNetworkController


static func deal_combat_damage(owner: Node, target: Node, damage: int) -> void:
	if not target.has_method("take_damage"):
		return
	if MapSession.is_online_match and OnlineGameSync.is_online_active():
		if MapSession.is_local_team(owner.team):
			var target_sync: int = int(target.get("net_sync_id")) if target.get("net_sync_id") != null else -1
			if target_sync >= 0:
				target.take_damage(damage, owner, owner.team)
				if owner.net_sync_id >= 0:
					OnlineGameSync.report_damage(owner.net_sync_id, target_sync, damage, int(owner.team))
				return
		if bool(target.get("net_remote_proxy")):
			return
	target.take_damage(damage, owner, owner.team)


static func take_damage_network_remote(owner: Node, amount: int, attacker_team: int) -> void:
	owner._network_damage = true
	owner.take_damage(amount, null, attacker_team)
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
		owner.current_hp = clampi(hp, 0, owner.hp_max)
		if owner.has_node("ProgressBar"):
			owner.get_node("ProgressBar").value = owner.current_hp


static func apply_heal_network_remote(owner: Node, amount: int, caster_sync_id: int) -> void:
	if amount <= 0 or owner.is_dying:
		return
	owner.current_hp = mini(owner.hp_max, owner.current_hp + amount)
	if owner.has_node("ProgressBar"):
		owner.get_node("ProgressBar").value = owner.current_hp
	var caster: Node = OnlineGameSync.get_unit(caster_sync_id)
	if is_instance_valid(caster) and caster.has_method("_attach_heal_effect_on"):
		caster._attach_heal_effect_on(owner)


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
			owner._on_attack_timer_timeout()
	owner.update_animation()
