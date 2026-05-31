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
const PORT_UNIT_TANK := 1
const PORT_UNIT_RANGE := 2

const SQUAD_MODE_ATTACK := "attack"
const SQUAD_MODE_DEFEND := "defend"
const SQUAD_MODE_NAVAL := "naval"

const COMBAT_SPELL_RADIUS := 180.0
const DEFEND_HOLD_RADIUS := 220.0
const HARD_GUARDIAN_UPGRADE_MAX := 3
const UNIT_CHEAP_LAND := UNIT_INFANTRY
const UNIT_EXPENSIVE_LAND := UNIT_MORTAR
const UNIT_CHEAP_NAVAL := PORT_UNIT_RANGE
const UNIT_EXPENSIVE_NAVAL := PORT_UNIT_TANK

## Facile — compositions simples, tirage aléatoire.
const SQUADS_SIMPLE: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_RANGE],
	[UNIT_HEAVY, UNIT_SUPPORT, UNIT_MORTAR],
]
## Intermédiaire — compositions plus équilibrées.
const SQUADS_NORMAL: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
	[UNIT_MORTAR, UNIT_MORTAR, UNIT_HEAL],
]
## Difficile — 5 équipes variées (siège, assault, anti-armure…).
const SQUADS_HARD: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT, UNIT_HEAL],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY, UNIT_HEAVY],
	[UNIT_MORTAR, UNIT_MORTAR, UNIT_HEAL, UNIT_ANTI_ARMOR],
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_HEAVY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_ANTI_ARMOR, UNIT_ANTI_ARMOR, UNIT_HEAL],
]

const DEFEND_SQUADS_SIMPLE: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
]
const DEFEND_SQUADS_NORMAL: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
]
const DEFEND_SQUADS_HARD: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
]

const NAVAL_SQUADS_SIMPLE: Array[Array] = [
	[PORT_UNIT_TANK],
	[PORT_UNIT_RANGE, PORT_UNIT_RANGE],
]
const NAVAL_SQUADS_NORMAL: Array[Array] = [
	[PORT_UNIT_TANK, PORT_UNIT_TANK],
	[PORT_UNIT_RANGE, PORT_UNIT_RANGE, PORT_UNIT_TANK],
]
const NAVAL_SQUADS_HARD: Array[Array] = [
	[PORT_UNIT_TANK, PORT_UNIT_TANK, PORT_UNIT_RANGE],
	[PORT_UNIT_RANGE, PORT_UNIT_RANGE, PORT_UNIT_TANK, PORT_UNIT_TANK],
]

const PROFILE_SIMPLE := {
	"think_interval": 0.5,
	"max_parallel_squads": 1,
	"squad_cooldown": 55.0,
	"build_speed": 0.75,
	"upgrade_interval": 45.0,
}
const PROFILE_NORMAL := {
	"think_interval": 0.4,
	"max_parallel_squads": 2,
	"squad_cooldown": 40.0,
	"build_speed": 1.0,
	"upgrade_interval": 30.0,
}
const PROFILE_HARD := {
	"think_interval": 0.3,
	"max_parallel_squads": 3,
	"squad_cooldown": 25.0,
	"build_speed": 1.5,
	"upgrade_interval": 20.0,
}

var current_difficulty: int = MapSession.AIDifficulty.NORMAL
var think_timer: Timer
var _profile: Dictionary = PROFILE_NORMAL

var _squad_slots: Array[Dictionary] = []
var _naval_squad_slots: Array[Dictionary] = []
var _squads: Dictionary = {}
var _camp_to_squad: Dictionary = {}
var _slot_by_squad: Dictionary = {}
var _naval_slot_by_squad: Dictionary = {}
var _defend_cooldowns: Dictionary = {}
var _next_squad_id: int = 1
var _last_template_index: int = -1
var _last_naval_template_index: int = -1
var _upgrade_timer: float = 0.0
var _connected_camps: Dictionary = {}
var _capture_listeners: Dictionary = {}
var _camp_healer_units: Dictionary = {}
var _pending_dedicated_healer: Dictionary = {}
var _hard_guardian_upgrades_used: int = 0
var _guardian_low_hp_upgraded: Dictionary = {}


func _ready() -> void:
	think_timer = Timer.new()
	add_child(think_timer)
	_set_difficulty(MapSession.get_ai_difficulty())
	think_timer.timeout.connect(_on_think)
	think_timer.start()


