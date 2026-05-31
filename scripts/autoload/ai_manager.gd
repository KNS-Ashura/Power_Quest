extends Node

const TEAM_PLAYER := 0
const TEAM_AI := 1
const TEAM_NEUTRAL := 2

const UNIT_INFANTRY := 0
const UNIT_RANGE := 1
const UNIT_HEAVY := 2
const UNIT_SUPPORT := 3
const UNIT_HEAL := 4
const UNIT_ANTI_ARMOR := 5
const UNIT_MORTAR := 6
const PORT_UNIT_TRANSPORT := 0

const TRANSPORT_MARK_RADIUS := 150.0
const COMBAT_SPELL_RADIUS := 180.0

const STARTING_GOLD := 200
const STARTING_GOLD_HARD := 350

const _TransportCtrl = preload("res://scripts/characters/player_transport_controller.gd")

## Logical squads: lots of infantry + heal + support, sometimes range/heavy.
const SQUAD_TEMPLATES: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_HEAL, UNIT_SUPPORT],
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_HEAL],
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_RANGE, UNIT_RANGE, UNIT_HEAL, UNIT_SUPPORT],
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_HEAL, UNIT_SUPPORT, UNIT_RANGE],
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_HEAVY, UNIT_HEAL, UNIT_SUPPORT],
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_ANTI_ARMOR, UNIT_HEAL],
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_HEAL, UNIT_SUPPORT],
]

const PROFILE_SIMPLE := {
	"think_interval": 0.85,
	"units_per_tick": 2,
	"queue_limit": 10,
	"upgrade_chance": 0.06,
	"player_target_bias": 0.55,
	"income_multiplier": 1.0,
}
const PROFILE_NORMAL := {
	"think_interval": 0.45,
	"units_per_tick": 3,
	"queue_limit": 14,
	"upgrade_chance": 0.1,
	"player_target_bias": 0.72,
	"income_multiplier": 1.0,
}
const PROFILE_HARD := {
	"think_interval": 0.22,
	"units_per_tick": 5,
	"queue_limit": 18,
	"upgrade_chance": 0.12,
	"player_target_bias": 0.88,
	"income_multiplier": 1.35,
}

var current_difficulty: int = MapSession.AIDifficulty.NORMAL
var ai_gold: int = STARTING_GOLD
var think_timer: Timer
var _profile: Dictionary = PROFILE_NORMAL
var _squad_remaining: Array[int] = []
var _focus_camp: Node2D = null
var _focus_refresh_ticks: int = 0
const FOCUS_REFRESH_TICKS := 28


func _ready() -> void:
	think_timer = Timer.new()
	add_child(think_timer)
	_set_difficulty(MapSession.get_ai_difficulty())
	think_timer.timeout.connect(_on_think)
	think_timer.start()
	GameManager.global_timer.timeout.connect(_on_global_cycle)


func init_match() -> void:
	_set_difficulty(MapSession.get_ai_difficulty())
	ai_gold = STARTING_GOLD_HARD if current_difficulty == MapSession.AIDifficulty.HARD else STARTING_GOLD
	_squad_remaining.clear()
	_focus_camp = null
	_focus_refresh_ticks = 0
	if is_instance_valid(think_timer):
		if not think_timer.is_stopped():
			think_timer.stop()
		think_timer.start()


func _on_global_cycle() -> void:
	if MapSession.is_online_match:
		return
	var income_mult: float = float(_profile.get("income_multiplier", 1.0))
	ai_gold += int(round(float(GameManager.cycle_gold_bonus) * income_mult))
	for camp in _owned_camps():
		var bonus: int = RegionManager.bonus_income_for_site(camp)
		var income: int = int(camp.income_per_second) + bonus
		ai_gold += int(round(float(income) * GameManager.cycle_time * income_mult))


