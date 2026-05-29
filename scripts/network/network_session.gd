extends Node

## Client Nakama (HTTP) + connexion au serveur de jeu (WebSocket).
## MVP : pas d'addon nakama-godot requis.

signal auth_ready
signal auth_failed(message: String)
signal session_closed
signal profile_updated(profile: Dictionary)
signal queue_updated(players: int, max_players: int, seconds_left: int)
signal match_ready(match_id: String, game_ws_url: String)
signal match_failed(message: String)
signal game_connected
signal game_connection_failed(message: String)
signal online_match_begin

const MAIN_SCENE := "res://scenes/jeu/Main.scn"
const MIN_PLAYERS_TO_START := 2
const FALLBACK_GAME_WS_URL := "wss://powerquest.robinmatelot.codes/game/"
const WS_CONNECT_RETRIES := 3
const WS_CONNECT_RETRY_DELAY_SEC := 1.5
## Corps RPC Nakama : le serveur attend une chaîne JSON, pas un objet. Vide = deux guillemets.
const NAKAMA_RPC_BODY_EMPTY := '""'

var is_authenticated: bool = false
var session_token: String = ""
var user_id: String = ""
var device_id: String = ""
var account_email: String = ""
var account_username: String = ""
var profile_cache: Dictionary = {}
var leaderboard_cache: Array = []
var _auth_mode: String = "" # "account" or "device"
var _pending_auth_email: String = ""
var _pending_auth_password: String = ""
var _pending_auth_username: String = ""
## Pseudo choisi à l'inscription — prioritaire sur le username auto Nakama (souvent aléatoire).
var _session_username_override: String = ""
var _leave_queue_pending: bool = false
var _awaiting_join_ack: bool = false
var _rpc_warn_last: Dictionary = {}
var _use_browser_http: bool = false
var _web_bridge_warned: bool = false
var _web_pending_id: String = ""
var _web_request_started_ms: int = 0
const WEB_HTTP_TIMEOUT_MS := 15000

var _http: HTTPRequest
var _http_queue: Array = []
var _http_busy: bool = false
var _last_queue_poll: float = 0.0
var _in_queue: bool = false
var _match_handoff_started: bool = false
var _ws_connecting: bool = false
var _match_peer: WebSocketMultiplayerPeer
var _server_registered_peers: Array[int] = []
var _peer_display_names: Dictionary = {}
var _server_match_started: bool = false
var _match_start_check_scheduled: bool = false
var _waiting_map_after_connect: bool = false
var _map_wait_elapsed: float = 0.0
const MAP_WAIT_TIMEOUT := 25.0


func _ready() -> void:
	# Le binaire --server n'a pas besoin du client Nakama / HTTP.
	if ServerMode.is_dedicated_server:
		return
	_use_browser_http = WebNakamaHttp.is_available()
	if _use_browser_http:
		# Injecte le pont fetch() au runtime (indépendant de index.html / export_presets).
		if not WebNakamaHttp.ensure_bridge():
			_use_browser_http = false
			call_deferred("_warn_missing_web_bridge")
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_load_or_create_device_id()


func is_account_logged_in() -> bool:
	return is_authenticated and _auth_mode == "account" and session_token != ""


func has_saved_account_credentials() -> bool:
	return FileAccess.file_exists("user://account_credentials.json")


func get_display_username() -> String:
	var forced := _session_username_override.strip_edges()
	if _is_human_username(forced):
		return forced
	var from_account := account_username.strip_edges()
	if _is_human_username(from_account):
		return from_account
	var from_profile := str(profile_cache.get("username", "")).strip_edges()
	if _is_human_username(from_profile):
		return from_profile
	if _pending_auth_username.strip_edges() != "":
		return _pending_auth_username.strip_edges()
	if account_email != "":
		var from_file := _load_saved_username_for_email(account_email)
		if _is_human_username(from_file):
			return from_file
	return "Joueur"


func sanitize_display_username(value: String) -> String:
	var cleaned := value.strip_edges()
	if _is_human_username(cleaned):
		return cleaned
	return ""


func register_peer_display_name(peer_id: int, display_name: String) -> void:
	var cleaned := sanitize_display_username(display_name)
	if cleaned == "":
		cleaned = "Joueur %d" % peer_id
	_peer_display_names[peer_id] = cleaned


func get_peer_display_name(peer_id: int) -> String:
	return str(_peer_display_names.get(peer_id, "Joueur %d" % peer_id))


func clear_peer_display_names() -> void:
	_peer_display_names.clear()


func _is_human_username(value: String) -> bool:
	if value == "":
		return false
	if value.length() < 2 or value.length() > 20:
		return false
	# Évite d'afficher un UUID / id technique à la place du pseudo.
	if value.length() >= 32 and value.count("-") >= 4:
		return false
	return true


func register_account(email: String, password: String, username: String) -> void:
	var e := AuthValidation.sanitize_email(email)
	var p := password
	var u := AuthValidation.sanitize_username(username)
	if e == "" or p == "" or u == "":
		auth_failed.emit("Email, pseudo et mot de passe requis.")
		return
	if not AuthValidation.is_valid_email(e):
		auth_failed.emit("Adresse email invalide.")
		return
	if not AuthValidation.is_valid_username(u):
		auth_failed.emit("Pseudo invalide (3-20 caractères, lettres/chiffres/_).")
		return
	var pwd_err := AuthValidation.is_valid_password(p)
	if pwd_err != "":
		auth_failed.emit(pwd_err)
		return
	_pending_auth_email = e
	_pending_auth_password = p
	_pending_auth_username = u
	_session_username_override = u
	# Nakama : username en query ET dans le corps (selon version / proxy).
	var url := "%s/v2/account/authenticate/email?create=true&username=%s" % [
		NetworkConfig.nakama_base_url(),
		u.uri_encode()
	]
	_enqueue_http({
		"kind": "auth_account",
		"is_registration": true,
		"url": url,
		"headers": _nakama_headers(false),
		"body": JSON.stringify({"email": e, "password": p, "username": u})
	})


