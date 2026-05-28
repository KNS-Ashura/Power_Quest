extends Node2D

const MIN_PLAYERS_TO_START := 2

@onready var _create_lobby: BaseButton = $PageGauche/CreateLobby
@onready var _join_room: BaseButton = $JoinRoom

var _status_label: Label
var _connecting_game: bool = false
var _lobby_active: bool = false


func _ready() -> void:
	_status_label = Label.new()
	_status_label.name = "NetworkStatus"
	_status_label.position = Vector2(118, 470)
	_status_label.custom_minimum_size = Vector2(400, 48)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	add_child(_status_label)
	_status_label.text = ""
	_create_lobby.pressed.connect(_on_create_lobby_pressed)
	_join_room.pressed.connect(_on_join_room_pressed)
	_connect_network_signals()
	visibility_changed.connect(_on_visibility_changed)
	# Multi2 est instancié dès le menu livre : ne pas lancer Nakama tant que la page n'est pas visible.
	if not visible:
		_status_label.text = "Appuyez sur CREATE LOBBY ou JOIN ROOM pour rejoindre la file."


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


func _on_visibility_changed() -> void:
	if not visible:
		_leave_lobby()


func _on_create_lobby_pressed() -> void:
	_start_lobby()


func _on_join_room_pressed() -> void:
	_start_lobby()


func _start_lobby() -> void:
	if _lobby_active:
		return
	if not NetworkSession.is_account_logged_in():
		_status_label.modulate = Color(1, 0.45, 0.45)
		_status_label.text = "Connecte-toi dans Profil avant de lancer le multijoueur."
		return
	_lobby_active = true
	_connecting_game = false
	_status_label.modulate = Color.WHITE
	_status_label.text = "Connexion à Nakama..."
	MapSession.active_map_index = 2
	NetworkSession.authenticate()


func _leave_lobby() -> void:
	_lobby_active = false
	NetworkSession.leave_ranked_queue()
	MapSession.reset_online_state()


func _on_auth_ready() -> void:
	_status_label.text = "En attente d'autres joueurs..."
	NetworkSession.leave_ranked_queue()
	await get_tree().create_timer(0.25).timeout
	NetworkSession.join_ranked_queue()


func _on_auth_failed(message: String) -> void:
	_lobby_active = false
	_status_label.modulate = Color(1, 0.45, 0.45)
	_status_label.text = message


func _on_queue_updated(players: int, max_players: int, seconds_left: int) -> void:
	if players < MIN_PLAYERS_TO_START:
		_status_label.text = "%d / %d — en attente (%d joueurs min.)" % [
			players, max_players, MIN_PLAYERS_TO_START
		]
	elif seconds_left > 0:
		_status_label.text = "%d / %d — lancement dans ~%d s" % [players, max_players, seconds_left]
	else:
		_status_label.text = "%d / %d — recherche d'adversaire…" % [players, max_players]


func _on_match_ready(_match_id: String, game_ws_url: String) -> void:
	if _connecting_game:
		return
	_connecting_game = true
	var ws := game_ws_url.strip_edges()
	if ws == "":
		ws = NetworkSession.resolved_game_ws_url()
	_status_label.text = "Connexion WebSocket…"
	await NetworkSession.connect_to_game_server(ws)
	_connecting_game = false


func _on_game_connected() -> void:
	_status_label.text = "Connecté — lancement dès que 2 joueurs sont prêts…"


func _on_online_match_begin() -> void:
	_status_label.text = "Chargement de la map…"


func _on_game_connection_failed(message: String) -> void:
	_lobby_active = false
	_status_label.modulate = Color(1, 0.45, 0.45)
	_status_label.text = message


func _on_match_failed(message: String) -> void:
	_lobby_active = false
	_status_label.modulate = Color(1, 0.45, 0.45)
	_status_label.text = message