func init_match() -> void:
	_set_difficulty(MapSession.get_ai_difficulty())
	_reset_squad_state()
	_upgrade_timer = 0.0
	_connected_camps.clear()
	_capture_listeners.clear()
	_camp_healer_units.clear()
	_pending_dedicated_healer.clear()
	_hard_guardian_upgrades_used = 0
	_guardian_low_hp_upgraded.clear()
	_sync_ai_camp_connections()
	_sync_camp_capture_listeners()
	if is_instance_valid(think_timer):
		if not think_timer.is_stopped():
			think_timer.stop()
		think_timer.start()


func _reset_squad_state() -> void:
	_squads.clear()
	_camp_to_squad.clear()
	_slot_by_squad.clear()
	_naval_slot_by_squad.clear()
	_defend_cooldowns.clear()
	_next_squad_id = 1
	_last_template_index = -1
	_last_naval_template_index = -1
	_squad_slots.clear()
	_naval_squad_slots.clear()
	var parallel: int = int(_profile.get("max_parallel_squads", 1))
	for _i in range(parallel):
		_squad_slots.append({"busy": false, "cooldown": 0.0})
		_naval_squad_slots.append({"busy": false, "cooldown": 0.0})


func _on_think() -> void:
	if MapSession.is_online_match or GameManager.match_over:
		return
	if current_difficulty != MapSession.get_ai_difficulty():
		_set_difficulty(MapSession.get_ai_difficulty())

	var owned: Array = _owned_camps()
	if owned.is_empty():
		return

	_apply_build_speed(owned)
	_sync_ai_camp_connections()
	_sync_camp_capture_listeners()
	_cleanup_stale_squads()
	_tick_squad_slots()
	_tick_defend_squads()
	_tick_naval_squad_slots()
	_tick_camp_healers()
	_tick_upgrades(owned)
	_tick_guardian_upgrades(owned)
	_bot_spells()
	_bot_attack()


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
		think_timer.wait_time = float(_profile.get("think_interval", 0.4))
	var parallel: int = int(_profile.get("max_parallel_squads", 1))
	while _squad_slots.size() < parallel:
		_squad_slots.append({"busy": false, "cooldown": 0.0})
	while _naval_squad_slots.size() < parallel:
		_naval_squad_slots.append({"busy": false, "cooldown": 0.0})


func _apply_build_speed(camps: Array) -> void:
	var speed: float = float(_profile.get("build_speed", 1.0))
	for camp in camps:
		if is_instance_valid(camp):
			camp.ai_build_speed_multiplier = speed


func _sync_ai_camp_connections() -> void:
	for camp in _owned_camps():
		if not is_instance_valid(camp):
			continue
		var camp_id: int = camp.get_instance_id()
		if _connected_camps.has(camp_id):
			continue
		if camp.has_signal("unit_produced") and not camp.unit_produced.is_connected(_on_camp_unit_produced):
			camp.unit_produced.connect(_on_camp_unit_produced.bind(camp))
		_connected_camps[camp_id] = true


func _sync_camp_capture_listeners() -> void:
	for camp in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(camp):
			continue
		var camp_id: int = camp.get_instance_id()
		if _capture_listeners.has(camp_id):
			continue
		if camp.has_signal("site_captured") and not camp.site_captured.is_connected(_on_site_captured):
			camp.site_captured.connect(_on_site_captured.bind(camp))
		_capture_listeners[camp_id] = true


func _on_site_captured(new_team: int, camp: Node) -> void:
	if MapSession.is_online_match or not _maintains_camp_healers():
		return
	if int(new_team) != TEAM_AI:
		return
	if not is_instance_valid(camp) or not _is_land_camp(camp):
		return
	call_deferred("_ensure_camp_healer", camp)


func _maintains_camp_healers() -> bool:
	return current_difficulty == MapSession.AIDifficulty.NORMAL \
		or current_difficulty == MapSession.AIDifficulty.HARD