func login_account(email: String, password: String) -> void:
	var e := AuthValidation.sanitize_email(email)
	var p := password
	if e == "" or p == "":
		auth_failed.emit("Email et mot de passe requis.")
		return
	if not AuthValidation.is_valid_email(e):
		auth_failed.emit("Adresse email invalide.")
		return
	var pwd_err := AuthValidation.is_valid_password(p)
	if pwd_err != "":
		auth_failed.emit(pwd_err)
		return
	_pending_auth_email = e
	_pending_auth_password = p
	_apply_saved_username_hints(e)
	_enqueue_http({
		"kind": "auth_account",
		"url": "%s/v2/account/authenticate/email?create=false" % NetworkConfig.nakama_base_url(),
		"headers": _nakama_headers(false),
		"body": JSON.stringify({"email": e, "password": p})
	})


func logout_account() -> void:
	leave_ranked_queue()
	is_authenticated = false
	session_token = ""
	user_id = ""
	account_email = ""
	account_username = ""
	_auth_mode = ""
	_pending_auth_email = ""
	_pending_auth_password = ""
	_pending_auth_username = ""
	_session_username_override = ""
	profile_cache.clear()
	leaderboard_cache.clear()
	_delete_saved_credentials()
	if _match_peer != null:
		_match_peer.close()
		_match_peer = null
	session_closed.emit()


func submit_match_result(win: bool, duration_seconds: int) -> void:
	if not is_account_logged_in():
		return
	var payload := JSON.stringify({
		"win": win,
		"duration_seconds": maxi(0, duration_seconds)
	})
	_rpc("submit_match_result", payload)


func request_player_profile() -> void:
	if not is_authenticated:
		return
	_rpc("get_player_profile")


func request_account_info() -> void:
	if not is_authenticated:
		return
	_enqueue_http({
		"kind": "account_info",
		"url": "%s/v2/account" % NetworkConfig.nakama_base_url(),
		"headers": _nakama_headers(true),
		"method": HTTPClient.METHOD_GET,
		"body": ""
	})


func _sync_username_on_server(username: String) -> void:
	if not is_authenticated:
		return
	var cleaned := sanitize_display_username(username)
	if cleaned == "":
		return
	_rpc("set_username", JSON.stringify({"username": cleaned}))


func _complete_auth_success() -> void:
	if profile_cache.is_empty():
		profile_cache = {}
	var display_name := get_display_username()
	if display_name != "Joueur":
		profile_cache["username"] = display_name
		profile_updated.emit(profile_cache.duplicate(true))
	request_account_info()
	request_player_profile()
	request_leaderboard()
	auth_ready.emit()


func request_leaderboard(limit: int = 20) -> void:
	if not is_authenticated:
		return
	var payload := JSON.stringify({"limit": clampi(limit, 1, 100)})
	_rpc("get_leaderboard", payload)


func _read_saved_credentials() -> Dictionary:
	if not FileAccess.file_exists("user://account_credentials.json"):
		return {}
	var parsed: Variant = _parse_json_safe(FileAccess.get_file_as_string("user://account_credentials.json"))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func _load_saved_username_for_email(email: String) -> String:
	var creds := _read_saved_credentials()
	if str(creds.get("email", "")).to_lower() != email.strip_edges().to_lower():
		return ""
	return str(creds.get("username", "")).strip_edges()


func _apply_saved_username_hints(email: String) -> void:
	var saved := _load_saved_username_for_email(email)
	_pending_auth_username = ""
	if _is_human_username(saved):
		_pending_auth_username = saved
		_session_username_override = saved


func _save_credentials(email: String, password: String, username: String = "") -> void:
	var f := FileAccess.open("user://account_credentials.json", FileAccess.WRITE)
	if f == null:
		return
	var data := {
		"email": email.strip_edges().to_lower(),
		"password": password,
	}
	var u := username.strip_edges()
	if u == "" and _is_human_username(_session_username_override):
		u = _session_username_override
	elif u == "" and _is_human_username(account_username):
		u = account_username
	if _is_human_username(u):
		data["username"] = u
	f.store_string(JSON.stringify(data))


func _delete_saved_credentials() -> void:
	if FileAccess.file_exists("user://account_credentials.json"):
		DirAccess.remove_absolute("user://account_credentials.json")


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
	if is_account_logged_in():
		auth_ready.emit()
		return
	if not FileAccess.file_exists("user://account_credentials.json"):
		auth_failed.emit("Connecte-toi ou crée un compte avant de lancer une partie.")
		return
	var parsed := _read_saved_credentials()
	if parsed.is_empty():
		auth_failed.emit("Identifiants locaux invalides. Reconnecte-toi.")
		return
	var email := str(parsed.get("email", ""))
	_apply_saved_username_hints(email)
	login_account(email, str(parsed.get("password", "")))


