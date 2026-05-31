class_name AITroopService
extends RefCounted

var mgr: Node
var camps: AICampService
var targeting: AITargetingService


func _init(manager: Node, camp_service: AICampService, targeting_service: AITargetingService) -> void:
	mgr = manager
	camps = camp_service
	targeting = targeting_service


func bot_attack() -> void:
	for troop in ai_troops():
		if not is_instance_valid(troop):
			continue
		if unit_type(troop) == UnitStats.UnitType.WATER_TRANSPORT:
			if troop.get_meta("ai_transport_mission", false):
				continue
			continue

		if troop.get_meta("ai_camp_healer", false):
			var home_camp: Node2D = targeting.spawn_camp_for_troop(troop)
			if home_camp != null \
					and troop.global_position.distance_to(home_camp.global_position) > AIConstants.DEFEND_HOLD_RADIUS:
				order_defend(troop, home_camp)
			continue

		var mode: String = str(troop.get_meta("ai_squad_mode", AIConstants.SQUAD_MODE_ATTACK))
		var spawn_camp: Node2D = targeting.spawn_camp_for_troop(troop)
		var region_id: int = int(troop.get_meta("ai_spawn_region_id", -1))

		if mode == AIConstants.SQUAD_MODE_DEFEND:
			if spawn_camp != null \
					and troop.global_position.distance_to(spawn_camp.global_position) > AIConstants.DEFEND_HOLD_RADIUS:
				order_defend(troop, spawn_camp)
			continue

		var target: Node2D = null
		var squad_id: int = int(troop.get_meta("ai_squad_id", -1))
		if squad_id >= 0 and mgr._squads.has(squad_id):
			var squad: Dictionary = mgr._squads[squad_id]
			target = targeting.resolve_target(
				int(squad.get("target_id", -1)),
				spawn_camp if spawn_camp != null else troop,
				mode,
				int(squad.get("region_id", region_id))
			)
		if target == null and spawn_camp != null:
			match mode:
				AIConstants.SQUAD_MODE_NAVAL:
					target = targeting.nearest_hostile_to(spawn_camp, region_id, false)
				_:
					target = targeting.nearest_hostile_to(spawn_camp, region_id, true)
		if target == null:
			continue

		var target_id: int = target.get_instance_id()
		if troop_needs_new_order(troop, target_id):
			if mode == AIConstants.SQUAD_MODE_NAVAL or is_naval_unit(troop):
				order_naval(troop, target)
			else:
				order_attack(troop, target)


func bot_spells() -> void:
	for troop in ai_troops():
		if not is_instance_valid(troop):
			continue
		if not troop.has_method("can_cast_spell") or not troop.has_method("cast_spell"):
			continue
		if not troop.can_cast_spell():
			continue
		if not troop_in_combat(troop):
			continue
		troop.cast_spell()


func order_attack(troop: Node2D, target_camp: Node2D) -> void:
	troop.set_meta("ai_camp_target", target_camp.get_instance_id())
	var guardian: Node2D = camps.guardian(target_camp)
	if guardian != null and troop.has_method("attack_target"):
		troop.attack_target(guardian)
	elif troop.has_method("move_to"):
		troop.move_to(target_camp.global_position)


func order_naval(troop: Node2D, target_camp: Node2D) -> void:
	troop.set_meta("ai_camp_target", target_camp.get_instance_id())
	var guardian: Node2D = camps.guardian(target_camp)
	if guardian != null and troop.has_method("attack_target"):
		troop.attack_target(guardian)
	elif troop.has_method("move_to"):
		troop.move_to(target_camp.global_position)


func order_defend(troop: Node2D, camp: Node2D) -> void:
	troop.set_meta("ai_camp_target", -1)
	if troop.has_method("move_to"):
		var offset := Vector2(randf_range(-40.0, 40.0), randf_range(-20.0, 20.0))
		troop.move_to(camp.global_position + offset)


func troop_needs_new_order(troop: Node2D, target_camp_id: int) -> bool:
	if int(troop.get_meta("ai_camp_target", -1)) != target_camp_id:
		return true
	var attack_node: Variant = troop.get("attack_target_node")
	if is_instance_valid(attack_node) and attack_node is Node2D:
		if troop.has_method("_is_valid_combat_target") and troop._is_valid_combat_target(attack_node):
			return false
	if troop.has_method("get") and troop.get("agent_navigation") is NavigationAgent2D:
		var agent: NavigationAgent2D = troop.agent_navigation
		if not agent.is_navigation_finished():
			return false
	return true


func troop_in_combat(troop: Node2D) -> bool:
	if troop.get("attack_target_node") != null:
		var target: Variant = troop.attack_target_node
		if is_instance_valid(target) and target is Node2D:
			return true
	if troop.has_method("get") and troop.get("zone_detection") is Area2D:
		var zone: Area2D = troop.zone_detection
		for body in zone.get_overlapping_bodies():
			if not is_instance_valid(body) or body == troop:
				continue
			if body.is_in_group("camps"):
				continue
			if body.has_method("take_damage") and NodeTeamUtils.is_enemy_of(body, AIConstants.TEAM_AI):
				return true
	return false


func ai_troops() -> Array[Node2D]:
	var troops: Array[Node2D] = []
	for node in mgr.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node) and node is Node2D:
			troops.append(node)
	return troops


func is_naval_unit(troop: Node2D) -> bool:
	var ut: int = unit_type(troop)
	return ut == UnitStats.UnitType.WATER_TANK \
		or ut == UnitStats.UnitType.WATER_RANGE \
		or ut == UnitStats.UnitType.WATER_TRANSPORT


func unit_type(troop: Node2D) -> int:
	var stats_variant: Variant = troop.get("stats")
	if stats_variant is UnitStats:
		return int((stats_variant as UnitStats).unit_type)
	return -1
