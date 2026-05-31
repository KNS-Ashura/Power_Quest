extends Node

var current_difficulty: int = MapSession.AIDifficulty.NORMAL
var think_timer: Timer
var _profile: Dictionary = AIConstants.PROFILE_NORMAL

var _squad_slots: Array[Dictionary] = []
var _naval_squad_slots: Array[Dictionary] = []
var _squads: Dictionary = {}
var _camp_to_squad: Dictionary = {}
var _slot_by_squad: Dictionary = {}
var _naval_slot_by_squad: Dictionary = {}
var _defend_cooldowns: Dictionary = {}
var _next_squad_id: int = 1
var _last_template_index: int = -1
var _upgrade_timer: float = 0.0
var _spawn_credit_timer: float = 0.0
var _connected_camps: Dictionary = {}
var _capture_listeners: Dictionary = {}
var _camp_healer_units: Dictionary = {}
var _pending_dedicated_healer: Dictionary = {}
var _camp_healer_granted: Dictionary = {}
var _ai_owned_camp_ids: Dictionary = {}
var _squad_spawn_credits: int = 0
var _ai_troop_deaths: int = 0
var _hard_guardian_upgrades_used: int = 0
var _guardian_low_hp_upgraded: Dictionary = {}
var _transport_missions: Dictionary = {}
var _transport_missions_by_port: Dictionary = {}

var camps: AICampService
var targeting: AITargetingService
var templates: AITemplateService
var healers: AIHealerService
var squads: AISquadService
var transport: AITransportService
var troops: AITroopService
var upgrades: AIUpgradeService


func _ready() -> void:
	_init_services()
	think_timer = Timer.new()
	add_child(think_timer)
	_set_difficulty(MapSession.get_ai_difficulty())
	think_timer.timeout.connect(_on_think)
	think_timer.start()


func _init_services() -> void:
	camps = AICampService.new(self)
	targeting = AITargetingService.new(self, camps)
	templates = AITemplateService.new(self, camps, targeting)
	healers = AIHealerService.new(self, camps)
	transport = AITransportService.new(self, camps, targeting, templates)
	squads = AISquadService.new(self, camps, targeting, templates)
	troops = AITroopService.new(self, camps, targeting)
	upgrades = AIUpgradeService.new(self, camps)


func init_match() -> void:
	_set_difficulty(MapSession.get_ai_difficulty())
	squads.reset_squad_state()
	_upgrade_timer = 0.0
	_spawn_credit_timer = AIConstants.SQUAD_SPAWN_CREDIT_INTERVAL
	_connected_camps.clear()
	_capture_listeners.clear()
	_camp_healer_units.clear()
	_pending_dedicated_healer.clear()
	_camp_healer_granted.clear()
	_ai_owned_camp_ids.clear()
	_ai_troop_deaths = 0
	_hard_guardian_upgrades_used = 0
	_guardian_low_hp_upgraded.clear()
	_transport_missions.clear()
	_transport_missions_by_port.clear()
	camps.sync_ai_camp_connections()
	camps.sync_camp_capture_listeners()
	camps.refresh_ai_owned_camps()
	_squad_spawn_credits = int(_profile.get("max_parallel_squads", 1))
	call_deferred("_deferred_grant_initial_camp_healers")
	if is_instance_valid(think_timer):
		if not think_timer.is_stopped():
			think_timer.stop()
		think_timer.start()


func _on_think() -> void:
	if MapSession.is_online_match or GameManager.match_over:
		return
	if current_difficulty != MapSession.get_ai_difficulty():
		_set_difficulty(MapSession.get_ai_difficulty())

	var owned: Array = camps.owned_camps()
	if owned.is_empty():
		return

	camps.apply_build_speed(owned)
	camps.sync_ai_camp_connections()
	camps.sync_camp_capture_listeners()
	squads.cleanup_stale_squads()
	_tick_spawn_credit_timer()
	squads.tick_squad_slots()
	squads.tick_defend_squads()
	squads.tick_naval_squad_slots()
	transport.tick_transport_missions()
	upgrades.tick_upgrades(owned)
	upgrades.tick_guardian_upgrades(owned)
	troops.bot_spells()
	troops.bot_attack()


func _set_difficulty(difficulty: int) -> void:
	current_difficulty = difficulty
	match current_difficulty:
		MapSession.AIDifficulty.SIMPLE:
			_profile = AIConstants.PROFILE_SIMPLE
		MapSession.AIDifficulty.HARD:
			_profile = AIConstants.PROFILE_HARD
		_:
			current_difficulty = MapSession.AIDifficulty.NORMAL
			_profile = AIConstants.PROFILE_NORMAL
	if is_instance_valid(think_timer):
		think_timer.wait_time = float(_profile.get("think_interval", 0.4))
	squads.resize_parallel_slots()


func _on_site_captured(new_team: int, camp: Node) -> void:
	camps.on_site_captured(new_team, camp)


func _on_camp_unit_produced(unit: Node, unit_id: int, camp: Node) -> void:
	healers.on_camp_unit_produced(unit, unit_id, camp)


func _deferred_grant_initial_camp_healers() -> void:
	healers.grant_initial_camp_healers()


func _deferred_ensure_camp_healer(camp: Node) -> void:
	healers.ensure_camp_healer(camp)


func _tick_spawn_credit_timer() -> void:
	var dt: float = float(_profile.get("think_interval", 0.4))
	_spawn_credit_timer -= dt
	if _spawn_credit_timer > 0.0:
		return
	squads.grant_spawn_credit()
	_spawn_credit_timer = AIConstants.SQUAD_SPAWN_CREDIT_INTERVAL
