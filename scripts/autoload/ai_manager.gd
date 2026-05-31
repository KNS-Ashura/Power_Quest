extends Node

const TEAM_PLAYER := 0
const TEAM_AI := 1
const TEAM_NEUTRAL := 2
const NAV_LAYER_GROUND := 1
const NAV_LAYER_WATER := 2

const TRANSPORT_PHASE_IDLE := 0
const TRANSPORT_PHASE_MARKED := 1
const TRANSPORT_PHASE_CARRYING := 2

const RAID_PHASE_BUILDING := 0
const RAID_PHASE_GATHERING := 1
const RAID_PHASE_TRANSPORT := 2
const RAID_PHASE_ATTACKING := 3

const UNIT_INFANTRY := 0
const UNIT_RANGE := 1
const UNIT_HEAVY := 2
const UNIT_SUPPORT := 3
const UNIT_HEAL := 4
const UNIT_ANTI_ARMOR := 5
const UNIT_MORTAR := 6
const PORT_UNIT_TRANSPORT := 0

const RAID_ASSIGN_RADIUS := 420.0
const RAID_GATHER_RADIUS := 200.0

const _TransportCtrl = preload("res://scripts/characters/player_transport_controller.gd")

const ARMY_COMPOSITIONS: Array[Dictionary] = [
	{UNIT_INFANTRY: 4, UNIT_HEAL: 1},
	{UNIT_INFANTRY: 5, UNIT_SUPPORT: 1},
	{UNIT_HEAVY: 1, UNIT_RANGE: 3},
	{UNIT_INFANTRY: 6},
	{UNIT_RANGE: 4, UNIT_ANTI_ARMOR: 1},
	{UNIT_INFANTRY: 3, UNIT_RANGE: 2, UNIT_HEAL: 1},
	{UNIT_HEAVY: 1, UNIT_ANTI_ARMOR: 1, UNIT_INFANTRY: 3},
	{UNIT_MORTAR: 1, UNIT_INFANTRY: 4},
	{UNIT_INFANTRY: 8},
	{UNIT_RANGE: 5, UNIT_SUPPORT: 1},
]

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
	"think_interval": 1.0,
	"reserve_gold": 0,
	"upgrade_reserve_gold": 250,
	"upgrade_chance": 0.08,
	"max_upgrades_per_think": 1,
	"queue_limit": 12,
	"max_raids": 2,
	"units_per_think": 4,
	"use_ports": true,
	"allow_transport": true,
	"neutral_priority": 1.0,
	"player_priority": 1.3,
	"disembark_distance": 130.0,
}
const PROFILE_NORMAL := {
	"think_interval": 0.65,
	"reserve_gold": 0,
	"upgrade_reserve_gold": 180,
	"upgrade_chance": 0.12,
	"max_upgrades_per_think": 1,
	"queue_limit": 16,
	"max_raids": 4,
	"units_per_think": 6,
	"use_ports": true,
	"allow_transport": true,
	"neutral_priority": 1.0,
	"player_priority": 1.7,
	"disembark_distance": 150.0,
}
const PROFILE_HARD := {
	"think_interval": 0.45,
	"reserve_gold": 0,
	"upgrade_reserve_gold": 120,
	"upgrade_chance": 0.18,
	"max_upgrades_per_think": 1,
	"queue_limit": 20,
	"max_raids": 6,
	"units_per_think": 8,
	"use_ports": true,
	"allow_transport": true,
	"neutral_priority": 1.1,
	"player_priority": 2.2,
	"disembark_distance": 170.0,
}

var current_difficulty: int = MapSession.AIDifficulty.NORMAL
var ai_gold: int = STARTING_GOLD
var think_timer: Timer
var _profile: Dictionary = PROFILE_NORMAL
var _transporter_targets: Dictionary = {}
var _active_raids: Array[Dictionary] = []
var _next_raid_id: int = 1
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
	_active_raids.clear()
	_next_raid_id = 1
	if is_instance_valid(think_timer):
		if not think_timer.is_stopped():
			think_timer.stop()
		think_timer.start()


func _on_global_cycle() -> void:
	# No AI in multiplayer: everything is controlled by human players.
	if MapSession.is_online_match:
		return
	ai_gold += GameManager.cycle_gold_bonus
	for camp in _get_owned_camps():
		var region_bonus: int = RegionManager.bonus_income_for_site(camp)
		ai_gold += (camp.income_per_second + region_bonus) * int(GameManager.cycle_time)