func join_ranked_queue() -> void:
	if not is_account_logged_in():
		match_failed.emit("Connecte-toi avec un compte avant de jouer en ligne.")
		return
	_awaiting_join_ack = true
	_in_queue = false
	_match_handoff_started = false
	_rpc("join_queue")


func leave_ranked_queue() -> void:
	_in_queue = false
	_awaiting_join_ack = false
	_match_handoff_started = false
	_ws_connecting = false
	if not is_authenticated or session_token == "":
		return
	if _leave_queue_pending:
		return
	_leave_queue_pending = true
	_rpc("leave_queue")


## inner_json : objet JSON sérialisé (ex. '{"limit":20}').
## Nakama HTTP RPC attend le payload comme CHAÎNE JSON encodée → on (re)stringifie.
## Sinon : 400 "cannot unmarshal object into Go value of type string".
func _rpc(id: String, inner_json: String = "") -> void:
	var url := "%s/v2/rpc/%s" % [NetworkConfig.nakama_base_url(), id]
	var headers := _nakama_headers(true)
	var body := NAKAMA_RPC_BODY_EMPTY if inner_json == "" else JSON.stringify(inner_json)
	_enqueue_http({"kind": "rpc", "rpc_id": id, "url": url, "headers": headers, "body": body})


func _enqueue_http(job: Dictionary) -> void:
	_http_queue.append(job)
	_pump_http_queue()


func _warn_missing_web_bridge() -> void:
	if _web_bridge_warned:
		return
	_web_bridge_warned = true
	push_warning(
		"[NetworkSession] Pont fetch() non injecté — repli sur HTTPRequest Godot."
	)


func _pump_http_queue() -> void:
	if _http_busy or _http_queue.is_empty():
		return
	if _web_pending_id != "":
		return
	var job: Dictionary = _http_queue.pop_front()
	if _use_browser_http and WebNakamaHttp.bridge_ready():
		_start_web_request(job)
		return
	if _http == null:
		return
	_http_busy = true
	_apply_http_job_meta(job)
	var err := _http.request(
		str(job.get("url", "")),
		job.get("headers", PackedStringArray()),
		int(job.get("method", HTTPClient.METHOD_POST)),
		str(job.get("body", ""))
	)
	if err != OK:
		_http_busy = false
		push_error("[NetworkSession] HTTP request failed to start: " + str(err))
		_pump_http_queue()


func _apply_http_job_meta(job: Dictionary) -> void:
	_http.set_meta("http_kind", str(job.get("kind", "")))
	if job.get("kind") == "rpc":
		_http.set_meta("rpc_id", str(job.get("rpc_id", "")))
	else:
		if _http.has_meta("rpc_id"):
			_http.remove_meta("rpc_id")
	if bool(job.get("is_registration", false)):
		_http.set_meta("is_registration", true)
	elif _http.has_meta("is_registration"):
		_http.remove_meta("is_registration")
	if job.has("desired_username"):
		_http.set_meta("desired_username", str(job.get("desired_username")))
	elif _http.has_meta("desired_username"):
		_http.remove_meta("desired_username")


## Export Web : envoie via fetch() navigateur (asynchrone), réponse lue dans _poll_web_request().
func _start_web_request(job: Dictionary) -> void:
	_http_busy = true
	_apply_http_job_meta(job)
	var url := str(job.get("url", ""))
	var method := int(job.get("method", HTTPClient.METHOD_POST))
	var headers: PackedStringArray = job.get("headers", PackedStringArray())
	var body := str(job.get("body", ""))
	_web_pending_id = "%d_%d" % [Time.get_ticks_usec(), randi()]
	_web_request_started_ms = Time.get_ticks_msec()
	if not WebNakamaHttp.send(_web_pending_id, url, method, headers, body):
		_web_pending_id = ""
		_http_busy = false
		_handle_error("Réseau Web indisponible (pont window.PQ).")
		_pump_http_queue()


func _poll_web_request() -> void:
	if _web_pending_id == "":
		return
	var res := WebNakamaHttp.poll(_web_pending_id)
	if res.is_empty():
		if Time.get_ticks_msec() - _web_request_started_ms > WEB_HTTP_TIMEOUT_MS:
			_web_pending_id = ""
			_http_busy = false
			_handle_error("Timeout réseau Web (Nakama injoignable).")
			_pump_http_queue()
		return
	_web_pending_id = ""
	var response_code := int(res.get("status", 0))
	var text := str(res.get("text", ""))
	if not bool(res.get("ok", false)) and response_code == 0:
		_http_busy = false
		_handle_error("Réseau Web : " + str(res.get("error", "fetch échoué")))
		_pump_http_queue()
		return
	# _on_http_completed remet _http_busy à false et relance le pump.
	_on_http_completed(
		HTTPRequest.RESULT_SUCCESS, response_code, PackedStringArray(), text.to_utf8_buffer()
	)


func _http_is_success(response_code: int) -> bool:
	return response_code >= 200 and response_code < 300


func _http_body_to_text(body: PackedByteArray) -> String:
	if body.is_empty():
		return ""
	var text := body.get_string_from_utf8()
	if text.is_empty():
		text = body.get_string_from_ascii()
	# Export Web : octets nuls dans le corps → JSON.parse échoue alors que le token est là.
	return text.replace("\u0000", "").strip_edges()


func _extract_json_object_text(text: String) -> String:
	var start := text.find("{")
	var end := text.rfind("}")
	if start < 0 or end <= start:
		return ""
	return text.substr(start, end - start + 1)


