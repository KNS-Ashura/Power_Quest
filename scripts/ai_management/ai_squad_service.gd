class_name AISquadService
extends RefCounted

var mgr: Node
var camps: AICampService
var targeting: AITargetingService
var templates: AITemplateService


func _init(
	manager: Node,
	camp_service: AICampService,
	targeting_service: AITargetingService,
	template_service: AITemplateService
) -> void:
	mgr = manager
	camps = camp_service
	targeting = targeting_service
	templates = template_service


func reset_squad_state() -> void:
	mgr._squads.clear()
	mgr._camp_to_squad.clear()
	mgr._slot_by_squad.clear()
	mgr._naval_slot_by_squad.clear()
	mgr._defend_cooldowns.clear()
	mgr._next_squad_id = 1
	mgr._last_template_index = -1
	mgr._squad_slots.clear()
	mgr._naval_squad_slots.clear()
	mgr._camp_healer_granted.clear()
	mgr._ai_owned_camp_ids.clear()
	mgr._squad_spawn_credits = 0
	mgr._ai_troop_deaths = 0
	mgr._transport_missions.clear()
	mgr._transport_missions_by_port.clear()
	var parallel: int = int(mgr._profile.get("max_parallel_squads", 1))
	for _i in range(parallel):
		mgr._squad_slots.append({"busy": false, "cooldown": 0.0})
		mgr._naval_squad_slots.append({"busy": false, "cooldown": 0.0})


func resize_parallel_slots() -> void:
	var parallel: int = int(mgr._profile.get("max_parallel_squads", 1))
	while mgr._squad_slots.size() < parallel:
		mgr._squad_slots.append({"busy": false, "cooldown": 0.0})
	while mgr._naval_squad_slots.size() < parallel:
		mgr._naval_squad_slots.append({"busy": false, "cooldown": 0.0})


func grant_spawn_credit() -> void:
	mgr._squad_spawn_credits += 1


func cleanup_stale_squads() -> void:
	var stale: Array[int] = []
	for squad_id: int in mgr._squads.keys():
		var squad: Dictionary = mgr._squads[squad_id]
		var camp_id: int = int(squad.get("camp_id", -1))
		var camp_obj: Variant = instance_from_id(camp_id)
		if not is_instance_valid(camp_obj):
			stale.append(squad_id)
			continue
		if int(camp_obj.get("team")) != AIConstants.TEAM_AI:
			stale.append(squad_id)
			var lost_camp_id: int = int(squad.get("camp_id", -1))
			mgr._pending_dedicated_healer.erase(lost_camp_id)
			mgr._camp_healer_units.erase(lost_camp_id)
	for squad_id in stale:
		finish_squad(squad_id)


func tick_squad_slots() -> void:
	if mgr._squad_spawn_credits <= 0:
		return
	for slot in mgr._squad_slots:
		if mgr._squad_spawn_credits <= 0:
			break
		if launch_attack_squad(slot):
			mgr._squad_spawn_credits -= 1


func tick_naval_squad_slots() -> void:
	if camps.owned_ports().is_empty() or mgr._squad_spawn_credits <= 0:
		return
	for slot in mgr._naval_squad_slots:
		if mgr._squad_spawn_credits <= 0:
			break
		if launch_naval_assault(slot):
			mgr._squad_spawn_credits -= 1
		elif launch_transport_expedition(slot):
			mgr._squad_spawn_credits -= 1


func launch_naval_assault(slot: Dictionary) -> bool:
	var spawn_port: Node = templates.pick_naval_assault_port()
	if spawn_port == null:
		return false
	var region_id: int = camps.region_for_site(spawn_port)
	var target: Node2D = targeting.pick_naval_assault_target(spawn_port as Node2D, region_id)
	if target == null:
		return false
	var naval_template: Array = templates.pick_naval_squad_template()
	if naval_template.is_empty():
		return false
	if AIConstants.DEBUG_NAVAL:
		print(
			"[AI-Naval] Assaut aquatique depuis %s -> %s (région %d)"
			% [spawn_port.name, target.name, region_id]
		)
	return launch_squad_at_camp(
		spawn_port, naval_template, AIConstants.SQUAD_MODE_NAVAL, target, slot, true
	)


func tick_defend_squads() -> void:
	if mgr._squad_spawn_credits <= 0:
		return
	if mgr.transport.should_reserve_credit_for_expedition():
		return
	for camp in camps.land_camps(camps.owned_camps()):
		if mgr._squad_spawn_credits <= 0:
			break
		if not is_instance_valid(camp) or not (camp is Node2D):
			continue
		var camp_id: int = camp.get_instance_id()
		if mgr._camp_to_squad.has(camp_id):
			continue
		if mgr._defend_cooldowns.has(camp_id):
			continue
		if targeting.has_regional_hostile(camp as Node2D):
			continue
		var template: Array = templates.pick_defend_template()
		if template.is_empty():
			continue
		if launch_squad_at_camp(camp, template, AIConstants.SQUAD_MODE_DEFEND, null, null):
			mgr._squad_spawn_credits -= 1
			mgr._defend_cooldowns[camp_id] = 9999.0


