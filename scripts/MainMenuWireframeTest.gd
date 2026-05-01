extends Control

@onready var profile_panel: Control = $ZoneA_PlayerInfo
@onready var btn_view_full_profile: Button = $ZoneA_PlayerInfo/Margin/VBox/Button_ViewFullProfile
@onready var btn_manage_account: Button = $ZoneA_PlayerInfo/Margin/VBox/Button_ManageAccount
@onready var btn_avatar_profile: Button = $ZoneA_PlayerInfo/Margin/VBox/Header/AvatarPlaceholder
@onready var btn_username_profile: Button = $ZoneA_PlayerInfo/Margin/VBox/Header/ProfileTexts/Username
@onready var btn_settings: Button = $ZoneC_BottomToolbar/Margin/HBox/Button_Settings
@onready var btn_quit: Button = $ZoneC_BottomToolbar/Margin/HBox/Button_Quit
@onready var settings_popup: Control = $SettingsPopup
@onready var settings_overlay: ColorRect = $SettingsOverlay
@onready var btn_quick_match: Button = $ZoneB_CenterMenu/Panel/Margin/Columns/Column_Multiplayer/Margin/VBox/Button_QuickMatchmaking
@onready var btn_ranked: Button = $ZoneB_CenterMenu/Panel/Margin/Columns/Column_Multiplayer/Margin/VBox/Button_Ranked
@onready var btn_create_game: Button = $ZoneB_CenterMenu/Panel/Margin/Columns/Column_CustomCommunity/Margin/VBox/Button_CreateGame
@onready var btn_join_game: Button = $ZoneB_CenterMenu/Panel/Margin/Columns/Column_CustomCommunity/Margin/VBox/Button_JoinGame
@onready var multiplayer_overlay: ColorRect = $MultiplayerOverlay
@onready var multiplayer_popup: Control = $MultiplayerPopup
@onready var lobby_code_input: LineEdit = $MultiplayerPopup/Margin/VBox/CodeRow/CodeInput
@onready var lobby_code_value: Label = $MultiplayerPopup/Margin/VBox/CodeCreatedRow/CodeValue
@onready var multiplayer_status: Label = $MultiplayerPopup/Margin/VBox/Status
@onready var btn_mp_create: Button = $MultiplayerPopup/Margin/VBox/ActionsRow/CreateCodeButton
@onready var btn_mp_join: Button = $MultiplayerPopup/Margin/VBox/ActionsRow/JoinCodeButton
@onready var btn_mp_close: Button = $MultiplayerPopup/Margin/VBox/Header/CloseButton
@onready var room_panel: Control = $MultiplayerPopup/Margin/VBox/RoomPanel
@onready var room_code_label: Label = $MultiplayerPopup/Margin/VBox/RoomPanel/RoomMargin/RoomVBox/RoomCode
@onready var room_players: ItemList = $MultiplayerPopup/Margin/VBox/RoomPanel/RoomMargin/RoomVBox/RoomPlayers
@onready var btn_room_copy: Button = $MultiplayerPopup/Margin/VBox/RoomPanel/RoomMargin/RoomVBox/RoomActions/CopyCodeButton
@onready var btn_room_start: Button = $MultiplayerPopup/Margin/VBox/RoomPanel/RoomMargin/RoomVBox/RoomActions/StartGameButton
@onready var btn_room_leave: Button = $MultiplayerPopup/Margin/VBox/RoomPanel/RoomMargin/RoomVBox/RoomActions/LeaveRoomButton

var _multiplayer_busy := false
var _player_ids: Array[String] = []
var _players_by_session := {}
var _current_room_code := ""

func _ready() -> void:
	_connect_ui_signals_ultra_safe()
	_reset_room_ui()

func _exit_tree() -> void:
	if ServerConnection.match_message.is_connected(_on_match_state):
		ServerConnection.match_message.disconnect(_on_match_state)

