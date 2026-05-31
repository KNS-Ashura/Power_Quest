extends Node

const _RegionDefs = preload("res://scripts/world/region_definitions.gd")
const TEAM_PLAYER := 0
const TEAM_AI := 1
const TEAM_NEUTRAL := 2

var cycle_time: float = 30.0
var cycle_gold_bonus: int = 50
var reinforcement_count: int = 2
var match_over: bool = false
var local_eliminated: bool = false
var _match_started_at: int = 0
var _result_reported: bool = false
const MATCH_STATE_CHECK_INTERVAL := 0.2
var _match_state_check_accumulator: float = MATCH_STATE_CHECK_INTERVAL

@onready var global_timer = Timer.new()


func _ready() -> void:
	add_child(global_timer)
	global_timer.wait_time = cycle_time
	global_timer.timeout.connect(_on_global_timer_timeout)
	global_timer.start()
	if not MapSession.is_online_match:
		call_deferred("_assign_initial_camps")


func init_match() -> void:
	match_over = false
	local_eliminated = false
	_result_reported = false
	_match_started_at = Time.get_unix_time_from_system()
	Economy.reset_for_match()
	if not global_timer.is_stopped():
		global_timer.stop()
	global_timer.start()
	if MapSession.is_online_match:
		MapSession.online_camps_ready = false
		OnlineMatch.begin_setup_after_main_loaded()
		return
	_assign_initial_camps()


func _assign_initial_camps() -> void:
	var all_camps := get_tree().get_nodes_in_group("camps")
	if all_camps.size() < 2:
		return

	var land: Array = []
	var ports: Array = []
	for camp in all_camps:
		if camp.has_method("is_port") and camp.is_port():
			ports.append(camp)
		else:
			land.append(camp)

	land.shuffle()
	ports.shuffle()

	var camps_per_player := maxi(1, all_camps.size() / 4)
	var player_sites: Array = [[], []]

	# Au moins un camp terrestre par campagne (joueur + IA) quand la carte en propose.
	if not land.is_empty():
		player_sites[0].append(land.pop_front())
	if not land.is_empty():
		player_sites[1].append(land.pop_front())

	var pool: Array = []
	pool.append_array(land)
	pool.append_array(ports)
	pool.shuffle()

	for team_idx in range(2):
		while player_sites[team_idx].size() < camps_per_player and not pool.is_empty():
			player_sites[team_idx].append(pool.pop_front())

	for camp in player_sites[0]:
		camp._capture_by_team(0)
	for camp in player_sites[1]:
		camp._capture_by_team(1)

	var assigned: Dictionary = {}
	for camp in player_sites[0]:
		assigned[camp] = true
	for camp in player_sites[1]:
		assigned[camp] = true
	for camp in all_camps:
		if not assigned.has(camp):
			camp._capture_by_team(2)

	_ensure_ai_land_camp_per_region(all_camps)
	RegionManager.init_match()


func _process(delta: float) -> void:
	if match_over:
		return
	if MapSession.is_online_match and local_eliminated:
		return
	if MapSession.is_online_match and not MapSession.online_camps_ready:
		return
	_match_state_check_accumulator += delta
	if _match_state_check_accumulator < MATCH_STATE_CHECK_INTERVAL:
		return
	_match_state_check_accumulator = 0.0

	var all_camps = get_tree().get_nodes_in_group("camps")
	if all_camps.size() == 0:
		return

	var local_camps := 0
	var hostile_camps := 0
	var teams_with_camps: Dictionary = {}

	for camp in all_camps:
		var t: int = int(camp.get("team"))
		if MapSession.is_neutral_team(t):
			continue
		if MapSession.is_local_team(t):
			local_camps += 1
		else:
			hostile_camps += 1
		teams_with_camps[t] = int(teams_with_camps.get(t, 0)) + 1

	if MapSession.is_online_match:
		if local_camps == 0 and not local_eliminated:
			local_eliminated = true
			_report_match_result(false)
			_show_match_result(false)
			return
		var rival_teams := 0
		for team_id in teams_with_camps.keys():
			if int(team_id) != MapSession.local_team:
				rival_teams += 1
		if rival_teams == 0 and local_camps > 0:
			match_over = true
			_report_match_result(true)
			_show_match_result(true)
		return

	if local_camps == 0:
		match_over = true
		_report_match_result(false)
		_show_match_result(false)
	elif hostile_camps == 0:
		match_over = true
		_report_match_result(true)
		_show_match_result(true)


