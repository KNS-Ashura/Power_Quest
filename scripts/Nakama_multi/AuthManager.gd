extends Node

func authenticate_player(email: String, password: String, username: String, create: bool):
	var auth_result = await ServerConnection.client.authenticate_email_async(email, password, username, create)
	
	if auth_result.is_exception():
		return {"success": false, "message": auth_result.get_exception().message}
	
	ServerConnection.session = auth_result
	var socket_ok = await ServerConnection.connect_socket()
	
	return {"success": socket_ok, "message": "OK" if socket_ok else "Erreur de Socket"}
