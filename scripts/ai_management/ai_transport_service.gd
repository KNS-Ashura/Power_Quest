class_name AITransportService
extends RefCounted

const PlayerTransportControllerRef = preload("res://scripts/characters/player_transport_controller.gd")

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


func should_reserve_credit_for_expedition() -> bool:
	if camps.owned_ports().is_empty() or mgr._squad_spawn_credits <= 0:
		return false
	if templates.pick_naval_assault_port() != null:
		return true
	return templates.pick_naval_spawn_port() != null


func launch_expedition(_slot: Dictionary) -> bool:
	var spawn_port: Node = templates.pick_naval_spawn_port()
	if spawn_port == null:
		if AIConstants.DEBUG_NAVAL:
			print("[AI-Naval] Transport: aucun port disponible")
		return false
	if not spawn_port.has_method("spawn_ai_squad_units"):
		return false

	var region_id: int = camps.region_for_site(spawn_port)
	var target: Node2D = targeting.pick_transport_target(spawn_port as Node2D, region_id)
	if target == null:
		if AIConstants.DEBUG_NAVAL:
			print("[AI-Naval] Transport: pas de cible depuis %s (région %d)" % [spawn_port.name, region_id])
		return false

	var land_template: Array = templates.duplicate_template(templates.pick_squad_template(target))
	if land_template.is_empty():
		return false

	var transport_spawned: Array = spawn_port.spawn_ai_squad_units([AIConstants.PORT_UNIT_TRANSPORT])
	if transport_spawned.is_empty():
		return false
	var transport: Node2D = transport_spawned[0] as Node2D
	if not is_instance_valid(transport):
		return false

	var land_camp: Node = templates.pick_land_camp_near_port(spawn_port)
	if land_camp == null:
		transport.queue_free()
		return false

	var land_units: Array = land_camp.spawn_ai_squad_units(land_template)
	if land_units.is_empty():
		transport.queue_free()
		return false

	if not PlayerTransportControllerRef.force_board_units(transport, land_units):
		for unit in land_units:
			if is_instance_valid(unit):
				unit.queue_free()
		transport.queue_free()
		return false

	var payload_ids: Array = []
	for unit in land_units:
		if is_instance_valid(unit):
			payload_ids.append(unit.get_instance_id())
			if unit is Node2D:
				mgr.healers.track_ai_troop(unit as Node2D)

	var transport_id: int = transport.get_instance_id()
	var port_id: int = spawn_port.get_instance_id()
	mgr._transport_missions[transport_id] = {
		"target_id": target.get_instance_id(),
		"port_id": port_id,
		"origin_region_id": region_id,
		"payload_ids": payload_ids,
	}
	mgr._transport_missions_by_port[port_id] = transport_id
	transport.set_meta("ai_transport_mission", true)
	mgr.healers.track_ai_troop(transport)
	order_transport_approach(transport, target)
	if AIConstants.DEBUG_NAVAL:
		print(
			"[AI-Naval] Transport lancé depuis %s -> %s (région %d, %d unités embarquées)"
			% [spawn_port.name, target.name, region_id, land_units.size()]
		)
	return true


