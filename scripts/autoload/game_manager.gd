extends Node

var cycle_time: float = 30.0
var cycle_gold_bonus: int = 100
var reinforcement_count: int = 2
var match_over: bool = false
var local_eliminated: bool = false
var _match_started_at: int = 0
var _result_reported: bool = false

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
	var all_camps = get_tree().get_nodes_in_group("camps")
	if all_camps.size() < 2:
		return

	all_camps.shuffle()

	var camps_per_player = max(1, all_camps.size() / 4)
	var index = 0

	for i in range(camps_per_player):
		all_camps[index]._capture_by_team(0)
		index += 1
		all_camps[index]._capture_by_team(1)
		index += 1

	while index < all_camps.size():
		all_camps[index]._capture_by_team(2)
		index += 1

	RegionManager.init_match()


func _process(_delta: float) -> void:
	if match_over:
		return
	if MapSession.is_online_match and local_eliminated:
		return
	if MapSession.is_online_match and not MapSession.online_camps_ready:
		return

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


## Raccourcis secrets (solo / test local) : * = tout capturer, $ = tout perdre.
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
	print("[GameManager] Cheat * : ", count, " camp(s) hostile(s) capture(s).")


func _debug_cheat_lose_all_local_camps() -> void:
	var enemy_team := _debug_primary_enemy_team()
	var count := 0
	for camp in get_tree().get_nodes_in_group("camps"):
		if not MapSession.is_local_team(int(camp.get("team"))):
			continue
		if camp.has_method("_capture_by_team"):
			camp._capture_by_team(enemy_team)
			count += 1
	print("[GameManager] Cheat $ : ", count, " camp(s) local(aux) perdus.")


func _on_global_timer_timeout() -> void:
	if match_over or local_eliminated:
		return
	if MapSession.is_online_match and not MapSession.online_camps_ready:
		return

	Economy.add_gold(cycle_gold_bonus)

	for camp in get_tree().get_nodes_in_group("camps"):
		if MapSession.is_local_team(int(camp.get("team"))):
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


## Panneau victoire/défaite par-dessus la partie (le jeu reste visible en arrière-plan).
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
		push_error("[GameManager] Scène de fin introuvable : " + panel_path)
		return

	layer.add_child(packed.instantiate())
	scene.add_child(layer)


func clear_result_overlay() -> void:
	if _result_overlay != null and is_instance_valid(_result_overlay):
		_result_overlay.queue_free()
	_result_overlay = null


## Remet à zéro l'état de partie (retour menu ou nouvelle partie).
func reset_session() -> void:
	match_over = false
	local_eliminated = false
	_result_reported = false
	_result_overlay = null
	Economy.reset_for_match()
	if AIManager.has_method("init_match"):
		AIManager.init_match()
