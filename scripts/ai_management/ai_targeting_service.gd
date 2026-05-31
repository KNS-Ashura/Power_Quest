class_name AITargetingService
extends RefCounted

var mgr: Node
var camps: AICampService


func _init(manager: Node, camp_service: AICampService) -> void:
	mgr = manager
	camps = camp_service


func is_hostile_site(team: int) -> bool:
	return team == AIConstants.TEAM_PLAYER or team == AIConstants.TEAM_NEUTRAL


func has_regional_hostile(origin: Node2D) -> bool:
	return nearest_hostile_to(origin, camps.region_for_site(origin), true) != null


func nearest_hostile_in_region_sites(origin: Node2D, region_id: int) -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for site in RegionManager.get_sites_for_region(region_id):
		if not is_instance_valid(site) or not (site is Node2D):
			continue
		if not is_hostile_site(int(site.get("team"))):
			continue
		var site_2d: Node2D = site as Node2D
		var d2: float = origin.global_position.distance_squared_to(site_2d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = site_2d
	return best


func nearest_hostile_outside_region_sites(origin: Node2D, region_id: int) -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for camp in camps.hostile_camps():
		if not is_instance_valid(camp) or not (camp is Node2D):
			continue
		var camp_region: int = RegionManager.get_region_id_for_site(camp)
		if camp_region == region_id:
			continue
		var camp_2d: Node2D = camp as Node2D
		var d2: float = origin.global_position.distance_squared_to(camp_2d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = camp_2d
	return best


func nearest_hostile_to(origin: Node2D, region_id: int = -1, same_region: bool = true) -> Node2D:
	if region_id < 0:
		region_id = camps.region_for_site(origin)
	if camps.uses_regions() and region_id >= 0:
		if same_region:
			return nearest_hostile_in_region_sites(origin, region_id)
		return nearest_hostile_outside_region_sites(origin, region_id)
	return nearest_hostile_global(origin)


func nearest_hostile_global(origin: Node2D) -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for camp in camps.hostile_camps():
		if not is_instance_valid(camp) or not (camp is Node2D):
			continue
		var camp_2d: Node2D = camp as Node2D
		var d2: float = origin.global_position.distance_squared_to(camp_2d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = camp_2d
	return best


func pick_transport_target(origin: Node2D, region_id: int) -> Node2D:
	var outside: Node2D = nearest_hostile_to(origin, region_id, false)
	if outside != null:
		return outside
	if nearest_hostile_in_region_sites(origin, region_id) != null:
		return null
	var global_target: Node2D = nearest_hostile_global(origin)
	if global_target == null:
		return null
	if camps.uses_regions() and region_id >= 0 and camps.region_for_site(global_target) == region_id:
		return null
	return global_target


func resolve_target(target_id: int, origin: Node2D, mode: String, region_id: int) -> Node2D:
	if target_id >= 0:
		var obj: Variant = instance_from_id(target_id)
		if is_instance_valid(obj) and obj is Node2D:
			if target_valid_for_mode(origin, obj as Node2D, mode, region_id):
				return obj as Node2D
	if origin == null:
		return null
	match mode:
		AIConstants.SQUAD_MODE_NAVAL:
			return nearest_hostile_to(origin, region_id, false)
		AIConstants.SQUAD_MODE_ATTACK:
			return nearest_hostile_to(origin, region_id, true)
		_:
			return null


func target_valid_for_mode(origin: Node2D, target: Node2D, mode: String, region_id: int) -> bool:
	if not is_hostile_site(int(target.get("team"))):
		return false
	if not camps.uses_regions() or region_id < 0:
		return true
	var target_region: int = RegionManager.get_region_id_for_site(target)
	match mode:
		AIConstants.SQUAD_MODE_NAVAL:
			return target_region != region_id
		_:
			return true


func spawn_camp_for_troop(troop: Node2D) -> Node2D:
	var camp_id: int = int(troop.get_meta("ai_home_camp_id", -1))
	if camp_id < 0:
		camp_id = int(troop.get_meta("ai_spawn_camp_id", -1))
	if camp_id < 0:
		return null
	var camp_obj: Variant = instance_from_id(camp_id)
	if is_instance_valid(camp_obj) and camp_obj is Node2D:
		return camp_obj as Node2D
	return null
