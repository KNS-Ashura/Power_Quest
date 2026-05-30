extends Node

var cycle_time: float = 30.0
var cycle_gold_bonus: int = 100
var reinforcement_count: int = 2
var match_over: bool = false
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
	_result_reported = false
	_match_started_at = Time.get_unix_time_from_system()
	if not global_timer.is_stopped():
		global_timer.stop()
	global_timer.start()
	if MapSession.is_online_match:
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

	var all_camps = get_tree().get_nodes_in_group("camps")
	if all_camps.size() == 0:
		return

	var local_camps := 0
	var hostile_camps := 0

	for camp in all_camps:
		var t: int = int(camp.get("team"))
		if MapSession.is_neutral_team(t):
			continue
		if MapSession.is_local_team(t):
			local_camps += 1
		else:
			hostile_camps += 1

	if local_camps == 0:
		match_over = true
		_report_match_result(false)
		_show_match_result(false)
	elif hostile_camps == 0:
		match_over = true
		_report_match_result(true)
		_show_match_result(true)


func _on_global_timer_timeout() -> void:
	if match_over:
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


const _MENU_SCENE := "res://scenes/menu/book-menu.tscn"
const _RESULT_FONT := "res://assets/menu/fonts/m5x7.ttf"
const _VICTORY_SFX := "res://assets/sounds/Victory Sound Effect.mp3"
const _DEFEAT_SFX := "res://assets/sounds/DEFEAT (Deep Voice) - Sound Effect.mp3"

var _result_overlay: CanvasLayer = null


## Écran de fin de partie (victoire/défaite) + récap par équipe, traduit.
func _show_match_result(win: bool) -> void:
	if ServerMode.is_dedicated_server:
		return
	if _result_overlay != null and is_instance_valid(_result_overlay):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return

	var font: FontFile = null
	if ResourceLoader.exists(_RESULT_FONT):
		font = load(_RESULT_FONT)

	var overlay := CanvasLayer.new()
	overlay.layer = 128
	_result_overlay = overlay

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := Label.new()
	title.text = tr("END_VICTORY") if win else tr("END_DEFEAT")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override(
		"font_color", Color(1, 0.85, 0.2) if win else Color(0.9, 0.3, 0.3)
	)
	if font != null:
		title.add_theme_font_override("font", font)
	box.add_child(title)

	var elapsed := int(maxi(0, Time.get_unix_time_from_system() - _match_started_at))
	var time_label := Label.new()
	time_label.text = tr("END_TIME") + " " + _format_duration(elapsed)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 28)
	if font != null:
		time_label.add_theme_font_override("font", font)
	box.add_child(time_label)

	_add_scoreboard_rows(box, font)

	var btn := Button.new()
	btn.text = tr("END_GO_TO_MENU")
	btn.custom_minimum_size = Vector2(260, 56)
	btn.add_theme_font_size_override("font_size", 28)
	if font != null:
		btn.add_theme_font_override("font", font)
	btn.pressed.connect(_on_result_go_to_menu)
	box.add_child(btn)

	scene.add_child(overlay)

	var sfx_path := _VICTORY_SFX if win else _DEFEAT_SFX
	if ResourceLoader.exists(sfx_path):
		var player := AudioStreamPlayer.new()
		player.stream = load(sfx_path)
		player.autoplay = true
		overlay.add_child(player)
		player.play()


## Ajoute une ligne par équipe (nom + camps + troupes) calculée en direct.
func _add_scoreboard_rows(box: VBoxContainer, font: FontFile) -> void:
	var camps_by_team: Dictionary = {}
	for camp in get_tree().get_nodes_in_group("camps"):
		var t: int = int(camp.get("team"))
		if MapSession.is_neutral_team(t):
			continue
		camps_by_team[t] = int(camps_by_team.get(t, 0)) + 1

	var troops_by_team: Dictionary = {}
	for grp in ["soldiers", "enemies"]:
		for unit in get_tree().get_nodes_in_group(grp):
			if unit.get("team") == null:
				continue
			var t: int = int(unit.get("team"))
			if MapSession.is_neutral_team(t):
				continue
			troops_by_team[t] = int(troops_by_team.get(t, 0)) + 1

	var teams: Array = camps_by_team.keys()
	for t in troops_by_team.keys():
		if not teams.has(t):
			teams.append(t)
	teams.sort()

	var header := Label.new()
	header.text = (
		tr("SB_PLAYER") + "   " + tr("SB_CAMPS") + " / " + tr("SB_TROOPS")
	)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	if font != null:
		header.add_theme_font_override("font", font)
	box.add_child(header)

	for t in teams:
		var row := Label.new()
		row.text = (
			MapSession.get_team_display_name(int(t))
			+ "   "
			+ str(int(camps_by_team.get(t, 0)))
			+ " / "
			+ str(int(troops_by_team.get(t, 0)))
		)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 20)
		if font != null:
			row.add_theme_font_override("font", font)
		box.add_child(row)


func _format_duration(total_sec: int) -> String:
	var m := total_sec / 60
	var s := total_sec % 60
	return str(m) + "m " + str(s).pad_zeros(2) + "s"


func _on_result_go_to_menu() -> void:
	if _result_overlay != null and is_instance_valid(_result_overlay):
		_result_overlay.queue_free()
	_result_overlay = null
	MapSession.reset_online_state()
	get_tree().change_scene_to_file(_MENU_SCENE)
