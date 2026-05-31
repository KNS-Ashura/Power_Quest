extends CharacterBody2D

const UnitNameUtilsRef = preload("res://scripts/common/unit_name_utils.gd")
const PlayerAnimationControllerRef = preload("res://scripts/characters/player_animation_controller.gd")
const PlayerTransportControllerRef = preload("res://scripts/characters/player_transport_controller.gd")
const PlayerNetworkControllerRef = preload("res://scripts/characters/player_network_controller.gd")
const PlayerSpellControllerRef = preload("res://scripts/characters/player_spell_controller.gd")
const PlayerMovementControllerRef = preload("res://scripts/characters/player_movement_controller.gd")
const PlayerCombatControllerRef = preload("res://scripts/characters/player_combat_controller.gd")

signal killed_by(killer, killer_team)

@export var stats: UnitStats

enum Owner { PLAYER, ENEMY, NEUTRAL }
@export var team: Owner = Owner.PLAYER

var net_sync_id: int = -1
var net_remote_proxy: bool = false
var _net_target_position: Vector2 = Vector2.ZERO
var _net_lerp_active: bool = false
var _network_damage: bool = false

var hp_max: int = 100
var current_hp: int = 100
var unit_speed: float = 150.0
var unit_damage: int = 10
var is_selected: bool = false
const SCENE_RANGE_PROJECTILE_LOOP = preload("uid://swrp6c3h83xg")
const SCENE_WATER_RANGE_PROJECTILE_LOOP = preload("uid://djbfyhto8wuop")
const SCENE_HEALER_PROJECTILE_LOOP = preload("uid://5cvanebkvuv0")
const SCENE_HEALER_EFFECT = preload("uid://cdvvumicj5qty")
const SCENE_SUPPORT_EFFECT = preload("uid://ca8jxgt0j8nmw")
const SCENE_DOUBLE_EFFECT = preload("uid://badrqmpt16vq7")
const INVULN_SPELL_DURATION_LEVEL_1 := 10.0
const BOOST_SPELL_DURATION_LEVEL_1 := 20.0
const INVULN_DURATION_BONUS_PER_LEVEL := 5.0
const BOOST_DURATION_BONUS_PER_LEVEL := 10.0
const SCENE_PORT_GUARDIAN_PROJECTILE_LOOP = preload("res://scenes/personnages/port_guardian/gardian-port-loop-projectile.tscn")
const SCENE_CAMP_GUARDIAN_PROJECTILE_LOOP = preload("uid://ofkkgjehycuj")
const SCENE_ANTI_ARMOR_PROJECTILE_LOOP = preload("res://scenes/personnages/anti_armor/anti-armor-loop-projectile.tscn")
const PORT_GUARDIAN_PASSIVE_SHOT_RADIUS := 420.0
const PORT_GUARDIAN_PROJECTILE_SPEED := 320.0
const CAMP_GUARDIAN_PROJECTILE_SPEED := 380.0
const ANTI_ARMOR_SPELL_PROJECTILE_SPEED := 120.0
const DEFAULT_HEAL_EFFECT_DURATION := 4.0
const BUFF_EFFECT_NODE_NAME := "BuffEffectVfx"
const ANTI_ARMOR_SPELL_DAMAGE_MULTIPLIER := 2.0
const ANTI_ARMOR_SPELL_DURATION_LEVEL_1 := 10.0
const ANTI_ARMOR_SPELL_DURATION_BONUS_PER_LEVEL := 2.0
const ANTI_ARMOR_SPELL_RADIUS_LEVEL_1 := 150.0
const ANTI_ARMOR_SPELL_RADIUS_BONUS_PER_LEVEL := 30.0
const RANGE_ZONE_FACTOR := 0.65
const HEALER_ZONE_FACTOR := 0.6
const CAMP_GUARDIAN_ZONE_FACTOR := 0.85
const SCENE_MORTAR_EXPLOSION_BASE = preload("res://scenes/personnages/mortar/explosion.tscn")
const SCENE_MORTAR_EXPLOSION_POISON = preload("res://scenes/personnages/mortar/poison-explosion.tscn")
const SCENE_MORTAR_EXPLOSION_FIRE = preload("res://scenes/personnages/mortar/fire-explosion.tscn")
const SCENE_MORTAR_EXPLOSION_ULT = preload("res://scenes/personnages/mortar/explosion-ult.tscn")
const MORTAR_ATTACK_COOLDOWN_LEVEL_1: float = 1.35
const MORTAR_ATTACK_COOLDOWN_LEVEL_2: float = 1.1
const MORTAR_ATTACK_COOLDOWN_LEVEL_3: float = 0.85
const MORTAR_ULT_DAMAGE_MULTIPLIER := 1.75
const MORTAR_ULT_EXPLOSION_RADIUS := 130.0
const SPELL_COOLDOWN_SECONDS := 60.0
const SCENE_WATER_TRANSPORT_MARK_FX = preload("res://scenes/personnages/water-transporter/water-transporter-effect.tscn")
const SCENE_WATER_TRANSPORT_BOARD_FX = preload("res://scenes/personnages/water-transporter/water-transporter-effect-2.tscn")
const WATER_TRANSPORT_MARK_RADIUS := 150.0
const WATER_TRANSPORT_COOLDOWN := 30.0
const WATER_TRANSPORT_SCALE_BONUS := 0.05
const WATER_TRANSPORT_DISEMBARK_TRIGGER_DIST := 60.0
const WATER_TRANSPORT_DISEMBARK_MAX_DIST := 30.0
const WATER_TRANSPORT_DISEMBARK_MIN_CLEARANCE := 18.0
const WATER_TRANSPORT_DISEMBARK_SPREAD := 14.0
const WATER_TRANSPORT_CAP_BY_LEVEL := {1: 5, 2: 8, 3: 11}
const PROJECTILE_ATTACK_ANIM_DELAY_RANGE := 0.11
const PROJECTILE_ATTACK_ANIM_DELAY_HEAL := 0.12
## Navigation 2D (bitmask) — must match regions in Main:
## layer 1 (value 1) = Nav_ground | layer 2 (value 2) = Nav_water
const NAV_LAYER_GROUND := 1
const NAV_LAYER_WATER := 2

