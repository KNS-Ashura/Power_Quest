extends Node2D

const MIN_PLAYERS_TO_START := 2
const JOIN_LABEL := "JOIN ROOM"
const CANCEL_LABEL := "CANCEL"

signal requires_login

@onready var _join_room: BaseButton = get_node_or_null("PageGauche/JoinRoom")

var _status_label: Label
var _connecting_game: bool = false
var _in_matchmaking: bool = false


func _ready() -> void:
	if _join_room == null:
		_join_room = find_child("JoinRoom", true, false) as BaseButton
	if _join_room == null:
		_join_room = find_child("Join", true, false) as BaseButton

	_status_label = Label.new()
	_status_label.name = "NetworkStatus"
	_status_label.position = Vector2(118, 470)
	_status_label.custom_minimum_size = Vector2(400, 48)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	add_child(_status_label)

	_safe_connect_pressed(_join_room, _on_join_room_pressed)
	_connect_network_signals()
	visibility_changed.connect(_on_visibility_changed)
	_reset_idle_ui()

	if _join_room == null:
		_status_label.modulate = Color(1, 0.45, 0.45)
		_status_label.text = "Bouton JOIN introuvable dans la scène Multi."


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


func _on_join_room_pressed() -> void:
	if _in_matchmaking:
		_cancel_matchmaking(true)
		return
	_start_matchmaking()


func _start_matchmaking() -> void:
	# Déjà connecté : lancer la file directement (pas de redirection).
	if NetworkSession.is_account_logged_in():
		_enter_matchmaking_ui()
		_status_label.text = "Connexion à la file..."
		NetworkSession.join_ranked_queue()
		return

	# Identifiants locaux : tenter reconnexion auto, pas de redirection immédiate.
	if NetworkSession.has_saved_account_credentials():
		_enter_matchmaking_ui()
		_status_label.text = "Connexion à Nakama..."
		NetworkSession.authenticate()
		return

	# Vraiment non connecté : redirection vers la page connexion.
	_status_label.modulate = Color(1, 0.45, 0.45)
	_status_label.text = "Connecte-toi pour jouer en ligne."
	requires_login.emit()


func _enter_matchmaking_ui() -> void:
	_in_matchmaking = true
	_connecting_game = false
	_set_join_button_mode(true)
	_status_label.modulate = Color.WHITE


func _cancel_matchmaking(show_message: bool) -> void:
	_in_matchmaking = false
	_connecting_game = false
	NetworkSession.leave_ranked_queue()
	MapSession.reset_online_state()
	_set_join_button_mode(false)
	if show_message:
		_reset_idle_ui()


func _reset_idle_ui() -> void:
	_status_label.modulate = Color.WHITE
	_status_label.text = "Appuyez sur JOIN ROOM pour rejoindre la file."


func _set_join_button_mode(in_queue: bool) -> void:
	if _join_room == null:
		return
	_join_room.text = CANCEL_LABEL if in_queue else JOIN_LABEL


func _on_auth_ready() -> void:
	if not _in_matchmaking:
		return
	if not NetworkSession.is_account_logged_in():
		_cancel_matchmaking(true)
		_status_label.modulate = Color(1, 0.45, 0.45)
		_status_label.text = "Session expirée. Reconnecte-toi."
		requires_login.emit()
		return
	_status_label.text = "En attente d'autres joueurs..."
	NetworkSession.join_ranked_queue()


func _on_auth_failed(message: String) -> void:
	_cancel_matchmaking(true)
	_status_label.modulate = Color(1, 0.45, 0.45)
	_status_label.text = message


func _on_session_closed() -> void:
	_cancel_matchmaking(false)


func _on_queue_updated(players: int, max_players: int, seconds_left: int) -> void:
	if not _in_matchmaking:
		return
	if players < MIN_PLAYERS_TO_START:
		_status_label.text = "%d / %d — en attente (%d joueurs min.)" % [
			players, max_players, MIN_PLAYERS_TO_START
		]
	elif seconds_left > 0:
		_status_label.text = "%d / %d — lancement dans %d s (nouveau joueur = +10 s)" % [
			players, max_players, seconds_left
		]
	else:
		_status_label.text = "%d / %d — connexion au serveur…" % [players, max_players]


func _on_match_ready(_match_id: String, game_ws_url: String) -> void:
	if not _in_matchmaking or _connecting_game:
		return
	_connecting_game = true
	var ws := game_ws_url.strip_edges()
	if ws == "":
		ws = NetworkSession.resolved_game_ws_url()
	_status_label.text = "Connexion WebSocket…"
	await NetworkSession.connect_to_game_server(ws)
	_connecting_game = false


func _on_game_connected() -> void:
	if not _in_matchmaking:
		return
	_status_label.text = "Connecté — lancement dès que 2 joueurs sont prêts…"


func _on_online_match_begin() -> void:
	var map_idx := MapSession.active_map_index
	_status_label.text = "Chargement de la map %d…" % map_idx


func _on_game_connection_failed(message: String) -> void:
	_cancel_matchmaking(true)
	_status_label.modulate = Color(1, 0.45, 0.45)
	_status_label.text = message


func _on_match_failed(message: String) -> void:
	_cancel_matchmaking(true)
	_status_label.modulate = Color(1, 0.45, 0.45)
	_status_label.text = message
