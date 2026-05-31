extends RefCounted
class_name PlayerCombatController


static func on_attack_timer_timeout(owner: Node) -> void:
	if not owner._is_valid_combat_target(owner.attack_target_node):
		owner._stop_combat()
		return
	if not (owner.attack_target_node in owner.zone_detection.get_overlapping_bodies()):
		owner._stop_combat()
		return
	if owner._is_healer():
		owner._play_attack_animation(owner.attack_target_node)
		owner._schedule_projectile_shot(owner.attack_target_node, owner.PROJECTILE_ATTACK_ANIM_DELAY_HEAL, true)
		return
	if owner._is_mortar():
		fire_mortar_base_attack(owner, owner.attack_target_node)
		return
	if owner._is_range() or owner._is_water_range_unit() or (owner.stats != null and owner.stats.is_ranged):
		owner._play_attack_animation(owner.attack_target_node)
		owner._schedule_projectile_shot(owner.attack_target_node, owner.PROJECTILE_ATTACK_ANIM_DELAY_RANGE, false)
		return
	if owner.attack_target_node.has_method("take_damage"):
		owner._play_attack_animation(owner.attack_target_node)
		owner._deal_combat_damage(owner.attack_target_node, owner.unit_damage)
		animate_melee_attack(owner)


static func animate_melee_attack(owner: Node) -> void:
	if is_instance_valid(owner.attack_target_node):
		for sprite in owner._animated_sprites():
			var flash: Tween = owner.create_tween()
			flash.tween_property(sprite, "modulate", Color.RED, 0.1)
			flash.tween_property(sprite, "modulate", owner._unit_color(), 0.1)


static func search_target_automatically(owner: Node) -> void:
	if owner._is_healer():
		var allies: Array = owner.zone_detection.get_overlapping_bodies().filter(func(c):
			return c != owner and owner._is_valid_combat_target(c)
		)
		if owner.is_camp_guardian:
			allies = allies.filter(func(c): return c.global_position.distance_to(owner.guard_position) <= owner.guard_defense_radius)
		if allies.size() > 0:
			allies.sort_custom(func(a, b):
				var ratio_a: float = float(a.current_hp) / max(1.0, float(a.hp_max))
				var ratio_b: float = float(b.current_hp) / max(1.0, float(b.hp_max))
				if ratio_a != ratio_b:
					return ratio_a < ratio_b
				return owner.global_position.distance_to(a.global_position) < owner.global_position.distance_to(b.global_position)
			)
			owner.attack_target(allies[0])
		return

	var targets: Array = owner.zone_detection.get_overlapping_bodies().filter(func(c):
		return c != owner and owner._is_valid_combat_target(c)
	)
	if owner.is_camp_guardian:
		targets = targets.filter(func(c): return c.global_position.distance_to(owner.guard_position) <= owner.guard_defense_radius)

	if targets.size() > 0:
		var best_target: Node2D = targets[0]
		for target in targets:
			var best_is_soldier: bool = not best_target.is_in_group("camps")
			var target_is_soldier: bool = not target.is_in_group("camps")
			if target_is_soldier and not best_is_soldier:
				best_target = target
				continue
			if target_is_soldier == best_is_soldier:
				var dist_best: float = owner.global_position.distance_to(best_target.global_position)
				var dist_target: float = owner.global_position.distance_to(target.global_position)
				if dist_target < dist_best:
					best_target = target
		owner.attack_target(best_target)


static func fire_range_projectile(owner: Node, target: Node2D) -> void:
	if not owner._is_valid_combat_target(target):
		owner._stop_combat()
		return
	var parent_node: Node = owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var scene_proj: PackedScene = owner.SCENE_WATER_RANGE_PROJECTILE_LOOP if owner._is_water_range_unit() else owner.SCENE_RANGE_PROJECTILE_LOOP
	var proj: Node = scene_proj.instantiate()
	parent_node.add_child(proj)
	proj.global_position = owner.global_position
	if proj.has_method("launch"):
		proj.launch(target, owner.unit_damage, owner)