func _on_think() -> void:
	# No AI in multiplayer.
	if MapSession.is_online_match:
		return
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
	var land_camps := _filter_land_camps(owned_camps)
	var owned_ports := _filter_ports(owned_camps)
	_try_start_new_raids(land_camps, owned_ports)
	_handle_raid_production(land_camps)
	_handle_port_production(owned_ports)
	_spend_excess_gold_on_camps(land_camps)


func _handle_military() -> void:
	_assign_spawned_units_to_raids()
	_cleanup_raids()
	_update_active_raids()
	_command_loose_troops()


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
	return 99999


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


func _filter_land_camps(camps: Array) -> Array:
	var result: Array = []
	for camp in camps:
		if not is_instance_valid(camp):
			continue
		if camp.has_method("is_port") and camp.is_port():
			continue
		result.append(camp)
	return result


func _filter_ports(camps: Array) -> Array:
	var result: Array = []
	for camp in camps:
		if not is_instance_valid(camp):
			continue
		if camp.has_method("is_port") and camp.is_port():
			result.append(camp)
	return result


func _flatten_composition(composition: Dictionary) -> Array[int]:
	var plan: Array[int] = []
	for raw_id in composition.keys():
		var unit_id: int = int(raw_id)
		var count: int = int(composition[unit_id])
		for _i in range(maxi(0, count)):
			plan.append(unit_id)
	return plan


func _composition_total_cost(camp: Node, plan: Array) -> int:
	var catalog: Dictionary = camp.get("unit_catalog")
	if not (catalog is Dictionary):
		return 999999
	var total: int = 0
	for raw_id in plan:
		var unit_id: int = int(raw_id)
		if not catalog.has(unit_id):
			return 999999
		var stats: UnitStats = catalog[unit_id]
		if stats == null:
			return 999999
		total += stats.price
	return total


func _camp_has_active_raid(camp: Node) -> bool:
	for raid in _active_raids:
		if raid.get("source_camp") == camp:
			return true
	return false


func _active_raid_count() -> int:
	return _active_raids.size()


func _region_for_site(site: Node) -> int:
	if site == null or not is_instance_valid(site):
		return -1
	for region_id in range(1, 32):
		if not RegionManager.has_region(region_id):
			continue
		for region_site in RegionManager.get_sites_for_region(region_id):
			if region_site == site:
				return region_id
	return -1


func _hostile_sites_in_region(region_id: int) -> Array:
	var result: Array = []
	if region_id < 0:
		return result
	for site in RegionManager.get_sites_for_region(region_id):
		if not is_instance_valid(site):
			continue
		var owner: int = int(site.get("team"))
		if owner == TEAM_NEUTRAL or owner == TEAM_PLAYER:
			result.append(site)
	return result


func _hostile_sites_outside_region(region_id: int) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(node):
			continue
		var owner: int = int(node.get("team"))
		if owner != TEAM_NEUTRAL and owner != TEAM_PLAYER:
			continue
		if _region_for_site(node) != region_id:
			result.append(node)
	return result


func _pick_raid_target(source_camp: Node, owned_ports: Array) -> Dictionary:
	var source_region: int = _region_for_site(source_camp)
	var same_region_targets: Array = _hostile_sites_in_region(source_region)
	if not same_region_targets.is_empty():
		return {
			"target": same_region_targets.pick_random() as Node2D,
			"use_transport": false,
			"embark_port": null,
		}

	if owned_ports.is_empty() or not bool(_profile.get("allow_transport", true)):
		return {}

	var other_targets: Array = _hostile_sites_outside_region(source_region)
	if other_targets.is_empty():
		return {}

	var embark_port: Node = _closest_site_to(source_camp, owned_ports)
	return {
		"target": other_targets.pick_random() as Node2D,
		"use_transport": true,
		"embark_port": embark_port,
	}