func _cleanup_stale_squads() -> void:
	var stale: Array[int] = []
	for squad_id: int in _squads.keys():
		var squad: Dictionary = _squads[squad_id]
		var camp_id: int = int(squad.get("camp_id", -1))
		var camp_obj: Variant = instance_from_id(camp_id)
		if not is_instance_valid(camp_obj):
			stale.append(squad_id)
			continue
		if int(camp_obj.get("team")) != TEAM_AI:
			stale.append(squad_id)
			var lost_camp_id: int = int(squad.get("camp_id", -1))
			_pending_dedicated_healer.erase(lost_camp_id)
			_camp_healer_units.erase(lost_camp_id)
	for squad_id in stale:
		_finish_squad(squad_id)


func _tick_squad_slots() -> void:
	var dt: float = float(_profile.get("think_interval", 0.4))
	var cooldown_time: float = float(_profile.get("squad_cooldown", 30.0))
	for slot in _squad_slots:
		if slot.get("busy", false):
			continue
		var cd: float = float(slot.get("cooldown", 0.0))
		if cd > 0.0:
			slot["cooldown"] = maxf(0.0, cd - dt)
			continue
		if _launch_attack_squad(slot):
			slot["busy"] = true
			slot["cooldown"] = cooldown_time


func _tick_naval_squad_slots() -> void:
	if _owned_ports().is_empty():
		return
	var dt: float = float(_profile.get("think_interval", 0.4))
	var cooldown_time: float = float(_profile.get("squad_cooldown", 30.0))
	for slot in _naval_squad_slots:
		if slot.get("busy", false):
			continue
		var cd: float = float(slot.get("cooldown", 0.0))
		if cd > 0.0:
			slot["cooldown"] = maxf(0.0, cd - dt)
			continue
		if _launch_naval_squad(slot):
			slot["busy"] = true
			slot["cooldown"] = cooldown_time


func _tick_defend_squads() -> void:
	var dt: float = float(_profile.get("think_interval", 0.4))
	var cooldown_time: float = float(_profile.get("squad_cooldown", 30.0))
	for camp in _land_camps(_owned_camps()):
		if not is_instance_valid(camp) or not (camp is Node2D):
			continue
		var camp_id: int = camp.get_instance_id()
		if _camp_to_squad.has(camp_id):
			continue
		if _defend_cooldowns.has(camp_id):
			var cd: float = float(_defend_cooldowns[camp_id]) - dt
			if cd > 0.0:
				_defend_cooldowns[camp_id] = cd
				continue
			_defend_cooldowns.erase(camp_id)
		if _has_regional_hostile(camp as Node2D):
			continue
		var template: Array = _pick_defend_template()
		if template.is_empty():
			continue
		if _launch_squad_at_camp(camp, template, SQUAD_MODE_DEFEND, null, null):
			_defend_cooldowns[camp_id] = cooldown_time


func _tick_upgrades(owned: Array) -> void:
	if current_difficulty == MapSession.AIDifficulty.HARD:
		return
	var dt: float = float(_profile.get("think_interval", 0.4))
	_upgrade_timer -= dt
	if _upgrade_timer > 0.0:
		return
	_upgrade_timer = float(_profile.get("upgrade_interval", 45.0))

	var candidates: Array = []
	for camp in owned:
		if not is_instance_valid(camp):
			continue
		if camp.has_method("can_upgrade") and camp.can_upgrade(TEAM_AI):
			candidates.append(camp)
	if candidates.is_empty():
		return
	var pick: Node = candidates.pick_random()
	if pick.has_method("upgrade_camp"):
		pick.upgrade_camp(false, TEAM_AI)


func _tick_guardian_upgrades(owned: Array) -> void:
	if current_difficulty != MapSession.AIDifficulty.HARD:
		return
	if _hard_guardian_upgrades_used >= HARD_GUARDIAN_UPGRADE_MAX:
		return
	for camp in owned:
		if _hard_guardian_upgrades_used >= HARD_GUARDIAN_UPGRADE_MAX:
			break
		if not is_instance_valid(camp) or not camp.has_method("can_upgrade"):
			continue
		if not camp.can_upgrade(TEAM_AI):
			continue
		var guardian: Node2D = _guardian(camp as Node2D)
		if guardian == null:
			continue
		var guardian_id: int = guardian.get_instance_id()
		if _guardian_low_hp_upgraded.has(guardian_id):
			continue
		if guardian.get("current_hp") == null or guardian.get("hp_max") == null:
			continue
		var current_hp: int = int(guardian.current_hp)
		var hp_max: int = int(guardian.hp_max)
		if current_hp > hp_max / 2:
			continue
		_guardian_low_hp_upgraded[guardian_id] = true
		if camp.upgrade_camp(false, TEAM_AI):
			_hard_guardian_upgrades_used += 1


