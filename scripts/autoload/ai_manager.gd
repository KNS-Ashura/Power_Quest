extends Node

const TEAM_PLAYER := 0
const TEAM_AI := 1
const TEAM_NEUTRAL := 2
const NAV_LAYER_GROUND := 1
const NAV_LAYER_WATER := 2

const TRANSPORT_PHASE_IDLE := 0
const TRANSPORT_PHASE_MARKED := 1
const TRANSPORT_PHASE_CARRYING := 2

const STARTING_GOLD := 200

const LAND_WEIGHTS_SIMPLE := {
	UnitStats.UnitType.INFANTRY: 7,
	UnitStats.UnitType.ARCHER: 3,
	UnitStats.UnitType.HEAVY: 2,
	UnitStats.UnitType.ANTI_ARMOR: 1,
	UnitStats.UnitType.MORTAR: 1,
}
const LAND_WEIGHTS_NORMAL := {
	UnitStats.UnitType.INFANTRY: 4,
	UnitStats.UnitType.ARCHER: 3,
	UnitStats.UnitType.HEAVY: 3,
	UnitStats.UnitType.SUPPORT: 2,
	UnitStats.UnitType.HEAL: 2,
	UnitStats.UnitType.ANTI_ARMOR: 2,
	UnitStats.UnitType.MORTAR: 2,
}
const LAND_WEIGHTS_HARD := {
	UnitStats.UnitType.INFANTRY: 2,
	UnitStats.UnitType.ARCHER: 3,
	UnitStats.UnitType.HEAVY: 4,
	UnitStats.UnitType.SUPPORT: 3,
	UnitStats.UnitType.HEAL: 3,
	UnitStats.UnitType.ANTI_ARMOR: 3,
	UnitStats.UnitType.MORTAR: 3,
}
const PORT_WEIGHTS_SIMPLE := {
	UnitStats.UnitType.WATER_TRANSPORT: 1,
	UnitStats.UnitType.WATER_TANK: 3,
	UnitStats.UnitType.WATER_RANGE: 2,
}
const PORT_WEIGHTS_NORMAL := {
	UnitStats.UnitType.WATER_TRANSPORT: 2,
	UnitStats.UnitType.WATER_TANK: 3,
	UnitStats.UnitType.WATER_RANGE: 3,
}
const PORT_WEIGHTS_HARD := {
	UnitStats.UnitType.WATER_TRANSPORT: 3,
	UnitStats.UnitType.WATER_TANK: 4,
	UnitStats.UnitType.WATER_RANGE: 4,
}

const PROFILE_SIMPLE := {
	"think_interval": 4.0,
	"reserve_gold": 140,
	"upgrade_reserve_gold": 180,
	"upgrade_chance": 0.25,
	"max_upgrades_per_think": 1,
	"queue_limit": 1,
	"use_ports": true,
	"allow_transport": false,
	"neutral_priority": 0.8,
	"player_priority": 1.0,
	"disembark_distance": 120.0,
}
const PROFILE_NORMAL := {
	"think_interval": 2.5,
	"reserve_gold": 90,
	"upgrade_reserve_gold": 120,
	"upgrade_chance": 0.5,
	"max_upgrades_per_think": 1,
	"queue_limit": 1,
	"use_ports": true,
	"allow_transport": true,
	"neutral_priority": 1.0,
	"player_priority": 1.4,
	"disembark_distance": 140.0,
}
const PROFILE_HARD := {
	"think_interval": 1.7,
	"reserve_gold": 40,
	"upgrade_reserve_gold": 70,
	"upgrade_chance": 0.8,
	"max_upgrades_per_think": 2,
	"queue_limit": 2,
	"use_ports": true,
	"allow_transport": true,
	"neutral_priority": 1.1,
	"player_priority": 1.8,
	"disembark_distance": 170.0,
}

var current_difficulty: int = MapSession.AIDifficulty.NORMAL
var ai_gold: int = STARTING_GOLD
var think_timer: Timer
var _profile: Dictionary = PROFILE_NORMAL
var _transporter_targets: Dictionary = {}
var _cached_navigation_regions: Array[NavigationRegion2D] = []
var _cached_ground_nav_map: RID = RID()
var _cached_water_nav_map: RID = RID()
var _land_command_cursor: int = 0
var _naval_command_cursor: int = 0
var _reachability_cache: Dictionary = {}
var _think_count: int = 0


func _ready() -> void:
	think_timer = Timer.new()
	add_child(think_timer)
	_set_difficulty(MapSession.get_ai_difficulty())
	think_timer.timeout.connect(_on_think)
	think_timer.start()
	GameManager.global_timer.timeout.connect(_on_global_cycle)