func _parse_json_safe(text: String) -> Variant:
	if text.is_empty():
		return null
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return null
	if cleaned.begins_with("\ufeff"):
		cleaned = cleaned.substr(1)
	if cleaned.begins_with("<"):
		return null
	var json := JSON.new()
	if json.parse(cleaned) == OK:
		return json.data
	var inner := _extract_json_object_text(cleaned)
	if inner != "" and inner != cleaned:
		var json2 := JSON.new()
		if json2.parse(inner) == OK:
			return json2.data
	return null


func _extract_auth_fields_from_text(text: String) -> Dictionary:
	var parsed: Variant = _parse_json_safe(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	var out := {}
	var token_re := RegEx.new()
	if token_re.compile("\"token\"\\s*:\\s*\"([^\"]+)\"") == OK:
		var m := token_re.search(text)
		if m:
			out["token"] = m.get_string(1)
	var uid_re := RegEx.new()
	if uid_re.compile("\"user_id\"\\s*:\\s*\"([^\"]+)\"") == OK:
		var m2 := uid_re.search(text)
		if m2:
			out["user_id"] = m2.get_string(1)
	return out


## Repli Web : extrait "username":"..." du texte brut quand JSON.parse échoue.
func _extract_username_from_text(text: String) -> String:
	if text.is_empty():
		return ""
	var re := RegEx.new()
	if re.compile("\"username\"\\s*:\\s*\"([^\"]+)\"") != OK:
		return ""
	var m := re.search(text)
	if m:
		return m.get_string(1).strip_edges()
	return ""


func _apply_auth_session_from_fields(fields: Dictionary, was_registration: bool) -> bool:
	if not fields.has("token") or str(fields["token"]) == "":
		return false
	session_token = str(fields["token"])
	if fields.has("user_id"):
		user_id = str(fields["user_id"])
	is_authenticated = true
	_auth_mode = "account"
	var token_payload := _parse_jwt_payload(session_token)
	account_email = str(token_payload.get("email", _pending_auth_email))
	var chosen_username := _pending_auth_username.strip_edges()
	var token_username := str(
		token_payload.get("username", token_payload.get("usn", ""))
	).strip_edges()
	if was_registration and _is_human_username(chosen_username):
		account_username = chosen_username
		_session_username_override = chosen_username
		if _pending_auth_email != "" and _pending_auth_password != "":
			_save_credentials(_pending_auth_email, _pending_auth_password, chosen_username)
		_pending_auth_email = ""
		_pending_auth_password = ""
		_pending_auth_username = ""
		call_deferred("_sync_username_on_server", chosen_username)
		_complete_auth_success()
	else:
		var saved_user := _load_saved_username_for_email(account_email)
		if _is_human_username(token_username):
			account_username = token_username
		elif _is_human_username(chosen_username):
			account_username = chosen_username
			_session_username_override = chosen_username
		elif _is_human_username(saved_user):
			account_username = saved_user
			_session_username_override = saved_user
			_sync_username_on_server(saved_user)
		if _pending_auth_email != "" and _pending_auth_password != "":
			_save_credentials(
				_pending_auth_email,
				_pending_auth_password,
				account_username if account_username != "" else saved_user
			)
		_pending_auth_email = ""
		_pending_auth_password = ""
		_pending_auth_username = ""
		_complete_auth_success()
	return true


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
	var http_kind := str(_http.get_meta("http_kind", ""))
	if _http.has_meta("http_kind"):
		_http.remove_meta("http_kind")
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_error(_http_result_message(result))
		return

	var text := _http_body_to_text(body)
	var parsed: Variant = _parse_json_safe(text)

	# Auth : le token peut être présent même si JSON.parse échoue (export Web / WASM).
	if http_kind == "auth_account" and _http_is_success(response_code):
		var was_registration := bool(_http.get_meta("is_registration", false)) if _http.has_meta("is_registration") else false
		if _http.has_meta("is_registration"):
			_http.remove_meta("is_registration")
		var fields: Dictionary
		if typeof(parsed) == TYPE_DICTIONARY:
			fields = parsed as Dictionary
		else:
			fields = _extract_auth_fields_from_text(text)
		if _apply_auth_session_from_fields(fields, was_registration):
			_pump_http_queue()
			return
		_handle_error(_friendly_auth_error(response_code, parsed, text))
		_pump_http_queue()
		return

	# Nakama renvoie parfois HTTP 200/204 avec corps vide (ex. PUT account) — ce n'est pas une erreur.
	if parsed == null and _http_is_success(response_code):
		if http_kind == "account_info":
			# Repli Web : si le JSON n'a pas parsé, on tente d'extraire le pseudo du texte brut.
			var fallback_user := _extract_username_from_text(text)
			if _is_human_username(fallback_user) and _session_username_override == "":
				account_username = fallback_user
				if profile_cache.is_empty():
					profile_cache = {}
				profile_cache["username"] = fallback_user
				profile_updated.emit(profile_cache)
			_pump_http_queue()
			return
		if http_kind == "account_update":
			var desired := ""
			if _http.has_meta("desired_username"):
				desired = str(_http.get_meta("desired_username"))
				_http.remove_meta("desired_username")
			if _is_human_username(desired):
				account_username = desired
				_session_username_override = desired
			_pump_http_queue()
			return

	if _http.has_meta("rpc_id"):
		var rpc_id: String = str(_http.get_meta("rpc_id"))
		_http.remove_meta("rpc_id")
		var rpc_payload := _resolve_rpc_payload(parsed, text)
		_handle_rpc_response(rpc_id, response_code, rpc_payload, text)
		_pump_http_queue()
		return

	if parsed == null:
		var preview := text.substr(0, mini(160, text.length())).strip_edges()
		push_warning(
			"[NetworkSession] Réponse non-JSON HTTP "
			+ str(response_code)
			+ " : "
			+ preview
		)
		_handle_error(
			"Réponse serveur illisible (HTTP " + str(response_code) + "). Réexporte le client Web."
		)
		return

	if http_kind == "account_info":
		if response_code == 200 and typeof(parsed) == TYPE_DICTIONARY:
			_apply_account_info(parsed)
			if profile_cache.is_empty():
				profile_cache = {}
			profile_cache["username"] = account_username
			var creds := _read_saved_credentials()
			if account_email != "" and creds.has("password"):
				_save_credentials(account_email, str(creds.get("password", "")), account_username)
			profile_updated.emit(profile_cache)
		_pump_http_queue()
		return

	if http_kind == "account_update":
		var desired := ""
		if _http.has_meta("desired_username"):
			desired = str(_http.get_meta("desired_username"))
			_http.remove_meta("desired_username")
		if _http_is_success(response_code):
			if typeof(parsed) == TYPE_DICTIONARY:
				_apply_account_info(parsed)
			if _is_human_username(desired):
				account_username = desired
				_session_username_override = desired
		_pump_http_queue()
		return

	# Auth device (legacy)
	if response_code == 200 and typeof(parsed) == TYPE_DICTIONARY:
		if parsed.has("token"):
			session_token = str(parsed["token"])
		if parsed.has("user_id"):
			user_id = str(parsed["user_id"])
		is_authenticated = true
		_auth_mode = "device"
		auth_ready.emit()
	else:
		_handle_error(_friendly_auth_error(response_code, parsed, text))
	_pump_http_queue()


func _resolve_rpc_payload(parsed: Variant, raw_text: String) -> Dictionary:
	var payload: Variant = _decode_nakama_rpc_payload(parsed)
	if typeof(payload) != TYPE_DICTIONARY:
		payload = _decode_nakama_rpc_payload_from_text(raw_text)
	if typeof(payload) == TYPE_DICTIONARY:
		return payload as Dictionary
	if _looks_like_queue_rpc_text(raw_text):
		return _extract_queue_fields_from_text(raw_text)
	return {}


func _looks_like_queue_rpc_text(text: String) -> bool:
	if text.is_empty():
		return false
	return text.find("players") >= 0 and (
		text.find("waiting") >= 0
		or text.find("matched") >= 0
		or text.find("wait") >= 0
		or text.find("max_players") >= 0
	)


func _decode_nakama_rpc_payload(parsed: Variant) -> Variant:
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	if not parsed.has("payload"):
		if parsed.has("status") or parsed.has("players"):
			return parsed
		return parsed
	var inner: Variant = parsed["payload"]
	var guard := 0
	while guard < 6:
		guard += 1
		if typeof(inner) == TYPE_DICTIONARY:
			return inner
		if typeof(inner) != TYPE_STRING:
			return null
		var inner_text := str(inner).strip_edges()
		var decoded: Variant = _parse_json_safe(inner_text)
		if typeof(decoded) == TYPE_DICTIONARY:
			return decoded
		# Export Web : parfois la chaîne payload garde des \" littéraux.
		var unescaped := inner_text.replace('\\"', '"')
		decoded = _parse_json_safe(unescaped)
		if typeof(decoded) == TYPE_DICTIONARY:
			return decoded
		if typeof(decoded) == TYPE_STRING:
			inner = decoded
			continue
		break
	return null


func _decode_nakama_rpc_payload_from_text(text: String) -> Variant:
	var wrapper: Variant = _parse_json_safe(text)
	if typeof(wrapper) == TYPE_DICTIONARY:
		var decoded: Variant = _decode_nakama_rpc_payload(wrapper)
		if typeof(decoded) == TYPE_DICTIONARY:
			return decoded
		if not (wrapper as Dictionary).has("payload"):
			return wrapper
	# Parse Godot/WASM KO : extraire la chaîne payload à la main puis re-parser.
	var inner_text := _extract_payload_string_literal(text)
	if inner_text != "":
		var inner_parsed: Variant = _parse_json_safe(inner_text)
		if typeof(inner_parsed) == TYPE_DICTIONARY:
			return inner_parsed
	# Réponse RPC sans enveloppe, ou JSON tronqué.
	var direct: Variant = _parse_json_safe(_extract_json_object_text(text))
	if typeof(direct) == TYPE_DICTIONARY:
		return direct
	# Détecter "left" UNIQUEMENT sur la vraie valeur "status":"left"
	# (sinon "seconds_left" déclenche un faux positif → 0/8).
	if _text_has_status_left(text):
		return {"status": "left", "players": 0}
	if _looks_like_queue_rpc_text(text):
		return _extract_queue_fields_from_text(text)
	return null


func _text_has_status_left(text: String) -> bool:
	# Gère le JSON échappé ("status":"left") et non échappé (\"status\":\"left\").
	var t := text.replace('\\"', '"').replace("\\\\", "\\")
	return t.find("\"status\":\"left\"") >= 0 or t.find("\"status\": \"left\"") >= 0


func _extract_payload_string_literal(text: String) -> String:
	var key_pos := text.find("\"payload\"")
	if key_pos < 0:
		return ""
	var colon := text.find(":", key_pos)
	if colon < 0:
		return ""
	var i := colon + 1
	while i < text.length() and text[i] in " \t\r\n":
		i += 1
	if i >= text.length() or text[i] != '"':
		return ""
	i += 1
	var out := ""
	while i < text.length():
		var ch := text[i]
		if ch == "\\" and i + 1 < text.length():
			var esc := text[i + 1]
			match esc:
				'"':
					out += '"'
				"\\":
					out += "\\"
				"/":
					out += "/"
				"b":
					out += "\b"
				"f":
					out += "\f"
				"n":
					out += "\n"
				"r":
					out += "\r"
				"t":
					out += "\t"
				_:
					out += esc
			i += 2
			continue
		if ch == '"':
			break
		out += ch
		i += 1
	return out


func _extract_queue_fields_from_text(text: String) -> Dictionary:
	# Déséchappe d'abord : les payloads RPC arrivent souvent en JSON échappé
	# (ex. \"players\":2), sinon les regex ne matchent rien.
	var t := text.replace('\\"', '"').replace("\\\\", "\\")
	var out := {"status": "waiting", "players": 1, "max_players": 8, "seconds_left": 60}
	if t.find("\"status\":\"matched\"") >= 0:
		out["status"] = "matched"
	elif t.find("\"status\":\"left\"") >= 0:
		out["status"] = "left"
	else:
		out["status"] = "waiting"
	for key in ["players", "max_players", "seconds_left"]:
		var val := _extract_json_int_field(t, key)
		if val >= 0:
			out[key] = val
	var match_re := RegEx.new()
	if match_re.compile("\"match_id\"\\s*:\\s*\"([^\"]*)\"") == OK:
		var mm := match_re.search(t)
		if mm:
			out["match_id"] = mm.get_string(1)
	var ws_re := RegEx.new()
	if ws_re.compile("\"game_ws_url\"\\s*:\\s*\"([^\"]*)\"") == OK:
		var wm := ws_re.search(t)
		if wm:
			out["game_ws_url"] = wm.get_string(1)
	return out


func _extract_json_int_field(text: String, field: String) -> int:
	var re := RegEx.new()
	if re.compile('"' + field + '"\\s*:\\s*(\\d+)') != OK:
		return -1
	var pos := 0
	while true:
		var m := re.search(text, pos)
		if m == null:
			return -1
		var start := m.get_start()
		if start > 0 and text[start - 1] == "_":
			pos = m.get_end()
			continue
		return int(m.get_string(1))
	return -1


func _is_benign_rpc(rpc_id: String) -> bool:
	return rpc_id in [
		"leave_queue", "ping", "set_username",
		"get_player_profile", "get_leaderboard",
	]


func _rpc_warn_once(key: String, message: String) -> void:
	var now := Time.get_ticks_msec()
	var last := int(_rpc_warn_last.get(key, 0))
	if now - last < 5000:
		return
	_rpc_warn_last[key] = now
	push_warning(message)


func _handle_rpc_response(rpc_id: String, code: int, payload: Dictionary, raw_text: String) -> void:
	if rpc_id == "leave_queue":
		_leave_queue_pending = false

	if code != 200:
		var detail := _format_nakama_error(null, raw_text)
		if not _is_benign_rpc(rpc_id):
			match_failed.emit(
				"RPC " + rpc_id + " (" + str(code) + "): " + detail
			)
		return

	if payload.is_empty():
		if rpc_id == "join_queue" or rpc_id == "queue_status":
			if _looks_like_queue_rpc_text(raw_text):
				payload = _extract_queue_fields_from_text(raw_text)
			else:
				payload = {"status": "waiting", "players": 1, "max_players": 8, "seconds_left": 60}
		elif _is_benign_rpc(rpc_id):
			return
		else:
			var preview := raw_text.substr(0, mini(160, raw_text.length())).strip_edges()
			_rpc_warn_once(
				"rpc_" + rpc_id,
				"[NetworkSession] RPC "
				+ rpc_id
				+ " illisible (HTTP "
				+ str(code)
				+ "): "
				+ preview
			)
			match_failed.emit(
				"Réponse RPC invalide (" + rpc_id + "). Aperçu : " + preview
			)
			return

	if rpc_id == "leave_queue" or rpc_id == "ping":
		return

	if rpc_id == "join_queue" or rpc_id == "queue_status":
		if rpc_id == "join_queue":
			_awaiting_join_ack = false
			if not payload.is_empty():
				_in_queue = true
		_apply_queue_payload(payload)
	elif rpc_id == "get_player_profile":
		_apply_player_profile_payload(payload)
	elif rpc_id == "get_leaderboard":
		_apply_leaderboard_payload(payload)
	elif rpc_id == "submit_match_result":
		request_player_profile()
		request_leaderboard()
	elif rpc_id == "set_username":
		if payload.is_empty():
			return
		if str(payload.get("status", "")) == "ok":
			var synced := str(payload.get("username", "")).strip_edges()
			if _is_human_username(synced):
				account_username = synced
				_session_username_override = synced
				var creds := _read_saved_credentials()
				if account_email != "" and creds.has("password"):
					_save_credentials(account_email, str(creds.get("password", "")), synced)
			return
		var err_msg := str(payload.get("message", "")).strip_edges()
		if err_msg == "":
			return
		if err_msg == "invalid_username" and _is_human_username(_session_username_override):
			return
		push_warning("[NetworkSession] set_username: " + err_msg)


func _apply_player_profile_payload(payload: Variant) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		profile_cache = {}
		profile_updated.emit(profile_cache)
		return
	profile_cache = (payload as Dictionary).duplicate(true)
	var recent_val: Variant = profile_cache.get("recent", [])
	if typeof(recent_val) == TYPE_DICTIONARY:
		profile_cache["recent"] = []
	var stats_username := str(profile_cache.get("username", "")).strip_edges()
	if _is_human_username(stats_username):
		account_username = stats_username
	elif _is_human_username(account_username):
		profile_cache["username"] = account_username
	profile_updated.emit(profile_cache)


func _apply_leaderboard_payload(payload: Variant) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		leaderboard_cache = []
	else:
		leaderboard_cache = _normalize_entries((payload as Dictionary).get("entries", []))
	profile_updated.emit(profile_cache)


func _apply_queue_payload(payload: Dictionary) -> void:
	var status := str(payload.get("status", "waiting"))
	if status == "wait":
		status = "waiting"
	var players := int(payload.get("players", 0))
	var max_p := int(payload.get("max_players", 8))
	var seconds := int(payload.get("seconds_left", 60))
	# Évite 0/8 : queue_status peut arriver avant que join_queue ait fini côté serveur.
	if status == "waiting" and players <= 0 and (_in_queue or _awaiting_join_ack):
		if _in_queue and not _awaiting_join_ack:
			_awaiting_join_ack = true
			_rpc("join_queue")
		players = 1
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
		return _normalize_game_ws_url(url)
	return FALLBACK_GAME_WS_URL


func _normalize_game_ws_url(url: String) -> String:
	var normalized := url.strip_edges()
	if normalized == "":
		return normalized
	if not normalized.ends_with("/"):
		normalized += "/"
	return normalized


func connect_to_game_server(ws_url: String = "") -> void:
	if _ws_connecting:
		print("[NetworkSession] Connexion WebSocket déjà en cours, ignorée.")
		return
	var primary_url := ws_url.strip_edges() if ws_url != "" else resolved_game_ws_url()
	if primary_url == "":
		primary_url = FALLBACK_GAME_WS_URL
	primary_url = _normalize_game_ws_url(primary_url)

	var urls_to_try: Array[String] = [primary_url]
	var dev_url := _normalize_game_ws_url(NetworkConfig.dev_game_ws_url)
	if NetworkConfig.use_dev_endpoints() or OS.has_feature("editor"):
		if dev_url != "" and dev_url != primary_url:
			urls_to_try.append(dev_url)

	_ws_connecting = true
	var last_error := ""
	for url in urls_to_try:
		for attempt in range(WS_CONNECT_RETRIES):
			var err_msg := await _try_connect_game_ws(url)
			if err_msg == "":
				_ws_connecting = false
				game_connected.emit()
				_waiting_map_after_connect = true
				_map_wait_elapsed = 0.0
				await get_tree().process_frame
				await get_tree().process_frame
				rpc_register_for_match.rpc_id(1, get_display_username())
				print(
					"[NetworkSession] WebSocket jeu connecté — enregistrement (peer %d)."
					% multiplayer.get_unique_id()
				)
				return
			last_error = err_msg
			if attempt < WS_CONNECT_RETRIES - 1:
				await get_tree().create_timer(WS_CONNECT_RETRY_DELAY_SEC).timeout

	_ws_connecting = false
	_match_handoff_started = false
	game_connection_failed.emit(last_error)


func _try_connect_game_ws(url: String) -> String:
	if _match_peer != null:
		_match_peer.close()
		_match_peer = null
	_match_peer = WebSocketMultiplayerPeer.new()
	print("[NetworkSession] Connexion WebSocket → ", url)
	var err := _match_peer.create_client(url)
	if err != OK:
		return "WebSocket client erreur %s (URL: %s)" % [str(err), url]
	multiplayer.multiplayer_peer = _match_peer
	await get_tree().process_frame

	var timeout_ms := 12000
	var start_ms := Time.get_ticks_msec()
	while true:
		var st := _match_peer.get_connection_status()
		if st == WebSocketMultiplayerPeer.CONNECTION_CONNECTED:
			return ""
		if st == WebSocketMultiplayerPeer.CONNECTION_DISCONNECTED:
			return (
				"WebSocket refusé (URL: %s). Le serveur jeu (port 9080) est-il actif ? "
				+ "VPS : systemctl status powerquest-game — Apache : ProxyPass /game/ → ws://127.0.0.1:9080/"
			) % url
		if Time.get_ticks_msec() - start_ms > timeout_ms:
			return (
				"Timeout WebSocket (%s). Vérifie powerquest-game sur le VPS (port 9080)."
			) % url
		await get_tree().create_timer(0.1).timeout
	return "Connexion WebSocket interrompue."


## Chaque client annonce sa présence ; le serveur lance la map à 2+ joueurs.
@rpc("any_peer", "reliable")
func rpc_register_for_match(display_name: String = "") -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0 or peer_id in _server_registered_peers:
		return
	register_peer_display_name(peer_id, display_name)
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
	var map_index := MapSession.pick_random_online_map_index()
	print("[NetworkSession] Lancement partie (%d joueurs, map %d)." % [player_count, map_index])
	MapSession.active_map_index = map_index
	MapSession.is_online_match = true
	MapSession.local_team = 0
	MapSession.online_player_count = player_count

	# Envoyer aux clients AVANT change_scene (sinon le WebSocket serveur était détruit).
	for peer_id in multiplayer.get_peers():
		rpc_begin_online_match.rpc_id(peer_id, player_count, map_index)
	await get_tree().create_timer(0.25).timeout

	if ServerMode.is_dedicated_server:
		get_tree().change_scene_to_file(MAIN_SCENE)
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)