## Physics layers: allies do not block each other (lateral slide).
const COLLISION_LAYER_WORLD := 1
const COLLISION_LAYER_PLAYER_UNIT := 2
const COLLISION_LAYER_ENEMY_UNIT := 4
const UNIT_BODY_RADIUS := 10.0
const GUARDIAN_BODY_RADIUS := 11.0
const SEPARATION_RADIUS := 52.0
const SEPARATION_FORCE := 95.0

@export var force_water_navigation: bool = false

@onready var agent_navigation = $NavigationAgent2D
var attack_target_node: Node2D = null
@onready var zone_detection = $ZoneDetection
@onready var attack_timer = $TimerAttaque

var search_interval: float = 0.5
var search_timer: float = 0.0
var passive_guardian_shot_timer: float = 0.0

var current_spell_cooldown: float = 0.0
var boost_time_remaining: float = 0.0
var boost_active: bool = false
var invulnerability_active: bool = false
var invulnerability_time_remaining: float = 0.0
var anti_armor_spell_active: bool = false
var anti_armor_spell_time_remaining: float = 0.0
var incoming_damage_multiplier: float = 1.0
var attack_rate_multiplier: float = 1.0
var is_dying: bool = false
var cycle_explosion_mortar: int = 0
var is_camp_guardian: bool = false
var guard_position: Vector2 = Vector2.ZERO
var guard_defense_radius: float = 260.0
var guard_chase_radius: float = 320.0
var _pending_projectile_ticket: int = 0

enum WaterTransportPhase { IDLE, UNITS_MARKED, CARRYING }
var water_transport_phase: WaterTransportPhase = WaterTransportPhase.IDLE
var water_transport_marked: Array[Node2D] = []
var water_transport_boarded: Array[Node2D] = []
var water_transport_origin: Dictionary = {}
var water_transport_cooldown: float = 0.0
var water_transport_base_scale: Vector2 = Vector2.ONE

