extends Node

## Client Nakama (HTTP) + connexion au serveur de jeu (WebSocket).
## MVP : pas d'addon nakama-godot requis.

signal auth_ready
signal auth_failed(message: String)
signal queue_updated(players: int, max_players: int, seconds_left: int)
signal match_ready(match_id: String, game_ws_url: String)
signal match_failed(message: String)
signal game_connected
signal game_connection_failed(message: String)
signal online_match_begin

const MAIN_SCENE := "res://scenes/jeu/Main.scn"
const MIN_PLAYERS_TO_START := 2
const FALLBACK_GAME_WS_URL := "wss://powerquest.robinmatelot.codes/game/"
## Corps RPC Nakama : le serveur attend une chaîne JSON, pas un objet. Vide = deux guillemets.
const NAKAMA_RPC_BODY_EMPTY := '""'

var is_authenticated: bool = false
var session_token: String = ""
var user_id: String = ""
var device_id: String = ""

var _http: HTTPRequest
var _http_queue: Array = []
var _http_busy: bool = false
var _last_queue_poll: float = 0.0
var _in_queue: bool = false
var _match_handoff_started: bool = false
var _ws_connecting: bool = false
var _match_peer: WebSocketMultiplayerPeer
var _server_registered_peers: Array[int] = []
var _server_match_started: bool = false
var _match_start_check_scheduled: bool = false
var _waiting_map_after_connect: bool = false
var _map_wait_elapsed: float = 0.0
const MAP_WAIT_TIMEOUT := 25.0


func _ready() -> void:
	# Le binaire --server n'a pas besoin du client Nakama / HTTP.
	if ServerMode.is_dedicated_server:
		return
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_load_or_create_device_id()


func _load_or_create_device_id() -> void:
	# Nakama exige un device id de 10 à 128 caractères.
	const MIN_LEN := 10
	const MAX_LEN := 128
	if OS.has_feature("web"):
		# Navigateur : 1 id persistant + suffixe par onglet (sessionStorage) pour tester à 2 onglets.
		device_id = _web_device_id()
		return
	var path := "user://device_id.txt"
	if FileAccess.file_exists(path):
		device_id = FileAccess.get_file_as_string(path).strip_edges()
	if device_id.length() < MIN_LEN or device_id.length() > MAX_LEN:
		device_id = "pq_web_%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(device_id)


func _web_device_id() -> String:
	const MIN_LEN := 10
	const MAX_LEN := 128
	if ClassDB.class_exists("JavaScriptBridge"):
		var js := (
			"(function(){"
			+ "let bk='pq_device_base';let b=localStorage.getItem(bk);"
			+ "if(!b){b='pq_'+Math.random().toString(36).slice(2,14);localStorage.setItem(bk,b);}"
			+ "let tk='pq_tab';let t=sessionStorage.getItem(tk);"
			+ "if(!t){t=Math.random().toString(36).slice(2,10);sessionStorage.setItem(tk,t);}"
			+ "return b+'_'+t;"
			+ "})()"
		)
		var result = JavaScriptBridge.eval(js, true)
		if result != null:
			var id := str(result).strip_edges()
			if id.length() >= MIN_LEN:
				return id.substr(0, MAX_LEN)
	return "pq_web_%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]


func authenticate() -> void:
	if is_authenticated:
		auth_ready.emit()
		return
	_enqueue_http({
		"kind": "auth",
		"url": "%s/v2/account/authenticate/device?create=true" % NetworkConfig.nakama_base_url(),
		"headers": _nakama_headers(false),
		"body": JSON.stringify({"id": device_id}),
	})


func join_ranked_queue() -> void:
	if not is_authenticated:
		match_failed.emit("Non connecté à Nakama")
		return
	_in_queue = true
	_rpc("join_queue")


func leave_ranked_queue() -> void:
	if not is_authenticated:
		return
	_in_queue = false
	_match_handoff_started = false
	_ws_connecting = false
	_rpc("leave_queue")