static func heal_amount(owner: Node) -> int:
	return int(max(10.0, float(owner.hp_max) * 0.12))


static func fire_heal_projectile(owner: Node, target: Node2D) -> void:
	if not owner._is_valid_combat_target(target):
		owner._stop_combat()
		return
	var parent_node: Node = owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj: Node = owner.SCENE_HEALER_PROJECTILE_LOOP.instantiate()
	parent_node.add_child(proj)
	proj.global_position = owner.global_position
	if proj.has_method("launch"):
		proj.launch(target, heal_amount(owner), owner)


static func schedule_projectile_shot(owner: Node, target: Node2D, delay_seconds: float, heal_projectile: bool) -> void:
	if not owner._is_valid_combat_target(target):
		return
	owner._pending_projectile_ticket += 1
	var ticket: int = owner._pending_projectile_ticket
	if delay_seconds <= 0.0:
		trigger_projectile_shot(owner, ticket, target, heal_projectile)
		return
	var timer: SceneTreeTimer = owner.get_tree().create_timer(delay_seconds)
	timer.timeout.connect(func(): trigger_projectile_shot(owner, ticket, target, heal_projectile), CONNECT_ONE_SHOT)


static func trigger_projectile_shot(owner: Node, ticket: int, target: Node2D, heal_projectile: bool) -> void:
	if ticket != owner._pending_projectile_ticket:
		return
	if not owner._is_valid_combat_target(target):
		return
	if not (target in owner.zone_detection.get_overlapping_bodies()):
		return
	if heal_projectile:
		fire_heal_projectile(owner, target)
	else:
		fire_range_projectile(owner, target)


static func handle_passive_guardian_shots(owner: Node, delta: float) -> void:
	var enemies: Array = passive_shot_enemies_in_range(owner)
	if enemies.is_empty():
		owner.passive_guardian_shot_timer = 0.0
		return
	owner.passive_guardian_shot_timer -= delta
	if owner.passive_guardian_shot_timer > 0.0:
		return
	owner.passive_guardian_shot_timer = 1.0 / float(owner._port_guardian_level())
	enemies.sort_custom(func(a, b):
		return owner.global_position.distance_to(a.global_position) < owner.global_position.distance_to(b.global_position)
	)
	fire_passive_guardian_projectile(owner, enemies[0])


