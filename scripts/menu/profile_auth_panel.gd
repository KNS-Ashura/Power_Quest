extends Node2D

@onready var _logout_button: BaseButton = get_node_or_null("Deconnexion")
@onready var _logout_label: Control = get_node_or_null("Deconnexion/Label")
@onready var _status_label: Label = get_node_or_null("TextureRect/Label")
@onready var _pseudo_label: Label = get_node_or_null("SectionInfo/Pseudo")
@onready var _level_label: Label = get_node_or_null("LevelControl/LVLNbr")
@onready var _winrate_label: Label = get_node_or_null("StatsDroite/NbrWinrate")
@onready var _matches_label: Label = get_node_or_null("StatsDroite/Fond5/NbrMatchs")
@onready var _time_label: Label = get_node_or_null("StatsDroite/NbrApm")


func _ready() -> void:
	_bind_logout_button()
	if not NetworkSession.auth_ready.is_connected(_refresh_profile_ui):
		NetworkSession.auth_ready.connect(_refresh_profile_ui)
	if not NetworkSession.session_closed.is_connected(_on_session_closed):
		NetworkSession.session_closed.connect(_on_session_closed)
	if not NetworkSession.profile_updated.is_connected(_on_profile_updated):
		NetworkSession.profile_updated.connect(_on_profile_updated)
	_refresh_profile_ui()


func _bind_logout_button() -> void:
	if _logout_button == null:
		return
	_logout_button.disabled = false
	_logout_button.mouse_filter = Control.MOUSE_FILTER_STOP
	if _logout_label != null:
		_logout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _logout_button.pressed.is_connected(_on_logout_pressed):
		_logout_button.pressed.connect(_on_logout_pressed)


func _on_logout_pressed() -> void:
	NetworkSession.logout_account()


func _refresh_profile_ui() -> void:
	var logged := NetworkSession.is_account_logged_in()
	if _logout_button != null:
		_logout_button.visible = logged
	if not logged:
		_clear_profile_display()
		return
	NetworkSession.request_account_info()
	NetworkSession.request_player_profile()
	NetworkSession.request_leaderboard()
	if _status_label != null:
		_status_label.text = "Connecté"
	_apply_username_display(NetworkSession.profile_cache)


func _on_profile_updated(profile: Dictionary) -> void:
	if not NetworkSession.is_account_logged_in():
		return
	_apply_username_display(profile)
	if _winrate_label != null:
		var wr := float(profile.get("winrate", 0.0))
		_winrate_label.text = str(snappedf(wr, 0.1)) + "%"
	if _matches_label != null:
		_matches_label.text = str(int(profile.get("games", 0)))
	var total_sec := int(profile.get("total_seconds", 0))
	if _time_label != null:
		_time_label.text = _format_time(total_sec)
	if _level_label != null:
		_level_label.text = str(int(profile.get("level", 0)))
	if _status_label != null:
		_status_label.text = "Connecté"


func _apply_username_display(_profile: Dictionary) -> void:
	if _pseudo_label == null:
		return
	_pseudo_label.text = NetworkSession.get_display_username()


func _clear_profile_display() -> void:
	if _status_label != null:
		_status_label.text = "Profil indisponible sans connexion."
	if _pseudo_label != null:
		_pseudo_label.text = "--"
	if _level_label != null:
		_level_label.text = "0"
	if _winrate_label != null:
		_winrate_label.text = "--"
	if _matches_label != null:
		_matches_label.text = "--"
	if _time_label != null:
		_time_label.text = "--"


func _on_session_closed() -> void:
	_clear_profile_display()


func _format_time(total_sec: int) -> String:
	var h := total_sec / 3600
	var m := (total_sec % 3600) / 60
	return "%02dh%02d" % [h, m]
