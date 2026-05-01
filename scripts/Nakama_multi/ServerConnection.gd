extends Node

signal match_message(data: NakamaRTAPI.MatchData)
## Émis quand le WebSocket temps réel se ferme (perte réseau, serveur, etc.).
signal match_socket_lost()
## Émis quand la socket temps réel est prête (connect_async OK ou déjà connectée).
signal match_realtime_ready()

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket
var current_match_id: String = ""
var current_host_user_id: String = ""
var local_session_id: String = ""
var known_player_sessions: Array[String] = []
var lobby_player_count: int = 0

const OP_LOBBY_STATE := 10
const OP_PLAYER_JOINED := 11
const OP_HOST_CHANGED := 12
const OP_PLAYER_LEFT := 13
const OP_GAME_START := 20
const OP_COMMAND := 21
const OP_SNAPSHOT := 22
const OP_RT_KEEPALIVE := 23
const OP_MATCH_TERMINATED := 99

var local_side: int = -1
var game_start_seed: int = 0
var game_started: bool = false
## Liste des joueurs : chaque entrée = { "username": String, "side": int }
var players_data: Array = []
var socket_connected: bool = false
## Dernière erreur temps réel (signal received_error) — rappelée au moment du `closed`.
var _last_rt_error_detail: String = ""

func _ready():
	client = Nakama.create_client("admin", "127.0.0.1", 7350, "http")


func has_valid_session() -> bool:
	if session == null:
		return false
	if session.is_exception():
		return false
	if session.has_method("is_expired") and session.is_expired():
		return false
	return true


func clear_session_and_socket() -> void:
	session = null
	current_match_id = ""
	current_host_user_id = ""
	local_session_id = ""
	known_player_sessions.clear()
	lobby_player_count = 0
	socket_connected = false
	if socket != null:
		_unbind_socket_lifecycle_signals()
		socket.close()
		socket = null


func connect_socket() -> bool:
	if not has_valid_session():
		push_warning("[ServerConnection] connect_socket appelé sans session valide.")
		return false

	if socket != null and socket_connected:
		_attach_match_forwarder()
		match_realtime_ready.emit()
		return true

	if socket != null:
		_unbind_socket_lifecycle_signals()
		socket.close()
		socket = null
		socket_connected = false

	socket = Nakama.create_socket_from(client)
	var result = await socket.connect_async(session)

	if result.is_exception():
		print("[ERREUR SOCKET] ", result.get_exception().message)
		socket = null
		socket_connected = false
		return false

	socket_connected = true
	_attach_match_forwarder()
	_bind_socket_lifecycle_signals()
	print("[SOCKET CONNECTÉ]")
	match_realtime_ready.emit()
	return true


func _bind_socket_lifecycle_signals() -> void:
	if socket == null:
		return
	if socket.has_signal("closed") and not socket.closed.is_connected(_on_nakama_socket_closed_wrapper):
		socket.closed.connect(_on_nakama_socket_closed_wrapper)
	if socket.has_signal("received_error") and not socket.received_error.is_connected(_on_nakama_received_error):
		socket.received_error.connect(_on_nakama_received_error)
	if socket.has_signal("connection_error") and not socket.connection_error.is_connected(_on_nakama_connection_error):
		socket.connection_error.connect(_on_nakama_connection_error)


func _unbind_socket_lifecycle_signals() -> void:
	if socket == null:
		return
	if socket.has_signal("closed") and socket.closed.is_connected(_on_nakama_socket_closed_wrapper):
		socket.closed.disconnect(_on_nakama_socket_closed_wrapper)
	if socket.has_signal("received_error") and socket.received_error.is_connected(_on_nakama_received_error):
		socket.received_error.disconnect(_on_nakama_received_error)
	if socket.has_signal("connection_error") and socket.connection_error.is_connected(_on_nakama_connection_error):
		socket.connection_error.disconnect(_on_nakama_connection_error)


func _on_nakama_socket_closed_wrapper() -> void:
	_on_nakama_socket_closed(null, null)


