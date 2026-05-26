extends StaticBody2D

const CampCatalogue = preload("res://scripts/camp/camp_catalogue.gd")

enum Owner { PLAYER, ENEMY, NEUTRAL }
enum SiteType { CAMP, PORT }

@export var team: Owner = Owner.NEUTRAL
@export var site_type: SiteType = SiteType.CAMP
@export var income_per_second: int = 5
@export var hp_max: int = 500
@export_range(1, 3, 1) var camp_level: int = 1
@export var production_time_multiplier: float = 1.0
@export var upgrade_cost_level_2: int = 200
@export var upgrade_cost_level_3: int = 350
@export var use_level_visual_overlays: bool = true
@export var camp_visual_variant: String = "map1"

var current_hp: int = hp_max
var guardian: Node2D = null
var unit_catalog: Dictionary = {}
var production_queue: Array = []
var remaining_time: float = 0.0
var current_unit_total_time: float = 1.0

@onready var spawn_point = $Marker2D
var income_timer: Timer
var _guardian_spawn_timer: float = 0.0

const GUARDIAN_DELAY_ONLINE := 1.0

signal production_updated(queue_size, progress)
signal camp_upgradedd(new_level)
signal site_captured(new_team)


func _ready() -> void:
	_detect_site_type()
	_detect_visual_variant()
	_apply_level_config()
	_refresh_unit_catalog()
	_apply_level_visuals()
	add_to_group("camps")
	_update_groups_and_visuals()

	if has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.play()

	income_timer = Timer.new()
	add_child(income_timer)
	income_timer.wait_time = 1.0
	income_timer.timeout.connect(_on_income_timer_timeout)
	income_timer.start()

	if MapSession.is_online_match:
		_guardian_spawn_timer = 999.0
		if not OnlineMatch.setup_complete.is_connected(_on_online_camps_ready):
			OnlineMatch.setup_complete.connect(_on_online_camps_ready, CONNECT_ONE_SHOT)
	else:
		_schedule_guardian_spawn()


func _on_online_camps_ready() -> void:
	_schedule_guardian_spawn()


func _detect_site_type() -> void:
	if site_type == SiteType.PORT:
		return
	var n := name.to_lower()
	if n == "port" or n.begins_with("port"):
		site_type = SiteType.PORT
		return
	var path := scene_file_path.to_lower()
	if path.contains("/port") or path.contains("port_nv") or path.contains("port2/"):
		site_type = SiteType.PORT


const OVERLAY_VISUAL_NODE_NAMES: Array[String] = [
	"AnimatedSprite2D2", "AnimatedSprite2D3", "Sprite2D2", "Sprite2D3"
]

func _detect_visual_variant() -> void:
	if MapSession.active_map_index == 2:
		camp_visual_variant = "map2"


func is_port() -> bool:
	return site_type == SiteType.PORT


func _refresh_unit_catalog() -> void:
	if is_port():
		unit_catalog = CampCatalogue.port_unit_catalog(camp_level)
	else:
		unit_catalog = CampCatalogue.land_unit_catalog(camp_level)


func _apply_level_visuals() -> void:
	var sprite_base := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite_base:
		sprite_base.play("animation_camp_V")

	for n in OVERLAY_VISUAL_NODE_NAMES:
		var old_node = get_node_or_null(n)
		if old_node:
			old_node.queue_free()

	if not use_level_visual_overlays:
		_apply_full_visual_from_template()
		return

	var paths_by_level: Dictionary = CampCatalogue.visual_paths(camp_visual_variant, is_port())
	var template_path: String = paths_by_level.get(camp_level, paths_by_level.get(1, ""))
	if template_path.is_empty():
		return
	var template_res = load(template_path)
	if not (template_res is PackedScene):
		return
	var template_root = (template_res as PackedScene).instantiate()
	if not is_instance_valid(template_root):
		return

	for n in OVERLAY_VISUAL_NODE_NAMES:
		var source_node = template_root.get_node_or_null(n)
		if source_node == null:
			continue
		var clone = source_node.duplicate()
		clone.name = n
		add_child(clone)
		var anchor := sprite_base if sprite_base else get_node_or_null("Sprite2D") as Node2D
		if anchor:
			move_child(clone, anchor.get_index() + 1)
		if clone is AnimatedSprite2D:
			var s: AnimatedSprite2D = clone
			if s.sprite_frames and s.animation != StringName("") and s.sprite_frames.has_animation(s.animation):
				s.play(s.animation)
	template_root.free()


