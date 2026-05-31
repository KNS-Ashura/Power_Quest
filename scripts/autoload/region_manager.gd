extends Node

const _RegionDefs = preload("res://scripts/world/region_definitions.gd")

signal region_captured(region_id: int, team: int, region_name: String)
signal region_lost(region_id: int, team: int)

var _sites_by_region: Dictionary = {}
var _control: Dictionary = {}


func init_match() -> void:
	_sites_by_region.clear()
	_control.clear()

	var map_index: int = MapSession.active_map_index
	var defs: Dictionary = _RegionDefs.regions_for_map(map_index)
	if defs.is_empty():
		if _RegionDefs.uses_auto_regions(map_index):
			_build_auto_regions_by_position()
			_recalculate_all()
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
			print(
				"Region %s entierement capturee — %s possede la region (+%s or/s par site)."
				% [_region_owner_label(current), region_name(region_id), _RegionDefs.BONUS_INCOME_PER_SITE]
			)


func _region_owner_label(team: int) -> String:
	if MapSession.is_local_team(team):
		return "Le Joueur"
	if not MapSession.is_online_match and team == 1:
		return "L'IA"
	return MapSession.get_team_display_name(team)


func _controlling_team(region_id: int) -> int:
	var sites: Array = _sites_by_region.get(region_id, [])
	if sites.is_empty():
		return -1
	var ref_team: int = sites[0].team
	if ref_team == 2:
		return -1
	for s in sites:
		if not is_instance_valid(s) or s.team != ref_team:
			return -1
	return ref_team