## Secret shortcuts (solo / local test): * = capture all, $ = lose all.
func _unhandled_input(event: InputEvent) -> void:
	if match_over or ServerMode.is_dedicated_server or MapSession.is_online_match:
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if get_tree().get_nodes_in_group("camps").is_empty():
		return

	if _cheat_key_matches(key, KEY_ASTERISK, 42):
		_debug_cheat_capture_all_hostile_camps()
		get_viewport().set_input_as_handled()
	elif _cheat_key_matches(key, KEY_DOLLAR, 36):
		_debug_cheat_lose_all_local_camps()
		get_viewport().set_input_as_handled()
	elif _cheat_key_matches(key, KEY_EQUAL, 43):
		_debug_cheat_capture_region(1)
		get_viewport().set_input_as_handled()


func _cheat_key_matches(key: InputEventKey, code: Key, unicode_char: int) -> bool:
	if key.keycode == code or key.physical_keycode == code:
		return true
	return unicode_char != 0 and key.unicode == unicode_char


func _debug_primary_enemy_team() -> int:
	for camp in get_tree().get_nodes_in_group("camps"):
		var t: int = int(camp.get("team"))
		if MapSession.is_hostile_team(t):
			return t
	return 1


func _debug_cheat_capture_all_hostile_camps() -> void:
	var local_team := MapSession.local_team if MapSession.is_online_match else 0
	var count := 0
	for camp in get_tree().get_nodes_in_group("camps"):
		var t: int = int(camp.get("team"))
		if MapSession.is_neutral_team(t) or MapSession.is_local_team(t):
			continue
		if camp.has_method("_capture_by_team"):
			camp._capture_by_team(local_team)
			count += 1
	print("[GameManager] Cheat *: ", count, " hostile camp(s) captured.")


func _debug_cheat_lose_all_local_camps() -> void:
	var enemy_team := _debug_primary_enemy_team()
	var count := 0
	for camp in get_tree().get_nodes_in_group("camps"):
		if not MapSession.is_local_team(int(camp.get("team"))):
			continue
		if camp.has_method("_capture_by_team"):
			camp._capture_by_team(enemy_team)
			count += 1
	print("[GameManager] Cheat $: ", count, " local camp(s) lost.")


func _debug_cheat_capture_region(region_id: int) -> void:
	if MapSession.active_map_index != 1:
		print("[GameManager] Cheat +: map 1 only.")
		return
	if not RegionManager.has_region(region_id):
		print("[GameManager] Cheat +: region %d not found." % region_id)
		return
	var local_team := 0 if not MapSession.is_online_match else MapSession.local_team
	var count := 0
	for site in RegionManager.get_sites_for_region(region_id):
		if not is_instance_valid(site):
			continue
		if site.has_method("_capture_by_team"):
			site._capture_by_team(local_team)
			count += 1
	print("[GameManager] Cheat +: captured region %d (%d site(s))." % [region_id, count])


func _on_global_timer_timeout() -> void:
	if match_over or local_eliminated:
		return
	if MapSession.is_online_match and not MapSession.online_camps_ready:
		return

	Economy.add_gold(cycle_gold_bonus)

	for camp in get_tree().get_nodes_in_group("camps"):
		if not MapSession.is_local_team(int(camp.get("team"))):
			continue
		if camp.has_method("is_port") and camp.is_port():
			continue
		camp.receive_reinforcements(reinforcement_count)
		break


func _report_match_result(win: bool) -> void:
	if _result_reported:
		return
	_result_reported = true
	if not NetworkSession.is_account_logged_in():
		return
	var elapsed := int(maxi(0, Time.get_unix_time_from_system() - _match_started_at))
	NetworkSession.submit_match_result(win, elapsed)


const VICTORY_SCENE := "res://scenes/ui/Scene_Victory.tscn"
const DEFEAT_SCENE := "res://scenes/ui/Scene_defeat.tscn"

var last_match_duration_sec: int = 0
var _result_overlay: CanvasLayer = null


