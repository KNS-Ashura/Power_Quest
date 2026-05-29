extends VBoxContainer

var template_ligne = preload("res://scenes/menu/leader_board_template.tscn")

func _ready() -> void:
	NetworkSession.profile_updated.connect(_on_profile_updated)
	NetworkSession.session_closed.connect(_rebuild)
	NetworkSession.auth_ready.connect(_on_auth_ready)
	_rebuild()


func _on_auth_ready() -> void:
	NetworkSession.request_leaderboard()


func _on_profile_updated(_profile: Dictionary) -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var data_joueurs: Array = NetworkSession.leaderboard_cache
	if data_joueurs.is_empty():
		return

	for i in range(data_joueurs.size()):
		var ligne = template_ligne.instantiate()
		var node_rank = ligne.get_node_or_null("Rank")
		var node_name = ligne.get_node_or_null("PlayerName")
		var node_time = ligne.get_node_or_null("PlayTime")
		var node_score = ligne.get_node_or_null("Score")
		var entry: Dictionary = data_joueurs[i]

		if node_rank:
			node_rank.text = str(i + 1) + "."
		if node_name:
			node_name.text = str(entry.get("username", "player"))
		if node_time:
			var total_sec := int(entry.get("total_seconds", 0))
			var h := total_sec / 3600
			var m := (total_sec % 3600) / 60
			node_time.text = "%02dh%02d" % [h, m]
		if node_score:
			var wr := float(entry.get("winrate", 0.0))
			node_score.text = str(snappedf(wr, 0.1)) + "%"

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

		add_child(ligne)