func _apply_full_visual_from_template() -> void:
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			remove_child(child)
			child.free()

	var paths_by_level: Dictionary = CampCatalogue.visual_paths(camp_visual_variant, is_port())
	var template_path: String = paths_by_level.get(camp_level, paths_by_level.get(1, ""))
	if template_path.is_empty():
		return
	var template_res = load(template_path)
	if not (template_res is PackedScene):
		return

	var template_root = (template_res as PackedScene).instantiate()
	if not is_instance_valid(template_root):
		return

	for source_node in template_root.get_children():
		if not (source_node is Sprite2D or source_node is AnimatedSprite2D):
			continue
		var clone = source_node.duplicate()
		add_child(clone)
		if clone is AnimatedSprite2D:
			var s: AnimatedSprite2D = clone
			if s.sprite_frames and s.animation != StringName("") and s.sprite_frames.has_animation(s.animation):
				s.play(s.animation)
	template_root.free()


func _apply_level_config() -> void:
	match camp_level:
		2:
			income_per_second = 7
			hp_max = 700
			production_time_multiplier = 0.85
		3:
			income_per_second = 10
			hp_max = 1000
			production_time_multiplier = 0.7
		_:
			income_per_second = 5
			hp_max = 500
			production_time_multiplier = 1.0
	current_hp = hp_max


func unit_build_time(unit_id: int) -> float:
	if not unit_catalog.has(unit_id):
		return 1.0
	return _build_time_for(unit_catalog[unit_id])


func _build_time_for(data: UnitStats) -> float:
	return max(0.1, data.build_time * production_time_multiplier)


func _process(delta: float) -> void:
	if _guardian_spawn_timer > 0.0:
		_guardian_spawn_timer -= delta
	if not is_instance_valid(guardian) and _can_spawn_guardian():
		_spawn_guardian()

	if production_queue.size() > 0:
		remaining_time -= delta
		production_updated.emit(production_queue.size(), 1.0 - (remaining_time / current_unit_total_time))
		if remaining_time <= 0:
			_finish_production()


func _can_spawn_guardian() -> bool:
	if not MapSession.is_online_match:
		return true
	if not MapSession.online_camps_ready:
		return false
	if _guardian_spawn_timer > 0.0:
		return false
	if MapSession.is_neutral_team(team):
		return false
	return true


func _schedule_guardian_spawn() -> void:
	if MapSession.is_online_match:
		_guardian_spawn_timer = GUARDIAN_DELAY_ONLINE
	else:
		_guardian_spawn_timer = 0.0


func _spawn_guardian() -> void:
	if is_instance_valid(guardian):
		return
	var new_guardian = CampCatalogue.guardian_scene_for_site(camp_level, is_port()).instantiate()
	if not ("stats" in new_guardian):
		push_warning("Invalid guardian scene: root must have 'stats' property.")
		new_guardian.queue_free()
		return
	new_guardian.stats = CampCatalogue.guardian_stats_for_site(camp_level, is_port())

	var spawn_position = _guardian_spawn_position()
	new_guardian.team = team

	if MapSession.is_local_team(team):
		new_guardian.add_to_group("soldiers")
	else:
		if new_guardian.is_in_group("soldiers"):
			new_guardian.remove_from_group("soldiers")
		new_guardian.add_to_group("enemies")

	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		new_guardian.queue_free()
		return
	parent_node.add_child(new_guardian)
	new_guardian.global_position = spawn_position
	if new_guardian.has_method("configure_guardian_mode"):
		new_guardian.configure_guardian_mode(spawn_position, 260.0, 320.0)
	new_guardian.killed_by.connect(_on_guardian_killed)
	guardian = new_guardian


func _guardian_spawn_position() -> Vector2:
	var base = spawn_point.global_position if is_instance_valid(spawn_point) else (global_position + Vector2(0, 90))
	base.y = max(base.y, global_position.y + 90.0)
	# Slightly offset from unit spawn to reduce initial blocking.
	return base + Vector2(randf_range(-22, 22), randf_range(-8, 18))


func _unit_spawn_position() -> Vector2:
	var base = spawn_point.global_position if is_instance_valid(spawn_point) else (global_position + Vector2(0, 90))
	base.y = max(base.y, global_position.y + 90.0)
	return base + Vector2(randf_range(-48, 48), randf_range(52, 88))


const NAV_LAYER_WATER := 2


func _water_spawn_position() -> Vector2:
	var origin: Vector2 = spawn_point.global_position if is_instance_valid(spawn_point) else global_position
	var best: Vector2 = origin
	var best_d2: float = INF
	var regions: Array[NavigationRegion2D] = []
	var root := get_tree().current_scene
	if is_instance_valid(root):
		_collect_navigation_regions(root, regions)
	for region in regions:
		if (region.navigation_layers & NAV_LAYER_WATER) == 0:
			continue
		var closest: Vector2 = NavigationServer2D.map_get_closest_point(region.get_navigation_map(), origin)
		var d2: float = origin.distance_squared_to(closest)
		if d2 < best_d2:
			best_d2 = d2
			best = closest
	if best_d2 == INF:
		push_warning("Port: no NavigationRegion2D on water layer (2). Spawning at port point.")
		return _unit_spawn_position()
	return best + Vector2(randf_range(-28, 28), randf_range(-28, 28))


