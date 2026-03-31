extends Node  # Modifié ici (Node au lieu de Node2D)

@onready var server = ServerConnection

func authenticate_player(email: String, password: String, username: String = ""):
	if not server.client:
		await get_tree().process_frame 
	
	# Appel à Nakama (create_account: true permet l'inscription auto)
	var auth_result = await server.client.authenticate_email_async(email, password, username, true)
	
	if auth_result.is_exception():
		print("[Auth] Erreur : ", auth_result.get_exception().message)
		return false
	
	server.set_session(auth_result)
	return true