## inner_json : chaîne JSON interne optionnelle (ex. '{"foo":1}'), pas un objet HTTP brut.
func _rpc(id: String, inner_json: String = "") -> void:
	var url := "%s/v2/rpc/%s" % [NetworkConfig.nakama_base_url(), id]
	var headers := _nakama_headers(true)
	var body := NAKAMA_RPC_BODY_EMPTY if inner_json == "" else JSON.stringify(inner_json)
	_enqueue_http({"kind": "rpc", "rpc_id": id, "url": url, "headers": headers, "body": body})


func _enqueue_http(job: Dictionary) -> void:
	_http_queue.append(job)
	_pump_http_queue()


func _pump_http_queue() -> void:
	if _http_busy or _http == null or _http_queue.is_empty():
		return
	var job: Dictionary = _http_queue.pop_front()
	_http_busy = true
	if job.get("kind") == "rpc":
		_http.set_meta("rpc_id", str(job.get("rpc_id", "")))
	else:
		if _http.has_meta("rpc_id"):
			_http.remove_meta("rpc_id")
	var err := _http.request(
		str(job.get("url", "")),
		job.get("headers", PackedStringArray()),
		HTTPClient.METHOD_POST,
		str(job.get("body", ""))
	)
	if err != OK:
		_http_busy = false
		push_error("[NetworkSession] HTTP request failed to start: %s" % str(err))
		_pump_http_queue()


func _nakama_headers(with_session: bool) -> PackedStringArray:
	# Export Web : ne pas demander gzip (sinon erreur Godot code 8 / stream_peer_gzip).
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept-Encoding: identity",
	])
	if with_session and session_token != "":
		headers.append("Authorization: Bearer %s" % session_token)
	else:
		var key_b64 := Marshalls.utf8_to_base64("%s:" % NetworkConfig.nakama_server_key)
		headers.append("Authorization: Basic %s" % key_b64)
	return headers


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_error(_http_result_message(result))
		return

	var text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)

	if response_code == 401 or response_code == 403:
		_handle_error("Auth Nakama refusée (%s)" % str(response_code))
		return

	if _http.has_meta("rpc_id"):
		var rpc_id: String = _http.get_meta("rpc_id")
		_http.remove_meta("rpc_id")
		_handle_rpc_response(rpc_id, response_code, parsed, text)
		_pump_http_queue()
		return

	# Auth device
	if response_code == 200 and typeof(parsed) == TYPE_DICTIONARY:
		if parsed.has("token"):
			session_token = str(parsed["token"])
		if parsed.has("user_id"):
			user_id = str(parsed["user_id"])
		is_authenticated = true
		auth_ready.emit()
	else:
		auth_failed.emit("Auth échouée (%s): %s" % [str(response_code), text])
	_pump_http_queue()


func _handle_rpc_response(rpc_id: String, code: int, parsed, raw_text: String) -> void:
	if code != 200:
		var detail := _format_nakama_error(parsed, raw_text)
		match_failed.emit("RPC %s (%s): %s" % [rpc_id, str(code), detail])
		return

	var payload = parsed
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("payload"):
		payload = JSON.parse_string(str(parsed["payload"]))

	if typeof(payload) != TYPE_DICTIONARY:
		match_failed.emit("Réponse RPC invalide")
		return

	if rpc_id == "join_queue" or rpc_id == "queue_status":
		_apply_queue_payload(payload)


func _apply_queue_payload(payload: Dictionary) -> void:
	var status := str(payload.get("status", "waiting"))
	var players := int(payload.get("players", 0))
	var max_p := int(payload.get("max_players", 8))
	var seconds := int(payload.get("seconds_left", 60))
	queue_updated.emit(players, max_p, seconds)

	if status == "matched" and players >= MIN_PLAYERS_TO_START:
		_in_queue = false
		if _match_handoff_started:
			return
		_match_handoff_started = true
		var match_id := str(payload.get("match_id", ""))
		var ws := str(payload.get("game_ws_url", "")).strip_edges()
		if ws == "":
			ws = resolved_game_ws_url()
		print("[NetworkSession] Match prêt — ws=%s" % ws)
		match_ready.emit(match_id, ws)