func _on_think() -> void:
	if MapSession.is_online_match or GameManager.match_over:
		return
	if current_difficulty != MapSession.get_ai_difficulty():
		_set_difficulty(MapSession.get_ai_difficulty())

	var owned: Array = _owned_camps()
	if owned.is_empty():
		return

	_bot_produce(owned)
	_bot_maybe_upgrade(owned)
	_bot_spells()
	_bot_attack()
	_bot_transport()


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
		think_timer.wait_time = float(_profile.get("think_interval", 0.45))


func _owned_camps() -> Array:
	return _camps_for_team(TEAM_AI)


func _camps_for_team(team: int) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("camps"):
		if is_instance_valid(node) and int(node.get("team")) == team:
			result.append(node)
	return result


func _land_camps(camps: Array) -> Array:
	var result: Array = []
	for camp in camps:
		if is_instance_valid(camp) and (not camp.has_method("is_port") or not camp.is_port()):
			result.append(camp)
	return result


func _owned_ports() -> Array:
	var result: Array = []
	for camp in _owned_camps():
		if is_instance_valid(camp) and camp.has_method("is_port") and camp.is_port():
			result.append(camp)
	return result


func _hostile_camps() -> Array:
	var result: Array = []
	for team in [TEAM_PLAYER, TEAM_NEUTRAL]:
		result.append_array(_camps_for_team(team))
	return result