func _collect_navigation_regions(node: Node, out: Array) -> void:
	if node is NavigationRegion2D:
		out.append(node)
	for child in node.get_children():
		_collect_navigation_regions(child, out)


func _on_guardian_killed(killer: Node2D, killer_team: int = -1) -> void:
	if killer_team != -1 and killer_team != team:
		_capture_by_team(killer_team)
	elif is_instance_valid(killer) and killer.get("team") != null and killer.team != team:
		_capture_by_team(killer.team)
	else:
		_capture_by_team(Owner.NEUTRAL)


func _capture_by_team(new_team: int) -> void:
	team = new_team
	current_hp = hp_max
	production_queue.clear()
	if is_instance_valid(guardian):
		guardian.queue_free()
		guardian = null
	_update_groups_and_visuals()
	_notify_capture()
	_schedule_guardian_spawn()


func _notify_capture() -> void:
	site_captured.emit(team)
	RegionManager.notify_site_changed(self)


func _on_income_timer_timeout() -> void:
	if MapSession.is_local_team(team):
		var bonus: int = RegionManager.bonus_income_for_site(self)
		Economy.add_gold(income_per_second + bonus)


func request_production(id: int = 0) -> void:
	if not MapSession.is_local_team(team) or not unit_catalog.has(id):
		return
	var data = unit_catalog[id]
	if Economy.spend_gold(data.price):
		production_queue.append(id)
		if production_queue.size() == 1:
			current_unit_total_time = _build_time_for(data)
			remaining_time = current_unit_total_time


func _finish_production() -> void:
	var unit_id = production_queue.pop_front()
	var stat = unit_catalog[unit_id]
	var scene := CampCatalogue.scene_for_unit(stat, unit_id, camp_level)
	if scene == null:
		push_warning("Missing unit scene for id %s (naval units may be WIP)." % str(unit_id))
		_advance_queue_after_failure()
		return
	var unit = scene.instantiate()
	if not ("stats" in unit):
		push_warning("Invalid unit scene for id %s: root must have 'stats' property." % str(unit_id))
		unit.queue_free()
		_advance_queue_after_failure()
		return
	unit.stats = stat
	if stat.unit_type == UnitStats.UnitType.WATER_RANGE \
			or stat.unit_type == UnitStats.UnitType.WATER_TANK \
			or stat.unit_type == UnitStats.UnitType.WATER_TRANSPORT:
		if "force_water_navigation" in unit:
			unit.force_water_navigation = true
	var spawn_position = _water_spawn_position() if is_port() else _unit_spawn_position()
	unit.team = team

	if MapSession.is_local_team(team):
		unit.add_to_group("soldiers")
	else:
		if unit.is_in_group("soldiers"):
			unit.remove_from_group("soldiers")
		unit.add_to_group("enemies")

	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		unit.queue_free()
		return
	parent_node.add_child(unit)
	unit.global_position = spawn_position
	if unit.has_method("_apply_stats_to_unit"):
		unit._apply_stats_to_unit()
	if unit.has_method("_configurer_calques_navigation"):
		unit._configurer_calques_navigation()
	_notify_network_spawn(unit, unit_id, spawn_position)
	_advance_queue_after_failure()


func _notify_network_spawn(unit: Node, unit_id: int, spawn_position: Vector2) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	if multiplayer.is_server():
		return
	OnlineGameSync.notify_unit_spawned(self, unit, unit_id, spawn_position)


func spawn_unite_reseau(
	unit_id: int, spawn_position: Vector2, spawn_team: int, sync_id: int = -1
) -> Node:
	if not unit_catalog.has(unit_id):
		return null
	var stat = unit_catalog[unit_id]
	var scene := CampCatalogue.scene_for_unit(stat, unit_id, camp_level)
	if scene == null:
		return null
	var unit = scene.instantiate()
	if not ("stats" in unit):
		unit.queue_free()
		return null
	unit.stats = stat
	unit.team = spawn_team
	if MapSession.is_local_team(spawn_team):
		unit.add_to_group("soldiers")
	else:
		if unit.is_in_group("soldiers"):
			unit.remove_from_group("soldiers")
		unit.add_to_group("enemies")
	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		unit.queue_free()
		return null
	parent_node.add_child(unit)
	unit.global_position = spawn_position
	if unit.has_method("_apply_stats_to_unit"):
		unit._apply_stats_to_unit()
	if unit.has_method("_configurer_calques_navigation"):
		unit._configurer_calques_navigation()
	if sync_id >= 0:
		unit.net_sync_id = sync_id
		unit.net_remote_proxy = true
		OnlineGameSync.register_unit(sync_id, unit)
	return unit


