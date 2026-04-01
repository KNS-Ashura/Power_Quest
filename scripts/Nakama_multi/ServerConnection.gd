extends Node

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket

func _ready():
	
	client = Nakama.create_client("admin", "127.0.0.1", 7350, "http")

func connect_socket() -> bool:
	if socket and not socket.is_closed():
		return true

	socket = Nakama.create_socket_from(client)
	var result = await socket.connect_async(session)

	if result.is_exception():
		print("[ERREUR SOCKET] ", result.get_exception().message)
		return false

	print("[SOCKET CONNECTÉ]")
	return true


func join_match(match_id: String) -> bool:
	if not socket: return false
	var res = await socket.join_match_async(match_id)
	if res.is_exception():
		print("[ERREUR JOIN] ", res.get_exception().message)
		return false
	return true
