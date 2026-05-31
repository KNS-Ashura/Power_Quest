class_name AIHealerService
extends RefCounted

var mgr: Node
var camps: AICampService


func _init(manager: Node, camp_service: AICampService) -> void:
	mgr = manager
	camps = camp_service


func maintains_camp_healers() -> bool:
	return mgr.current_difficulty == MapSession.AIDifficulty.NORMAL \
		or mgr.current_difficulty == MapSession.AIDifficulty.HARD


func grant_initial_camp_healers() -> void:
	if not maintains_camp_healers():
		return
	for camp in camps.land_camps(camps.owned_camps()):
		ensure_camp_healer(camp)


func ensure_camp_healer(camp: Node) -> void:
	if not is_instance_valid(camp) or not camps.is_land_camp(camp):
		return
	var camp_id: int = camp.get_instance_id()
	if mgr._camp_healer_granted.has(camp_id):
		return
	if camp_has_living_healer(camp_id):
		mgr._camp_healer_granted[camp_id] = true
		return
	if camp_healer_queued(camp):
		return
	if not camp.unit_catalog.has(AIConstants.UNIT_HEAL):
		return
	if camp.has_method("request_ai_production") and camp.request_ai_production(AIConstants.UNIT_HEAL):
		mgr._pending_dedicated_healer[camp_id] = true
		mgr._camp_healer_granted[camp_id] = true


func camp_has_living_healer(camp_id: int) -> bool:
	var healer: Variant = mgr._camp_healer_units.get(camp_id)
	if not is_instance_valid(healer):
		mgr._camp_healer_units.erase(camp_id)
		return false
	if healer is Node2D:
		if healer.get("current_hp") != null and int(healer.current_hp) <= 0:
			mgr._camp_healer_units.erase(camp_id)
			return false
		return true
	return false


func camp_healer_queued(camp: Node) -> bool:
	if not is_instance_valid(camp):
		return false
	var camp_id: int = camp.get_instance_id()
	if mgr._pending_dedicated_healer.has(camp_id):
		return true
	for unit_id in camp.get("production_queue"):
		if int(unit_id) == AIConstants.UNIT_HEAL:
			return true
	return false


func bind_camp_healer(camp_id: int, healer: Node2D, camp: Node2D) -> void:
	if not is_instance_valid(healer):
		return
	var previous: Variant = mgr._camp_healer_units.get(camp_id)
	if is_instance_valid(previous) and previous is Node2D and previous != healer:
		if mgr._camp_healer_units.get(camp_id) == previous:
			mgr._camp_healer_units.erase(camp_id)
	mgr._camp_healer_units[camp_id] = healer
	healer.set_meta("ai_camp_healer", true)
	healer.set_meta("ai_home_camp_id", camp_id)
	if healer.has_signal("killed_by"):
		var callable: Callable = on_camp_healer_killed.bind(healer, camp_id)
		if not healer.killed_by.is_connected(callable):
			healer.killed_by.connect(callable)
	var exit_callable: Callable = on_camp_healer_tree_exiting.bind(healer, camp_id)
	if not healer.tree_exiting.is_connected(exit_callable):
		healer.tree_exiting.connect(exit_callable)
	if camp != null:
		mgr.troops.order_defend(healer, camp)
	track_ai_troop(healer)


func on_camp_healer_killed(_killer: Variant, _killer_team: Variant, healer: Node2D, camp_id: int) -> void:
	release_camp_healer(camp_id, healer)


func on_camp_healer_tree_exiting(healer: Node2D, camp_id: int) -> void:
	release_camp_healer(camp_id, healer)


func release_camp_healer(camp_id: int, healer: Node2D) -> void:
	if mgr._camp_healer_units.get(camp_id) == healer:
		mgr._camp_healer_units.erase(camp_id)
	mgr._pending_dedicated_healer.erase(camp_id)


func track_ai_troop(troop: Node2D) -> void:
	if not is_instance_valid(troop) or troop.get_meta("ai_death_tracked", false):
		return
	troop.set_meta("ai_death_tracked", true)
	if troop.has_signal("killed_by"):
		var callable: Callable = on_ai_troop_killed.bind(troop)
		if not troop.killed_by.is_connected(callable):
			troop.killed_by.connect(callable)


func on_ai_troop_killed(_killer: Variant, _killer_team: Variant, troop: Node2D) -> void:
	if not is_instance_valid(troop):
		return
	mgr._ai_troop_deaths += 1
	if mgr._ai_troop_deaths >= AIConstants.SQUAD_RESPAWN_DEATH_THRESHOLD:
		mgr._ai_troop_deaths = 0
		mgr.squads.grant_spawn_credit()


func on_camp_unit_produced(unit: Node, unit_id: int, camp: Node) -> void:
	if not is_instance_valid(camp):
		return
	var camp_id: int = camp.get_instance_id()

	if int(unit_id) == AIConstants.UNIT_HEAL and maintains_camp_healers() and camps.is_land_camp(camp):
		if not mgr._pending_dedicated_healer.has(camp_id):
			return
		mgr._pending_dedicated_healer.erase(camp_id)
		if is_instance_valid(unit) and unit is Node2D:
			var home_camp: Node2D = null
			if camp is Node2D:
				home_camp = camp as Node2D
			bind_camp_healer(camp_id, unit as Node2D, home_camp)
			mgr._camp_healer_granted[camp_id] = true
		return

	if is_instance_valid(unit) and unit is Node2D:
		track_ai_troop(unit as Node2D)