func _pick_focus_camp() -> Node2D:
	var player_camps: Array = _camps_for_team(TEAM_PLAYER)
	var neutral_camps: Array = _camps_for_team(TEAM_NEUTRAL)
	var pool: Array = []
	var bias: float = float(_profile.get("player_target_bias", 0.7))
	if not player_camps.is_empty() and (neutral_camps.is_empty() or randf() < bias):
		pool = player_camps
	elif not neutral_camps.is_empty():
		pool = neutral_camps
	elif not player_camps.is_empty():
		pool = player_camps
	else:
		return null

	var rally: Vector2 = _ai_rally_point()
	var best: Node2D = null
	var best_d2: float = INF
	for camp in pool:
		if not (camp is Node2D) or not is_instance_valid(camp):
			continue
		var d2: float = rally.distance_squared_to((camp as Node2D).global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = camp as Node2D
	return best if best != null else pool.pick_random() as Node2D


func _ai_rally_point() -> Vector2:
	var owned: Array = _owned_camps()
	if owned.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	var count: int = 0
	for camp in owned:
		if camp is Node2D and is_instance_valid(camp):
			sum += (camp as Node2D).global_position
			count += 1
	return sum / float(maxi(1, count))


func _get_focus_camp() -> Node2D:
	_focus_refresh_ticks += 1
	var needs_refresh: bool = _focus_refresh_ticks >= FOCUS_REFRESH_TICKS
	if is_instance_valid(_focus_camp):
		var owner: int = int(_focus_camp.get("team"))
		if owner == TEAM_AI:
			needs_refresh = true
	else:
		needs_refresh = true

	if needs_refresh:
		_focus_refresh_ticks = 0
		_focus_camp = _pick_focus_camp()
	return _focus_camp


func _refill_squad() -> void:
	var template: Array = SQUAD_TEMPLATES.pick_random()
	_squad_remaining.clear()
	for unit_id in template:
		_squad_remaining.append(int(unit_id))


func _bot_produce(owned: Array) -> void:
	if _squad_remaining.is_empty():
		_refill_squad()

	var land: Array = _land_camps(owned)
	if land.is_empty():
		return
	land.shuffle()

	var budget: int = int(_profile.get("units_per_tick", 3))
	var queue_limit: int = int(_profile.get("queue_limit", 14))

	for camp in land:
		if budget <= 0:
			break
		if not is_instance_valid(camp):
			continue
		var queue: Array = camp.get("production_queue")
		while budget > 0 and not _squad_remaining.is_empty() and queue.size() < queue_limit:
			var unit_id: int = _squad_remaining[0]
			if _queue_unit(camp, unit_id):
				_squad_remaining.pop_front()
				budget -= 1
			else:
				break

	# Keep one transport cooking if we own a port and gold allows.
	if randf() < 0.35:
		for port in _owned_ports():
			if not is_instance_valid(port):
				continue
			var q: Array = port.get("production_queue")
			if q.size() >= queue_limit:
				continue
			_queue_unit(port, PORT_UNIT_TRANSPORT)
			break


func _queue_unit(camp: Node, unit_id: int) -> bool:
	if not is_instance_valid(camp):
		return false
	var catalog: Dictionary = camp.get("unit_catalog")
	if not (catalog is Dictionary) or not catalog.has(unit_id):
		return false
	var data: UnitStats = catalog[unit_id]
	if data == null or ai_gold < data.price:
		return false
	ai_gold -= data.price
	camp.production_queue.append(unit_id)
	if camp.production_queue.size() == 1:
		camp.current_unit_total_time = camp.unit_build_time(unit_id) if camp.has_method("unit_build_time") else data.build_time
		camp.remaining_time = camp.current_unit_total_time
	return true


func _bot_maybe_upgrade(owned: Array) -> void:
	if randf() > float(_profile.get("upgrade_chance", 0.1)):
		return
	if ai_gold < 280:
		return

	var best: Node = null
	var best_score: float = -INF
	for camp in owned:
		if not is_instance_valid(camp):
			continue
		if not camp.has_method("can_upgrade") or not camp.can_upgrade(TEAM_AI):
			continue
		var cost: int = int(camp.next_upgrade_cost()) if camp.has_method("next_upgrade_cost") else -1
		if cost <= 0 or ai_gold < cost + 120:
			continue
		var score: float = float(4 - int(camp.get("camp_level")))
		if score > best_score:
			best_score = score
			best = camp

	if best != null and best.has_method("upgrade_camp"):
		var cost: int = int(best.next_upgrade_cost())
		if cost > 0 and best.upgrade_camp(false, TEAM_AI):
			ai_gold -= cost


func _bot_attack() -> void:
	var target: Node2D = _get_focus_camp()
	if target == null:
		return

	var target_id: int = target.get_instance_id()
	for troop in _ai_troops():
		if not is_instance_valid(troop):
			continue
		var unit_type: int = _unit_type(troop)
		if unit_type == UnitStats.UnitType.WATER_TRANSPORT:
			continue
		if unit_type == UnitStats.UnitType.WATER_TANK or unit_type == UnitStats.UnitType.WATER_RANGE:
			if _troop_needs_new_order(troop, target_id):
				_order_naval(troop, target)
			continue
		if _troop_needs_new_order(troop, target_id):
			_order_land_attack(troop, target)


func _troop_needs_new_order(troop: Node2D, target_camp_id: int) -> bool:
	if int(troop.get_meta("ai_camp_target", -1)) != target_camp_id:
		return true
	var attack_node: Variant = troop.get("attack_target_node")
	if attack_node is Node2D and is_instance_valid(attack_node):
		if troop.has_method("_is_valid_combat_target") and troop._is_valid_combat_target(attack_node):
			return false
	if troop.has_method("get") and troop.get("agent_navigation") is NavigationAgent2D:
		var agent: NavigationAgent2D = troop.agent_navigation
		if not agent.is_navigation_finished():
			return false
	return true


func _order_land_attack(troop: Node2D, target_camp: Node2D) -> void:
	troop.set_meta("ai_camp_target", target_camp.get_instance_id())
	var guardian: Node2D = _guardian(target_camp)
	if guardian != null and troop.has_method("attack_target"):
		troop.attack_target(guardian)
	elif troop.has_method("move_to"):
		troop.move_to(target_camp.global_position)


func _order_naval(troop: Node2D, target_camp: Node2D) -> void:
	troop.set_meta("ai_camp_target", target_camp.get_instance_id())
	var guardian: Node2D = _guardian(target_camp)
	if guardian != null and troop.has_method("attack_target"):
		troop.attack_target(guardian)
	elif troop.has_method("move_to"):
		troop.move_to(target_camp.global_position)


func _bot_transport() -> void:
	if _owned_ports().is_empty():
		return

	for troop in _ai_troops():
		if not is_instance_valid(troop):
			continue
		if _unit_type(troop) != UnitStats.UnitType.WATER_TRANSPORT:
			continue
		_operate_transporter(troop as Node2D)


func _operate_transporter(transporter: Node2D) -> void:
	if not transporter.has_method("get_water_transport_phase"):
		return

	var phase: int = int(transporter.get_water_transport_phase())
	if phase == 0: # IDLE — embarque seulement les unités déjà au port, sans les tirer.
		var near: int = _boardable_count(transporter, _ai_troops())
		if near > 0 and transporter.has_method("can_use_water_transport") and transporter.can_use_water_transport():
			if transporter.has_method("water_transport_step"):
				transporter.water_transport_step()
	elif phase == 1: # MARKED
		if transporter.has_method("water_transport_step"):
			transporter.water_transport_step()
	elif phase == 2: # CARRYING
		var target: Node2D = _get_focus_camp()
		if target == null:
			return
		var land_point: Vector2 = _TransportCtrl.nearest_ground_point(transporter, target.global_position)
		if land_point == Vector2.INF:
			land_point = target.global_position
		if transporter.has_method("move_to"):
			transporter.move_to(land_point)
		if transporter.global_position.distance_to(land_point) <= 160.0:
			if transporter.has_method("water_transport_step"):
				transporter.water_transport_step()


func _boardable_count(transporter: Node2D, troops: Array[Node2D]) -> int:
	var count: int = 0
	for troop in troops:
		if not is_instance_valid(troop) or troop == transporter:
			continue
		var ut: int = _unit_type(troop)
		if ut == UnitStats.UnitType.WATER_TRANSPORT \
				or ut == UnitStats.UnitType.WATER_TANK \
				or ut == UnitStats.UnitType.WATER_RANGE:
			continue
		if troop.global_position.distance_to(transporter.global_position) > TRANSPORT_MARK_RADIUS:
			continue
		if _TransportCtrl.is_land_unit_transportable(transporter, troop):
			count += 1
	return count


func _bot_spells() -> void:
	for troop in _ai_troops():
		if not is_instance_valid(troop):
			continue
		if not troop.has_method("can_cast_spell") or not troop.has_method("cast_spell"):
			continue
		if not troop.can_cast_spell():
			continue
		if not _troop_in_combat(troop):
			continue
		troop.cast_spell()


func _troop_in_combat(troop: Node2D) -> bool:
	if troop.get("attack_target_node") != null:
		var target: Variant = troop.attack_target_node
		if target is Node2D and is_instance_valid(target):
			return true
	if troop.has_method("get") and troop.get("zone_detection") is Area2D:
		var zone: Area2D = troop.zone_detection
		for body in zone.get_overlapping_bodies():
			if not is_instance_valid(body) or body == troop:
				continue
			if body.is_in_group("camps"):
				continue
			if body.has_method("take_damage") and NodeTeamUtils.is_enemy_of(body, TEAM_AI):
				return true
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = COMBAT_SPELL_RADIUS
	query.shape = circle
	query.transform = Transform2D(0, troop.global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for res in troop.get_world_2d().direct_space_state.intersect_shape(query):
		var obj: Variant = res.collider
		if obj == null or obj == troop:
			continue
		if obj.has_method("take_damage") and NodeTeamUtils.is_enemy_of(obj, TEAM_AI):
			return true
	return false


func _ai_troops() -> Array[Node2D]:
	var troops: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Node2D and is_instance_valid(node):
			troops.append(node)
	return troops


func _unit_type(troop: Node2D) -> int:
	var stats_variant: Variant = troop.get("stats")
	if stats_variant is UnitStats:
		return int((stats_variant as UnitStats).unit_type)
	return -1


func _guardian(camp: Node2D) -> Node2D:
	var g: Variant = camp.get("guardian")
	if g is Node2D and is_instance_valid(g):
		return g
	return null