func _connect_ui_signals_ultra_safe() -> void:
	if btn_view_full_profile and not btn_view_full_profile.pressed.is_connected(_on_button_view_full_profile_pressed):
		btn_view_full_profile.pressed.connect(_on_button_view_full_profile_pressed)
	if btn_manage_account and not btn_manage_account.pressed.is_connected(_on_button_manage_account_pressed):
		btn_manage_account.pressed.connect(_on_button_manage_account_pressed)
	if btn_avatar_profile and not btn_avatar_profile.pressed.is_connected(_on_button_view_full_profile_pressed):
		btn_avatar_profile.pressed.connect(_on_button_view_full_profile_pressed)
	if btn_username_profile and not btn_username_profile.pressed.is_connected(_on_button_view_full_profile_pressed):
		btn_username_profile.pressed.connect(_on_button_view_full_profile_pressed)
	if btn_settings and not btn_settings.pressed.is_connected(_on_button_settings_pressed):
		btn_settings.pressed.connect(_on_button_settings_pressed)
	if btn_quit and not btn_quit.pressed.is_connected(_on_button_quit_pressed):
		btn_quit.pressed.connect(_on_button_quit_pressed)
	if btn_quick_match and not btn_quick_match.pressed.is_connected(_on_button_quick_matchmaking_pressed):
		btn_quick_match.pressed.connect(_on_button_quick_matchmaking_pressed)
	if btn_ranked and not btn_ranked.pressed.is_connected(_on_button_ranked_pressed):
		btn_ranked.pressed.connect(_on_button_ranked_pressed)
	if btn_create_game and not btn_create_game.pressed.is_connected(_on_button_create_game_pressed):
		btn_create_game.pressed.connect(_on_button_create_game_pressed)
	if btn_join_game and not btn_join_game.pressed.is_connected(_on_button_join_game_pressed):
		btn_join_game.pressed.connect(_on_button_join_game_pressed)
	if btn_mp_create and not btn_mp_create.pressed.is_connected(_on_multiplayer_create_code_pressed):
		btn_mp_create.pressed.connect(_on_multiplayer_create_code_pressed)
	if btn_mp_join and not btn_mp_join.pressed.is_connected(_on_multiplayer_join_code_pressed):
		btn_mp_join.pressed.connect(_on_multiplayer_join_code_pressed)
	if btn_mp_close and not btn_mp_close.pressed.is_connected(_on_multiplayer_close_pressed):
		btn_mp_close.pressed.connect(_on_multiplayer_close_pressed)
	if btn_room_copy and not btn_room_copy.pressed.is_connected(_on_room_copy_code_pressed):
		btn_room_copy.pressed.connect(_on_room_copy_code_pressed)
	if btn_room_start and not btn_room_start.pressed.is_connected(_on_room_start_game_pressed):
		btn_room_start.pressed.connect(_on_room_start_game_pressed)
	if btn_room_leave and not btn_room_leave.pressed.is_connected(_on_room_leave_pressed):
		btn_room_leave.pressed.connect(_on_room_leave_pressed)

func _on_button_view_full_profile_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menus/player_profile_wireframe.tscn")

func _on_button_manage_account_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menus/account_management_menu.tscn")

func _on_button_settings_pressed() -> void:
	if settings_popup:
		settings_popup.show()
	if settings_overlay:
		settings_overlay.show()

func _on_close_settings_pressed() -> void:
	if settings_popup:
		settings_popup.hide()
	if settings_overlay:
		settings_overlay.hide()

func _on_apply_settings_pressed() -> void:
	_on_close_settings_pressed()

func _on_button_quick_matchmaking_pressed() -> void:
	_open_multiplayer_popup()
	multiplayer_status.text = "Le matchmaking public n'est pas actif sur ce wireframe."

func _on_button_ranked_pressed() -> void:
	_open_multiplayer_popup()
	multiplayer_status.text = "Le mode classe n'est pas actif sur ce wireframe."

func _on_button_create_game_pressed() -> void:
	_open_multiplayer_popup()
	multiplayer_status.text = "Creez un salon prive ou rejoignez un code."