func init_match() -> void:
	ai_gold = STARTING_GOLD
	_set_difficulty(MapSession.get_ai_difficulty())
	_transporter_targets.clear()
	if is_instance_valid(think_timer):
		if not think_timer.is_stopped():
			think_timer.stop()
		think_timer.start()


func _on_global_cycle() -> void:
	ai_gold += GameManager.cycle_gold_bonus
	for camp in _get_owned_camps():
		var region_bonus: int = RegionManager.bonus_income_for_site(camp)
		ai_gold += (camp.income_per_second + region_bonus) * int(GameManager.cycle_time)


func _on_think() -> void:
	if GameManager.match_over:
		return
	if current_difficulty != MapSession.get_ai_difficulty():
		_set_difficulty(MapSession.get_ai_difficulty())
	_think_count += 1
	if _think_count % 3 == 1 or not _cached_ground_nav_map.is_valid() or not _cached_water_nav_map.is_valid():
		_refresh_navigation_caches()
	_reachability_cache.clear()
	var owned_camps = _get_owned_camps()
	if owned_camps.is_empty():
		return

	_handle_upgrades(owned_camps)
	_handle_production(owned_camps)
	_handle_military()


func _get_owned_camps() -> Array:
	return _get_camps_for_teams([TEAM_AI])


func _handle_production(owned_camps: Array) -> void:
	for camp in owned_camps:
		if not is_instance_valid(camp):
			continue
		var queue: Array = camp.get("production_queue")
		if queue.size() >= int(_profile.get("queue_limit", 1)):
			continue
		var is_port_site: bool = camp.has_method("is_port") and camp.is_port()
		if is_port_site and not bool(_profile.get("use_ports", true)):
			continue

		var catalog_variant: Variant = camp.get("unit_catalog")
		if not (catalog_variant is Dictionary):
			continue
		var catalog: Dictionary = catalog_variant
		if catalog.is_empty():
			continue

		var chosen_unit: int = _pick_unit_id_for_camp(camp, catalog, is_port_site)
		if chosen_unit == -1:
			continue
		if not catalog.has(chosen_unit):
			continue

		var data: UnitStats = catalog[chosen_unit]
		if ai_gold < data.price:
			continue
		ai_gold -= data.price
		camp.production_queue.append(chosen_unit)
		if camp.production_queue.size() == 1:
			camp.current_unit_total_time = camp.unit_build_time(chosen_unit) if camp.has_method("unit_build_time") else data.build_time
			camp.remaining_time = camp.current_unit_total_time


func _handle_upgrades(owned_camps: Array) -> void:
	var reserve_gold: int = int(_profile.get("upgrade_reserve_gold", 120))
	var upgrade_chance: float = float(_profile.get("upgrade_chance", 0.5))
	var max_upgrades: int = int(_profile.get("max_upgrades_per_think", 1))
	var candidates: Array[Dictionary] = []

	for camp in owned_camps:
		if not is_instance_valid(camp):
			continue
		if not camp.has_method("next_upgrade_cost") or not camp.has_method("upgrade_camp"):
			continue
		if camp.has_method("can_upgrade") and not camp.can_upgrade(TEAM_AI):
			continue

		var cost: int = int(camp.next_upgrade_cost())
		if cost <= 0:
			continue
		if ai_gold - cost < reserve_gold:
			continue

		var level: int = int(camp.get("camp_level"))
		var score: float = float(4 - level)
		var is_port_site: bool = camp.has_method("is_port") and camp.is_port()
		if is_port_site:
			score += 0.9
		if current_difficulty == MapSession.AIDifficulty.HARD and is_port_site:
			score += 0.6
		candidates.append({"camp": camp, "cost": cost, "score": score})

	if candidates.is_empty():
		return

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))

	var upgraded_count: int = 0
	for entry in candidates:
		if upgraded_count >= max_upgrades:
			break
		if randf() > upgrade_chance:
			continue
		var camp: Node = entry["camp"]
		var cost: int = int(entry["cost"])
		if ai_gold < cost:
			continue
		if not is_instance_valid(camp):
			continue
		if camp.upgrade_camp(false, TEAM_AI):
			ai_gold -= cost
			upgraded_count += 1