func _apply_stats_to_unit() -> void:
	if not stats:
		return
	hp_max = stats.hp_max
	current_hp = hp_max
	unit_speed = stats.speed
	unit_damage = stats.damage
	_apply_unit_color()
	if has_node("ProgressBar"):
		$ProgressBar.max_value = hp_max
		$ProgressBar.value = current_hp
	var radius := _detection_zone_radius()
	var shape = $ZoneDetection/CollisionShape2D.shape
	if shape is CircleShape2D:
		$ZoneDetection/CollisionShape2D.shape = shape.duplicate()
		$ZoneDetection/CollisionShape2D.shape.radius = radius
	if is_instance_valid(agent_navigation):
		agent_navigation.target_desired_distance = max(8.0, radius - 5.0)

func _ready() -> void:
	water_transport_base_scale = scale
	_apply_stats_to_unit()
	_configure_navigation_layers()
	_configure_movement_and_collisions()
	agent_navigation.path_desired_distance = 10.0
	await get_tree().process_frame
	agent_navigation.target_position = global_position
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	_configure_death_animations()

func _configure_navigation_layers() -> void:
	if not is_instance_valid(agent_navigation):
		return
	if _is_naval_unit():
		agent_navigation.navigation_layers = NAV_LAYER_WATER
	else:
		agent_navigation.navigation_layers = NAV_LAYER_GROUND

func _is_naval_unit() -> bool:
	if force_water_navigation:
		return true
	if stats != null:
		return stats.unit_type == UnitStats.UnitType.WATER_TANK \
			or stats.unit_type == UnitStats.UnitType.WATER_RANGE \
			or stats.unit_type == UnitStats.UnitType.WATER_TRANSPORT
	var scene_path := scene_file_path
	return scene_path.contains("/water-range/") or scene_path.contains("/water-tank/")

func set_selection(selected: bool) -> void:
	is_selected = selected
	self.modulate = Color(1.2, 1.2, 1.2) if is_selected else Color(1, 1, 1)


func is_selectable_as_local_army() -> bool:
	return MapSession.is_local_team(int(team))


func matches_selection_hotkey(keycode: int) -> bool:
	if is_camp_guardian or stats == null:
		return false
	return UnitStats.selection_hotkey_for_type(stats.unit_type) == keycode


func move_to(target_position: Vector2) -> void:
	if net_remote_proxy:
		return
	if is_camp_guardian:
		return
	attack_target_node = null
	if is_instance_valid(agent_navigation):
		agent_navigation.target_desired_distance = 8.0
	agent_navigation.target_position = target_position

func _stop_combat() -> void:
	attack_target_node = null
	_pending_projectile_ticket += 1
	if is_instance_valid(attack_timer):
		attack_timer.stop()
	velocity = Vector2.ZERO

func _is_valid_combat_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_inside_tree():
		return false
	if "is_dying" in target and target.is_dying:
		return false
	if "current_hp" in target and target.current_hp <= 0:
		return false
	if _is_healer():
		if not ("current_hp" in target and "hp_max" in target):
			return false
		var ally_team: int = NodeTeamUtils.team_id(target)
		if ally_team < 0 or ally_team != team:
			return false
		return target.current_hp < target.hp_max
	if target.has_method("take_damage"):
		if target.is_in_group("camps"):
			return false
		if NodeTeamUtils.is_same_team(target, self):
			return false
		return true
	return false

func attack_target(target: Node2D) -> void:
	if net_remote_proxy:
		return
	if not _is_valid_combat_target(target):
		return
	if is_camp_guardian and is_instance_valid(target):
		if target.global_position.distance_to(guard_position) > guard_chase_radius:
			return
	attack_target_node = target
	if is_instance_valid(target):
		if is_instance_valid(agent_navigation):
			agent_navigation.target_desired_distance = max(8.0, _detection_zone_radius() - 5.0)
		agent_navigation.target_position = target.global_position

var last_facing_direction: String = "f"

