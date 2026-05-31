extends Node2D

## Win/loss overlay panel: centered above the ongoing match.
## ColorRect stays invisible until "return to menu" is pressed.

const _PANEL_CENTER := Vector2(131.0, 92.0)


func _ready() -> void:
	_prepare_fade_rect()
	_center_panel()
	_populate_labels()


func _prepare_fade_rect() -> void:
	var fade := get_node_or_null("ColorRect") as ColorRect
	if fade == null:
		return
	# Hidden during display: the game stays visible behind the panel.
	fade.visible = false
	fade.modulate.a = 0.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size
	position = vp * 0.5 - _PANEL_CENTER


func _populate_labels() -> void:
	var username_label := get_node_or_null("Pseudo") as Label
	if username_label != null:
		username_label.text = NetworkSession.get_display_username()

	var time_lbl := get_node_or_null("TMPGAME") as Label
	if time_lbl != null:
		time_lbl.text = GameManager.format_match_duration(GameManager.last_match_duration_sec)

	var victory_lbl := get_node_or_null("Victory") as Label
	if victory_lbl != null:
		victory_lbl.text = tr("END_VICTORY")

	var defeat_lbl := get_node_or_null("msg_defeat") as Label
	if defeat_lbl != null:
		defeat_lbl.text = tr("END_DEFEAT")

	var menu_lbl := get_node_or_null("Menu") as Label
	if menu_lbl != null:
		menu_lbl.text = tr("END_GO_TO_MENU")

	var goto_lbl := get_node_or_null("GOTOMENU") as Label
	if goto_lbl != null:
		goto_lbl.text = tr("END_GO_TO_MENU")