static func passive_shot_enemies_in_range(owner: Node) -> Array:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = owner.PORT_GUARDIAN_PASSIVE_SHOT_RADIUS
	query.shape = circle
	query.transform = Transform2D(0, owner.global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = owner.COLLISION_LAYER_PLAYER_UNIT | owner.COLLISION_LAYER_ENEMY_UNIT

	var targets: Array = []
	for res in owner.get_world_2d().direct_space_state.intersect_shape(query):
		var obj: Variant = res.collider
		if not is_instance_valid(obj) or obj == owner:
			continue
		if not obj.has_method("take_damage") or obj.is_in_group("camps"):
			continue
		if obj.get("team") == null or obj.team == owner.team:
			continue
		if obj.global_position.distance_to(owner.guard_position) > owner.guard_chase_radius:
			continue
		targets.append(obj)
	return targets


static func passive_guardian_projectile_scene(owner: Node) -> PackedScene:
	if owner._is_port_guardian():
		return owner.SCENE_PORT_GUARDIAN_PROJECTILE_LOOP
	return owner.SCENE_CAMP_GUARDIAN_PROJECTILE_LOOP


static func passive_guardian_projectile_speed(owner: Node) -> float:
	if owner._is_port_guardian():
		return owner.PORT_GUARDIAN_PROJECTILE_SPEED
	return owner.CAMP_GUARDIAN_PROJECTILE_SPEED


static func fire_passive_guardian_projectile(owner: Node, target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	var parent_node: Node = owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj: Node = passive_guardian_projectile_scene(owner).instantiate()
	parent_node.add_child(proj)
	proj.global_position = owner.global_position
	if proj.has_method("launch"):
		proj.launch(target, owner.unit_damage, owner, passive_guardian_projectile_speed(owner))


static func fire_mortar_base_attack(owner: Node, target: Node2D) -> void:
	if not owner._is_valid_combat_target(target):
		owner._stop_combat()
		return
	owner._play_attack_animation(target)
	fire_mortar_at_range(owner, target)


static func fire_mortar_at_range(owner: Node, target: Node2D) -> void:
	if not owner._is_valid_combat_target(target):
		owner._stop_combat()
		return
	var impact_position: Vector2 = target.global_position
	var explosion: Dictionary = next_mortar_explosion(owner)
	spawn_mortar_explosion_vfx(owner, explosion["scene"], impact_position)
	apply_area_damage(owner, impact_position, explosion["radius"], explosion["damage"])


static func next_mortar_explosion(owner: Node) -> Dictionary:
	var base: Dictionary = {
		"scene": owner.SCENE_MORTAR_EXPLOSION_BASE,
		"radius": 96.0,
		"damage": owner.unit_damage
	}
	var poison: Dictionary = {
		"scene": owner.SCENE_MORTAR_EXPLOSION_POISON,
		"radius": 108.0,
		"damage": int(round(float(owner.unit_damage) * 0.72))
	}
	var fire: Dictionary = {
		"scene": owner.SCENE_MORTAR_EXPLOSION_FIRE,
		"radius": 122.0,
		"damage": int(round(float(owner.unit_damage) * 0.92))
	}

	var level: int = owner._mortar_level()
	var sequence: Array = [base]
	if level == 2:
		sequence = [base, poison]
	elif level >= 3:
		sequence = [base, poison, fire]

	var index: int = owner.cycle_explosion_mortar % sequence.size()
	owner.cycle_explosion_mortar += 1
	return sequence[index]


static func spawn_mortar_explosion_vfx(owner: Node, scene: PackedScene, position_world: Vector2) -> void:
	if scene == null:
		return
	var parent_node: Node = owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var vfx: Node = scene.instantiate()
	parent_node.add_child(vfx)
	vfx.global_position = position_world
	if vfx.is_in_group("soldiers"):
		vfx.remove_from_group("soldiers")
	var sprite := vfx.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(sprite):
		if sprite.sprite_frames and sprite.sprite_frames.has_animation("explosion"):
			sprite.sprite_frames.set_animation_loop("explosion", false)
			sprite.play("explosion")
			sprite.animation_finished.connect(func(): if is_instance_valid(vfx): vfx.queue_free(), CONNECT_ONE_SHOT)
		else:
			vfx.queue_free()


static func apply_area_damage(owner: Node, center: Vector2, radius: float, damage: int) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0, center)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var results: Array = owner.get_world_2d().direct_space_state.intersect_shape(query)
	for res in results:
		var obj: Variant = res.collider
		if not is_instance_valid(obj):
			continue
		if obj == owner:
			continue
		if not obj.has_method("take_damage"):
			continue
		if obj.get("team") == null or obj.team == owner.team:
			continue
		if obj.is_in_group("camps"):
			continue
		owner._deal_combat_damage(obj, damage)


static func apply_heal_to_target(owner: Node, target: Node2D) -> void:
	if not owner._is_valid_combat_target(target):
		owner._stop_combat()
		return

	var heal: int = heal_amount(owner)
	_apply_heal_local(owner, target, heal)
	_report_heal_network(owner, target, heal)


static func _apply_heal_local(owner: Node, target: Node2D, heal: int) -> void:
	target.current_hp = min(target.hp_max, target.current_hp + heal)
	if target.has_node("ProgressBar"):
		target.get_node("ProgressBar").value = target.current_hp
	owner._attach_heal_effect_on(target)


static func _report_heal_network(owner: Node, target: Node, heal: int) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	if not MapSession.is_local_team(int(owner.team)):
		return
	var target_sync: int = int(target.get("net_sync_id")) if target.get("net_sync_id") != null else -1
	if target_sync < 0 or owner.net_sync_id < 0:
		return
	OnlineGameSync.report_heal(owner.net_sync_id, target_sync, heal)