func _handle_military() -> void:
	var troops: Array[Node2D] = _get_enemy_troops()
	if troops.is_empty():
		return

	var transporters: Array[Node2D] = []
	var naval: Array[Node2D] = []
	var land: Array[Node2D] = []
	for troop in troops:
		var unit_type: int = _unit_type_of(troop)
		if unit_type == UnitStats.UnitType.WATER_TRANSPORT:
			transporters.append(troop)
		elif unit_type == UnitStats.UnitType.WATER_TANK or unit_type == UnitStats.UnitType.WATER_RANGE:
			naval.append(troop)
		else:
			land.append(troop)

	_command_troop_group(land, false, NAV_LAYER_GROUND)
	_command_troop_group(naval, true, NAV_LAYER_WATER)
	if bool(_profile.get("allow_transport", false)):
		_handle_transporters(transporters)


func _set_difficulty(difficulty: int) -> void:
	current_difficulty = difficulty
	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			_profile = PROFILE_SIMPLE
		MapSession.AIDifficulty.HARD:
			_profile = PROFILE_HARD
		_:
			current_difficulty = MapSession.AIDifficulty.NORMAL
			_profile = PROFILE_NORMAL
	if is_instance_valid(think_timer):
		think_timer.wait_time = float(_profile.get("think_interval", 2.5))


func _get_camps_for_teams(teams: Array[int]) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(node):
			continue
		var team_value: int = int(node.get("team"))
		if teams.has(team_value):
			result.append(node)
	return result


func _pick_unit_id_for_camp(camp: Node, catalog: Dictionary, is_port_site: bool) -> int:
	var weights: Dictionary = _weights_for_camp(is_port_site)
	var weighted_pool: Array[int] = []
	var cheapest_id: int = -1
	var cheapest_price: int = 999999
	for raw_id in catalog.keys():
		var unit_id: int = int(raw_id)
		var stats: UnitStats = catalog[unit_id]
		if stats == null:
			continue
		if stats.price < cheapest_price:
			cheapest_price = stats.price
			cheapest_id = unit_id
		if ai_gold < stats.price:
			continue
		var weight: int = int(weights.get(int(stats.unit_type), 1))
		for _w in range(maxi(1, weight)):
			weighted_pool.append(unit_id)

	if weighted_pool.is_empty():
		if ai_gold >= cheapest_price:
			return cheapest_id
		return -1

	if ai_gold < int(_profile.get("reserve_gold", 0)) and cheapest_id != -1 and randf() < 0.55:
		return cheapest_id
	return weighted_pool.pick_random()


func _weights_for_camp(is_port_site: bool) -> Dictionary:
	if is_port_site:
		var port_weights: Dictionary
		match current_difficulty:
			MapSession.AIDifficulty.SIMPLE:
				port_weights = PORT_WEIGHTS_SIMPLE.duplicate(true)
			MapSession.AIDifficulty.HARD:
				port_weights = PORT_WEIGHTS_HARD.duplicate(true)
			_:
				port_weights = PORT_WEIGHTS_NORMAL.duplicate(true)
		if current_difficulty == MapSession.AIDifficulty.HARD:
			var land_units: int = _count_enemy_land_units()
			var transporters: int = _count_enemy_units_of_type(UnitStats.UnitType.WATER_TRANSPORT)
			if land_units > transporters * 4:
				port_weights[UnitStats.UnitType.WATER_TRANSPORT] = int(port_weights.get(UnitStats.UnitType.WATER_TRANSPORT, 3)) + 3
		return port_weights

	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return LAND_WEIGHTS_SIMPLE
		MapSession.AIDifficulty.HARD:
			return LAND_WEIGHTS_HARD
		_:
			return LAND_WEIGHTS_NORMAL


func _get_enemy_troops() -> Array[Node2D]:
	var troops: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Node2D and is_instance_valid(node):
			troops.append(node)
	return troops


func _unit_type_of(troop: Node2D) -> int:
	var stats_variant: Variant = troop.get("stats")
	if stats_variant is UnitStats:
		var unit_stats: UnitStats = stats_variant
		return int(unit_stats.unit_type)
	return -1