func resolved_game_ws_url() -> String:
	var url := NetworkConfig.resolved_game_ws_url().strip_edges()
	if url != "":
		return url
	return FALLBACK_GAME_WS_URL


func connect_to_game_server(ws_url: String = "") -> void:
	if _ws_connecting:
		print("[NetworkSession] Connexion WebSocket déjà en cours, ignorée.")
		return
	var url := ws_url.strip_edges() if ws_url != "" else resolved_game_ws_url()
	if url == "":
		url = FALLBACK_GAME_WS_URL
	_ws_connecting = true
	if _match_peer != null:
		_match_peer.close()
		_match_peer = null
	_match_peer = WebSocketMultiplayerPeer.new()
	print("[NetworkSession] Connexion WebSocket → ", url)
	var err := _match_peer.create_client(url)
	if err != OK:
		_ws_connecting = false
		game_connection_failed.emit("WebSocket client erreur %s (URL: %s)" % [str(err), url])
		return
	multiplayer.multiplayer_peer = _match_peer
	await get_tree().process_frame

	var timeout_ms := 12000
	var start_ms := Time.get_ticks_msec()
	while true:
		var st := _match_peer.get_connection_status()
		if st == WebSocketMultiplayerPeer.CONNECTION_CONNECTED:
			break
		if st == WebSocketMultiplayerPeer.CONNECTION_DISCONNECTED:
			_ws_connecting = false
			game_connection_failed.emit(
				"WebSocket refusé ou proxy /game incorrect (URL: %s). Vérifie Apache ProxyPass /game → ws://127.0.0.1:9080 et powerquest-game actif."
				% url
			)
			return
		if Time.get_ticks_msec() - start_ms > timeout_ms:
			_ws_connecting = false
			game_connection_failed.emit(
				"Timeout WebSocket (%s). VPS : systemctl status powerquest-game ; ss -tlnp | grep 9080 ; test WSS avec curl GET (pas HEAD) sur /game/"
				% url
			)
			return
		await get_tree().create_timer(0.1).timeout

	_ws_connecting = false
	game_connected.emit()
	_waiting_map_after_connect = true
	_map_wait_elapsed = 0.0
	# Laisser le canal RPC se stabiliser (surtout export Web).
	await get_tree().process_frame
	await get_tree().process_frame
	rpc_register_for_match.rpc_id(1)
	print("[NetworkSession] WebSocket jeu connecté — enregistrement auprès du serveur (peer local %d)." % multiplayer.get_unique_id())


## Chaque client annonce sa présence ; le serveur lance la map à 2+ joueurs.
@rpc("any_peer", "reliable")
func rpc_register_for_match() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0 or peer_id in _server_registered_peers:
		return
	_server_registered_peers.append(peer_id)
	print(
		"[NetworkSession] Client enregistré peer %d (%d/%d)."
		% [peer_id, _server_registered_peers.size(), MIN_PLAYERS_TO_START]
	)
	if _server_registered_peers.size() >= MIN_PLAYERS_TO_START:
		server_begin_online_match(_server_registered_peers.size())


## Le peer WebSocket vit sur cet autoload pour survivre au change_scene (serveur dédié).
func attach_server_peer(peer: WebSocketMultiplayerPeer) -> void:
	_match_peer = peer
	multiplayer.multiplayer_peer = peer
	if not peer.peer_connected.is_connected(_on_server_peer_connected):
		peer.peer_connected.connect(_on_server_peer_connected)
	if not peer.peer_disconnected.is_connected(_on_server_peer_disconnected):
		peer.peer_disconnected.connect(_on_server_peer_disconnected)
	print("[NetworkSession] Peer serveur attaché (autoload — survit au change_scene).")


func _on_server_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[NetworkSession] Client WebSocket connecté: ", peer_id)
	_schedule_server_match_start_check()


func _on_server_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[NetworkSession] Client WebSocket déconnecté: ", peer_id)
	_server_registered_peers.erase(peer_id)
	if multiplayer.get_peers().is_empty():
		reset_server_match_state()


func _schedule_server_match_start_check() -> void:
	if _match_start_check_scheduled or _server_match_started:
		return
	_match_start_check_scheduled = true
	_run_server_match_start_check()


