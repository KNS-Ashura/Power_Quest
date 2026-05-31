class_name AICampService
extends RefCounted

var mgr: Node


func _init(manager: Node) -> void:
	mgr = manager


func apply_build_speed(camps: Array) -> void:
	var speed: float = float(mgr._profile.get("build_speed", 1.0))
	for camp in camps:
		if is_instance_valid(camp):
			camp.ai_build_speed_multiplier = speed


func sync_ai_camp_connections() -> void:
	for camp in owned_camps():
		if not is_instance_valid(camp):
			continue
		var camp_id: int = camp.get_instance_id()
		if mgr._connected_camps.has(camp_id):
			continue
		if camp.has_signal("unit_produced") \
				and not camp.unit_produced.is_connected(mgr._on_camp_unit_produced):
			camp.unit_produced.connect(mgr._on_camp_unit_produced.bind(camp))
		mgr._connected_camps[camp_id] = true


func sync_camp_capture_listeners() -> void:
	for camp in mgr.get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(camp):
			continue
		var camp_id: int = camp.get_instance_id()
		if mgr._capture_listeners.has(camp_id):
			continue
		if camp.has_signal("site_captured") \
				and not camp.site_captured.is_connected(mgr._on_site_captured):
			camp.site_captured.connect(mgr._on_site_captured.bind(camp))
		mgr._capture_listeners[camp_id] = true


func refresh_ai_owned_camps() -> void:
	mgr._ai_owned_camp_ids.clear()
	for camp in owned_camps():
		if is_instance_valid(camp):
			mgr._ai_owned_camp_ids[camp.get_instance_id()] = true


func on_site_captured(new_team: int, camp: Node) -> void:
	if MapSession.is_online_match or not is_instance_valid(camp):
		return
	var camp_id: int = camp.get_instance_id()
	var was_ai: bool = mgr._ai_owned_camp_ids.has(camp_id)

	if int(new_team) == AIConstants.TEAM_AI:
		mgr._ai_owned_camp_ids[camp_id] = true
		if mgr.healers.maintains_camp_healers() and is_land_camp(camp):
			mgr.call_deferred("_deferred_ensure_camp_healer", camp)
	elif was_ai:
		mgr._ai_owned_camp_ids.erase(camp_id)
		mgr._camp_healer_granted.erase(camp_id)
		mgr._camp_healer_units.erase(camp_id)
		mgr._pending_dedicated_healer.erase(camp_id)
		mgr.squads.grant_spawn_credit()


func owned_camps() -> Array:
	return camps_for_team(AIConstants.TEAM_AI)


func owned_ports() -> Array:
	var result: Array = []
	for camp in owned_camps():
		if is_instance_valid(camp) and camp.has_method("is_port") and camp.is_port():
			result.append(camp)
	return result


func camps_for_team(team: int) -> Array:
	var result: Array = []
	for node in mgr.get_tree().get_nodes_in_group("camps"):
		if is_instance_valid(node) and int(node.get("team")) == team:
			result.append(node)
	return result


func land_camps(camps: Array) -> Array:
	var result: Array = []
	for camp in camps:
		if is_instance_valid(camp) and (not camp.has_method("is_port") or not camp.is_port()):
			result.append(camp)
	return result


func hostile_camps() -> Array:
	var result: Array = []
	for team in [AIConstants.TEAM_PLAYER, AIConstants.TEAM_NEUTRAL]:
		result.append_array(camps_for_team(team))
	return result


func is_land_camp(camp: Node) -> bool:
	return is_instance_valid(camp) and (not camp.has_method("is_port") or not camp.is_port())


func region_for_site(site: Node) -> int:
	if RegionManager.has_regions_for_current_map():
		return RegionManager.get_region_id_for_site(site)
	return -1


func uses_regions() -> bool:
	return RegionManager.has_regions_for_current_map()


func is_land_reachable(from_site: Node, to_site: Node) -> bool:
	return RegionManager.is_land_reachable_between(from_site, to_site)


func guardian(camp: Node2D) -> Node2D:
	var g: Variant = camp.get("guardian")
	if is_instance_valid(g) and g is Node2D:
		return g
	return null