func _on_button_join_game_pressed() -> void:
	_open_multiplayer_popup()
	multiplayer_status.text = "Entrez un code a 6 caracteres puis cliquez Rejoindre."
	if lobby_code_input:
		lobby_code_input.grab_focus()

func _on_multiplayer_create_code_pressed() -> void:
	if _multiplayer_busy:
		return
	if not await _ensure_multiplayer_ready():
		return
	_set_multiplayer_busy(true, "Generation du code...")
	var res = await LobbyManager.create_lobby()
	if not bool(res.get("success", false)):
		_set_multiplayer_busy(false, "Erreur : " + str(res.get("msg", "Impossible de creer le salon.")))
		return
	var code := str(res.get("code", ""))
	if lobby_code_value:
		lobby_code_value.text = code if code != "" else "------"
	_current_room_code = code
	_set_multiplayer_busy(false, "Salon cree. Code : " + code)
	_enter_room_mode("Salon cree. En attente de joueurs...")

func _on_multiplayer_join_code_pressed() -> void:
	if _multiplayer_busy:
		return
	if not await _ensure_multiplayer_ready():
		return
	if lobby_code_input == null:
		return
	var code := lobby_code_input.text.to_upper().strip_edges()
	if code.length() != 6:
		multiplayer_status.text = "Le code doit contenir 6 caracteres."
		return
	_set_multiplayer_busy(true, "Connexion au salon...")
	var res = await LobbyManager.join_lobby(code)
	if not bool(res.get("success", false)):
		_set_multiplayer_busy(false, "Code invalide ou salon indisponible.")
		return
	_current_room_code = code
	_set_multiplayer_busy(false, "Connexion reussie.")
	_enter_room_mode("Connecte au salon.")

func _on_multiplayer_close_pressed() -> void:
	if _multiplayer_busy:
		return
	_close_multiplayer_popup()

func _ensure_multiplayer_ready() -> bool:
	if ServerConnection.session == null:
		get_tree().change_scene_to_file("res://scene_login.tscn")
		return false
	if not await ServerConnection.connect_socket():
		_open_multiplayer_popup()
		multiplayer_status.text = "Impossible de connecter le socket."
		return false
	ServerConnection.ensure_match_bus()
	if not ServerConnection.match_message.is_connected(_on_match_state):
		ServerConnection.match_message.connect(_on_match_state)
	return true

func _set_multiplayer_busy(is_busy: bool, status_text: String) -> void:
	_multiplayer_busy = is_busy
	if multiplayer_status:
		multiplayer_status.text = status_text
	if btn_mp_create:
		btn_mp_create.disabled = is_busy
	if btn_mp_join:
		btn_mp_join.disabled = is_busy
	if btn_mp_close:
		btn_mp_close.disabled = is_busy
	if btn_quick_match:
		btn_quick_match.disabled = is_busy
	if btn_ranked:
		btn_ranked.disabled = is_busy
	if btn_create_game:
		btn_create_game.disabled = is_busy
	if btn_join_game:
		btn_join_game.disabled = is_busy
	_update_room_start_button()

func _open_multiplayer_popup() -> void:
	if multiplayer_overlay:
		multiplayer_overlay.show()
	if multiplayer_popup:
		multiplayer_popup.show()

func _close_multiplayer_popup() -> void:
	if multiplayer_overlay:
		multiplayer_overlay.hide()
	if multiplayer_popup:
		multiplayer_popup.hide()

func _on_button_quit_pressed() -> void:
	get_tree().quit()

func _enter_room_mode(status_text: String) -> void:
	if room_panel:
		room_panel.show()
	if room_code_label:
		room_code_label.text = "Code: " + (_current_room_code if _current_room_code != "" else "------")
	if multiplayer_status:
		multiplayer_status.text = status_text
	_refresh_room_players()
	_update_room_start_button()

func _reset_room_ui() -> void:
	_player_ids.clear()
	_players_by_session.clear()
	_current_room_code = ""
	if room_panel:
		room_panel.hide()
	if room_code_label:
		room_code_label.text = "Code: ------"
	if room_players:
		room_players.clear()