func _physics_process(_delta: float) -> void:
	if is_dying:
		return
	if net_remote_proxy:
		_physics_process_network_proxy(_delta)
		return

	if is_camp_guardian and (_is_port_guardian() or _is_camp_guardian_unit()):
		_handle_passive_guardian_shots(_delta)

	var should_move = true
	if is_instance_valid(agent_navigation):
		if is_instance_valid(attack_target_node):
			agent_navigation.target_desired_distance = max(8.0, _detection_zone_radius() - 5.0)
		else:
			agent_navigation.target_desired_distance = 8.0

	if current_spell_cooldown > 0:
		current_spell_cooldown -= _delta
	if water_transport_cooldown > 0.0:
		water_transport_cooldown = maxf(0.0, water_transport_cooldown - _delta)

	if boost_active:
		boost_time_remaining -= _delta
		if boost_time_remaining <= 0:
			boost_active = false
			unit_speed = stats.speed
			unit_damage = stats.damage
			attack_rate_multiplier = 1.0
			_apply_unit_color()
			_update_visual_effect(self)

	if invulnerability_active:
		invulnerability_time_remaining -= _delta
		if invulnerability_time_remaining <= 0:
			invulnerability_active = false
			_apply_unit_color()
			_update_visual_effect(self)

	if anti_armor_spell_active:
		anti_armor_spell_time_remaining -= _delta
		if anti_armor_spell_time_remaining <= 0:
			anti_armor_spell_active = false
			anti_armor_spell_time_remaining = 0.0
			incoming_damage_multiplier = 1.0
			_apply_unit_color()

	if is_instance_valid(attack_target_node) and not _is_valid_combat_target(attack_target_node):
		_stop_combat()

	if is_instance_valid(attack_target_node):
		var valid_target := attack_target_node
		if is_camp_guardian and valid_target.global_position.distance_to(guard_position) > guard_chase_radius:
			_stop_combat()
			agent_navigation.target_position = guard_position
			should_move = true
		else:
			agent_navigation.target_position = valid_target.global_position
			var in_zone: bool = valid_target in zone_detection.get_overlapping_bodies()
			if in_zone:
				should_move = false
				if attack_timer.is_stopped():
					if _is_mortar():
						attack_timer.start(_mortar_level_cooldown())
					else:
						var attack_rate = _current_attack_rate()
						attack_timer.start(1.0 / attack_rate)
			else:
				_stop_combat()
	else:
		if is_instance_valid(attack_timer):
			attack_timer.stop()
		search_timer -= _delta
		if search_timer <= 0:
			_search_target_automatically()
			search_timer = search_interval

		if is_camp_guardian and global_position.distance_to(guard_position) > 8.0:
			agent_navigation.target_position = guard_position
		elif agent_navigation.is_navigation_finished():
			should_move = false

	if should_move:
		var next_point = agent_navigation.get_next_path_position()
		_apply_movement_toward(next_point)
	else:
		velocity = Vector2.ZERO

	update_animation()

func _on_attack_timer_timeout() -> void:
	PlayerCombatControllerRef.on_attack_timer_timeout(self)

func _animate_melee_attack() -> void:
	PlayerCombatControllerRef.animate_melee_attack(self)

func _search_target_automatically() -> void:
	PlayerCombatControllerRef.search_target_automatically(self)

func _is_healer() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.HEAL

func _is_range() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.ARCHER

func _is_water_range_unit() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.WATER_RANGE

func _is_mortar() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.MORTAR

func _is_anti_armor() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.ANTI_ARMOR

func _fire_range_projectile(target: Node2D) -> void:
	PlayerCombatControllerRef.fire_range_projectile(self, target)

func _heal_amount() -> int:
	return PlayerCombatControllerRef.heal_amount(self)

func _fire_heal_projectile(target: Node2D) -> void:
	PlayerCombatControllerRef.fire_heal_projectile(self, target)


func _schedule_projectile_shot(target: Node2D, delay_seconds: float, heal_projectile: bool) -> void:
	PlayerCombatControllerRef.schedule_projectile_shot(self, target, delay_seconds, heal_projectile)


func _trigger_projectile_shot(ticket: int, target: Node2D, heal_projectile: bool) -> void:
	PlayerCombatControllerRef.trigger_projectile_shot(self, ticket, target, heal_projectile)

func _is_port_guardian() -> bool:
	return scene_file_path.contains("/port_guardian/")

func _is_camp_guardian_unit() -> bool:
	return is_camp_guardian and scene_file_path.contains("/guardian/") and not _is_port_guardian()

func _port_guardian_level() -> int:
	if stats == null:
		return 1
	return UnitNameUtilsRef.level_from_unit_name(String(stats.name))

func _detection_zone_radius() -> float:
	if stats == null:
		return 100.0
	if _is_healer():
		return stats.range * HEALER_ZONE_FACTOR
	if _is_range():
		return stats.range * RANGE_ZONE_FACTOR
	if is_camp_guardian and not _is_port_guardian():
		return stats.range * CAMP_GUARDIAN_ZONE_FACTOR
	return stats.range

