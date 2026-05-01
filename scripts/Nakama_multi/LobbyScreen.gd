extends Control

@onready var label_code: Label = %Label_CodeRecu
@onready var input_saisie: LineEdit = %LineEdit_SaisieCode
@onready var status_label: Label = %Label_Status_Lobby

@onready var btn_creer: Button = %Button_creer
@onready var btn_join: Button = %Button_join
@onready var btn_copy: Button = %Button_copy
@onready var btn_start: Button = %Button_start

enum State { IDLE, BUSY, IN_LOBBY }
var _state = State.IDLE
var _transition_done: bool = false

func _ready():
	await get_tree().process_frame

	if not ServerConnection.has_valid_session():
		get_tree().change_scene_to_file("res://scene_login.tscn")
		return
	if not await ServerConnection.connect_socket():
		get_tree().change_scene_to_file("res://scene_login.tscn")
		return

	ServerConnection.ensure_match_bus()
	if not ServerConnection.match_message.is_connected(_on_match_state):
		ServerConnection.match_message.connect(_on_match_state)

	if btn_start and not btn_start.pressed.is_connected(_on_button_start_pressed):
		btn_start.pressed.connect(_on_button_start_pressed)

	_update_ui(State.IDLE)

func _on_button_creer_pressed():
	_update_ui(State.BUSY)
	status_label.text = "Génération du code..."
	var res = await LobbyManager.create_lobby()

	if res["success"]:
		label_code.text = res["code"]
		status_label.text = "Salon créé ! Partagez le code."
		_update_ui(State.IN_LOBBY)
	else:
		status_label.text = "Erreur : " + res["msg"]
		_update_ui(State.IDLE)

func _on_button_join_pressed():
	var code = input_saisie.text.to_upper().strip_edges()
	if code.length() != 6:
		status_label.text = "Code doit faire 6 caractères."
		return

	_update_ui(State.BUSY)
	var res = await LobbyManager.join_lobby(code)

	if res["success"]:
		status_label.text = "Connexion au salon..."
		_update_ui(State.IN_LOBBY)
	else:
		status_label.text = "Code introuvable."
		_update_ui(State.IDLE)

func _on_button_start_pressed():
	if not ServerConnection.is_local_host():
		return
	if ServerConnection.lobby_player_count < 2:
		return
	await ServerConnection.socket.send_match_state_async(
		ServerConnection.current_match_id,
		ServerConnection.OP_GAME_START,
		""
	)

func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
	var data = ServerConnection.parse_match_state_data(state.data)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		return

	match data.get("type", ""):
		"player_joined":
			ServerConnection.lobby_player_count = int(data.get("player_count", 0))
			status_label.text = "Joueurs : %d/%d" % [ServerConnection.lobby_player_count, 8]
			_update_ui(_state)
		"lobby_state":
			ServerConnection.lobby_player_count = int(data.get("player_count", 0))
			ServerConnection.current_host_user_id = str(data.get("host_user_id", "")).strip_edges()
			ServerConnection.local_session_id = str(data.get("self_session_id", "")).strip_edges()
			ServerConnection.local_side = int(data.get("side", -1))
			ServerConnection.known_player_sessions.clear()
			ServerConnection.players_data.clear()
			for p in data.get("players", []):
				var sid := str(p.get("session_id", ""))
				if sid != "":
					ServerConnection.known_player_sessions.append(sid)
				var uname := str(p.get("username", "Joueur")).strip_edges()
				var pside := int(p.get("side", -1))
				ServerConnection.players_data.append({"username": uname, "side": pside})
			status_label.text = "Joueurs : %d/%d" % [ServerConnection.lobby_player_count, 8]
			_update_ui(_state)
		"host_changed":
			ServerConnection.current_host_user_id = str(data.get("new_host_user_id", "")).strip_edges()
			_update_ui(_state)
		"player_left":
			ServerConnection.lobby_player_count = int(data.get("player_count", 0))
			status_label.text = "Joueurs : %d/%d — En attente..." % [ServerConnection.lobby_player_count, 8]
			_update_ui(_state)
		"match_terminated":
			ServerConnection.lobby_player_count = 0
			status_label.text = "Salon fermé par le serveur."
			_update_ui(State.IDLE)
			label_code.text = ""
		"game_start":
			print("[LOBBY] game_start reçu | transition_done=", _transition_done)
			if _transition_done:
				return
			_transition_done = true
			ServerConnection.game_start_seed = int(data.get("started_at_tick", 0))
			ServerConnection.game_started = true
			print("[LOBBY] game_started=", ServerConnection.game_started, " seed=", ServerConnection.game_start_seed, " local_side=", ServerConnection.local_side, " lobby_player_count=", ServerConnection.lobby_player_count)
			get_tree().change_scene_to_file("res://scenes/jeu/Main.tscn")

func _on_button_copy_pressed():
	if label_code.text != "":
		DisplayServer.clipboard_set(label_code.text)
		status_label.text = "Code copié !"

func _update_ui(s):
	_state = s
	if btn_creer: btn_creer.disabled = (s != State.IDLE)
	if btn_join: btn_join.disabled = (s != State.IDLE)
	if btn_copy: btn_copy.disabled = (label_code.text == "")
	if btn_start:
		btn_start.visible = (s == State.IN_LOBBY)
		var can_start = s == State.IN_LOBBY and ServerConnection.is_local_host() and ServerConnection.lobby_player_count >= 2
		btn_start.disabled = not can_start
