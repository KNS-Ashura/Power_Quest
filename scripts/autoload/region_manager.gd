extends Node

const _RegionDefs = preload("res://scripts/world/region_definitions.gd")
const SCENE_REGION_SEE := preload("res://scenes/camp-port/animation/region-see.tscn")
const SCENE_REGION_CAPTURE := preload("res://scenes/camp-port/animation/region-capture.tscn")

signal region_captured(region_id: int, team: int, region_name: String)
signal region_lost(region_id: int, team: int)
signal regions_ready

var _sites_by_region: Dictionary = {}
var _control: Dictionary = {}
var _site_to_region: Dictionary = {}
var _site_to_landmass: Dictionary = {}
var _see_fx_by_region: Dictionary = {}
var minimap_region_filter: int = -1


func init_match() -> void:
	_sites_by_region.clear()
	_control.clear()
	_site_to_region.clear()
	minimap_region_filter = -1
	hide_all_region_see()

	var map_index: int = MapSession.active_map_index
	var defs: Dictionary = _RegionDefs.regions_for_map(map_index)
	if defs.is_empty():
		if _RegionDefs.uses_auto_regions(map_index):
			_build_auto_regions_by_position()
			_recalculate_all()
			_rebuild_site_region_index()
			_rebuild_landmass_index()
		regions_ready.emit()
		return

	var by_name: Dictionary = {}
	var all_sites: Array = []
	for site in get_tree().get_nodes_in_group("camps"):
		all_sites.append(site)
		by_name[site.name] = site

	for region_id in defs:
		var config: Dictionary = defs[region_id]
		var names: Array = config.get("sites", [])
		var sites: Array = []
		for node_name in names:
			var site := _resolve_site(by_name, all_sites, String(node_name))
			if site != null:
				sites.append(site)
			else:
				push_warning("RegionManager: site '%s' not found (region %s)" % [node_name, region_id])
		if not sites.is_empty():
			_sites_by_region[region_id] = sites

	_recalculate_all()
	_rebuild_site_region_index()
	_rebuild_landmass_index()
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


func get_region_id_for_site(site: Node) -> int:
	if site == null or not is_instance_valid(site):
		return -1
	return int(_site_to_region.get(site.get_instance_id(), -1))


func are_sites_in_same_region(site_a: Node, site_b: Node) -> bool:
	if not has_regions_for_current_map():
		return true
	var region_a: int = get_region_id_for_site(site_a)
	var region_b: int = get_region_id_for_site(site_b)
	if region_a < 0 or region_b < 0:
		return false
	return region_a == region_b


func is_land_reachable_between(site_a: Node, site_b: Node) -> bool:
	if site_a == null or site_b == null or not is_instance_valid(site_a) or not is_instance_valid(site_b):
		return false
	if site_a == site_b:
		return true
	if not has_regions_for_current_map():
		return true
	var id_a: int = site_a.get_instance_id()
	var id_b: int = site_b.get_instance_id()
	if not _site_to_landmass.has(id_a) or not _site_to_landmass.has(id_b):
		return are_sites_in_same_region(site_a, site_b)
	return _site_to_landmass[id_a] == _site_to_landmass[id_b]


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


func _resolve_site(by_name: Dictionary, all_sites: Array, node_name: String) -> Node:
	if by_name.has(node_name):
		return by_name[node_name]
	for alias in _site_name_aliases(node_name):
		if by_name.has(alias):
			return by_name[alias]
	var target_number := _site_number_from_name(node_name)
	if target_number < 0:
		return null
	for site in all_sites:
		if _site_number_from_name(site.name) == target_number \
				and _same_site_kind(node_name, site.name):
			return site
	return null


func _site_name_aliases(node_name: String) -> Array[String]:
	var key := node_name.to_lower()
	if key == "port":
		return ["port1"]
	if key == "port1":
		return ["port"]
	if key == "camp":
		return ["camp1"]
	if key == "camp1":
		return ["camp"]
	return []


func _site_number_from_name(node_name: String) -> int:
	var key := node_name.to_lower()
	if key == "camp" or key == "port":
		return 1
	if key.begins_with("camp"):
		var suffix := key.substr(4)
		return int(suffix) if suffix.is_valid_int() else -1
	if key.begins_with("port"):
		var suffix := key.substr(4)
		return int(suffix) if suffix.is_valid_int() else -1
	return -1


func _same_site_kind(expected_name: String, actual_name: String) -> bool:
	var expected := expected_name.to_lower()
	var actual := actual_name.to_lower()
	var expected_is_port := expected == "port" or expected.begins_with("port")
	var actual_is_port := actual == "port" or actual.begins_with("port")
	return expected_is_port == actual_is_port


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


func _rebuild_site_region_index() -> void:
	_site_to_region.clear()
	for region_id in _sites_by_region:
		for site in _sites_by_region[region_id]:
			if is_instance_valid(site):
				_site_to_region[site.get_instance_id()] = region_id


func _rebuild_landmass_index() -> void:
	_site_to_landmass.clear()
	var map_index: int = MapSession.active_map_index
	for region_id in _sites_by_region:
		var sites: Array = _sites_by_region[region_id]
		var groups: Array = _RegionDefs.landmass_groups_for_region(map_index, region_id)
		if groups.is_empty():
			for site in sites:
				if is_instance_valid(site):
					_site_to_landmass[site.get_instance_id()] = Vector2i(region_id, 0)
			continue

		var by_name: Dictionary = {}
		for site in sites:
			if is_instance_valid(site):
				by_name[site.name] = site

		var assigned: Dictionary = {}
		for group_idx in range(groups.size()):
			for node_name in groups[group_idx]:
				var site: Node = _resolve_site(by_name, sites, String(node_name))
				if site != null:
					_site_to_landmass[site.get_instance_id()] = Vector2i(region_id, group_idx)
					assigned[site.get_instance_id()] = true

		for site in sites:
			if not is_instance_valid(site):
				continue
			if not assigned.has(site.get_instance_id()):
				_site_to_landmass[site.get_instance_id()] = Vector2i(region_id, 0)


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
			if MapSession.is_local_team(current):
				Economy.add_gold(_RegionDefs.REGION_CAPTURE_GOLD_PLAYER)
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
