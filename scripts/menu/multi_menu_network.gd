extends Node2D

const MIN_PLAYERS_TO_START := 2

signal requires_login

@onready var _join_room: TextureButton = get_node_or_null("PageGauche/JoinRoom")
@onready var _join_label: Label = get_node_or_null("PageGauche/JoinRoom/Label")
@onready var _status_label: Label = get_node_or_null("PageGauche/StatusPanel/NetworkStatus")
@onready var _loading_spinner: TextureRect = get_node_or_null("PageGauche/StatusPanel/LoadingSpinner")

var _connecting_game: bool = false
var _in_matchmaking: bool = false
var _spinner_angle: float = 0.0


func _ready() -> void:
	if _join_room == null:
		_join_room = find_child("JoinRoom", true, false) as TextureButton
	if _join_label == null and _join_room != null:
		_join_label = _join_room.get_node_or_null("Label") as Label
	if _status_label == null:
		_status_label = get_node_or_null("PageGauche/StatusPanel/NetworkStatus") as Label

	_setup_texture_button(_join_room)
	var back_btn := get_node_or_null("PageGauche/BackToMenu") as TextureButton
	_setup_texture_button(back_btn)

	_safe_connect_pressed(_join_room, _on_join_room_pressed)
	_connect_network_signals()
	visibility_changed.connect(_on_visibility_changed)
	_reset_idle_ui()
	set_process(false)

	if _join_room == null:
		_set_status_text("JOIN button not found in Multi scene.", true)