func reset_server_match_state() -> void:
	_server_registered_peers.clear()
	clear_peer_display_names()
	_server_match_started = false


## Appelé par le serveur de jeu quand 2+ clients sont connectés (RPC).
@rpc("authority", "call_remote", "reliable")
func rpc_begin_online_match(
	player_count: int = MIN_PLAYERS_TO_START, map_index: int = 0
) -> void:
	if ServerMode.is_dedicated_server:
		return
	var map_idx := MapSession.normalize_online_map_index(
		map_index if map_index > 0 else MapSession.active_map_index
	)
	print("[NetworkSession] Client — démarrage map %d (%d joueurs)." % [map_idx, player_count])
	_waiting_map_after_connect = false
	_load_online_match_scene(player_count, map_idx)


func _load_online_match_scene(
	player_count: int = MIN_PLAYERS_TO_START, map_index: int = 0
) -> void:
	MapSession.active_map_index = MapSession.normalize_online_map_index(
		map_index if map_index > 0 else MapSession.active_map_index
	)
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


func _normalize_entries(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	if typeof(value) == TYPE_DICTIONARY:
		var out: Array = []
		for key in value.keys():
			var item: Variant = value[key]
			if typeof(item) == TYPE_DICTIONARY:
				out.append(item)
		return out
	return []


func _friendly_auth_error(response_code: int, parsed, raw_text: String) -> String:
	if typeof(parsed) == TYPE_DICTIONARY:
		var msg := str(parsed.get("message", "")).to_lower()
		if response_code == 401 or response_code == 403:
			return "Email ou mot de passe incorrect."
		if response_code == 409 or "already" in msg or "exists" in msg or "unique" in msg:
			if "username" in msg or "pseudo" in msg:
				return "Ce pseudo est déjà pris. Choisis-en un autre."
			return "Cet email ou ce pseudo est déjà utilisé."
		if response_code == 400:
			if "email" in msg:
				return "Format d'email invalide."
			if "password" in msg:
				return "Mot de passe invalide."
			if "username" in msg:
				return "Pseudo invalide ou déjà pris."
			return "Données invalides. Vérifie email, pseudo et mot de passe."
	if response_code == 0:
		return "Impossible de joindre le serveur. Vérifie ta connexion."
	if response_code >= 200 and response_code < 300:
		return "Réponse serveur inattendue. Réexporte le client Web puis redéploie sur le VPS."
	if typeof(parsed) == TYPE_DICTIONARY:
		var msg := str(parsed.get("message", "")).strip_edges()
		if msg != "":
			return msg
	return "Connexion refusée (HTTP %s)." % str(response_code)


func _format_nakama_error(parsed, raw_text: String) -> String:
	if typeof(parsed) == TYPE_DICTIONARY:
		if parsed.has("message") and parsed.has("code"):
			return "Nakama code %s — %s" % [
				str(parsed.get("code")), str(parsed.get("message"))
			]
	return raw_text


func _apply_account_info(parsed: Dictionary) -> void:
	if parsed.has("user") and typeof(parsed["user"]) == TYPE_DICTIONARY:
		var user: Dictionary = parsed["user"] as Dictionary
		if user.has("id"):
			user_id = str(user.get("id", user_id))
		var api_email := str(user.get("email", "")).strip_edges()
		if api_email != "":
			account_email = api_email
		if _session_username_override == "":
			var api_username := str(user.get("username", "")).strip_edges()
			if _is_human_username(api_username):
				account_username = api_username
	var root_email := str(parsed.get("email", "")).strip_edges()
	if root_email != "":
		account_email = root_email
	if _session_username_override == "":
		var root_username := str(parsed.get("username", "")).strip_edges()
		if _is_human_username(root_username):
			account_username = root_username
	else:
		account_username = _session_username_override


func _parse_jwt_payload(token: String) -> Dictionary:
	var parts := token.split(".")
	if parts.size() < 2:
		return {}
	var b64 := parts[1].replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var decoded := Marshalls.base64_to_utf8(b64)
	var parsed: Variant = _parse_json_safe(decoded)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func _handle_error(msg: String) -> void:
	_pending_auth_email = ""
	_pending_auth_password = ""
	_leave_queue_pending = false
	_pump_http_queue()
	if _in_queue:
		match_failed.emit(msg)
	elif is_authenticated:
		# Ne pas déconnecter l'utilisateur pour une erreur HTTP secondaire (ex. leave_queue).
		push_warning("[NetworkSession] " + msg)
	else:
		auth_failed.emit(msg)


func _process(_delta: float) -> void:
	# Export Web : récupère la réponse fetch() en cours (asynchrone).
	if _web_pending_id != "":
		_poll_web_request()
	if _waiting_map_after_connect:
		_map_wait_elapsed += _delta
		if _map_wait_elapsed >= MAP_WAIT_TIMEOUT:
			_waiting_map_after_connect = false
			game_connection_failed.emit(
				"La map n'a pas démarré. Ouvre un 2e onglet (Multijoueur) ou vérifie le serveur jeu (port 9080)."
			)
	if not _in_queue or not is_authenticated or _match_handoff_started or _awaiting_join_ack:
		return
	if _http_busy:
		return
	_last_queue_poll += _delta
	if _last_queue_poll < 2.0:
		return
	_last_queue_poll = 0.0
	_rpc("queue_status")