func _tick_camp_healers() -> void:
	if not _maintains_camp_healers():
		return
	for camp in _land_camps(_owned_camps()):
		_ensure_camp_healer(camp)


func _ensure_camp_healer(camp: Node) -> void:
	if not is_instance_valid(camp) or not _is_land_camp(camp):
		return
	var camp_id: int = camp.get_instance_id()
	if _camp_has_living_healer(camp_id):
		return
	if _camp_healer_queued(camp):
		return
	if not camp.unit_catalog.has(UNIT_HEAL):
		return
	if camp.has_method("request_ai_production") and camp.request_ai_production(UNIT_HEAL):
		_pending_dedicated_healer[camp_id] = true


func _camp_has_living_healer(camp_id: int) -> bool:
	var healer: Variant = _camp_healer_units.get(camp_id)
	if not is_instance_valid(healer):
		_camp_healer_units.erase(camp_id)
		return false
	if healer is Node2D:
		if healer.get("current_hp") != null and int(healer.current_hp) <= 0:
			_camp_healer_units.erase(camp_id)
			return false
		return true
	return false


func _camp_healer_queued(camp: Node) -> bool:
	if not is_instance_valid(camp):
		return false
	var camp_id: int = camp.get_instance_id()
	if _pending_dedicated_healer.has(camp_id):
		return true
	for unit_id in camp.get("production_queue"):
		if int(unit_id) == UNIT_HEAL:
			return true
	return false


func _bind_camp_healer(camp_id: int, healer: Node2D, camp: Node2D) -> void:
	if not is_instance_valid(healer):
		return
	var previous: Variant = _camp_healer_units.get(camp_id)
	if is_instance_valid(previous) and previous is Node2D and previous != healer:
		if _camp_healer_units.get(camp_id) == previous:
			_camp_healer_units.erase(camp_id)
	_camp_healer_units[camp_id] = healer
	healer.set_meta("ai_camp_healer", true)
	healer.set_meta("ai_home_camp_id", camp_id)
	if healer.has_signal("killed_by"):
		var callable: Callable = _on_camp_healer_killed.bind(healer, camp_id)
		if not healer.killed_by.is_connected(callable):
			healer.killed_by.connect(callable)
	var exit_callable: Callable = _on_camp_healer_tree_exiting.bind(healer, camp_id)
	if not healer.tree_exiting.is_connected(exit_callable):
		healer.tree_exiting.connect(exit_callable)
	if camp != null:
		_order_defend(healer, camp)


func _on_camp_healer_killed(_killer: Variant, _killer_team: Variant, healer: Node2D, camp_id: int) -> void:
	_release_camp_healer(camp_id, healer)


func _on_camp_healer_tree_exiting(healer: Node2D, camp_id: int) -> void:
	_release_camp_healer(camp_id, healer)


func _release_camp_healer(camp_id: int, healer: Node2D) -> void:
	if _camp_healer_units.get(camp_id) == healer:
		_camp_healer_units.erase(camp_id)
	_pending_dedicated_healer.erase(camp_id)


func _is_land_camp(camp: Node) -> bool:
	return is_instance_valid(camp) and (not camp.has_method("is_port") or not camp.is_port())


func _launch_attack_squad(slot: Dictionary) -> bool:
	var spawn_camp: Node = _pick_attack_spawn_camp()
	if spawn_camp == null:
		return false
	var region_id: int = _region_for_site(spawn_camp)
	var target: Node2D = _nearest_hostile_to(spawn_camp as Node2D, region_id, true)
	if target == null:
		return false
	var template: Array = _pick_squad_template(target)
	if template.is_empty():
		return false
	return _launch_squad_at_camp(spawn_camp, template, SQUAD_MODE_ATTACK, target, slot)


func _launch_naval_squad(slot: Dictionary) -> bool:
	var spawn_port: Node = _pick_naval_spawn_port()
	if spawn_port == null:
		return false
	var region_id: int = _region_for_site(spawn_port)
	var target: Node2D = _nearest_hostile_to(spawn_port as Node2D, region_id, false)
	if target == null:
		return false
	var template: Array = _pick_naval_template()
	if template.is_empty():
		return false
	return _launch_squad_at_camp(spawn_port, template, SQUAD_MODE_NAVAL, target, slot, true)