func _command_troop_group(troops: Array[Node2D], prefer_ports: bool, required_layer: int) -> void:
	if troops.is_empty():
		return
	var batch_size: int = _military_batch_size()
	if troops.size() <= batch_size:
		for troop in troops:
			if not is_instance_valid(troop):
				continue
			var target_camp: Node2D = _pick_target_camp_for(troop.global_position, prefer_ports, required_layer)
			if target_camp == null:
				if required_layer == NAV_LAYER_GROUND and troop.has_method("move_to"):
					troop.move_to(_best_embark_point(troop.global_position))
				continue
			_issue_attack_order(troop, target_camp)
		return

	var use_land_cursor: bool = required_layer == NAV_LAYER_GROUND
	var cursor: int = _land_command_cursor if use_land_cursor else _naval_command_cursor
	cursor = posmod(cursor, troops.size())
	var processed: int = 0
	while processed < batch_size:
		var idx: int = (cursor + processed) % troops.size()
		var troop: Node2D = troops[idx]
		if not is_instance_valid(troop):
			processed += 1
			continue
		var target_camp: Node2D = _pick_target_camp_for(troop.global_position, prefer_ports, required_layer)
		if target_camp == null:
			if required_layer == NAV_LAYER_GROUND and troop.has_method("move_to"):
				troop.move_to(_best_embark_point(troop.global_position))
			processed += 1
			continue
		_issue_attack_order(troop, target_camp)
		processed += 1
	var next_cursor: int = (cursor + batch_size) % troops.size()
	if use_land_cursor:
		_land_command_cursor = next_cursor
	else:
		_naval_command_cursor = next_cursor


func _military_batch_size() -> int:
	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return 8
		MapSession.AIDifficulty.HARD:
			return 20
		_:
			return 12


func _pick_target_camp_for(from_pos: Vector2, prefer_ports: bool, required_layer: int = 0) -> Node2D:
	var player_camps: Array = _get_camps_for_teams([TEAM_PLAYER])
	var neutral_camps: Array = _get_camps_for_teams([TEAM_NEUTRAL])
	var candidates: Array = []
	candidates.append_array(player_camps)
	candidates.append_array(neutral_camps)
	if candidates.is_empty():
		return null

	var best_camp: Node2D = null
	var best_score: float = -INF
	for camp in candidates:
		if not (camp is Node2D) or not is_instance_valid(camp):
			continue
		var camp_node := camp as Node2D
		if required_layer != 0 and not _is_reachable_on_layer(from_pos, camp_node.global_position, required_layer):
			continue
		var base_score: float = _camp_base_score(camp)
		var distance_score: float = 2000.0 / maxf(80.0, from_pos.distance_to(camp_node.global_position))
		var is_port_site: bool = camp.has_method("is_port") and camp.is_port()
		if prefer_ports and is_port_site:
			base_score += 1.4
		elif prefer_ports and not is_port_site:
			base_score *= 0.85
		var total: float = base_score + distance_score
		if total > best_score:
			best_score = total
			best_camp = camp_node
	return best_camp


func _camp_base_score(camp: Node) -> float:
	var owner: int = int(camp.get("team"))
	var player_priority: float = float(_profile.get("player_priority", 1.0))
	var neutral_priority: float = float(_profile.get("neutral_priority", 1.0))
	var score: float = player_priority if owner == TEAM_PLAYER else neutral_priority
	var guardian: Node2D = _valid_guardian(camp)
	if guardian != null and guardian.get("current_hp") != null and guardian.get("hp_max") != null:
		var hp_ratio: float = float(guardian.current_hp) / maxf(1.0, float(guardian.hp_max))
		score += (1.0 - hp_ratio) * 0.9
	return score


func _valid_guardian(camp: Node) -> Node2D:
	var guardian_variant: Variant = camp.get("guardian")
	if guardian_variant is Node2D and is_instance_valid(guardian_variant):
		return guardian_variant
	return null


func _issue_attack_order(troop: Node2D, target_camp: Node2D) -> void:
	var guardian: Node2D = _valid_guardian(target_camp)
	if guardian != null and troop.has_method("attack_target"):
		troop.attack_target(guardian)
	elif troop.has_method("move_to"):
		troop.move_to(target_camp.global_position)


func _handle_transporters(transporters: Array[Node2D]) -> void:
	if transporters.is_empty():
		return
	var target_candidates: Array = _get_camps_for_teams([TEAM_PLAYER, TEAM_NEUTRAL])
	if target_candidates.is_empty():
		return
	for transporter in transporters:
		if not is_instance_valid(transporter):
			continue
		var target: Node2D = _target_for_transporter(transporter, target_candidates)
		if target == null:
			continue
		_update_transporter_cycle(transporter, target)


func _target_for_transporter(transporter: Node2D, target_candidates: Array) -> Node2D:
	var key: int = transporter.get_instance_id()
	var stored: Variant = _transporter_targets.get(key)
	if stored is WeakRef:
		var remembered: Variant = stored.get_ref()
		if remembered is Node2D and is_instance_valid(remembered):
			return remembered
	var picked: Node2D = _pick_target_camp_for(transporter.global_position, false, NAV_LAYER_WATER)
	if picked != null:
		_transporter_targets[key] = weakref(picked)
	return picked


