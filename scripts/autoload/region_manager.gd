extends Node

const _RegionDefs = preload("res://scripts/world/region_definitions.gd")

signal region_captured(region_id: int, team: int, region_name: String)
signal region_lost(region_id: int, team: int)

var _sites_by_region: Dictionary = {}
var _control: Dictionary = {}


func init_match() -> void:
	_sites_by_region.clear()
	_control.clear()

	var defs: Dictionary = _RegionDefs.regions_for_map(MapSession.active_map_index)
	if defs.is_empty():
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
	var defs: Dictionary = _RegionDefs.regions_for_map(MapSession.active_map_index)
	if defs.has(region_id):
		return defs[region_id].get("name", "Region %s" % region_id)
	return ""


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
			print("Region %s controlled by team %s (+%s gold/s per site)" % [
				region_name(region_id), current, _RegionDefs.BONUS_INCOME_PER_SITE
			])


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
