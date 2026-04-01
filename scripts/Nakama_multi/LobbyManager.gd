extends Node


func create_lobby() -> Dictionary:
	var rpc_result = await ServerConnection.socket.rpc_async("create_private_match", "")

	if rpc_result.is_exception():
		return {"success": false, "code": "", "msg": rpc_result.get_exception().message}

	var data = JSON.parse_string(rpc_result.payload)
	if data == null or not data.has("match_id"):
		return {"success": false, "code": "", "msg": "Réponse serveur invalide."}

	var joined = await ServerConnection.join_match(data["match_id"])
	if not joined:
		return {"success": false, "code": data.get("code", ""), "msg": "Échec de la jonction."}

	return {"success": true, "code": data["code"]}


func join_lobby(code: String) -> Dictionary:
	var payload = JSON.stringify({"code": code.to_upper().strip_edges()})
	var rpc_result = await ServerConnection.socket.rpc_async("join_match_by_label", payload)

	if rpc_result.is_exception():
		return {"success": false, "msg": rpc_result.get_exception().message}

	var data = JSON.parse_string(rpc_result.payload)
	if data == null or not data.has("match_id"):
		return {"success": false, "msg": "Code invalide."}

	var joined = await ServerConnection.join_match(data["match_id"])
	return {"success": joined, "msg": "OK" if joined else "Erreur jonction"}
