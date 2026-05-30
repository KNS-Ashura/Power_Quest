extends Node

## Serveur de jeu MVP : WebSocket, lance Main quand au moins 2 clients sont connectés.

const DEFAULT_PORT := 9080
const MIN_PLAYERS_TO_START := 2
const MAIN_SCENE := "res://scenes/jeu/Main.scn"

var _peer: WebSocketMultiplayerPeer
var _match_started: bool = false
var _listen_port: int = DEFAULT_PORT


func _ready() -> void:
	print("[GameServer] Scène serveur chargée (game_server_main.gd).")
	_listen_port = _read_port_from_cmdline()
	print("[GameServer] Port demandé : %d (args user: %s)" % [_listen_port, str(OS.get_cmdline_user_args())])
	_peer = WebSocketMultiplayerPeer.new()
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	var err := _peer.create_server(_listen_port)
	if err != OK:
		var msg := (
			"Impossible d'écouter sur le port %d (%s / code %s). "
			+ "Souvent : port déjà utilisé → systemctl stop powerquest-game && fuser -k %d/tcp"
		) % [_listen_port, error_string(err), str(err), _listen_port]
		push_error(msg)
		printerr("[GameServer] ", msg)
		return
	# Peer sur NetworkSession (autoload) : ne pas le perdre quand on charge Main.tscn.
	NetworkSession.attach_server_peer(_peer)
	print("[GameServer] OK — écoute sur le port %d, en attente de %d+ joueurs." % [_listen_port, MIN_PLAYERS_TO_START])


func _read_port_from_cmdline() -> int:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			return int(args[i + 1])
	return DEFAULT_PORT


func _on_peer_connected(peer_id: int) -> void:
	print("[GameServer] Client connecté: ", peer_id)
	_try_start_match()
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(_try_start_match, CONNECT_ONE_SHOT)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[GameServer] Client déconnecté: ", peer_id)


func _try_start_match() -> void:
	if _match_started:
		return
	if NetworkSession.is_server_match_running():
		_match_started = true
		return
	var count := multiplayer.get_peers().size()
	if count < MIN_PLAYERS_TO_START:
		return
	_match_started = true
	print("[GameServer] Secours — %d peers, lancement via NetworkSession." % count)
	if NetworkSession.has_method("server_begin_online_match"):
		NetworkSession.server_begin_online_match(count)
