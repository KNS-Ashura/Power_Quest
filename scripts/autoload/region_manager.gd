extends Node

const _RegionDefs = preload("res://scripts/world/region_definitions.gd")
const SCENE_REGION_SEE := preload("res://scenes/camp-port/animation/region-see.tscn")
const SCENE_REGION_CAPTURE := preload("res://scenes/camp-port/animation/region-capture.tscn")

signal region_captured(region_id: int, team: int, region_name: String)
signal region_lost(region_id: int, team: int)
signal regions_ready

var _sites_by_region: Dictionary = {}
var _control: Dictionary = {}
var _see_fx_by_region: Dictionary = {}
var minimap_region_filter: int = -1


func init_match() -> void:
	_sites_by_region.clear()
	_control.clear()
	minimap_region_filter = -1
	hide_all_region_see()

	var map_index: int = MapSession.active_map_index
	var defs: Dictionary = _RegionDefs.regions_for_map(map_index)
	if defs.is_empty():
		if _RegionDefs.uses_auto_regions(map_index):
			_build_auto_regions_by_position()
			_recalculate_all()
		regions_ready.emit()
		return

	var by_name: Dictionary = {}
	for site in get_tree().get_nodes_in_group("camps"):
		by_name[site.name] = site

	for region_id in defs:
		var config: Dictionary = defs[region_id]
		var names: Array = config.get("sites", [])
		var sites: Array = []
		for node_name in names:
			if by_name.has(node_name):
				sites.append(by_name[node_name])
			else:
				push_warning("RegionManager: site '%s' not found (region %s)" % [node_name, region_id])
		if not sites.is_empty():
			_sites_by_region[region_id] = sites

	_recalculate_all()
	regions_ready.emit()


func notify_site_changed(_site: Node = null) -> void:
	if _sites_by_region.is_empty():
		return
	_recalculate_all()


func bonus_income_for_site(site: Node) -> int:
	if site == null or not is_instance_valid(site):
		return 0
	var team: int = int(site.get("team"))
	if team == 2:
		return 0
	for region_id in _sites_by_region:
		var sites: Array = _sites_by_region[region_id]
		if site in sites and _control.get(region_id, -1) == team:
			return _RegionDefs.BONUS_INCOME_PER_SITE
	return 0


func is_region_controlled(region_id: int, team: int) -> bool:
	return _control.get(region_id, -1) == team


func has_regions_for_current_map() -> bool:
	return not _sites_by_region.is_empty()


func has_region(region_id: int) -> bool:
	return _sites_by_region.has(region_id)


func get_controlling_team(region_id: int) -> int:
	return _control.get(region_id, -1)


func get_sites_for_region(region_id: int) -> Array:
	return _sites_by_region.get(region_id, []).duplicate()


func set_minimap_region_filter(region_id: int) -> void:
	minimap_region_filter = region_id if has_region(region_id) else -1


func should_show_camp_on_minimap(camp: Node) -> bool:
	if minimap_region_filter < 0:
		return true
	if not is_instance_valid(camp):
		return false
	for site in get_sites_for_region(minimap_region_filter):
		if site == camp:
			return true
	return false


func show_region_see(region_id: int) -> void:
	if not has_region(region_id):
		return
	hide_region_see(region_id)
	var team := get_controlling_team(region_id)
	var fx_list: Array = []
	for site in get_sites_for_region(region_id):
		var fx := _spawn_region_vfx(site, SCENE_REGION_SEE, team)
		if fx != null:
			fx_list.append(fx)
	if not fx_list.is_empty():
		_see_fx_by_region[region_id] = fx_list


func hide_region_see(region_id: int) -> void:
	if not _see_fx_by_region.has(region_id):
		return
	for fx in _see_fx_by_region[region_id]:
		if is_instance_valid(fx):
			fx.queue_free()
	_see_fx_by_region.erase(region_id)


func hide_all_region_see() -> void:
	for region_id in _see_fx_by_region.keys():
		hide_region_see(region_id)


func play_region_capture_vfx(region_id: int, team: int) -> void:
	for site in get_sites_for_region(region_id):
		_spawn_region_vfx(site, SCENE_REGION_CAPTURE, team)


func _spawn_region_vfx(site: Node, packed: PackedScene, controlling_team: int) -> Node2D:
	if not is_instance_valid(site) or packed == null:
		return null
	var parent_node := site.get_parent()
	if not is_instance_valid(parent_node):
		return null
	var fx: Node2D = packed.instantiate() as Node2D
	if fx == null:
		return null
	parent_node.add_child(fx)
	fx.global_position = site.global_position
	if fx.has_method("set_team_tint"):
		fx.set_team_tint(controlling_team)
	return fx


func region_name(region_id: int) -> String:
	var map_index: int = MapSession.active_map_index
	var defs: Dictionary = _RegionDefs.regions_for_map(map_index)
	if defs.has(region_id):
		return defs[region_id].get("name", "Region %s" % region_id)
	if _RegionDefs.uses_auto_regions(map_index):
		return _RegionDefs.auto_region_display_name(region_id)
	return ""


func _build_auto_regions_by_position() -> void:
	var sites: Array = get_tree().get_nodes_in_group("camps")
	if sites.is_empty():
		return

	sites.sort_custom(func(a: Node, b: Node) -> bool:
		return a.global_position.y < b.global_position.y
	)

	var count: int = sites.size()
	var third: int = maxi(1, count / 3)
	var two_thirds: int = mini(count, third * 2)

	_sites_by_region[1] = sites.slice(0, third)
	_sites_by_region[2] = sites.slice(third, two_thirds)
	_sites_by_region[3] = sites.slice(two_thirds, count)

	print(
		"RegionManager: auto regions for map %d (%d sites, %d/%d/%d)."
		% [MapSession.active_map_index, count, third, two_thirds - third, count - two_thirds]
	)


func _recalculate_all() -> void:
	for region_id in _sites_by_region:
		var previous: int = _control.get(region_id, -1)
		var current := _controlling_team(region_id)
		if current == previous:
			continue
		if previous >= 0 and previous != 2:
			region_lost.emit(region_id, previous)
		_control[region_id] = current
		if current >= 0 and current != 2:
			region_captured.emit(region_id, current, region_name(region_id))
			play_region_capture_vfx(region_id, current)
	_refresh_active_see_tints()


func _refresh_active_see_tints() -> void:
	for region_id in _see_fx_by_region:
		var team := get_controlling_team(region_id)
		for fx in _see_fx_by_region[region_id]:
			if is_instance_valid(fx) and fx.has_method("set_team_tint"):
				fx.set_team_tint(team)


func _region_owner_label(team: int) -> String:
	if MapSession.is_local_team(team):
		return "The Player"
	if not MapSession.is_online_match and team == 1:
		return "The AI"
	return MapSession.get_team_display_name(team)


func _controlling_team(region_id: int) -> int:
	var sites: Array = _sites_by_region.get(region_id, [])
	if sites.is_empty():
		return -1
	var ref_team: int = NodeTeamUtils.team_id(sites[0])
	if ref_team < 0 or ref_team == 2:
		return -1
	for s in sites:
		if NodeTeamUtils.team_id(s) != ref_team:
			return -1
	return ref_team
