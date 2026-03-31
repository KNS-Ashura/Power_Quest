extends Node

var server_key: String = "admin" 
var host: String = "127.0.0.1"
var port: int = 7350
var scheme: String = "http"

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket

func _ready():
	client = Nakama.create_client(server_key, host, port, scheme)
	if client:
		print("[Nakama] Client initialisé.")

func set_session(new_session: NakamaSession):
	session = new_session
	print("[Nakama] Session active : ", session.username)

# connexion a la game instant
func connect_socket():
	# on recup la fonction create_socket_from deja dans les addons
	socket = Nakama.create_socket_from(client)
	
	
	var connected = await socket.connect_async(session)
	
	if not connected.is_exception():
		print("[Nakama] Socket ouvert avec succès !")
		return true
	else:
		print("[Nakama] Erreur d'ouverture du Socket : ", connected.get_exception().message)
		return false