func _handle_passive_guardian_shots(delta: float) -> void:
	PlayerCombatControllerRef.handle_passive_guardian_shots(self, delta)

func _passive_shot_enemies_in_range() -> Array:
	return PlayerCombatControllerRef.passive_shot_enemies_in_range(self)

func _passive_guardian_projectile_scene() -> PackedScene:
	return PlayerCombatControllerRef.passive_guardian_projectile_scene(self)

func _passive_guardian_projectile_speed() -> float:
	return PlayerCombatControllerRef.passive_guardian_projectile_speed(self)

func _fire_passive_guardian_projectile(target: Node2D) -> void:
	PlayerCombatControllerRef.fire_passive_guardian_projectile(self, target)

func _heal_effect_duration() -> float:
	return DEFAULT_HEAL_EFFECT_DURATION

func _unit_level() -> int:
	if stats == null:
		return 1
	return UnitNameUtilsRef.level_from_unit_name(String(stats.name))

func _invulnerability_spell_duration() -> float:
	var level := _unit_level()
	return INVULN_SPELL_DURATION_LEVEL_1 + float(level - 1) * INVULN_DURATION_BONUS_PER_LEVEL

func _boost_spell_duration() -> float:
	var level := _unit_level()
	return BOOST_SPELL_DURATION_LEVEL_1 + float(level - 1) * BOOST_DURATION_BONUS_PER_LEVEL

func _visual_effect_duration_on_target(target: Node2D) -> float:
	var duration := 0.0
	if target.get("invulnerability_active") and target.invulnerability_active:
		duration = maxf(duration, target.invulnerability_time_remaining)
	if target.get("boost_active") and target.boost_active:
		duration = maxf(duration, target.boost_time_remaining)
	return duration

func _effect_scene_for_target(target: Node2D) -> PackedScene:
	var invuln: bool = target.get("invulnerability_active") == true and bool(target.invulnerability_active)
	var boost: bool = target.get("boost_active") == true and bool(target.boost_active)
	if invuln and boost:
		return SCENE_DOUBLE_EFFECT
	if invuln:
		return SCENE_HEALER_EFFECT
	if boost:
		return SCENE_SUPPORT_EFFECT
	return null