func format_match_duration(total_sec: int) -> String:
	var h := total_sec / 3600
	var m := (total_sec % 3600) / 60
	var s := total_sec % 60
	if h > 0:
		return str(h) + "h " + str(m).pad_zeros(2) + "m " + str(s).pad_zeros(2) + "s"
	return str(m) + "m " + str(s).pad_zeros(2) + "s"


## Win/loss overlay above the match (game stays visible in the background).
func _show_match_result(win: bool) -> void:
	if ServerMode.is_dedicated_server:
		return
	if _result_overlay != null and is_instance_valid(_result_overlay):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return

	last_match_duration_sec = int(maxi(0, Time.get_unix_time_from_system() - _match_started_at))

	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "MatchResultOverlay"
	_result_overlay = layer

	var panel_path := VICTORY_SCENE if win else DEFEAT_SCENE
	var packed: PackedScene = load(panel_path) as PackedScene
	if packed == null:
		push_error("[GameManager] End screen scene not found: " + panel_path)
		return

	layer.add_child(packed.instantiate())
	scene.add_child(layer)


func clear_result_overlay() -> void:
	if _result_overlay != null and is_instance_valid(_result_overlay):
		_result_overlay.queue_free()
	_result_overlay = null


## Reset match state (return to menu or new game).
func reset_session() -> void:
	match_over = false
	local_eliminated = false
	_result_reported = false
	_result_overlay = null
	if Music.has_method("stop"):
		Music.stop()
	Economy.reset_for_match()
	if AIManager.has_method("init_match"):
		AIManager.init_match()


func _ensure_ai_land_camp_per_region(all_camps: Array) -> void:
	if MapSession.is_online_match:
		return
	var region_defs: Dictionary = _RegionDefs.regions_for_map(MapSession.active_map_index)
	if region_defs.is_empty():
		return

	var by_name: Dictionary = {}
	for camp in all_camps:
		if is_instance_valid(camp):
			by_name[camp.name] = camp

	for region_id in region_defs:
		var config: Dictionary = region_defs[region_id]
		var land_in_region: Array = []
		for node_name in config.get("sites", []):
			var site: Node = _resolve_camp_by_name(by_name, all_camps, String(node_name))
			if site != null and _is_land_camp_site(site):
				land_in_region.append(site)
		if land_in_region.is_empty():
			continue
		if _region_has_team_land_camp(land_in_region, TEAM_AI):
			continue
		var pick: Node = _pick_land_camp_for_ai(land_in_region)
		if pick != null:
			pick._capture_by_team(TEAM_AI)


func _region_has_team_land_camp(land_camps: Array, team: int) -> bool:
	for camp in land_camps:
		if is_instance_valid(camp) and int(camp.get("team")) == team:
			return true
	return false


func _pick_land_camp_for_ai(land_camps: Array) -> Node:
	for camp in land_camps:
		if is_instance_valid(camp) and int(camp.get("team")) == TEAM_NEUTRAL:
			return camp
	for camp in land_camps:
		if is_instance_valid(camp) and int(camp.get("team")) == TEAM_PLAYER:
			return camp
	return null


func _is_land_camp_site(camp: Node) -> bool:
	return is_instance_valid(camp) and (not camp.has_method("is_port") or not camp.is_port())


func _resolve_camp_by_name(by_name: Dictionary, all_camps: Array, node_name: String) -> Node:
	if by_name.has(node_name):
		return by_name[node_name]
	for alias in _camp_name_aliases(node_name):
		if by_name.has(alias):
			return by_name[alias]
	var target_number := _camp_number_from_name(node_name)
	if target_number < 0:
		return null
	for camp in all_camps:
		if not is_instance_valid(camp):
			continue
		if _camp_number_from_name(camp.name) == target_number \
				and _same_camp_kind(node_name, camp.name):
			return camp
	return null


func _camp_name_aliases(node_name: String) -> Array[String]:
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


func _camp_number_from_name(node_name: String) -> int:
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


func _same_camp_kind(expected_name: String, actual_name: String) -> bool:
	var expected := expected_name.to_lower()
	var actual := actual_name.to_lower()
	var expected_is_port := expected == "port" or expected.begins_with("port")
	var actual_is_port := actual == "port" or actual.begins_with("port")
	return expected_is_port == actual_is_port
