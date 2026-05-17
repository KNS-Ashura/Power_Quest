extends Node

enum AIProfile { AGGRESSIVE, STRATEGIC, SCATTERED }
var current_profile: AIProfile = AIProfile.STRATEGIC
var ai_gold: int = 200
var think_timer: Timer


func _ready() -> void:
	think_timer = Timer.new()
	add_child(think_timer)
	think_timer.wait_time = 3.0
	think_timer.timeout.connect(_on_think)
	think_timer.start()
	GameManager.global_timer.timeout.connect(_on_global_cycle)


func init_match() -> void:
	ai_gold = 200
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
	var owned_camps = _get_owned_camps()
	if owned_camps.is_empty():
		return

	_handle_production(owned_camps)
	_handle_military()


func _get_owned_camps() -> Array:
	return get_tree().get_nodes_in_group("camps").filter(func(c): return c.get("team") == 1)


func _handle_production(owned_camps: Array) -> void:
	for camp in owned_camps:
		if camp.production_queue.size() > 1:
			continue

		var chosen_unit = -1
		match current_profile:
			AIProfile.AGGRESSIVE:
				chosen_unit = [0, 0, 0, 1].pick_random()
			AIProfile.STRATEGIC:
				chosen_unit = [1, 2, 4, 5, 6].pick_random()
			AIProfile.SCATTERED:
				chosen_unit = randi() % 7

		if chosen_unit != -1 and camp.unit_catalog.has(chosen_unit):
			var data = camp.unit_catalog[chosen_unit]
			if ai_gold >= data.price:
				ai_gold -= data.price
				camp.production_queue.append(chosen_unit)
				if camp.production_queue.size() == 1:
					camp.current_unit_total_time = camp.unit_build_time(chosen_unit) if camp.has_method("unit_build_time") else data.build_time
					camp.remaining_time = camp.current_unit_total_time


func _handle_military() -> void:
	var troops = get_tree().get_nodes_in_group("enemies").filter(
		func(t): return is_instance_valid(t) and t is Node2D
	)
	if troops.is_empty():
		return

	match current_profile:
		AIProfile.AGGRESSIVE:
			var c = _find_nearest_camp(troops[0].global_position, 0)
			if c:
				_issue_attack_order(troops, c)
		AIProfile.STRATEGIC:
			var c = _find_nearest_camp(troops[0].global_position, 2)
			if not c:
				c = _find_nearest_camp(troops[0].global_position, 0)
			if c:
				_issue_attack_order(troops, c)
		AIProfile.SCATTERED:
			for t in troops:
				if randf() > 0.5:
					var targets = get_tree().get_nodes_in_group("camps").filter(func(ca): return ca.get("team") in [0, 2])
					if not targets.is_empty():
						var target = targets.pick_random()
						if t.has_method("attack_target") and is_instance_valid(target.guardian):
							t.attack_target(target.guardian)


func _find_nearest_camp(pos: Vector2, team_id: int) -> Node2D:
	var camps = get_tree().get_nodes_in_group("camps").filter(
		func(ca): return is_instance_valid(ca) and ca.get("team") == team_id and ca is Node2D
	)
	if camps.is_empty():
		return null
	camps.sort_custom(func(a, b): return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	return camps[0]


func _issue_attack_order(troops: Array, target_camp: Node2D) -> void:
	if not is_instance_valid(target_camp.guardian):
		return
	for t in troops:
		if t.has_method("attack_target") and not is_instance_valid(t.get("attack_target_node")):
			t.attack_target(target_camp.guardian)
