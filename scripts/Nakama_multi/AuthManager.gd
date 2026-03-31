extends Node  

func authenticate_player(email: String, password: String, username: String, create: bool):
	var server = ServerConnection
	
	
	var auth_result = await server.client.authenticate_email_async(email, password, username, create)
	
	if auth_result.is_exception():
		print("[Auth] Erreur : ", auth_result.get_exception().message)
		return {"success": false, "message": auth_result.get_exception().message}
	
	server.set_session(auth_result)
	
	
	await server.connect_socket()
	
	return {"success": true, "message": "OK"}