func tick_transport_missions() -> void:
	var finished: Array[int] = []
	var stale: Array[int] = []

	for transport_id: int in mgr._transport_missions.keys():
		var mission: Dictionary = mgr._transport_missions[transport_id]
		var transport_obj: Variant = instance_from_id(transport_id)
		if not is_instance_valid(transport_obj) or not (transport_obj is Node2D):
			stale.append(transport_id)
			continue
		var transport: Node2D = transport_obj as Node2D
		if PlayerTransportControllerRef.get_phase(transport) != PlayerTransportControllerRef.PHASE_CARRYING:
			continue

		var target_obj: Variant = instance_from_id(int(mission.get("target_id", -1)))
		if not is_instance_valid(target_obj) or not targeting.is_hostile_site(int(target_obj.get("team"))):
			var fallback: Node2D = targeting.nearest_hostile_global(transport)
			if fallback != null:
				mission["target_id"] = fallback.get_instance_id()
				target_obj = fallback
			else:
				stale.append(transport_id)
				continue

		var target_camp: Node2D = target_obj as Node2D
		if transport_can_disembark_at_target(transport, target_camp, mission):
			if PlayerTransportControllerRef.disembark(transport):
				assign_transport_payload(mission, target_camp)
				finished.append(transport_id)
				continue

		if transport.global_position.distance_squared_to(transport_water_goal(transport, target_camp)) > 24.0 * 24.0:
			order_transport_approach(transport, target_camp)

	for transport_id in stale:
		cleanup_transport_mission(transport_id)
	for transport_id in finished:
		cleanup_transport_mission(transport_id)


func order_transport_approach(transport: Node2D, target_camp: Node2D) -> void:
	var water_goal: Vector2 = transport_water_goal(transport, target_camp)
	if transport.has_method("move_to"):
		transport.move_to(water_goal)


func transport_water_goal(transport: Node2D, target_camp: Node2D) -> Vector2:
	var water_goal: Vector2 = PlayerTransportControllerRef.nearest_water_point_near(
		transport, target_camp.global_position)
	if water_goal == Vector2.INF:
		return target_camp.global_position
	return water_goal


func transport_can_disembark_at_target(
	transport: Node2D, target_camp: Node2D, mission: Dictionary
) -> bool:
	if not PlayerTransportControllerRef.can_disembark_at(transport, transport.global_position):
		return false

	var port_obj: Variant = instance_from_id(int(mission.get("port_id", -1)))
	if is_instance_valid(port_obj) and port_obj is Node2D:
		var port: Node2D = port_obj as Node2D
		if transport.global_position.distance_to(port.global_position) < AIConstants.TRANSPORT_MIN_TRAVEL_FROM_PORT:
			return false

	var origin_region: int = int(mission.get("origin_region_id", -1))
	var target_region: int = camps.region_for_site(target_camp)
	if camps.uses_regions() and origin_region >= 0 and target_region >= 0:
		if origin_region == target_region:
			return false
	elif is_instance_valid(port_obj) and port_obj is Node2D:
		if transport.global_position.distance_to(target_camp.global_position) \
				>= transport.global_position.distance_to((port_obj as Node2D).global_position):
			return false

	var water_goal: Vector2 = transport_water_goal(transport, target_camp)
	if transport.global_position.distance_to(water_goal) > AIConstants.TRANSPORT_DISEMBARK_NEAR_TARGET:
		return false
	return true


func assign_transport_payload(mission: Dictionary, target: Node2D) -> void:
	var target_region: int = camps.region_for_site(target)
	for raw_id in mission.get("payload_ids", []):
		var unit_obj: Variant = instance_from_id(int(raw_id))
		if not is_instance_valid(unit_obj) or not (unit_obj is Node2D):
			continue
		var troop: Node2D = unit_obj as Node2D
		troop.set_meta("ai_squad_mode", AIConstants.SQUAD_MODE_ATTACK)
		troop.set_meta("ai_spawn_region_id", target_region)
		mgr.healers.track_ai_troop(troop)
		mgr.troops.order_attack(troop, target)


func cleanup_transport_mission(transport_id: int) -> void:
	if not mgr._transport_missions.has(transport_id):
		return
	var mission: Dictionary = mgr._transport_missions[transport_id]
	var port_id: int = int(mission.get("port_id", -1))
	if mgr._transport_missions_by_port.get(port_id, -1) == transport_id:
		mgr._transport_missions_by_port.erase(port_id)
	mgr._transport_missions.erase(transport_id)
	var transport_obj: Variant = instance_from_id(transport_id)
	if is_instance_valid(transport_obj):
		transport_obj.remove_meta("ai_transport_mission")
