extends Node

# Configuration identique au docker-compose
var server_key: String = "admin"
var host: String = "127.0.0.1"
var port: int = 7350
var scheme: String = "http"

# On utilise des variables typées pour aider l'autocomplétion
var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket

func _ready():
	# Initialisation immédiate du client
	client = Nakama.create_client(server_key, host, port, scheme)
	
	if client:
		print("[Nakama] Client initialisé avec succès sur ", host, ":", port)
	else:
		push_error("[Nakama] Échec de l'initialisation du client !")

func set_session(new_session: NakamaSession):
	session = new_session
	print("[Nakama] Session active pour l'utilisateur : ", session.username)

# Vérification de sécurité pour les autres scripts
func is_ready() -> bool:
	return client != null
