extends RefCounted
class_name PlayerSpellController


static func can_cast_spell(owner: Node) -> bool:
	if not owner.stats or owner.is_dying:
		return false
	if owner.current_spell_cooldown > 0.0:
		return false
	if owner._is_mortar() or owner._is_healer() or (owner.stats.unit_type == UnitStats.UnitType.SUPPORT) or owner._is_anti_armor():
		return true
	return owner.stats.spell_cooldown > 0.0


static func cast_spell(owner: Node) -> bool:
	if not can_cast_spell(owner):
		return false
	if owner._is_mortar():
		if cast_spell_mortar_ult(owner):
			owner.current_spell_cooldown = owner.SPELL_COOLDOWN_SECONDS
			return true
		return false
	if owner._is_anti_armor():
		if cast_spell_anti_armor(owner):
			owner.current_spell_cooldown = owner.SPELL_COOLDOWN_SECONDS
			return true
		return false

	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 150.0
	query.shape = circle
	query.transform = Transform2D(0, owner.global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var results: Array = owner.get_world_2d().direct_space_state.intersect_shape(query)
	var group := "soldiers" if MapSession.is_local_team(int(owner.team)) else "enemies"
	var any_effect: bool = false
	var target_sync_ids: Array = []

	for res in results:
		var obj: Variant = res.collider
		if not obj or not obj.is_in_group(group):
			continue
		if owner.stats.unit_type == UnitStats.UnitType.SUPPORT and obj.has_method("receive_boost"):
			obj.receive_boost(owner._boost_spell_duration())
			any_effect = true
			_append_sync_id(target_sync_ids, obj)
		elif owner.stats.unit_type == UnitStats.UnitType.HEAL and obj.has_method("receive_invulnerability_spell"):
			obj.receive_invulnerability_spell(owner._invulnerability_spell_duration())
			any_effect = true
			_append_sync_id(target_sync_ids, obj)

	if not any_effect:
		return false

	owner.current_spell_cooldown = owner.SPELL_COOLDOWN_SECONDS
	_report_spell_network(owner, target_sync_ids)
	_play_spell_sfx(owner)
	return true


static func cast_spell_mortar_ult(owner: Node) -> bool:
	var level: int = owner._mortar_level()
	var max_targets: int = 1
	if level == 2:
		max_targets = 2
	elif level >= 3:
		max_targets = 3

	var targets: Array = closest_enemy_targets_mortar(owner, max_targets)
	if targets.is_empty():
		return false

	var spell_damage: int = int(round(float(owner.unit_damage) * owner.MORTAR_ULT_DAMAGE_MULTIPLIER))
	var ult_radius: float = owner.MORTAR_ULT_EXPLOSION_RADIUS
	var impact_positions: Array = []
	for target in targets:
		var impact_position: Vector2 = target.global_position
		impact_positions.append(impact_position)
		owner._spawn_mortar_explosion_vfx(owner.SCENE_MORTAR_EXPLOSION_ULT, impact_position)
		owner._apply_area_damage(impact_position, ult_radius, spell_damage)
	_report_mortar_spell_network(owner, impact_positions)
	_play_spell_sfx(owner, "nuclear")
	return true


static func anti_armor_spell_radius(owner: Node) -> float:
	return owner.ANTI_ARMOR_SPELL_RADIUS_LEVEL_1 + float(owner._unit_level() - 1) * owner.ANTI_ARMOR_SPELL_RADIUS_BONUS_PER_LEVEL


static func anti_armor_spell_duration(owner: Node) -> float:
	if owner.stats and owner.stats.spell_duration > 0.0:
		return owner.stats.spell_duration
	return owner.ANTI_ARMOR_SPELL_DURATION_LEVEL_1 + float(owner._unit_level() - 1) * owner.ANTI_ARMOR_SPELL_DURATION_BONUS_PER_LEVEL


static func cast_spell_anti_armor(owner: Node) -> bool:
	var targets: Array[Node2D] = anti_armor_spell_enemy_targets(owner)
	if targets.is_empty():
		return false
	var target: Node2D = highest_hp_anti_armor_target(targets)
	if not is_instance_valid(target):
		return false
	fire_anti_armor_spell_projectile(owner, target)
	var target_sync_ids: Array = []
	_append_sync_id(target_sync_ids, target)
	_report_anti_armor_spell_network(owner, target_sync_ids)
	_play_spell_sfx(owner, "antiarmor")
	return true


static func _play_spell_sfx(owner: Node, kind: String = "") -> void:
	if not MapSession.is_local_team(int(owner.get("team"))):
		return
	match kind:
		"nuclear":
			Sound.play_nuclear()
		"antiarmor":
			Sound.play_antiarmor()
		_:
			if not owner.stats:
				return
			match owner.stats.unit_type:
				UnitStats.UnitType.HEAL:
					Sound.play_heal()
				UnitStats.UnitType.SUPPORT:
					Sound.play_boost()
				_:
					pass


static func anti_armor_spell_enemy_targets(owner: Node) -> Array[Node2D]:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = anti_armor_spell_radius(owner)
	query.shape = circle
	query.transform = Transform2D(0, owner.global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result: Array[Node2D] = []
	for res in owner.get_world_2d().direct_space_state.intersect_shape(query):
		var obj := res.collider as Node2D
		if not is_instance_valid(obj) or obj == owner:
			continue
		if obj.is_in_group("camps"):
			continue
		if not NodeTeamUtils.is_enemy_of(obj, int(owner.team)):
			continue
		if not obj.has_method("take_damage"):
			continue
		result.append(obj)
	return result


static func highest_hp_anti_armor_target(targets: Array[Node2D]) -> Node2D:
	var best_target: Node2D = null
	var best_hp: int = -1
	for target in targets:
		if not is_instance_valid(target):
			continue
		var hp: int = int(target.get("current_hp")) if target.get("current_hp") != null else int(target.get("hp_max"))
		if best_target == null or hp > best_hp:
			best_target = target
			best_hp = hp
	return best_target


static func fire_anti_armor_spell_projectile(owner: Node, target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	var parent_node := owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj: Node = owner.SCENE_ANTI_ARMOR_PROJECTILE_LOOP.instantiate()
	parent_node.add_child(proj)
	proj.global_position = owner.global_position
	if proj.has_method("launch"):
		proj.launch(
			target,
			anti_armor_spell_duration(owner),
			owner.ANTI_ARMOR_SPELL_DAMAGE_MULTIPLIER,
			owner,
			owner.ANTI_ARMOR_SPELL_PROJECTILE_SPEED
		)


static func closest_enemy_targets_mortar(owner: Node, max_count: int) -> Array:
	var targets: Array = owner.zone_detection.get_overlapping_bodies().filter(func(c):
		return is_instance_valid(c) \
			and c != owner \
			and c.has_method("take_damage") \
			and not c.is_in_group("camps") \
			and NodeTeamUtils.is_enemy_of(c, int(owner.team))
	)
	if targets.is_empty():
		return []

	targets.sort_custom(func(a, b):
		return owner.global_position.distance_to(a.global_position) < owner.global_position.distance_to(b.global_position)
	)

	var result: Array = []
	var limit: int = mini(max_count, targets.size())
	for i in range(limit):
		result.append(targets[i])
	return result


static func receive_invulnerability_spell(owner: Node, duration: float) -> void:
	if duration <= 0.0 or not owner.stats:
		return
	owner.invulnerability_active = true
	owner.invulnerability_time_remaining = maxf(owner.invulnerability_time_remaining, duration)
	owner._apply_unit_color()
	owner._update_visual_effect(owner)


static func receive_boost(owner: Node, duration: float) -> void:
	if duration <= 0.0 or not owner.stats:
		return
	owner.boost_active = true
	owner.boost_time_remaining = maxf(owner.boost_time_remaining, duration)
	owner.unit_speed = owner.stats.speed * 1.25
	owner.unit_damage = int(round(owner.stats.damage * 1.25))
	owner.attack_rate_multiplier = 1.25
	owner._apply_unit_color()
	owner._update_visual_effect(owner)


static func receive_anti_armor_spell(owner: Node, duration: float, multiplier: float) -> void:
	if duration <= 0.0 or multiplier <= 1.0 or not owner.stats:
		return
	owner.anti_armor_spell_active = true
	owner.anti_armor_spell_time_remaining = maxf(owner.anti_armor_spell_time_remaining, duration)
	owner.incoming_damage_multiplier = maxf(owner.incoming_damage_multiplier, multiplier)
	owner._apply_unit_color()


static func current_attack_rate(owner: Node) -> float:
	var base_rate: float = owner.stats.attack_rate if owner.stats and "attack_rate" in owner.stats else 1.0
	return base_rate * owner.attack_rate_multiplier


static func unit_color(owner: Node) -> Color:
	if owner.invulnerability_active and owner.boost_active:
		return Color(0.45, 1.0, 0.55)
	if owner.invulnerability_active:
		return Color(0.35, 1.0, 0.45)
	if owner.boost_active:
		return Color(1.0, 0.95, 0.25)
	if owner.anti_armor_spell_active:
		return Color(1.0, 0.45, 0.85)
	# Colors relative to the local viewer: gray = neutral, red = hostile player,
	# white = own troops (never red on your own screen).
	var t: int = int(owner.team)
	if MapSession.is_neutral_team(t):
		return Color(0.6, 0.6, 0.6)
	if MapSession.is_hostile_team(t):
		return Color(1.0, 0.2, 0.2)
	return Color.WHITE


static func apply_unit_color(owner: Node) -> void:
	for sprite in owner._animated_sprites():
		sprite.modulate = unit_color(owner)


static func _append_sync_id(dest: Array, unit: Node) -> void:
	if unit.get("net_sync_id") == null:
		return
	var sid: int = int(unit.net_sync_id)
	if sid >= 0 and not dest.has(sid):
		dest.append(sid)


static func _report_spell_network(owner: Node, target_sync_ids: Array) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	if owner.net_sync_id < 0 or bool(owner.get("net_remote_proxy")):
		return
	if not MapSession.is_local_team(int(owner.team)):
		return
	var spell_type: int = OnlineGameSync.SPELL_INVULN
	var params: Dictionary = {"duration": owner._invulnerability_spell_duration()}
	if owner.stats and owner.stats.unit_type == UnitStats.UnitType.SUPPORT:
		spell_type = OnlineGameSync.SPELL_BOOST
		params = {"duration": owner._boost_spell_duration()}
	OnlineGameSync.report_spell_cast(owner.net_sync_id, spell_type, target_sync_ids, params)


static func _report_mortar_spell_network(owner: Node, positions: Array) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	if owner.net_sync_id < 0 or bool(owner.get("net_remote_proxy")):
		return
	if not MapSession.is_local_team(int(owner.team)):
		return
	OnlineGameSync.report_spell_cast(
		owner.net_sync_id, OnlineGameSync.SPELL_MORTAR, [], {"positions": positions}
	)


static func _report_anti_armor_spell_network(owner: Node, target_sync_ids: Array) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	if owner.net_sync_id < 0 or bool(owner.get("net_remote_proxy")):
		return
	if not MapSession.is_local_team(int(owner.team)):
		return
	OnlineGameSync.report_spell_cast(
		owner.net_sync_id,
		OnlineGameSync.SPELL_ANTI_ARMOR,
		target_sync_ids,
		{
			"duration": anti_armor_spell_duration(owner),
			"multiplier": owner.ANTI_ARMOR_SPELL_DAMAGE_MULTIPLIER,
		}
	)


static func apply_spell_network_remote(
	owner: Node, spell_type: int, target_sync_ids: Array, params: Dictionary
) -> void:
	owner.current_spell_cooldown = owner.SPELL_COOLDOWN_SECONDS
	match spell_type:
		OnlineGameSync.SPELL_INVULN:
			var duration: float = float(params.get("duration", 0.0))
			for sid in target_sync_ids:
				var unit: Node = OnlineGameSync.get_unit(int(sid))
				if unit != null:
					receive_invulnerability_spell(unit, duration)
		OnlineGameSync.SPELL_BOOST:
			var boost_duration: float = float(params.get("duration", 0.0))
			for sid in target_sync_ids:
				var ally: Node = OnlineGameSync.get_unit(int(sid))
				if ally != null:
					receive_boost(ally, boost_duration)
		OnlineGameSync.SPELL_MORTAR:
			var positions: Variant = params.get("positions", [])
			if positions is Array:
				for pos in positions:
					if pos is Vector2:
						owner._spawn_mortar_explosion_vfx(owner.SCENE_MORTAR_EXPLOSION_ULT, pos)
		OnlineGameSync.SPELL_ANTI_ARMOR:
			for sid in target_sync_ids:
				var target: Node = OnlineGameSync.get_unit(int(sid))
				if target is Node2D:
					fire_anti_armor_spell_projectile(owner, target as Node2D)