func _advance_queue_after_failure() -> void:
	if production_queue.size() > 0:
		current_unit_total_time = _build_time_for(unit_catalog[production_queue[0]])
		remaining_time = current_unit_total_time
	else:
		production_updated.emit(0, 0)


func next_upgrade_cost() -> int:
	match camp_level:
		1:
			return upgrade_cost_level_2
		2:
			return upgrade_cost_level_3
		_:
			return -1


func can_upgrade(owner_required: int = Owner.PLAYER) -> bool:
	if MapSession.is_online_match:
		return MapSession.is_local_team(team) and camp_level < 3
	return team == owner_required and camp_level < 3


func upgrade_camp(use_economy: bool = true, owner_required: int = Owner.PLAYER) -> bool:
	if not can_upgrade(owner_required):
		return false

	var cost = next_upgrade_cost()
	if cost <= 0:
		return false
	if use_economy and not Economy.spend_gold(cost):
		return false

	camp_level += 1
	_apply_level_config()
	_refresh_unit_catalog()
	_apply_level_visuals()
	camp_upgradedd.emit(camp_level)

	if production_queue.size() > 0:
		current_unit_total_time = _build_time_for(unit_catalog[production_queue[0]])
		remaining_time = min(remaining_time, current_unit_total_time)
		production_updated.emit(production_queue.size(), 1.0 - (remaining_time / current_unit_total_time))

	if is_instance_valid(guardian):
		guardian.queue_free()
		guardian = null

	return true


func set_selection(selected: bool) -> void:
	modulate = Color(1.5, 1.5, 1.5) if selected else Color(1, 1, 1)


func take_damage(amount: int, attacker: Node2D = null) -> void:
	current_hp -= amount
	if current_hp <= 0:
		_capture(attacker)


func _capture(attacker: Node2D, attacker_team: int = -1) -> void:
	current_hp = hp_max
	production_queue.clear()
	if attacker_team != -1:
		team = attacker_team
	elif is_instance_valid(attacker) and attacker.get("team") != null:
		team = attacker.team
	else:
		team = Owner.NEUTRAL
	if is_instance_valid(guardian):
		guardian.queue_free()
		guardian = null
	_update_groups_and_visuals()
	_notify_capture()
	_schedule_guardian_spawn()


func _update_groups_and_visuals() -> void:
	var color_rect = get_node_or_null("ColorRect") as ColorRect
	var label_node = get_node_or_null("Label") as Label
	var is_friendly := MapSession.is_local_team(team)
	var is_neutral := MapSession.is_neutral_team(team)

	if not is_friendly:
		if color_rect == null:
			color_rect = ColorRect.new()
			color_rect.name = "ColorRect"
			color_rect.offset_left = -64.0
			color_rect.offset_top = -52.0
			color_rect.offset_right = 64.0
			color_rect.offset_bottom = 48.0
			color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(color_rect)
		if label_node == null:
			label_node = Label.new()
			label_node.name = "Label"
			label_node.offset_left = -40.0
			label_node.offset_top = -80.0
			label_node.offset_right = 40.0
			label_node.offset_bottom = -57.0
			label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			add_child(label_node)

	if is_in_group("enemies"):
		remove_from_group("enemies")

	if is_friendly:
		if color_rect:
			color_rect.visible = false
		if label_node:
			label_node.visible = false
	elif is_neutral:
		if color_rect:
			color_rect.visible = true
			color_rect.color = Color(0.5, 0.5, 0.5, 0.3)
		if label_node:
			label_node.visible = true
			label_node.text = "NEUTRE" if not is_port() else "PORT NEUTRE"
	else:
		if MapSession.is_hostile_team(team):
			add_to_group("enemies")
		if color_rect:
			color_rect.visible = true
			color_rect.color = Color(0.8, 0.1, 0.1, 0.3)
		if label_node:
			label_node.visible = true
			label_node.text = "ENNEMI" if not is_port() else "PORT ENNEMI"
	queue_redraw()


func receive_reinforcements(count: int) -> void:
	if is_port():
		return
	var infantry_stats = CampCatalogue.stats_for_level(CampCatalogue.STATS_INFANTRY, camp_level)
	for _i in range(count):
		var unit = CampCatalogue.scene_for_unit(infantry_stats, 0, camp_level).instantiate()
		unit.stats = infantry_stats
		var spawn_position = _unit_spawn_position()
		var parent_node = get_parent()
		if not is_instance_valid(parent_node):
			unit.queue_free()
			return
		parent_node.add_child(unit)
		unit.global_position = spawn_position