func _run_server_match_start_check() -> void:
	await get_tree().create_timer(1.5).timeout
	_match_start_check_scheduled = false
	if _server_match_started:
		return
	var peer_count := multiplayer.get_peers().size()
	if peer_count < MIN_PLAYERS_TO_START:
		return
	var reg_count := _server_registered_peers.size()
	var count := maxi(reg_count, peer_count)
	print(
		"[NetworkSession] Secours lancement — peers=%d, enregistrés=%d."
		% [peer_count, reg_count]
	)
	server_begin_online_match(count)


func server_begin_online_match(player_count: int = MIN_PLAYERS_TO_START) -> void:
	if _server_match_started:
		return
	_server_match_started = true
	_server_registered_peers.clear()
	_waiting_map_after_connect = false
	print("[NetworkSession] Lancement partie (%d joueurs)." % player_count)
	MapSession.active_map_index = 2
	MapSession.is_online_match = true
	MapSession.local_team = 0
	MapSession.online_player_count = player_count

	# Envoyer aux clients AVANT change_scene (sinon le WebSocket serveur était détruit).
	for peer_id in multiplayer.get_peers():
		rpc_begin_online_match.rpc_id(peer_id, player_count)
	await get_tree().create_timer(0.25).timeout

	if ServerMode.is_dedicated_server:
		get_tree().change_scene_to_file(MAIN_SCENE)
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)


func reset_server_match_state() -> void:
	_server_registered_peers.clear()
	_server_match_started = false


## Appelé par le serveur de jeu quand 2+ clients sont connectés (RPC).
@rpc("authority", "call_remote", "reliable")
func rpc_begin_online_match(player_count: int = MIN_PLAYERS_TO_START) -> void:
	if ServerMode.is_dedicated_server:
		return
	print("[NetworkSession] Client — démarrage map (%d joueurs)." % player_count)
	_waiting_map_after_connect = false
	_load_online_match_scene(player_count)


func _load_online_match_scene(player_count: int = MIN_PLAYERS_TO_START) -> void:
	MapSession.active_map_index = 2
	MapSession.is_online_match = true
	MapSession.local_team = 0
	MapSession.online_player_count = player_count
	get_tree().change_scene_to_file(MAIN_SCENE)
	online_match_begin.emit()


func _http_result_message(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Connexion impossible (réseau ou API injoignable)"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Nom de domaine introuvable (DNS)"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connexion coupée — CORS Nakama ou WebSocket /game (souvent 503 = serveur jeu arrêté sur le VPS)"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Erreur certificat SSL (HTTPS)"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Requête refusée par le navigateur (CORS ou mixed content)"
		8:
			# RESULT_BODY_DECODE_ERROR (selon versions Godot) — souvent gzip sur /v2
			return "Réponse illisible (gzip) — réexport Web + Apache sans compression sur /v2"
		_:
			return "Erreur HTTP Godot code %s" % str(result)


func _format_nakama_error(parsed, raw_text: String) -> String:
	if typeof(parsed) == TYPE_DICTIONARY:
		if parsed.has("message") and parsed.has("code"):
			return "Nakama code %s — %s" % [
				str(parsed.get("code")), str(parsed.get("message"))
			]
	return raw_text


func _handle_error(msg: String) -> void:
	_pump_http_queue()
	if _in_queue:
		match_failed.emit(msg)
	else:
		auth_failed.emit(msg)


func _process(_delta: float) -> void:
	if _waiting_map_after_connect:
		_map_wait_elapsed += _delta
		if _map_wait_elapsed >= MAP_WAIT_TIMEOUT:
			_waiting_map_after_connect = false
			game_connection_failed.emit(
				"La map n'a pas démarré. Ouvre un 2e onglet (Multijoueur) ou vérifie le serveur jeu (port 9080)."
			)
	if not _in_queue or not is_authenticated or _match_handoff_started:
		return
	if _http_busy:
		return
	_last_queue_poll += _delta
	if _last_queue_poll < 1.0:
		return
	_last_queue_poll = 0.0
	_rpc("queue_status")