func _launch_squad_at_camp(
	spawn_camp: Node,
	template: Array,
	mode: String,
	target: Node2D,
	slot: Variant,
	is_naval_slot: bool = false
) -> bool:
	if not spawn_camp.has_method("spawn_ai_squad_units"):
		return false

	var final_template: Array = _apply_difficulty_squad_bonus(_duplicate_template(template), is_naval_slot)
	if final_template.is_empty():
		return false

	var squad_id: int = _next_squad_id
	_next_squad_id += 1
	var camp_id: int = spawn_camp.get_instance_id()
	var region_id: int = _region_for_site(spawn_camp)
	var squad: Dictionary = {
		"mode": mode,
		"camp_id": camp_id,
		"region_id": region_id,
		"target_id": target.get_instance_id() if target != null else -1,
		"remaining": 0,
		"members": [],
	}
	_squads[squad_id] = squad
	_camp_to_squad[camp_id] = squad_id
	if slot is Dictionary:
		if is_naval_slot:
			_naval_slot_by_squad[squad_id] = slot
		else:
			_slot_by_squad[squad_id] = slot

	var spawned: Array = spawn_camp.spawn_ai_squad_units(final_template)
	if spawned.is_empty():
		_abort_squad(squad_id)
		return false

	for unit in spawned:
		if is_instance_valid(unit) and unit is Node2D:
			_register_squad_member(squad_id, squad, unit as Node2D, camp_id)

	_dispatch_squad(squad)
	_finish_squad(squad_id)
	return true


func _register_squad_member(squad_id: int, squad: Dictionary, troop: Node2D, camp_id: int) -> void:
	var mode: String = str(squad.get("mode", SQUAD_MODE_ATTACK))
	var region_id: int = int(squad.get("region_id", -1))
	troop.set_meta("ai_squad_id", squad_id)
	troop.set_meta("ai_squad_mode", mode)
	troop.set_meta("ai_spawn_camp_id", camp_id)
	troop.set_meta("ai_spawn_region_id", region_id)
	var members: Array = squad.get("members", [])
	members.append(troop)
	squad["members"] = members


func _apply_difficulty_squad_bonus(template: Array, naval: bool) -> Array:
	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			if naval:
				template.append(UNIT_CHEAP_NAVAL)
			else:
				template.append(UNIT_CHEAP_LAND)
		MapSession.AIDifficulty.HARD:
			if naval:
				template.append(UNIT_CHEAP_NAVAL)
				template.append(UNIT_EXPENSIVE_NAVAL)
			else:
				template.append(UNIT_CHEAP_LAND)
				template.append(UNIT_EXPENSIVE_LAND)
		_:
			if naval:
				template.append(UNIT_EXPENSIVE_NAVAL)
			else:
				template.append(UNIT_EXPENSIVE_LAND)
	return template


func _abort_squad(squad_id: int) -> void:
	if not _squads.has(squad_id):
		return
	var data: Dictionary = _squads[squad_id]
	var camp_id: int = int(data.get("camp_id", -1))
	if _camp_to_squad.get(camp_id, -1) == squad_id:
		_camp_to_squad.erase(camp_id)
	_squads.erase(squad_id)
	_release_squad_slot(squad_id)


func _finish_squad(squad_id: int) -> void:
	if not _squads.has(squad_id):
		return
	var data: Dictionary = _squads[squad_id]
	var camp_id: int = int(data.get("camp_id", -1))
	if _camp_to_squad.get(camp_id, -1) == squad_id:
		_camp_to_squad.erase(camp_id)
	_squads.erase(squad_id)
	_release_squad_slot(squad_id)


func _release_squad_slot(squad_id: int) -> void:
	if _slot_by_squad.has(squad_id):
		var slot: Dictionary = _slot_by_squad[squad_id]
		slot["busy"] = false
		_slot_by_squad.erase(squad_id)
	if _naval_slot_by_squad.has(squad_id):
		var naval_slot: Dictionary = _naval_slot_by_squad[squad_id]
		naval_slot["busy"] = false
		_naval_slot_by_squad.erase(squad_id)