func _update_visual_effect(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	var existing := target.get_node_or_null(BUFF_EFFECT_NODE_NAME)
	if is_instance_valid(existing):
		existing.queue_free()
	var scene_fx := _effect_scene_for_target(target)
	if scene_fx == null:
		return
	var duration := _visual_effect_duration_on_target(target)
	if duration <= 0.0:
		return
	var fx = scene_fx.instantiate()
	fx.name = BUFF_EFFECT_NODE_NAME
	target.add_child(fx)
	if fx.has_method("start"):
		fx.start(duration)

func _attach_heal_effect_on(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if target.get("invulnerability_active") and target.invulnerability_active:
		_update_visual_effect(target)
		return
	_attach_effect_on_target(target, SCENE_HEALER_EFFECT, _heal_effect_duration())

func _attach_effect_on_target(target: Node2D, scene_fx: PackedScene, duration: float) -> void:
	if not is_instance_valid(target) or scene_fx == null or duration <= 0.0:
		return
	var existing := target.get_node_or_null(BUFF_EFFECT_NODE_NAME)
	if is_instance_valid(existing):
		existing.queue_free()
	var fx = scene_fx.instantiate()
	fx.name = BUFF_EFFECT_NODE_NAME
	target.add_child(fx)
	if fx.has_method("start"):
		fx.start(duration)

func _mortar_level() -> int:
	return _unit_level()

func _mortar_level_cooldown() -> float:
	var level := _mortar_level()
	if level >= 3:
		return MORTAR_ATTACK_COOLDOWN_LEVEL_3
	if level == 2:
		return MORTAR_ATTACK_COOLDOWN_LEVEL_2
	return MORTAR_ATTACK_COOLDOWN_LEVEL_1

func _fire_mortar_at_range(target: Node2D) -> void:
	PlayerCombatControllerRef.fire_mortar_at_range(self, target)

func _next_mortar_explosion() -> Dictionary:
	return PlayerCombatControllerRef.next_mortar_explosion(self)

func _spawn_mortar_explosion_vfx(scene: PackedScene, position_world: Vector2) -> void:
	PlayerCombatControllerRef.spawn_mortar_explosion_vfx(self, scene, position_world)

func _apply_area_damage(center: Vector2, radius: float, damage: int) -> void:
	PlayerCombatControllerRef.apply_area_damage(self, center, radius, damage)

func _apply_heal_to_target(target: Node2D) -> void:
	PlayerCombatControllerRef.apply_heal_to_target(self, target)

func update_animation() -> void:
	PlayerAnimationControllerRef.update_animation(self)

func take_damage(amount: int, attacker = null, attacker_team: int = -1) -> void:
	if is_dying or invulnerability_active:
		return
	if (
		MapSession.is_online_match
		and OnlineGameSync.is_online_active()
		and not _network_damage
		and MapSession.is_local_team(team)
		and net_sync_id >= 0
	):
		return

	var final_damage = amount

	if is_instance_valid(attacker) and "stats" in attacker and attacker.stats != null:
		if attacker.stats.unit_type == 5:
			final_damage = final_damage * 3 if (stats and stats.unit_type == 2) else int(float(final_damage) * 0.5)
	if anti_armor_spell_active:
		final_damage = int(round(float(final_damage) * incoming_damage_multiplier))

	current_hp -= final_damage

	if has_node("ProgressBar"):
		$ProgressBar.value = current_hp

	if current_hp <= 0:
		var eq = attacker_team
		if eq == -1:
			eq = NodeTeamUtils.team_id(attacker)
		die(attacker, eq)

func die(killer: Node2D = null, killer_team: int = -1) -> void:
	if is_dying:
		return
	# Owner is authoritative on their unit's death: always report it
	# (even when killed by network damage) so proxies are removed everywhere.
	if (
		MapSession.is_online_match
		and OnlineGameSync.is_online_active()
		and MapSession.is_local_team(team)
		and net_sync_id >= 0
	):
		OnlineGameSync.report_unit_death(net_sync_id)

	if _is_water_transporter():
		if water_transport_boarded.size() > 0:
			_water_transport_release_boarded_at_origin()
		elif water_transport_phase == WaterTransportPhase.UNITS_MARKED:
			_water_transport_clear_marked()

	is_dying = true
	if _is_mortar():
		_play_animation_on_sprites("attack_" + last_facing_direction, "idle_" + last_facing_direction)
		_spawn_mortar_explosion_vfx(SCENE_MORTAR_EXPLOSION_BASE, global_position)
		_apply_area_damage(global_position, 120.0, int(round(float(unit_damage) * 1.15)))
		await get_tree().create_timer(0.22).timeout
	killed_by.emit(killer, killer_team)
	velocity = Vector2.ZERO
	_stop_combat()

	# Stop physics/agent blocking as soon as the death anim starts.
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(agent_navigation):
		agent_navigation.target_position = global_position
		agent_navigation.avoidance_enabled = false

	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if has_node("ZoneDetection"):
		$ZoneDetection.monitoring = false
		$ZoneDetection.monitorable = false
	if has_node("ZoneDetection/CollisionShape2D"):
		$ZoneDetection/CollisionShape2D.set_deferred("disabled", true)

	var death_anim_played := _play_death_animation()
	if death_anim_played:
		await $AnimatedSprite2D.animation_finished
	queue_free()

func _play_death_animation() -> bool:
	return PlayerAnimationControllerRef.play_death_animation(self)

func _play_attack_animation(target: Node2D) -> void:
	PlayerAnimationControllerRef.play_attack_animation(self, target)

func _direction_from_target(target_position: Vector2) -> String:
	return PlayerAnimationControllerRef.direction_from_target(self, target_position)

func _animated_sprites() -> Array[AnimatedSprite2D]:
	return PlayerAnimationControllerRef.animated_sprites(self)

func _play_animation_on_sprites(anim: String, fallback: String = "") -> void:
	PlayerAnimationControllerRef.play_on_sprites(self, anim, fallback)

func _configure_death_animations() -> void:
	PlayerAnimationControllerRef.configure_death_animations(self)

func _is_water_transporter() -> bool:
	return PlayerTransportControllerRef.is_water_transporter(self)


func get_water_transport_cooldown_remaining() -> float:
	return PlayerTransportControllerRef.get_cooldown_remaining(self)


func get_spell_cooldown_remaining() -> float:
	return maxf(0.0, current_spell_cooldown)


func get_water_transport_phase() -> int:
	return PlayerTransportControllerRef.get_phase(self)


func get_anti_armor_spell_radius() -> float:
	return _anti_armor_spell_radius()


func can_use_water_transport() -> bool:
	return PlayerTransportControllerRef.can_use(self)


func water_transport_step() -> bool:
	return PlayerTransportControllerRef.step(self)


func water_transport_cancel_mark() -> void:
	PlayerTransportControllerRef.cancel_mark(self)


func _water_transport_capacity() -> int:
	return PlayerTransportControllerRef.capacity(self)


func _is_land_unit_transportable(unit: Node) -> bool:
	return PlayerTransportControllerRef.is_land_unit_transportable(self, unit)


func _water_transport_mark_allies() -> bool:
	return PlayerTransportControllerRef.mark_allies(self)


func _water_transport_allies_in_radius() -> Array[Node2D]:
	return PlayerTransportControllerRef.allies_in_radius(self)


func _water_transport_board_marked() -> bool:
	return PlayerTransportControllerRef.board_marked(self)


func _water_transport_disembark() -> bool:
	return PlayerTransportControllerRef.disembark(self)


func _water_transport_reset_after_disembark() -> void:
	PlayerTransportControllerRef.reset_after_disembark(self)


func _water_transport_clear_marked() -> void:
	PlayerTransportControllerRef.clear_marked(self)


func _water_transport_release_boarded_at_origin() -> void:
	PlayerTransportControllerRef.release_boarded_at_origin(self)


func _water_transport_hide_unit(unit: Node2D) -> void:
	PlayerTransportControllerRef.hide_unit(self, unit)


func _water_transport_show_unit(unit: Node2D, spawn_pos: Vector2) -> void:
	PlayerTransportControllerRef.show_unit(self, unit, spawn_pos)


func _stop_unit_combat(unit: Node) -> void:
	PlayerTransportControllerRef.stop_unit_combat(unit)


func _remove_transport_fx(unit: Node2D) -> void:
	PlayerTransportControllerRef.remove_transport_fx(self, unit)


func _water_transport_nav_regions() -> Array[NavigationRegion2D]:
	return PlayerTransportControllerRef.nav_regions(self)


func _water_transport_closest_point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	return PlayerTransportControllerRef.closest_point_on_segment(point, a, b)


func _water_transport_closest_point_on_polygon(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	return PlayerTransportControllerRef.closest_point_on_polygon(point, polygon)


func _water_transport_surface_mask_at(world_pos: Vector2) -> int:
	return PlayerTransportControllerRef.surface_mask_at(self, world_pos)


func _water_transport_is_valid_land_point(world_pos: Vector2) -> bool:
	return PlayerTransportControllerRef.is_valid_land_point(self, world_pos)


func _water_transport_closest_on_layers(from: Vector2, layer_mask: int) -> Vector2:
	return PlayerTransportControllerRef.closest_on_layers(self, from, layer_mask)


func _water_transport_nearest_ground_point(from: Vector2) -> Vector2:
	return PlayerTransportControllerRef.nearest_ground_point(self, from)


func _collect_nav_regions_for_transport(node: Node, out: Array) -> void:
	PlayerTransportControllerRef.collect_nav_regions(node, out)


func can_cast_spell() -> bool:
	return PlayerSpellControllerRef.can_cast_spell(self)

func cast_spell() -> bool:
	return PlayerSpellControllerRef.cast_spell(self)

func _cast_spell_mortar_ult() -> bool:
	return PlayerSpellControllerRef.cast_spell_mortar_ult(self)


func _anti_armor_spell_radius() -> float:
	return PlayerSpellControllerRef.anti_armor_spell_radius(self)


func _anti_armor_spell_duration() -> float:
	return PlayerSpellControllerRef.anti_armor_spell_duration(self)


func _cast_spell_anti_armor() -> bool:
	return PlayerSpellControllerRef.cast_spell_anti_armor(self)


func _anti_armor_spell_enemy_targets() -> Array[Node2D]:
	return PlayerSpellControllerRef.anti_armor_spell_enemy_targets(self)


func _highest_hp_anti_armor_target(targets: Array[Node2D]) -> Node2D:
	return PlayerSpellControllerRef.highest_hp_anti_armor_target(targets)


func _fire_anti_armor_spell_projectile(target: Node2D) -> void:
	PlayerSpellControllerRef.fire_anti_armor_spell_projectile(self, target)

func _closest_enemy_targets_mortar(max_count: int) -> Array:
	return PlayerSpellControllerRef.closest_enemy_targets_mortar(self, max_count)

func receive_invulnerability_spell(duration: float) -> void:
	PlayerSpellControllerRef.receive_invulnerability_spell(self, duration)

func receive_boost(duration: float) -> void:
	PlayerSpellControllerRef.receive_boost(self, duration)


func receive_anti_armor_spell(duration: float, multiplier: float = ANTI_ARMOR_SPELL_DAMAGE_MULTIPLIER) -> void:
	PlayerSpellControllerRef.receive_anti_armor_spell(self, duration, multiplier)

func _current_attack_rate() -> float:
	return PlayerSpellControllerRef.current_attack_rate(self)

func _unit_color() -> Color:
	return PlayerSpellControllerRef.unit_color(self)

func _apply_unit_color() -> void:
	PlayerSpellControllerRef.apply_unit_color(self)

func configure_guardian_mode(anchor_position: Vector2, defense_radius: float = 260.0, chase_radius: float = 320.0) -> void:
	PlayerMovementControllerRef.configure_guardian_mode(self, anchor_position, defense_radius, chase_radius)


func _is_guardian_scene() -> bool:
	return PlayerMovementControllerRef.is_guardian_scene(self)


func _configure_movement_and_collisions() -> void:
	PlayerMovementControllerRef.configure_movement_and_collisions(self)


func _apply_team_collision_layers() -> void:
	PlayerMovementControllerRef.apply_team_collision_layers(self)


func _configure_detection_zone() -> void:
	PlayerMovementControllerRef.configure_detection_zone(self)


func _configure_collision_shape() -> void:
	PlayerMovementControllerRef.configure_collision_shape(self)


func _configure_navigation_avoidance() -> void:
	PlayerMovementControllerRef.configure_navigation_avoidance(self)


func _apply_movement_toward(next_point: Vector2) -> void:
	PlayerMovementControllerRef.apply_movement_toward(self, next_point)


func _compute_desired_velocity(next_point: Vector2) -> Vector2:
	return PlayerMovementControllerRef.compute_desired_velocity(self, next_point)


func _deal_combat_damage(target: Node, damage: int) -> void:
	PlayerNetworkControllerRef.deal_combat_damage(self, target, damage)


func take_damage_network_remote(amount: int, attacker_team: int) -> void:
	PlayerNetworkControllerRef.take_damage_network_remote(self, amount, attacker_team)


func apply_network_order(move_to: Vector2, target: Node) -> void:
	PlayerNetworkControllerRef.apply_network_order(self, move_to, target)


func apply_network_state(pos: Vector2, vel: Vector2, hp: int) -> void:
	PlayerNetworkControllerRef.apply_network_state(self, pos, vel, hp)


func force_network_death() -> void:
	PlayerNetworkControllerRef.force_network_death(self)


func eliminate_instantly() -> void:
	if is_dying or is_queued_for_deletion():
		return
	is_dying = true
	if net_sync_id >= 0:
		OnlineGameSync.unregister_unit(net_sync_id)
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(agent_navigation):
		agent_navigation.target_position = global_position
		agent_navigation.avoidance_enabled = false
	queue_free()


func apply_heal_network_remote(amount: int, caster_sync_id: int) -> void:
	PlayerNetworkControllerRef.apply_heal_network_remote(self, amount, caster_sync_id)


func apply_spell_network_remote(spell_type: int, target_sync_ids: Array, params: Dictionary) -> void:
	PlayerSpellControllerRef.apply_spell_network_remote(self, spell_type, target_sync_ids, params)


func _physics_process_network_proxy(delta: float) -> void:
	PlayerNetworkControllerRef.physics_process_network_proxy(self, delta)


func _compute_ally_repulsion() -> Vector2:
	return PlayerMovementControllerRef.compute_ally_repulsion(self)