func launch_attack_squad(slot: Dictionary) -> bool:
	var spawn_camp: Node = templates.pick_attack_spawn_camp()
	if spawn_camp == null:
		return false
	var region_id: int = camps.region_for_site(spawn_camp)
	var target: Node2D = targeting.nearest_hostile_to(spawn_camp as Node2D, region_id, true, true)
	if target == null:
		return false
	var squad_template: Array = templates.pick_squad_template(target)
	if squad_template.is_empty():
		return false
	return launch_squad_at_camp(spawn_camp, squad_template, AIConstants.SQUAD_MODE_ATTACK, target, slot)


func launch_transport_expedition(_slot: Dictionary) -> bool:
	return mgr.transport.launch_expedition(_slot)


func launch_squad_at_camp(
	spawn_camp: Node,
	squad_template: Array,
	mode: String,
	target: Node2D,
	slot: Variant,
	is_naval_slot: bool = false
) -> bool:
	if not spawn_camp.has_method("spawn_ai_squad_units"):
		return false

	var final_template: Array = templates.duplicate_template(squad_template)
	if final_template.is_empty():
		return false

	var squad_id: int = mgr._next_squad_id
	mgr._next_squad_id += 1
	var camp_id: int = spawn_camp.get_instance_id()
	var region_id: int = camps.region_for_site(spawn_camp)
	var squad: Dictionary = {
		"mode": mode,
		"camp_id": camp_id,
		"region_id": region_id,
		"target_id": target.get_instance_id() if target != null else -1,
		"remaining": 0,
		"members": [],
	}
	mgr._squads[squad_id] = squad
	mgr._camp_to_squad[camp_id] = squad_id
	if slot is Dictionary:
		if is_naval_slot:
			mgr._naval_slot_by_squad[squad_id] = slot
		else:
			mgr._slot_by_squad[squad_id] = slot

	var spawned: Array = spawn_camp.spawn_ai_squad_units(final_template)
	if spawned.is_empty():
		abort_squad(squad_id)
		return false

	for unit in spawned:
		if is_instance_valid(unit) and unit is Node2D:
			var troop: Node2D = unit as Node2D
			register_squad_member(squad_id, squad, troop, camp_id)
			mgr.healers.track_ai_troop(troop)

	dispatch_squad(squad)
	finish_squad(squad_id)
	return true


func register_squad_member(squad_id: int, squad: Dictionary, troop: Node2D, camp_id: int) -> void:
	var mode: String = str(squad.get("mode", AIConstants.SQUAD_MODE_ATTACK))
	var region_id: int = int(squad.get("region_id", -1))
	troop.set_meta("ai_squad_id", squad_id)
	troop.set_meta("ai_squad_mode", mode)
	troop.set_meta("ai_spawn_camp_id", camp_id)
	troop.set_meta("ai_spawn_region_id", region_id)
	var members: Array = squad.get("members", [])
	members.append(troop)
	squad["members"] = members


func abort_squad(squad_id: int) -> void:
	if not mgr._squads.has(squad_id):
		return
	var data: Dictionary = mgr._squads[squad_id]
	var camp_id: int = int(data.get("camp_id", -1))
	if mgr._camp_to_squad.get(camp_id, -1) == squad_id:
		mgr._camp_to_squad.erase(camp_id)
	mgr._squads.erase(squad_id)
	release_squad_slot(squad_id)


func finish_squad(squad_id: int) -> void:
	if not mgr._squads.has(squad_id):
		return
	var data: Dictionary = mgr._squads[squad_id]
	var camp_id: int = int(data.get("camp_id", -1))
	if mgr._camp_to_squad.get(camp_id, -1) == squad_id:
		mgr._camp_to_squad.erase(camp_id)
	mgr._squads.erase(squad_id)
	release_squad_slot(squad_id)


func release_squad_slot(squad_id: int) -> void:
	if mgr._slot_by_squad.has(squad_id):
		var slot: Dictionary = mgr._slot_by_squad[squad_id]
		slot["busy"] = false
		mgr._slot_by_squad.erase(squad_id)
	if mgr._naval_slot_by_squad.has(squad_id):
		var naval_slot: Dictionary = mgr._naval_slot_by_squad[squad_id]
		naval_slot["busy"] = false
		mgr._naval_slot_by_squad.erase(squad_id)


func dispatch_squad(squad: Dictionary) -> void:
	var mode: String = str(squad.get("mode", AIConstants.SQUAD_MODE_ATTACK))
	var region_id: int = int(squad.get("region_id", -1))
	var camp_id: int = int(squad.get("camp_id", -1))
	var spawn_camp_obj: Variant = instance_from_id(camp_id)
	var spawn_camp: Node2D = null
	if is_instance_valid(spawn_camp_obj) and spawn_camp_obj is Node2D:
		spawn_camp = spawn_camp_obj as Node2D
	var target: Node2D = targeting.resolve_target(
		int(squad.get("target_id", -1)),
		spawn_camp,
		mode,
		region_id
	)
	for member in squad.get("members", []):
		if not is_instance_valid(member) or not (member is Node2D):
			continue
		var troop: Node2D = member as Node2D
		if troop.get_meta("ai_camp_healer", false):
			continue
		match mode:
			AIConstants.SQUAD_MODE_DEFEND:
				if spawn_camp != null:
					mgr.troops.order_defend(troop, spawn_camp)
			AIConstants.SQUAD_MODE_NAVAL:
				if target != null:
					mgr.troops.order_naval(troop, target)
			_:
				if target != null:
					mgr.troops.order_attack(troop, target)
