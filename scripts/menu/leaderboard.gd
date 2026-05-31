extends VBoxContainer

const ROW_TEMPLATE: PackedScene = preload("res://scenes/menu/leader_board_template.tscn")

func _ready() -> void:
	NetworkSession.leaderboard_updated.connect(_on_leaderboard_updated)
	NetworkSession.profile_updated.connect(_on_profile_updated)
	NetworkSession.session_closed.connect(_rebuild)
	NetworkSession.auth_ready.connect(_on_auth_ready)
	call_deferred("_refresh_leaderboard")


func _on_auth_ready() -> void:
	_refresh_leaderboard()


func _refresh_leaderboard() -> void:
	if NetworkSession.is_account_logged_in():
		NetworkSession.request_leaderboard()


func _on_profile_updated(_profile: Dictionary) -> void:
	if NetworkSession.leaderboard_cache.is_empty():
		_refresh_leaderboard()


func _on_leaderboard_updated(_entries: Array) -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var player_data: Array = NetworkSession.leaderboard_cache.duplicate()
	player_data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("wins", 0)) > int(b.get("wins", 0))
	)
	if player_data.is_empty():
		var placeholder: Node = ROW_TEMPLATE.instantiate()
		var node_name = placeholder.get_node_or_null("PlayerName")
		if node_name:
			node_name.text = tr("LEADERBOARD_EMPTY")
		add_child(placeholder)
		return

	for i in range(player_data.size()):
		var row: Node = ROW_TEMPLATE.instantiate()
		var node_rank = row.get_node_or_null("Rank")
		var node_name = row.get_node_or_null("PlayerName")
		var node_score = row.get_node_or_null("Score")
		var entry: Dictionary = player_data[i]

		if node_rank:
			node_rank.text = str(i + 1) + "."
		if node_name:
			node_name.text = NetworkSession.get_leaderboard_display_name(entry)
		if node_score:
			var wins := int(entry.get("wins", 0))
			if wins <= 0:
				wins = int(entry.get("subscore", 0))
			node_score.text = str(wins)

		if node_rank:
			match i:
				0:
					node_rank.add_theme_color_override("font_color", Color("#d4af37"))
					if node_name:
						node_name.add_theme_color_override("font_color", Color("#d4af37"))
				1:
					node_rank.add_theme_color_override("font_color", Color("#4a5568"))
					if node_name:
						node_name.add_theme_color_override("font_color", Color("#4a5568"))
				2:
					node_rank.add_theme_color_override("font_color", Color("#cd7f32"))
					if node_name:
						node_name.add_theme_color_override("font_color", Color("#cd7f32"))
				_:
					node_rank.add_theme_color_override("font_color", Color("#3a2010"))

		add_child(row)