func _closest_site_to(from_site: Node, sites: Array) -> Node:
	var best: Node = null
	var best_d2: float = INF
	if not is_instance_valid(from_site):
		return null
	var from_pos: Vector2 = (from_site as Node2D).global_position
	for site in sites:
		if not (site is Node2D) or not is_instance_valid(site):
			continue
		var d2: float = from_pos.distance_squared_to((site as Node2D).global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = site
	return best


func _try_start_new_raids(land_camps: Array, owned_ports: Array) -> void:
	var max_raids: int = int(_profile.get("max_raids", 1))
	while _active_raid_count() < max_raids:
		var available_camps: Array = []
		for camp in land_camps:
			if is_instance_valid(camp) and not _camp_has_active_raid(camp):
				available_camps.append(camp)
		if available_camps.is_empty():
			break

		var source_camp: Node = available_camps.pick_random()
		var composition: Dictionary = ARMY_COMPOSITIONS.pick_random()
		var plan: Array[int] = _flatten_composition(composition)
		if plan.is_empty():
			break

		var first_unit_cost: int = _composition_total_cost(source_camp, [plan[0]])
		if ai_gold < first_unit_cost:
			break

		var target_info: Dictionary = _pick_raid_target(source_camp, owned_ports)
		if target_info.is_empty() or target_info.get("target") == null:
			break

		var target: Node2D = target_info["target"]
		var raid := {
			"id": _next_raid_id,
			"source_camp": source_camp,
			"target": target,
			"plan_remaining": plan.duplicate(),
			"plan_total": plan.size(),
			"units": [],
			"phase": RAID_PHASE_BUILDING,
			"use_transport": bool(target_info.get("use_transport", false)),
			"embark_port": target_info.get("embark_port"),
			"transporter": null,
		}
		_next_raid_id += 1
		_active_raids.append(raid)


func _queue_unit_on_camp(camp: Node, unit_id: int) -> bool:
	if not is_instance_valid(camp):
		return false
	var catalog_variant: Variant = camp.get("unit_catalog")
	if not (catalog_variant is Dictionary):
		return false
	var catalog: Dictionary = catalog_variant
	if not catalog.has(unit_id):
		return false
	var queue: Array = camp.get("production_queue")
	if queue.size() >= int(_profile.get("queue_limit", 8)):
		return false
	var data: UnitStats = catalog[unit_id]
	if ai_gold < data.price:
		return false
	ai_gold -= data.price
	camp.production_queue.append(unit_id)
	if camp.production_queue.size() == 1:
		camp.current_unit_total_time = camp.unit_build_time(unit_id) if camp.has_method("unit_build_time") else data.build_time
		camp.remaining_time = camp.current_unit_total_time
	return true


func _handle_raid_production(land_camps: Array) -> void:
	var units_per_think: int = int(_profile.get("units_per_think", 4))
	for raid in _active_raids:
		if int(raid.get("phase", RAID_PHASE_BUILDING)) != RAID_PHASE_BUILDING:
			continue
		var source_camp: Node = raid.get("source_camp")
		if not is_instance_valid(source_camp):
			continue
		var plan_remaining: Array = raid.get("plan_remaining", [])
		var queued: int = 0
		while queued < units_per_think and not plan_remaining.is_empty():
			var queue: Array = source_camp.get("production_queue")
			if queue.size() >= int(_profile.get("queue_limit", 8)):
				break
			var next_unit_id: int = int(plan_remaining[0])
			if _queue_unit_on_camp(source_camp, next_unit_id):
				plan_remaining.pop_front()
				queued += 1
			else:
				break


func _handle_port_production(owned_ports: Array) -> void:
	if owned_ports.is_empty() or not bool(_profile.get("use_ports", true)):
		return

	var needs_transport: bool = false
	for raid in _active_raids:
		if not bool(raid.get("use_transport", false)):
			continue
		if int(raid.get("phase", RAID_PHASE_BUILDING)) > RAID_PHASE_BUILDING:
			var transporter: Variant = raid.get("transporter")
			if transporter == null or not is_instance_valid(transporter):
				needs_transport = true
				break

	if not needs_transport and current_difficulty != MapSession.AIDifficulty.HARD:
		return

	for port in owned_ports:
		if not is_instance_valid(port):
			continue
		var queue: Array = port.get("production_queue")
		if queue.size() >= int(_profile.get("queue_limit", 8)):
			continue
		if needs_transport:
			if _queue_unit_on_camp(port, PORT_UNIT_TRANSPORT):
				return
		elif current_difficulty == MapSession.AIDifficulty.HARD:
			var catalog: Dictionary = port.get("unit_catalog")
			if catalog.has(1) and _queue_unit_on_camp(port, 1):
				return


func _spend_excess_gold_on_camps(land_camps: Array) -> void:
	if ai_gold < 200:
		return
	var units_per_think: int = int(_profile.get("units_per_think", 4))
	for camp in land_camps:
		if not is_instance_valid(camp) or _camp_has_active_raid(camp):
			continue
		var catalog: Dictionary = camp.get("unit_catalog")
		if not (catalog is Dictionary) or catalog.is_empty():
			continue
		var queued: int = 0
		while queued < units_per_think and ai_gold >= 200:
			var queue: Array = camp.get("production_queue")
			if queue.size() >= int(_profile.get("queue_limit", 8)):
				break
			var unit_id: int = _pick_unit_id_for_camp(camp, catalog, false)
			if unit_id == -1:
				break
			if _queue_unit_on_camp(camp, unit_id):
				queued += 1
			else:
				break


func _assign_spawned_units_to_raids() -> void:
	for troop in _get_enemy_troops():
		if not is_instance_valid(troop):
			continue
		if _unit_type_of(troop) == UnitStats.UnitType.WATER_TRANSPORT:
			continue
		if troop.has_meta("ai_raid_id"):
			continue
		for raid in _active_raids:
			var source_camp: Node = raid.get("source_camp")
			if not is_instance_valid(source_camp):
				continue
			if troop.global_position.distance_to(source_camp.global_position) > RAID_ASSIGN_RADIUS:
				continue
			var units: Array = raid.get("units", [])
			if units.size() >= int(raid.get("plan_total", 0)):
				continue
			units.append(troop)
			raid["units"] = units
			troop.set_meta("ai_raid_id", int(raid.get("id", 0)))
			break


func _raid_units_ready(raid: Dictionary) -> bool:
	var plan_remaining: Array = raid.get("plan_remaining", [])
	if not plan_remaining.is_empty():
		return false
	var source_camp: Node = raid.get("source_camp")
	if is_instance_valid(source_camp):
		var queue: Array = source_camp.get("production_queue")
		if not queue.is_empty():
			return false
	return int((raid.get("units", []) as Array).size()) >= int(raid.get("plan_total", 0))


func _advance_raid_phase_if_ready(raid: Dictionary) -> void:
	if not _raid_units_ready(raid):
		return
	if bool(raid.get("use_transport", false)):
		raid["phase"] = RAID_PHASE_GATHERING
	else:
		raid["phase"] = RAID_PHASE_ATTACKING


func _find_idle_transporter() -> Node2D:
	for troop in _get_enemy_troops():
		if not is_instance_valid(troop):
			continue
		if troop.has_meta("ai_raid_id"):
			continue
		if _unit_type_of(troop) != UnitStats.UnitType.WATER_TRANSPORT:
			continue
		if troop.has_method("get_water_transport_phase") \
				and int(troop.get_water_transport_phase()) == TRANSPORT_PHASE_IDLE \
				and troop.has_method("can_use_water_transport") \
				and troop.can_use_water_transport():
			return troop
	return null


func _update_active_raids() -> void:
	for raid in _active_raids:
		_advance_raid_phase_if_ready(raid)
		var phase: int = int(raid.get("phase", RAID_PHASE_BUILDING))
		match phase:
			RAID_PHASE_GATHERING:
				_execute_raid_gathering(raid)
			RAID_PHASE_TRANSPORT:
				_execute_raid_transport(raid)
			RAID_PHASE_ATTACKING:
				_execute_raid_attack(raid)


func _execute_raid_gathering(raid: Dictionary) -> void:
	var embark_port: Node = raid.get("embark_port")
	var target: Node2D = raid.get("target")
	if not is_instance_valid(embark_port) or not is_instance_valid(target):
		raid["phase"] = RAID_PHASE_ATTACKING
		return

	var transporter: Node2D = raid.get("transporter")
	if transporter == null or not is_instance_valid(transporter):
		transporter = _find_idle_transporter()
		raid["transporter"] = transporter

	var rally_point: Vector2 = (embark_port as Node2D).global_position
	for unit in raid.get("units", []):
		if is_instance_valid(unit) and unit.has_method("move_to"):
			if unit.global_position.distance_to(rally_point) > RAID_GATHER_RADIUS:
				unit.move_to(rally_point)

	if transporter == null or not is_instance_valid(transporter):
		return

	if transporter.has_method("move_to"):
		transporter.move_to(rally_point)

	var all_near_port: bool = true
	for unit in raid.get("units", []):
		if not is_instance_valid(unit):
			continue
		if unit.global_position.distance_to(rally_point) > RAID_GATHER_RADIUS:
			all_near_port = false
			break

	if not all_near_port:
		return
	if transporter.global_position.distance_to(rally_point) > RAID_GATHER_RADIUS + 40.0:
		return
	if transporter.has_method("water_transport_step"):
		transporter.water_transport_step()
	if transporter.has_method("get_water_transport_phase") \
			and int(transporter.get_water_transport_phase()) == TRANSPORT_PHASE_CARRYING:
		raid["phase"] = RAID_PHASE_TRANSPORT


func _execute_raid_transport(raid: Dictionary) -> void:
	var transporter: Node2D = raid.get("transporter")
	var target: Node2D = raid.get("target")
	if not is_instance_valid(transporter) or not is_instance_valid(target):
		raid["phase"] = RAID_PHASE_ATTACKING
		return

	var disembark_point: Vector2 = _TransportCtrl.nearest_ground_point(transporter, target.global_position)
	if disembark_point == Vector2.INF:
		disembark_point = target.global_position

	if transporter.has_method("move_to"):
		transporter.move_to(disembark_point)

	if transporter.has_method("get_water_transport_phase") \
			and int(transporter.get_water_transport_phase()) == TRANSPORT_PHASE_CARRYING \
			and transporter.global_position.distance_to(disembark_point) <= float(_profile.get("disembark_distance", 150.0)):
		if transporter.has_method("water_transport_step"):
			transporter.water_transport_step()
		raid["phase"] = RAID_PHASE_ATTACKING


func _execute_raid_attack(raid: Dictionary) -> void:
	var target: Node2D = raid.get("target")
	if not is_instance_valid(target):
		return
	for unit in raid.get("units", []):
		if is_instance_valid(unit):
			_issue_attack_order(unit, target)
	if raid.has("transporter"):
		var transporter: Variant = raid.get("transporter")
		if transporter is Node2D and is_instance_valid(transporter):
			if transporter.has_method("get_water_transport_phase") \
					and int(transporter.get_water_transport_phase()) == TRANSPORT_PHASE_IDLE:
				_issue_attack_order(transporter, target)


func _cleanup_raids() -> void:
	var survivors: Array[Dictionary] = []
	for raid in _active_raids:
		var target: Node2D = raid.get("target")
		if is_instance_valid(target) and int(target.get("team")) == TEAM_AI:
			for unit in raid.get("units", []):
				if is_instance_valid(unit):
					unit.remove_meta("ai_raid_id")
			continue

		var live_units: int = 0
		for unit in raid.get("units", []):
			if is_instance_valid(unit):
				live_units += 1

		if live_units == 0 and _raid_units_ready(raid):
			for unit in raid.get("units", []):
				if is_instance_valid(unit):
					unit.remove_meta("ai_raid_id")
			continue

		if int(raid.get("phase", RAID_PHASE_BUILDING)) == RAID_PHASE_ATTACKING and live_units == 0:
			continue

		survivors.append(raid)
	_active_raids = survivors


func _command_loose_troops() -> void:
	var loose_land: Array[Node2D] = []
	var loose_naval: Array[Node2D] = []
	var loose_transporters: Array[Node2D] = []
	for troop in _get_enemy_troops():
		if not is_instance_valid(troop) or troop.has_meta("ai_raid_id"):
			continue
		var unit_type: int = _unit_type_of(troop)
		if unit_type == UnitStats.UnitType.WATER_TRANSPORT:
			loose_transporters.append(troop)
		elif unit_type == UnitStats.UnitType.WATER_TANK or unit_type == UnitStats.UnitType.WATER_RANGE:
			loose_naval.append(troop)
		else:
			loose_land.append(troop)
	if not loose_land.is_empty():
		_command_troop_group(loose_land, false, NAV_LAYER_GROUND)
	if not loose_naval.is_empty():
		_command_troop_group(loose_naval, true, NAV_LAYER_WATER)
	if bool(_profile.get("allow_transport", false)) and not loose_transporters.is_empty():
		_handle_transporters(loose_transporters)