func _on_room_copy_code_pressed() -> void:
	if _current_room_code == "":
		return
	DisplayServer.clipboard_set(_current_room_code)
	multiplayer_status.text = "Code copie."

func _on_room_leave_pressed() -> void:
	if _multiplayer_busy:
		return
	_set_multiplayer_busy(true, "Sortie du salon...")
	await ServerConnection.leave_current_match()
	_set_multiplayer_busy(false, "Salon quitte.")
	_reset_room_ui()

func _on_room_start_game_pressed() -> void:
	multiplayer_status.text = "Le lancement de partie est desactive dans ce wireframe."

func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
	var data = ServerConnection.parse_match_state_data(state.data)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		return
	match data.get("type", ""):
		"player_joined":
			ServerConnection.lobby_player_count = int(data.get("player_count", 0))
			var joined_id := str(data.get("user_id", ""))
			var joined_session := str(data.get("session_id", ""))
			if joined_session != "":
				_players_by_session[joined_session] = joined_id
				_sync_known_sessions()
			elif joined_id != "" and not _player_ids.has(joined_id):
				_player_ids.append(joined_id)
			multiplayer_status.text = "Joueurs : %d/2" % data.get("player_count", 0)
			_refresh_room_players()
		"lobby_state":
			ServerConnection.lobby_player_count = int(data.get("player_count", 0))
			var user_id: String = str(ServerConnection.get_local_user_id())
			if user_id != "" and not _player_ids.has(user_id):
				_player_ids.append(user_id)
			ServerConnection.current_host_user_id = str(data.get("host_user_id", "")).strip_edges()
			ServerConnection.local_session_id = str(data.get("self_session_id", "")).strip_edges()
			_players_by_session.clear()
			for p in data.get("players", []):
				var sid := str(p.get("session_id", ""))
				var uid := str(p.get("user_id", ""))
				if sid != "":
					_players_by_session[sid] = uid
			_sync_known_sessions()
			multiplayer_status.text = "Joueurs : %d/2" % data.get("player_count", 0)
			_refresh_room_players()
		"host_changed":
			ServerConnection.current_host_user_id = str(data.get("new_host_user_id", "")).strip_edges()
			multiplayer_status.text = "Nouvel hote assigne."
			_refresh_room_players()
		"player_left":
			ServerConnection.lobby_player_count = int(data.get("player_count", 0))
			var left_id := str(data.get("user_id", ""))
			var left_session := str(data.get("session_id", ""))
			if left_session != "" and _players_by_session.has(left_session):
				_players_by_session.erase(left_session)
				_sync_known_sessions()
			if _player_ids.has(left_id):
				_player_ids.erase(left_id)
			multiplayer_status.text = "Joueurs : %d/2" % data.get("player_count", 0)
			_refresh_room_players()
		"match_terminated":
			multiplayer_status.text = "Salon ferme par le serveur."
			_reset_room_ui()

func _sync_known_sessions() -> void:
	ServerConnection.known_player_sessions.clear()
	for sid in _players_by_session.keys():
		ServerConnection.known_player_sessions.append(str(sid))

func _refresh_room_players() -> void:
	if room_players == null:
		return
	room_players.clear()
	var local_id: String = str(ServerConnection.get_local_user_id())
	if _players_by_session.size() > 0:
		for sid in _players_by_session.keys():
			var uid := str(_players_by_session[sid])
			var role := " (hote)" if uid == ServerConnection.current_host_user_id else ""
			var marker := " (vous)" if sid == ServerConnection.local_session_id else ""
			room_players.add_item(uid + role + marker)
	else:
		for uid in _player_ids:
			var role_fallback := " (hote)" if uid == ServerConnection.current_host_user_id else ""
			var marker_fallback := " (vous)" if uid == local_id else ""
			room_players.add_item(uid + role_fallback + marker_fallback)
	_update_room_start_button()

func _update_room_start_button() -> void:
	if btn_room_start == null:
		return
	btn_room_start.disabled = true
	btn_room_start.tooltip_text = "Le lancement de partie n'est pas actif dans ce wireframe."