## Le signal `closed` du SDK est souvent sans argument ; code/reason WebSocket peuvent être lus via l’adaptateur si exposés.
func _on_nakama_socket_closed(code: Variant, reason: Variant) -> void:
	var ws_code: Variant = code
	var ws_reason: Variant = reason
	if socket != null:
		if socket.has_method("get_close_code"):
			ws_code = socket.call("get_close_code")
		if socket.has_method("get_close_reason"):
			ws_reason = socket.call("get_close_reason")
	socket_connected = false
	var err_tail := ""
	if _last_rt_error_detail != "":
		err_tail = " | dernier received_error/conn: %s" % _last_rt_error_detail
	push_warning(
		"[ServerConnection] Socket Nakama fermée — code=%s reason=%s%s"
		% [str(ws_code), str(ws_reason), err_tail]
	)
	_last_rt_error_detail = ""
	match_socket_lost.emit()


func _on_nakama_received_error(err: Variant) -> void:
	# Éviter `NakamaRTAPI.Error` : le segment `.Error` peut être confondu avec l’enum globale `Error`.
	_last_rt_error_detail = str(err)
	if typeof(err) == TYPE_OBJECT and err != null:
		var c: Variant = err.get("code")
		var m: Variant = err.get("message")
		if c != null or m != null:
			_last_rt_error_detail = "code=%s message=%s" % [str(c), str(m)]
	push_warning("[ServerConnection] Nakama socket received_error: %s" % _last_rt_error_detail)


func _on_nakama_connection_error(err: Variant) -> void:
	_last_rt_error_detail = "connection_error: %s" % str(err)
	push_warning("[ServerConnection] Nakama socket connection_error: %s" % _last_rt_error_detail)


## `socket_connected` (flag local) — ne garantit pas STATE_OPEN seul ; préférer `is_socket_ready_for_match()` pour l’envoi.
func is_socket_connected() -> bool:
	return socket != null and socket_connected


## Ne pas appeler send_match_state si le WS n'est pas ouvert (sinon spam NakamaSocketAdapter ready_state != STATE_OPEN).
func is_socket_ready_for_match() -> bool:
	if socket == null or not socket_connected or current_match_id == "":
		return false
	if socket.has_method("is_connected_to_host"):
		return bool(socket.call("is_connected_to_host"))
	if socket.has_method("is_connected"):
		return bool(socket.call("is_connected"))
	return true


func _attach_match_forwarder() -> void:
	if socket == null:
		return
	if not socket.received_match_state.is_connected(_emit_match_message):
		socket.received_match_state.connect(_emit_match_message)


## À appeler si le socket existe déjà (ex. écran lobby sans repasser par connect_socket).
func ensure_match_bus() -> void:
	_attach_match_forwarder()


func _emit_match_message(state: NakamaRTAPI.MatchData) -> void:
	match_message.emit(state)


func join_match(match_id: String) -> bool:
	if not socket:
		return false
	lobby_player_count = 0
	var res = await socket.join_match_async(match_id)
	if res.is_exception():
		print("[ERREUR JOIN] ", res.get_exception().message)
		return false
	current_match_id = match_id
	return true

func leave_current_match() -> void:
	if socket == null or current_match_id == "":
		return
	await socket.leave_match_async(current_match_id)
	current_match_id = ""
	current_host_user_id = ""
	local_session_id = ""
	known_player_sessions.clear()
	lobby_player_count = 0


func normalize_uid(uid: String) -> String:
	return uid.strip_edges().to_lower()


func get_local_user_id() -> String:
	if session == null:
		return ""
	return str(session.user_id).strip_edges()


func is_local_host() -> bool:
	var me := normalize_uid(get_local_user_id())
	var hid := normalize_uid(current_host_user_id)
	return me != "" and hid != "" and me == hid


func get_display_player_name() -> String:
	if not has_valid_session():
		return "Joueur (solo)"
	var u := str(session.username).strip_edges() if session.username != null else ""
	if u != "":
		return u
	var id := get_local_user_id()
	if id == "":
		return "Joueur"
	if id.length() > 12:
		return id.substr(0, 10) + "…"
	return id


## Nakama peut fournir une String ou un PackedByteArray selon la version du client.
func parse_match_state_data(raw: Variant) -> Variant:
	if raw == null:
		return null
	var text: String
	if raw is String:
		text = raw
	elif raw is PackedByteArray:
		text = (raw as PackedByteArray).get_string_from_utf8()
	else:
		text = str(raw)
	if text.is_empty():
		return null
	return JSON.parse_string(text)