func _update_transporter_cycle(transporter: Node2D, target_camp: Node2D) -> void:
	if not transporter.has_method("get_water_transport_phase"):
		return
	var phase: int = int(transporter.get_water_transport_phase())
	if phase == TRANSPORT_PHASE_IDLE:
		var staging: Vector2 = _best_embark_point(transporter.global_position)
		if transporter.has_method("move_to"):
			transporter.move_to(staging)
		if transporter.global_position.distance_to(staging) < 90.0:
			if transporter.has_method("can_use_water_transport") and transporter.can_use_water_transport():
				transporter.water_transport_step()
	elif phase == TRANSPORT_PHASE_MARKED:
		transporter.water_transport_step()
	elif phase == TRANSPORT_PHASE_CARRYING:
		var destination: Vector2 = target_camp.global_position
		if transporter.has_method("move_to"):
			transporter.move_to(destination)
		if transporter.global_position.distance_to(destination) <= float(_profile.get("disembark_distance", 140.0)):
			transporter.water_transport_step()


func _best_embark_point(from_pos: Vector2) -> Vector2:
	var owned_camps: Array = _get_owned_camps()
	var best_pos: Vector2 = from_pos
	var best_d2: float = INF
	for camp in owned_camps:
		if not (camp is Node2D):
			continue
		var camp_node := camp as Node2D
		var d2: float = from_pos.distance_squared_to(camp_node.global_position)
		if camp.has_method("is_port") and camp.is_port():
			d2 *= 0.7
		if d2 < best_d2:
			best_d2 = d2
			best_pos = camp_node.global_position
	return best_pos


func _count_enemy_units_of_type(unit_type: int) -> int:
	var count: int = 0
	for troop in _get_enemy_troops():
		if _unit_type_of(troop) == unit_type:
			count += 1
	return count


func _count_enemy_land_units() -> int:
	var count: int = 0
	for troop in _get_enemy_troops():
		var unit_type: int = _unit_type_of(troop)
		if unit_type == UnitStats.UnitType.WATER_TRANSPORT \
		or unit_type == UnitStats.UnitType.WATER_TANK \
		or unit_type == UnitStats.UnitType.WATER_RANGE:
			continue
		count += 1
	return count


func _refresh_navigation_caches() -> void:
	_cached_navigation_regions.clear()
	var root := get_tree().current_scene
	if is_instance_valid(root):
		_collect_navigation_regions(root, _cached_navigation_regions)
	_cached_ground_nav_map = _find_nav_map_for_layer(NAV_LAYER_GROUND)
	_cached_water_nav_map = _find_nav_map_for_layer(NAV_LAYER_WATER)


func _collect_navigation_regions(node: Node, out: Array[NavigationRegion2D]) -> void:
	if node is NavigationRegion2D:
		out.append(node)
	for child in node.get_children():
		_collect_navigation_regions(child, out)


func _find_nav_map_for_layer(layer_mask: int) -> RID:
	for region in _cached_navigation_regions:
		if not is_instance_valid(region):
			continue
		if (region.navigation_layers & layer_mask) == 0:
			continue
		var nav_map: RID = region.get_navigation_map()
		if nav_map.is_valid():
			return nav_map
	return RID()


func _is_reachable_on_layer(from_pos: Vector2, to_pos: Vector2, layer_mask: int) -> bool:
	var from_qx: int = int(round(from_pos.x / 48.0))
	var from_qy: int = int(round(from_pos.y / 48.0))
	var to_qx: int = int(round(to_pos.x / 48.0))
	var to_qy: int = int(round(to_pos.y / 48.0))
	var key: String = "%d|%d|%d|%d|%d" % [layer_mask, from_qx, from_qy, to_qx, to_qy]
	if _reachability_cache.has(key):
		return bool(_reachability_cache[key])

	var nav_map: RID = RID()
	if layer_mask == NAV_LAYER_GROUND:
		nav_map = _cached_ground_nav_map
	elif layer_mask == NAV_LAYER_WATER:
		nav_map = _cached_water_nav_map
	if not nav_map.is_valid():
		_reachability_cache[key] = false
		return false
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from_pos, to_pos, true, layer_mask)
	if path.size() < 2:
		_reachability_cache[key] = false
		return false
	var reachable: bool = path[path.size() - 1].distance_to(to_pos) <= 120.0
	_reachability_cache[key] = reachable
	return reachable
