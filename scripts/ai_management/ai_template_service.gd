class_name AITemplateService
extends RefCounted

var mgr: Node
var camps: AICampService
var targeting: AITargetingService


func _init(manager: Node, camp_service: AICampService, targeting_service: AITargetingService) -> void:
	mgr = manager
	camps = camp_service
	targeting = targeting_service


func pick_attack_spawn_camp() -> Node:
	var land: Array = camps.land_camps(camps.owned_camps())
	var viable: Array = []
	for camp in land:
		if not is_instance_valid(camp) or not (camp is Node2D):
			continue
		if mgr._camp_to_squad.has(camp.get_instance_id()):
			continue
		if targeting.nearest_hostile_to(camp as Node2D, camps.region_for_site(camp), true, true) != null:
			viable.append(camp)
	if viable.is_empty():
		return null
	viable.shuffle()
	return viable[0]


func pick_naval_assault_port() -> Node:
	var viable: Array = []
	for port in camps.owned_ports():
		if not is_instance_valid(port) or not (port is Node2D):
			continue
		if mgr._camp_to_squad.has(port.get_instance_id()):
			continue
		var region_id: int = camps.region_for_site(port)
		if targeting.pick_naval_assault_target(port as Node2D, region_id) != null:
			viable.append(port)
	if viable.is_empty():
		return null
	viable.shuffle()
	return viable[0]


func pick_naval_spawn_port() -> Node:
	var viable: Array = []
	for port in camps.owned_ports():
		if not is_instance_valid(port) or not (port is Node2D):
			continue
		if mgr._camp_to_squad.has(port.get_instance_id()):
			continue
		if mgr._transport_missions_by_port.has(port.get_instance_id()):
			continue
		if targeting.pick_transport_target(port as Node2D, camps.region_for_site(port)) != null:
			viable.append(port)
	if viable.is_empty():
		return null
	viable.shuffle()
	return viable[0]


func pick_land_camp_near_port(port: Node) -> Node:
	if not is_instance_valid(port) or not (port is Node2D):
		return null
	var port_pos: Vector2 = (port as Node2D).global_position
	var best: Node = null
	var best_d2: float = INF
	for camp in camps.land_camps(camps.owned_camps()):
		if not is_instance_valid(camp) or not (camp is Node2D):
			continue
		if not camp.has_method("spawn_ai_squad_units"):
			continue
		var d2: float = port_pos.distance_squared_to((camp as Node2D).global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = camp
	return best


func pick_naval_squad_template() -> Array:
	if AIConstants.NAVAL_SQUADS.is_empty():
		return []
	return duplicate_template(AIConstants.NAVAL_SQUADS.pick_random())


func pick_squad_template(target: Node2D) -> Array:
	var pool: Array = templates_for_difficulty()
	if pool.is_empty():
		return []

	match mgr.current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return duplicate_template(pool.pick_random())
		MapSession.AIDifficulty.HARD:
			return duplicate_template(pick_hard_template(pool, target))
		_:
			return duplicate_template(pick_normal_template(pool))


func pick_defend_template() -> Array:
	var pool: Array = defend_templates_for_difficulty()
	if pool.is_empty():
		return []
	return duplicate_template(pool.pick_random())


func templates_for_difficulty() -> Array:
	match mgr.current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return AIConstants.SQUADS_SIMPLE
		MapSession.AIDifficulty.HARD:
			return AIConstants.SQUADS_HARD
		_:
			return AIConstants.SQUADS_NORMAL


func defend_templates_for_difficulty() -> Array:
	match mgr.current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return AIConstants.DEFEND_SQUADS_SIMPLE
		MapSession.AIDifficulty.HARD:
			return AIConstants.DEFEND_SQUADS_HARD
		_:
			return AIConstants.DEFEND_SQUADS_NORMAL


func duplicate_template(template: Array) -> Array:
	var copy: Array = []
	for unit_id in template:
		copy.append(int(unit_id))
	return copy


func pick_normal_template(pool: Array) -> Array:
	if pool.size() == 1:
		mgr._last_template_index = 0
		return pool[0]
	var idx: int = randi() % pool.size()
	if idx == mgr._last_template_index:
		idx = (idx + 1) % pool.size()
	mgr._last_template_index = idx
	return pool[idx]


func pick_hard_template(pool: Array, target: Node2D) -> Array:
	var player_owned: bool = int(target.get("team")) == AIConstants.TEAM_PLAYER
	var heavy_near: bool = heavy_enemies_near(target.global_position, 420.0)

	var weights: PackedFloat32Array = PackedFloat32Array()
	for i in range(pool.size()):
		var w: float = 1.0
		var tpl: Array = pool[i]
		var has_mortar: bool = AIConstants.UNIT_MORTAR in tpl
		var has_anti: bool = AIConstants.UNIT_ANTI_ARMOR in tpl
		var has_heal: bool = AIConstants.UNIT_HEAL in tpl
		var size: int = tpl.size()

		if player_owned:
			w += 0.35
			if has_heal:
				w += 0.25
			if size >= 6:
				w += 0.2
		if heavy_near and has_anti:
			w += 0.6
		if heavy_near and has_mortar:
			w += 0.35
		if i == mgr._last_template_index:
			w *= 0.25
		weights.append(w)

	var total: float = 0.0
	for w in weights:
		total += w
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in range(pool.size()):
		acc += weights[i]
		if roll <= acc:
			mgr._last_template_index = i
			return pool[i]
	mgr._last_template_index = 0
	return pool[0]


func heavy_enemies_near(center: Vector2, radius: float) -> bool:
	for troop in mgr.get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(troop) or not (troop is Node2D):
			continue
		if mgr.troops.unit_type(troop as Node2D) != UnitStats.UnitType.HEAVY:
			continue
		if (troop as Node2D).global_position.distance_to(center) <= radius:
			return true
	return false