func _on_camp_unit_produced(unit: Node, unit_id: int, camp: Node) -> void:
	if not is_instance_valid(camp):
		return
	var camp_id: int = camp.get_instance_id()

	if int(unit_id) == UNIT_HEAL and _maintains_camp_healers() and _is_land_camp(camp):
		var assign_dedicated: bool = _pending_dedicated_healer.has(camp_id)
		if assign_dedicated:
			_pending_dedicated_healer.erase(camp_id)
		elif not _camp_has_living_healer(camp_id):
			assign_dedicated = true
		if assign_dedicated and is_instance_valid(unit) and unit is Node2D:
			var home_camp: Node2D = null
			if is_instance_valid(camp) and camp is Node2D:
				home_camp = camp as Node2D
			_bind_camp_healer(camp_id, unit as Node2D, home_camp)


func _dispatch_squad(squad: Dictionary) -> void:
	var mode: String = str(squad.get("mode", SQUAD_MODE_ATTACK))
	var region_id: int = int(squad.get("region_id", -1))
	var camp_id: int = int(squad.get("camp_id", -1))
	var spawn_camp_obj: Variant = instance_from_id(camp_id)
	var spawn_camp: Node2D = null
	if is_instance_valid(spawn_camp_obj) and spawn_camp_obj is Node2D:
		spawn_camp = spawn_camp_obj as Node2D
	var target: Node2D = _resolve_target(
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
			SQUAD_MODE_DEFEND:
				if spawn_camp != null:
					_order_defend(troop, spawn_camp)
			SQUAD_MODE_NAVAL:
				if target != null:
					_order_naval(troop, target)
			_:
				if target != null:
					_order_attack(troop, target)


func _pick_attack_spawn_camp() -> Node:
	var land: Array = _land_camps(_owned_camps())
	var viable: Array = []
	for camp in land:
		if not is_instance_valid(camp) or not (camp is Node2D):
			continue
		if _camp_to_squad.has(camp.get_instance_id()):
			continue
		if _nearest_hostile_to(camp as Node2D, _region_for_site(camp), true) != null:
			viable.append(camp)
	if viable.is_empty():
		return null
	viable.shuffle()
	return viable[0]


func _pick_naval_spawn_port() -> Node:
	var ports: Array = _owned_ports()
	var viable: Array = []
	for port in ports:
		if not is_instance_valid(port) or not (port is Node2D):
			continue
		if _camp_to_squad.has(port.get_instance_id()):
			continue
		if _nearest_hostile_to(port as Node2D, _region_for_site(port), false) != null:
			viable.append(port)
	if viable.is_empty():
		return null
	viable.shuffle()
	return viable[0]


func _pick_squad_template(target: Node2D) -> Array:
	var pool: Array = _templates_for_difficulty()
	if pool.is_empty():
		return []

	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return _duplicate_template(pool.pick_random())
		MapSession.AIDifficulty.HARD:
			return _duplicate_template(_pick_hard_template(pool, target))
		_:
			return _duplicate_template(_pick_normal_template(pool))


func _pick_defend_template() -> Array:
	var pool: Array = _defend_templates_for_difficulty()
	if pool.is_empty():
		return []
	return _duplicate_template(pool.pick_random())


func _pick_naval_template() -> Array:
	var pool: Array = _naval_templates_for_difficulty()
	if pool.is_empty():
		return []
	if pool.size() == 1:
		_last_naval_template_index = 0
		return _duplicate_template(pool[0])
	var idx: int = randi() % pool.size()
	if idx == _last_naval_template_index:
		idx = (idx + 1) % pool.size()
	_last_naval_template_index = idx
	return _duplicate_template(pool[idx])


func _templates_for_difficulty() -> Array:
	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return SQUADS_SIMPLE
		MapSession.AIDifficulty.HARD:
			return SQUADS_HARD
		_:
			return SQUADS_NORMAL


func _defend_templates_for_difficulty() -> Array:
	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return DEFEND_SQUADS_SIMPLE
		MapSession.AIDifficulty.HARD:
			return DEFEND_SQUADS_HARD
		_:
			return DEFEND_SQUADS_NORMAL


func _naval_templates_for_difficulty() -> Array:
	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return NAVAL_SQUADS_SIMPLE
		MapSession.AIDifficulty.HARD:
			return NAVAL_SQUADS_HARD
		_:
			return NAVAL_SQUADS_NORMAL


func _duplicate_template(template: Array) -> Array:
	var copy: Array = []
	for unit_id in template:
		copy.append(int(unit_id))
	return copy


func _pick_normal_template(pool: Array) -> Array:
	if pool.size() == 1:
		_last_template_index = 0
		return pool[0]
	var idx: int = randi() % pool.size()
	if idx == _last_template_index:
		idx = (idx + 1) % pool.size()
	_last_template_index = idx
	return pool[idx]


func _pick_hard_template(pool: Array, target: Node2D) -> Array:
	var player_owned: bool = int(target.get("team")) == TEAM_PLAYER
	var heavy_near: bool = _heavy_enemies_near(target.global_position, 420.0)

	var weights: PackedFloat32Array = PackedFloat32Array()
	for i in range(pool.size()):
		var w: float = 1.0
		var tpl: Array = pool[i]
		var has_mortar: bool = UNIT_MORTAR in tpl
		var has_anti: bool = UNIT_ANTI_ARMOR in tpl
		var has_heal: bool = UNIT_HEAL in tpl
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
		if i == _last_template_index:
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
			_last_template_index = i
			return pool[i]
	_last_template_index = 0
	return pool[0]


func _heavy_enemies_near(center: Vector2, radius: float) -> bool:
	for troop in get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(troop) or not (troop is Node2D):
			continue
		if _unit_type(troop as Node2D) != UnitStats.UnitType.HEAVY:
			continue
		if (troop as Node2D).global_position.distance_to(center) <= radius:
			return true
	return false


func _region_for_site(site: Node) -> int:
	if RegionManager.has_regions_for_current_map():
		return RegionManager.get_region_id_for_site(site)
	return -1


func _uses_regions() -> bool:
	return RegionManager.has_regions_for_current_map()


func _has_regional_hostile(origin: Node2D) -> bool:
	return _nearest_hostile_to(origin, _region_for_site(origin), true) != null


func _is_hostile_site(team: int) -> bool:
	return team == TEAM_PLAYER or team == TEAM_NEUTRAL


func _nearest_hostile_in_region_sites(origin: Node2D, region_id: int) -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for site in RegionManager.get_sites_for_region(region_id):
		if not is_instance_valid(site) or not (site is Node2D):
			continue
		if not _is_hostile_site(int(site.get("team"))):
			continue
		var site_2d: Node2D = site as Node2D
		var d2: float = origin.global_position.distance_squared_to(site_2d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = site_2d
	return best


func _nearest_hostile_outside_region_sites(origin: Node2D, region_id: int) -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for camp in _hostile_camps():
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


func _nearest_hostile_to(origin: Node2D, region_id: int = -1, same_region: bool = true) -> Node2D:
	if region_id < 0:
		region_id = _region_for_site(origin)
	if _uses_regions() and region_id >= 0:
		if same_region:
			return _nearest_hostile_in_region_sites(origin, region_id)
		return _nearest_hostile_outside_region_sites(origin, region_id)

	var best: Node2D = null
	var best_d2: float = INF
	for camp in _hostile_camps():
		if not is_instance_valid(camp) or not (camp is Node2D):
			continue
		var camp_2d: Node2D = camp as Node2D
		var d2: float = origin.global_position.distance_squared_to(camp_2d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = camp_2d
	return best


func _resolve_target(target_id: int, origin: Node2D, mode: String, region_id: int) -> Node2D:
	if target_id >= 0:
		var obj: Variant = instance_from_id(target_id)
		if is_instance_valid(obj) and obj is Node2D:
			if _target_valid_for_mode(origin, obj as Node2D, mode, region_id):
				return obj as Node2D
	if origin == null:
		return null
	match mode:
		SQUAD_MODE_NAVAL:
			return _nearest_hostile_to(origin, region_id, false)
		SQUAD_MODE_ATTACK:
			return _nearest_hostile_to(origin, region_id, true)
		_:
			return null


func _target_valid_for_mode(origin: Node2D, target: Node2D, mode: String, region_id: int) -> bool:
	if not _is_hostile_site(int(target.get("team"))):
		return false
	if not _uses_regions() or region_id < 0:
		return true
	var target_region: int = RegionManager.get_region_id_for_site(target)
	match mode:
		SQUAD_MODE_NAVAL:
			return target_region != region_id
		SQUAD_MODE_ATTACK:
			if target_region >= 0:
				return target_region == region_id
			return RegionManager.are_sites_in_same_region(origin, target)
		_:
			return true


func _spawn_camp_for_troop(troop: Node2D) -> Node2D:
	var camp_id: int = int(troop.get_meta("ai_home_camp_id", -1))
	if camp_id < 0:
		camp_id = int(troop.get_meta("ai_spawn_camp_id", -1))
	if camp_id < 0:
		return null
	var camp_obj: Variant = instance_from_id(camp_id)
	if is_instance_valid(camp_obj) and camp_obj is Node2D:
		return camp_obj as Node2D
	return null


func _owned_camps() -> Array:
	return _camps_for_team(TEAM_AI)


func _owned_ports() -> Array:
	var result: Array = []
	for camp in _owned_camps():
		if is_instance_valid(camp) and camp.has_method("is_port") and camp.is_port():
			result.append(camp)
	return result


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


func _hostile_camps() -> Array:
	var result: Array = []
	for team in [TEAM_PLAYER, TEAM_NEUTRAL]:
		result.append_array(_camps_for_team(team))
	return result


func _bot_attack() -> void:
	for troop in _ai_troops():
		if not is_instance_valid(troop):
			continue
		if _unit_type(troop) == UnitStats.UnitType.WATER_TRANSPORT:
			continue

		if troop.get_meta("ai_camp_healer", false):
			var home_camp: Node2D = _spawn_camp_for_troop(troop)
			if home_camp != null and troop.global_position.distance_to(home_camp.global_position) > DEFEND_HOLD_RADIUS:
				_order_defend(troop, home_camp)
			continue

		var mode: String = str(troop.get_meta("ai_squad_mode", SQUAD_MODE_ATTACK))
		var spawn_camp: Node2D = _spawn_camp_for_troop(troop)
		var region_id: int = int(troop.get_meta("ai_spawn_region_id", -1))

		if mode == SQUAD_MODE_DEFEND:
			if spawn_camp != null and troop.global_position.distance_to(spawn_camp.global_position) > DEFEND_HOLD_RADIUS:
				_order_defend(troop, spawn_camp)
			continue

		var target: Node2D = null
		var squad_id: int = int(troop.get_meta("ai_squad_id", -1))
		if squad_id >= 0 and _squads.has(squad_id):
			var squad: Dictionary = _squads[squad_id]
			target = _resolve_target(
				int(squad.get("target_id", -1)),
				spawn_camp if spawn_camp != null else troop,
				mode,
				int(squad.get("region_id", region_id))
			)
		if target == null and spawn_camp != null:
			match mode:
				SQUAD_MODE_NAVAL:
					target = _nearest_hostile_to(spawn_camp, region_id, false)
				_:
					target = _nearest_hostile_to(spawn_camp, region_id, true)
		if target == null:
			continue

		var target_id: int = target.get_instance_id()
		if _troop_needs_new_order(troop, target_id):
			if mode == SQUAD_MODE_NAVAL or _is_naval_unit(troop):
				_order_naval(troop, target)
			else:
				_order_attack(troop, target)


func _troop_needs_new_order(troop: Node2D, target_camp_id: int) -> bool:
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


func _order_attack(troop: Node2D, target_camp: Node2D) -> void:
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


func _order_defend(troop: Node2D, camp: Node2D) -> void:
	troop.set_meta("ai_camp_target", -1)
	if troop.has_method("move_to"):
		var offset := Vector2(randf_range(-40.0, 40.0), randf_range(-20.0, 20.0))
		troop.move_to(camp.global_position + offset)


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
		if is_instance_valid(target) and target is Node2D:
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
		if is_instance_valid(node) and node is Node2D:
			troops.append(node)
	return troops


func _is_naval_unit(troop: Node2D) -> bool:
	var ut: int = _unit_type(troop)
	return ut == UnitStats.UnitType.WATER_TANK \
		or ut == UnitStats.UnitType.WATER_RANGE \
		or ut == UnitStats.UnitType.WATER_TRANSPORT


func _unit_type(troop: Node2D) -> int:
	var stats_variant: Variant = troop.get("stats")
	if stats_variant is UnitStats:
		return int((stats_variant as UnitStats).unit_type)
	return -1


func _guardian(camp: Node2D) -> Node2D:
	var g: Variant = camp.get("guardian")
	if is_instance_valid(g) and g is Node2D:
		return g
	return null