func _setup_texture_button(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.disabled = false
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in btn.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _safe_connect_pressed(btn: BaseButton, callback: Callable) -> void:
	if btn == null:
		return
	if not btn.pressed.is_connected(callback):
		btn.pressed.connect(callback)


func _connect_network_signals() -> void:
	if not NetworkSession.auth_ready.is_connected(_on_auth_ready):
		NetworkSession.auth_ready.connect(_on_auth_ready)
	if not NetworkSession.auth_failed.is_connected(_on_auth_failed):
		NetworkSession.auth_failed.connect(_on_auth_failed)
	if not NetworkSession.queue_updated.is_connected(_on_queue_updated):
		NetworkSession.queue_updated.connect(_on_queue_updated)
	if not NetworkSession.match_ready.is_connected(_on_match_ready):
		NetworkSession.match_ready.connect(_on_match_ready)
	if not NetworkSession.match_failed.is_connected(_on_match_failed):
		NetworkSession.match_failed.connect(_on_match_failed)
	if not NetworkSession.game_connected.is_connected(_on_game_connected):
		NetworkSession.game_connected.connect(_on_game_connected)
	if not NetworkSession.game_connection_failed.is_connected(_on_game_connection_failed):
		NetworkSession.game_connection_failed.connect(_on_game_connection_failed)
	if not NetworkSession.online_match_begin.is_connected(_on_online_match_begin):
		NetworkSession.online_match_begin.connect(_on_online_match_begin)
	if not NetworkSession.session_closed.is_connected(_on_session_closed):
		NetworkSession.session_closed.connect(_on_session_closed)


func _on_visibility_changed() -> void:
	if not visible:
		_cancel_matchmaking(false)


func _process(delta: float) -> void:
	if _loading_spinner == null or not _loading_spinner.visible:
		return
	_spinner_angle += delta * 240.0
	_loading_spinner.rotation = deg_to_rad(_spinner_angle)


func _on_join_room_pressed() -> void:
	if _in_matchmaking:
		_cancel_matchmaking(true)
		return
	_start_matchmaking()


func _start_matchmaking() -> void:
	if NetworkSession.is_account_logged_in():
		_enter_matchmaking_ui()
		_set_status_text(tr("MULTI_CONNECTING_QUEUE"))
		NetworkSession.join_ranked_queue()
		return

	if NetworkSession.has_saved_account_credentials():
		_enter_matchmaking_ui()
		_set_status_text(tr("MULTI_CONNECTING_NAKAMA"))
		await NetworkSession.authenticate_and_wait()
		if not NetworkSession.is_account_logged_in():
			_cancel_matchmaking(true)
			_set_status_text(tr("MULTI_LOGIN_REQUIRED"), true)
			requires_login.emit()
			return
		_set_status_text(tr("MULTI_CONNECTING_QUEUE"))
		NetworkSession.join_ranked_queue()
		return

	_set_status_text(tr("MULTI_LOGIN_REQUIRED"), true)
	requires_login.emit()


func _enter_matchmaking_ui() -> void:
	_in_matchmaking = true
	_connecting_game = false
	_set_join_button_mode(true)
	_set_loading_visible(true)


func _cancel_matchmaking(show_message: bool) -> void:
	if not _in_matchmaking and not _connecting_game:
		return
	_in_matchmaking = false
	_connecting_game = false
	NetworkSession.leave_ranked_queue()
	MapSession.reset_online_state()
	_set_join_button_mode(false)
	_set_loading_visible(false)
	if show_message:
		_reset_idle_ui()


func _reset_idle_ui() -> void:
	_set_loading_visible(false)
	_set_status_text(tr("MULTI_PRESS_JOIN"))


func _set_join_button_mode(in_queue: bool) -> void:
	var label_text := tr("MULTI_CANCEL") if in_queue else tr("MULTI_JOIN")
	if _join_label != null:
		_join_label.text = label_text


func _set_status_text(text: String, is_error: bool = false) -> void:
	if _status_label == null:
		push_warning("[MultiMenu] " + text)
		return
	_status_label.text = text
	if is_error:
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
	else:
		_status_label.add_theme_color_override("font_color", Color(0.176471, 0.105882, 0.0784314))


func _set_loading_visible(visible: bool) -> void:
	if _loading_spinner != null:
		_loading_spinner.visible = visible
	set_process(visible)
	if not visible:
		_spinner_angle = 0.0
		if _loading_spinner != null:
			_loading_spinner.rotation = 0.0



func _on_auth_ready() -> void:
	if not _in_matchmaking:
		return
	if not NetworkSession.is_account_logged_in():
		_cancel_matchmaking(true)
		_set_status_text(tr("MULTI_SESSION_EXPIRED"), true)
		requires_login.emit()
		return
	_set_status_text(tr("MULTI_WAITING_PLAYERS"))
	NetworkSession.join_ranked_queue()


func _on_auth_failed(message: String) -> void:
	_cancel_matchmaking(true)
	_set_status_text(message, true)


func _on_session_closed() -> void:
	_cancel_matchmaking(false)


func _on_queue_updated(players: int, max_players: int, seconds_left: int) -> void:
	if not _in_matchmaking:
		return
	_set_loading_visible(true)
	var prefix := str(players) + " / " + str(max_players) + " — "
	if players < MIN_PLAYERS_TO_START:
		_set_status_text(prefix + tr("MULTI_WAITING_MIN").format([MIN_PLAYERS_TO_START]))
	elif seconds_left > 0:
		var timer_hint := tr("MULTI_TIMER_FULL") if players >= max_players else "10s"
		_set_status_text(
			prefix
			+ tr("MULTI_LAUNCH_IN").format([seconds_left])
			+ " ("
			+ timer_hint
			+ ")"
		)
	else:
		_set_status_text(prefix + tr("MULTI_CONNECTING_SERVER"))


func _on_match_ready(_match_id: String, game_ws_url: String) -> void:
	if not _in_matchmaking or _connecting_game:
		return
	_connecting_game = true
	_set_loading_visible(true)
	var ws := game_ws_url.strip_edges()
	if ws == "":
		ws = NetworkSession.resolved_game_ws_url()
	_set_status_text(tr("MULTI_WS_CONNECTING"))
	await NetworkSession.connect_to_game_server(ws)
	_connecting_game = false
	if _in_matchmaking:
		_set_loading_visible(true)


func _on_game_connected() -> void:
	if not _in_matchmaking:
		return
	_set_status_text(tr("MULTI_GAME_CONNECTED"))


func _on_online_match_begin() -> void:
	var map_idx := MapSession.active_map_index
	_set_status_text(tr("MULTI_LOADING_MAP").format([map_idx]))
	_set_loading_visible(true)


func _on_game_connection_failed(message: String) -> void:
	_cancel_matchmaking(true)
	_set_status_text(message, true)


func _on_match_failed(message: String) -> void:
	_cancel_matchmaking(true)
	_set_status_text(message, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_set_join_button_mode(_in_matchmaking)
		if not _in_matchmaking and not _connecting_game:
			_reset_idle_ui()
