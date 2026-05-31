extends CanvasLayer

const LINE_SCENE := preload("res://scenes/menu/ligne_joueur.tscn")
const REFRESH_INTERVAL := 1.0

@onready var _list: VBoxContainer = $MainPanel/TableauContainer/ListeJoueurs

var _refresh_timer: Timer


func _ready() -> void:
	layer = 15
	if ServerMode.is_dedicated_server:
		visible = false
		return

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_INTERVAL
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(refresh)
	add_child(_refresh_timer)

	if not Economy.gold_changed.is_connected(_on_economy_gold_changed):
		Economy.gold_changed.connect(_on_economy_gold_changed)
	if not OnlineGameSync.team_gold_changed.is_connected(_on_remote_team_gold_changed):
		OnlineGameSync.team_gold_changed.connect(_on_remote_team_gold_changed)

	call_deferred("refresh")


func _exit_tree() -> void:
	if Economy.gold_changed.is_connected(_on_economy_gold_changed):
		Economy.gold_changed.disconnect(_on_economy_gold_changed)
	if OnlineGameSync.team_gold_changed.is_connected(_on_remote_team_gold_changed):
		OnlineGameSync.team_gold_changed.disconnect(_on_remote_team_gold_changed)


func _on_remote_team_gold_changed(_team_id: int, _amount: int) -> void:
	refresh()


func _on_economy_gold_changed(_new_amount: int) -> void:
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()


func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for row in _build_rows():
		_add_row(row)


func _build_rows() -> Array:
	var rows: Array = []
	for team_id in _discover_teams():
		var gold_val: Variant = _gold_for_team(team_id)
		rows.append({
			"team": team_id,
			"name": _team_display_name(team_id),
			"troops": _count_units_for_team(team_id),
			"camps": _count_camps_for_team(team_id),
			"gold": gold_val if gold_val != null else -1,
			"local": MapSession.is_local_team(team_id),
		})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["local"] != b["local"]:
			return a["local"]
		if a["camps"] != b["camps"]:
			return a["camps"] > b["camps"]
		if a["troops"] != b["troops"]:
			return a["troops"] > b["troops"]
		return int(a["team"]) < int(b["team"])
	)
	return rows


func _discover_teams() -> Array:
	var teams: Dictionary = {}
	if MapSession.is_online_match:
		for team_id in MapSession.team_display_names.keys():
			teams[int(team_id)] = true
	for camp in get_tree().get_nodes_in_group("camps"):
		var t: int = int(camp.get("team"))
		if not MapSession.is_neutral_team(t):
			teams[t] = true
	for group_name in ["soldiers", "enemies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or node.get("team") == null:
				continue
			var t: int = int(node.get("team"))
			if not MapSession.is_neutral_team(t):
				teams[t] = true
	if teams.is_empty() and not MapSession.is_online_match:
		teams[0] = true
		teams[1] = true
	var out: Array = teams.keys()
	out.sort()
	return out


func _count_units_for_team(team_id: int) -> int:
	var count := 0
	for group_name in ["soldiers", "enemies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or node.get("team") == null:
				continue
			if int(node.get("team")) == team_id:
				count += 1
	return count


func _count_camps_for_team(team_id: int) -> int:
	var count := 0
	for camp in get_tree().get_nodes_in_group("camps"):
		if not is_instance_valid(camp):
			continue
		if int(camp.get("team")) == team_id:
			count += 1
	return count


func _gold_for_team(team_id: int) -> Variant:
	if MapSession.is_local_team(team_id):
		return Economy.gold
	if MapSession.is_online_match:
		var synced_gold := OnlineGameSync.get_team_gold(team_id)
		if synced_gold >= 0:
			return synced_gold
	return null


func _team_display_name(team_id: int) -> String:
	if MapSession.is_local_team(team_id):
		var username := NetworkSession.get_display_username().strip_edges()
		if username != "":
			return username
		return tr("SB_YOU")
	return MapSession.get_team_display_name(team_id)


func _add_row(row: Dictionary) -> void:
	var line: HBoxContainer = LINE_SCENE.instantiate()
	var name_lbl: Label = line.get_node_or_null("TxtNom") as Label
	var troops_lbl: Label = line.get_node_or_null("TxtTroupes") as Label
	var camps_lbl: Label = line.get_node_or_null("TxtCamps") as Label
	var gold_lbl: Label = line.get_node_or_null("TxtOr") as Label

	if name_lbl:
		name_lbl.text = str(row.get("name", ""))
	if troops_lbl:
		troops_lbl.text = str(row.get("troops", 0))
	if camps_lbl:
		camps_lbl.text = str(row.get("camps", 0))
	if gold_lbl:
		var gold_val: int = int(row.get("gold", -1))
		gold_lbl.text = str(gold_val) if gold_val >= 0 else "—"

	if row.get("local", false):
		var accent := Color(0.15, 0.45, 0.2)
		for lbl in [name_lbl, troops_lbl, camps_lbl, gold_lbl]:
			if lbl:
				lbl.add_theme_color_override("font_color", accent)

	_list.add_child(line)
