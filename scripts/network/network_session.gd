extends Node

## Nakama client (HTTP) + game server connection (WebSocket).
## MVP: no nakama-godot addon required.

signal auth_ready
signal auth_failed(message: String)
signal session_closed
signal profile_updated(profile: Dictionary)
signal leaderboard_updated(entries: Array)
signal queue_updated(players: int, max_players: int, seconds_left: int)
signal match_ready(match_id: String, game_ws_url: String)
signal match_failed(message: String)
signal game_connected
signal game_connection_failed(message: String)
signal online_match_begin
## Account-linked preferences (language, etc.) from Nakama storage.
signal preferences_loaded(prefs: Dictionary)

const MAIN_SCENE := "res://scenes/jeu/Main.scn"
const MIN_PLAYERS_TO_START := 2
const MAX_PLAYERS_TO_START := 8
## Grace window after the 2nd player so the rest of the group can join (up to 8).
const LOBBY_START_GRACE_SEC := 5.0
const FALLBACK_GAME_WS_URL := "wss://powerquest.robinmatelot.codes/game/"
const WS_CONNECT_RETRIES := 3
const WS_CONNECT_RETRY_DELAY_SEC := 1.5
## Nakama RPC body: server expects a JSON string, not an object. Empty = two quotes.
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
## Username chosen at signup — overrides auto Nakama username (often random).
var _session_username_override: String = ""
var _leave_queue_pending: bool = false
var _awaiting_join_ack: bool = false
var _join_ack_started_ms: int = 0
var _auth_http_pending: bool = false
var _auth_http_started_ms: int = 0
var _rpc_warn_last: Dictionary = {}
var _use_browser_http: bool = false
var _web_bridge_warned: bool = false
var _web_pending_id: String = ""
var _web_request_started_ms: int = 0
var _web_http_retry_scheduled: bool = false
var _auto_reconnect_running: bool = false
const WEB_HTTP_TIMEOUT_MS := 15000
const JOIN_ACK_TIMEOUT_MS := 20000
const AUTH_HTTP_TIMEOUT_MS := 25000
const WEB_CREDS_STORAGE_KEY := "pq_account_credentials"
const WEB_SESSION_STORAGE_KEY := "pq_session_state"

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
	# --server binary does not need the Nakama / HTTP client.
	if ServerMode.is_dedicated_server:
		return
	_use_browser_http = WebNakamaHttp.is_available()
	if _use_browser_http:
		# Inject fetch() bridge at runtime (independent of index.html / export_presets).
		if not WebNakamaHttp.ensure_bridge():
			_use_browser_http = false
			call_deferred("_warn_missing_web_bridge")
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_load_or_create_device_id()
	call_deferred("_run_auto_reconnect_attempt")


func _ensure_web_http_ready() -> bool:
	if not OS.has_feature("web") or not WebNakamaHttp.is_available():
		return false
	if WebNakamaHttp.ensure_bridge():
		_use_browser_http = true
		return true
	_use_browser_http = false
	return false


func _run_auto_reconnect_attempt(attempt: int = 0) -> void:
	if _auto_reconnect_running and attempt == 0:
		return
	if attempt == 0:
		_auto_reconnect_running = true
	if is_account_logged_in():
		_auto_reconnect_running = false
		return
	if OS.has_feature("web"):
		WebNakamaHttp.ensure_bridge()
		await get_tree().process_frame
		await get_tree().process_frame
	if _try_restore_persisted_session():
		_auto_reconnect_running = false
		return
	if not has_saved_account_credentials():
		if OS.has_feature("web") and attempt < 20:
			await get_tree().create_timer(0.2).timeout
			_run_auto_reconnect_attempt(attempt + 1)
			return
		_auto_reconnect_running = false
		return
	if OS.has_feature("web"):
		_ensure_web_http_ready()
		if not WebNakamaHttp.bridge_ready() and attempt < 24:
			await get_tree().create_timer(0.25).timeout
			_run_auto_reconnect_attempt(attempt + 1)
			return
	await _authenticate_with_saved_credentials()
	_auto_reconnect_running = false


func _try_auto_reconnect() -> void:
	_run_auto_reconnect_attempt()


func authenticate_and_wait() -> void:
	await _authenticate_with_saved_credentials()


func is_account_logged_in() -> bool:
	return is_authenticated and _auth_mode == "account" and session_token != ""


func has_saved_account_credentials() -> bool:
	return _credentials_are_usable(_read_saved_credentials())


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
	return "Player"


func sanitize_display_username(value: String) -> String:
	var cleaned := value.strip_edges()
	if _is_human_username(cleaned):
		return cleaned
	return ""


func register_peer_display_name(peer_id: int, display_name: String) -> void:
	var cleaned := sanitize_display_username(display_name)
	if cleaned == "":
		cleaned = "Player %d" % peer_id
	_peer_display_names[peer_id] = cleaned


func get_peer_display_name(peer_id: int) -> String:
	return str(_peer_display_names.get(peer_id, "Player %d" % peer_id))


func clear_peer_display_names() -> void:
	_peer_display_names.clear()


func _is_human_username(value: String) -> bool:
	if value == "":
		return false
	if value.length() < 2 or value.length() > 20:
		return false
	# Avoid showing a UUID / technical id instead of the display name.
	if value.length() >= 32 and value.count("-") >= 4:
		return false
	return true


func register_account(email: String, password: String, username: String) -> void:
	var e := AuthValidation.sanitize_email(email)
	var p := password
	var u := AuthValidation.sanitize_username(username)
	if e == "" or p == "" or u == "":
		auth_failed.emit(tr("AUTH_NEED_FIELDS"))
		return
	if not AuthValidation.is_valid_email(e):
		auth_failed.emit(tr("AUTH_INVALID_EMAIL"))
		return
	if not AuthValidation.is_valid_username(u):
		auth_failed.emit(tr("AUTH_USERNAME_RULES"))
		return
	var pwd_err := AuthValidation.is_valid_password(p)
	if pwd_err != "":
		auth_failed.emit(pwd_err)
		return
	_pending_auth_email = e
	_pending_auth_password = p
	_pending_auth_username = u
	_session_username_override = u
	_begin_auth_http_request()
	# Nakama: username in query AND body (depends on version / proxy).
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
		auth_failed.emit(tr("AUTH_NEED_EMAIL_PWD"))
		return
	if not AuthValidation.is_valid_email(e):
		auth_failed.emit(tr("AUTH_INVALID_EMAIL"))
		return
	var pwd_err := AuthValidation.is_valid_password(p)
	if pwd_err != "":
		auth_failed.emit(pwd_err)
		return
	_pending_auth_email = e
	_pending_auth_password = p
	_apply_saved_username_hints(e)
	_begin_auth_http_request()
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
	leaderboard_updated.emit(leaderboard_cache)
	_delete_saved_credentials()
	_delete_persisted_session()
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


## --- Account-linked preferences (native Nakama storage, no server module) ---

const PREFS_COLLECTION := "pq_prefs"
const PREFS_KEY := "settings"


## Read account preferences (language, etc.) → emits preferences_loaded.
func request_account_preferences() -> void:
	if not is_account_logged_in():
		return
	var body := JSON.stringify({
		"object_ids": [{"collection": PREFS_COLLECTION, "key": PREFS_KEY}]
	})
	_enqueue_http({
		"kind": "prefs_read",
		"url": "%s/v2/storage" % NetworkConfig.nakama_base_url(),
		"method": HTTPClient.METHOD_POST,
		"headers": _nakama_headers(true),
		"body": body,
	})


## Write account preferences (best-effort: failure is non-blocking).
func save_account_preferences(prefs: Dictionary) -> void:
	if not is_account_logged_in():
		return
	var body := JSON.stringify({
		"objects": [{
			"collection": PREFS_COLLECTION,
			"key": PREFS_KEY,
			"value": JSON.stringify(prefs),
			"permission_read": 1,
			"permission_write": 1,
		}]
	})
	_enqueue_http({
		"kind": "prefs_write",
		"url": "%s/v2/storage" % NetworkConfig.nakama_base_url(),
		"method": HTTPClient.METHOD_PUT,
		"headers": _nakama_headers(true),
		"body": body,
	})


func _extract_prefs_from_storage(parsed: Variant, raw_text: String) -> Dictionary:
	var objects: Array = []
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("objects"):
		var o: Variant = parsed["objects"]
		if typeof(o) == TYPE_ARRAY:
			objects = o
	if objects.is_empty():
		return _extract_prefs_from_text(raw_text)
	var first: Variant = objects[0]
	if typeof(first) != TYPE_DICTIONARY:
		return {}
	var value_variant: Variant = (first as Dictionary).get("value", "")
	if typeof(value_variant) == TYPE_DICTIONARY:
		return value_variant as Dictionary
	var decoded: Variant = _parse_json_safe(str(value_variant))
	if typeof(decoded) == TYPE_DICTIONARY:
		return decoded as Dictionary
	return _extract_prefs_from_text(raw_text)


## Web fallback: extract "language":"xx" from raw text (possibly escaped).
func _extract_prefs_from_text(text: String) -> Dictionary:
	var out := {}
	if text.is_empty():
		return out
	var re := RegEx.new()
	if re.compile("\\\\?\"language\\\\?\"\\s*:\\s*\\\\?\"([a-zA-Z]{2})\\\\?\"") == OK:
		var m := re.search(text)
		if m:
			out["language"] = m.get_string(1)
	return out


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


func _begin_auth_http_request() -> void:
	_auth_http_pending = true
	_auth_http_started_ms = Time.get_ticks_msec()
	if OS.has_feature("web"):
		_ensure_web_http_ready()


func _clear_auth_http_pending() -> void:
	_auth_http_pending = false
	_auth_http_started_ms = 0


func _complete_auth_success() -> void:
	_clear_auth_http_pending()
	if profile_cache.is_empty():
		profile_cache = {}
	var display_name := get_display_username()
	if display_name != "Player":
		profile_cache["username"] = display_name
		profile_updated.emit(profile_cache.duplicate(true))
	_save_persisted_session()
	auth_ready.emit()
	call_deferred("_fetch_post_auth_data")


func _fetch_post_auth_data() -> void:
	if not is_account_logged_in():
		return
	request_account_info()
	request_player_profile()
	request_leaderboard()


func request_leaderboard(limit: int = 20) -> void:
	if not is_authenticated:
		return
	var payload := JSON.stringify({"limit": clampi(limit, 1, 100)})
	_rpc("get_leaderboard", payload)


func _credentials_are_usable(creds: Dictionary) -> bool:
	return (
		str(creds.get("email", "")).strip_edges() != ""
		and str(creds.get("password", "")) != ""
	)


func _read_saved_credentials() -> Dictionary:
	# Web: localStorage is authoritative (IndexedDB user:// may be empty or stale).
	if OS.has_feature("web"):
		var from_web := _read_web_saved_credentials()
		if _credentials_are_usable(from_web):
			return from_web
	var from_file := _read_credentials_file()
	if _credentials_are_usable(from_file):
		return from_file
	if FileAccess.file_exists("user://account_credentials.json"):
		DirAccess.remove_absolute("user://account_credentials.json")
	if not OS.has_feature("web"):
		var from_web := _read_web_saved_credentials()
		if _credentials_are_usable(from_web):
			return from_web
	return {}


func _read_credentials_file() -> Dictionary:
	if not FileAccess.file_exists("user://account_credentials.json"):
		return {}
	var parsed: Variant = _parse_json_safe(
		FileAccess.get_file_as_string("user://account_credentials.json")
	)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func _read_web_saved_credentials() -> Dictionary:
	return _read_web_storage(WEB_CREDS_STORAGE_KEY)


func _read_web_storage(storage_key: String) -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw_str := ""
	if WebNakamaHttp.is_available():
		WebNakamaHttp.ensure_bridge()
		raw_str = WebNakamaHttp.ls_get(storage_key).strip_edges()
	if raw_str.is_empty() and ClassDB.class_exists("JavaScriptBridge"):
		var payload := JSON.stringify({"key": storage_key})
		var raw: Variant = JavaScriptBridge.eval(
			"(function(p){try{return localStorage.getItem(p.key)||'';}catch(e){return '';}})("
			+ payload
			+ ")",
			true
		)
		if raw != null:
			raw_str = str(raw).strip_edges()
	if raw_str.is_empty():
		return {}
	return _decode_web_storage_json(raw_str)


func _decode_web_storage_json(raw_str: String) -> Dictionary:
	var parsed: Variant = _parse_json_safe(raw_str)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	if typeof(parsed) == TYPE_STRING:
		var inner: Variant = _parse_json_safe(str(parsed))
		if typeof(inner) == TYPE_DICTIONARY:
			return inner as Dictionary
	return _extract_credentials_from_text(raw_str)


func _extract_credentials_from_text(text: String) -> Dictionary:
	var out := {}
	if text.is_empty():
		return out
	var email_re := RegEx.new()
	if email_re.compile("\"email\"\\s*:\\s*\"([^\"]+)\"") == OK:
		var em := email_re.search(text)
		if em:
			out["email"] = em.get_string(1)
	var pass_re := RegEx.new()
	if pass_re.compile("\"password\"\\s*:\\s*\"([^\"]*)\"") == OK:
		var pm := pass_re.search(text)
		if pm:
			out["password"] = pm.get_string(1)
	var user_re := RegEx.new()
	if user_re.compile("\"username\"\\s*:\\s*\"([^\"]+)\"") == OK:
		var um := user_re.search(text)
		if um:
			out["username"] = um.get_string(1)
	return out


func _write_web_storage(storage_key: String, json_text: String) -> void:
	if not OS.has_feature("web") or json_text.is_empty():
		return
	if WebNakamaHttp.is_available():
		WebNakamaHttp.ls_set(storage_key, json_text)
		return
	if not ClassDB.class_exists("JavaScriptBridge"):
		return
	var payload := JSON.stringify({"key": storage_key, "value": json_text})
	JavaScriptBridge.eval(
		"(function(p){try{localStorage.setItem(p.key,p.value);}catch(e){}})(" + payload + ")",
		true
	)


func _remove_web_storage(storage_key: String) -> void:
	if not OS.has_feature("web"):
		return
	if WebNakamaHttp.is_available():
		WebNakamaHttp.ls_del(storage_key)
		return
	if not ClassDB.class_exists("JavaScriptBridge"):
		return
	var payload := JSON.stringify({"key": storage_key})
	JavaScriptBridge.eval(
		"(function(p){try{localStorage.removeItem(p.key);}catch(e){}})(" + payload + ")",
		true
	)


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
	var json_text := JSON.stringify(data)
	var f := FileAccess.open("user://account_credentials.json", FileAccess.WRITE)
	if f != null:
		f.store_string(json_text)
	_save_web_credentials(json_text)


func _save_web_credentials(json_text: String) -> void:
	_write_web_storage(WEB_CREDS_STORAGE_KEY, json_text)


func _save_persisted_session() -> void:
	if not is_account_logged_in():
		return
	var data := {
		"token": session_token,
		"user_id": user_id,
		"email": account_email,
		"username": account_username,
		"auth_mode": _auth_mode,
	}
	var json_text := JSON.stringify(data)
	var file := FileAccess.open("user://session_state.json", FileAccess.WRITE)
	if file != null:
		file.store_string(json_text)
	_write_web_storage(WEB_SESSION_STORAGE_KEY, json_text)


func _session_data_is_usable(data: Dictionary) -> bool:
	var token := str(data.get("token", "")).strip_edges()
	if token.is_empty():
		return false
	if str(data.get("auth_mode", "account")) != "account":
		return false
	return not _jwt_is_expired(token)


func _read_persisted_session() -> Dictionary:
	if OS.has_feature("web"):
		var from_web := _read_web_storage(WEB_SESSION_STORAGE_KEY)
		if _session_data_is_usable(from_web):
			return from_web
		if not from_web.is_empty() or WebNakamaHttp.ls_get(WEB_SESSION_STORAGE_KEY) != "":
			_remove_web_storage(WEB_SESSION_STORAGE_KEY)
	var from_file := _read_session_file()
	if _session_data_is_usable(from_file):
		return from_file
	if FileAccess.file_exists("user://session_state.json"):
		DirAccess.remove_absolute("user://session_state.json")
	if not OS.has_feature("web"):
		var from_web := _read_web_storage(WEB_SESSION_STORAGE_KEY)
		if _session_data_is_usable(from_web):
			return from_web
	return {}


func _read_session_file() -> Dictionary:
	if not FileAccess.file_exists("user://session_state.json"):
		return {}
	var parsed: Variant = _parse_json_safe(
		FileAccess.get_file_as_string("user://session_state.json")
	)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func _delete_persisted_session() -> void:
	if FileAccess.file_exists("user://session_state.json"):
		DirAccess.remove_absolute("user://session_state.json")
	_remove_web_storage(WEB_SESSION_STORAGE_KEY)


func _try_restore_persisted_session() -> bool:
	var data := _read_persisted_session()
	if data.is_empty():
		return false
	var token := str(data.get("token", "")).strip_edges()
	session_token = token
	user_id = str(data.get("user_id", ""))
	account_email = str(data.get("email", ""))
	account_username = str(data.get("username", ""))
	_auth_mode = str(data.get("auth_mode", "account"))
	if _auth_mode != "account":
		return false
	is_authenticated = true
	if _is_human_username(account_username):
		_session_username_override = account_username
	_complete_auth_success()
	return true


func _delete_saved_credentials() -> void:
	if FileAccess.file_exists("user://account_credentials.json"):
		DirAccess.remove_absolute("user://account_credentials.json")
	_remove_web_storage(WEB_CREDS_STORAGE_KEY)


func _load_or_create_device_id() -> void:
	# Nakama requires a device id between 10 and 128 characters.
	const MIN_LEN := 10
	const MAX_LEN := 128
	if OS.has_feature("web"):
		# Browser: one persistent id + per-tab suffix (sessionStorage) for two-tab testing.
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
	var parsed := _read_saved_credentials()
	if not _credentials_are_usable(parsed):
		auth_failed.emit(tr("AUTH_LOGIN_FIRST"))
		return
	var email := str(parsed.get("email", ""))
	_apply_saved_username_hints(email)
	login_account(email, str(parsed.get("password", "")))


func _authenticate_with_saved_credentials() -> void:
	if is_account_logged_in():
		auth_ready.emit()
		return
	var parsed := _read_saved_credentials()
	if not _credentials_are_usable(parsed):
		return
	var finished := false
	var on_ready := func() -> void:
		finished = true
	var on_failed := func(_message: String) -> void:
		finished = true
	if not auth_ready.is_connected(on_ready):
		auth_ready.connect(on_ready, CONNECT_ONE_SHOT)
	if not auth_failed.is_connected(on_failed):
		auth_failed.connect(on_failed, CONNECT_ONE_SHOT)
	authenticate()
	var deadline_ms := Time.get_ticks_msec() + 20000
	while not finished and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
	if auth_ready.is_connected(on_ready):
		auth_ready.disconnect(on_ready)
	if auth_failed.is_connected(on_failed):
		auth_failed.disconnect(on_failed)
	if not finished:
		if is_account_logged_in():
			auth_ready.emit()
		elif _credentials_are_usable(_read_saved_credentials()):
			auth_failed.emit(tr("AUTH_TIMEOUT"))


func join_ranked_queue() -> void:
	if not is_account_logged_in():
		match_failed.emit(tr("AUTH_ACCOUNT_REQUIRED"))
		return
	_awaiting_join_ack = true
	_join_ack_started_ms = Time.get_ticks_msec()
	_in_queue = false
	_match_handoff_started = false
	_rpc("join_queue")


func leave_ranked_queue() -> void:
	_in_queue = false
	_awaiting_join_ack = false
	_join_ack_started_ms = 0
	_match_handoff_started = false
	_ws_connecting = false
	if not is_authenticated or session_token == "":
		return
	if _leave_queue_pending:
		return
	_leave_queue_pending = true
	_rpc("leave_queue")


## inner_json: serialized JSON object (e.g. '{"limit":20}').
## Nakama HTTP RPC expects payload as an encoded JSON STRING → we (re)stringify.
## Otherwise: 400 "cannot unmarshal object into Go value of type string".
func _rpc(id: String, inner_json: String = "") -> void:
	var url := "%s/v2/rpc/%s" % [NetworkConfig.nakama_base_url(), id]
	var headers := _nakama_headers(true)
	var body := NAKAMA_RPC_BODY_EMPTY if inner_json == "" else JSON.stringify(inner_json)
	_enqueue_http({"kind": "rpc", "rpc_id": id, "url": url, "headers": headers, "body": body})


func _enqueue_http(job: Dictionary) -> void:
	var kind := str(job.get("kind", ""))
	if kind == "auth_account":
		_http_queue.push_front(job)
		_pump_http_queue()
		return
	if kind == "rpc":
		var rpc_id := str(job.get("rpc_id", ""))
		if rpc_id in ["join_queue", "queue_status", "leave_queue"]:
			_http_queue.push_front(job)
			_pump_http_queue()
			return
	_http_queue.append(job)
	_pump_http_queue()


func _warn_missing_web_bridge() -> void:
	if _web_bridge_warned:
		return
	_web_bridge_warned = true
	push_warning(
		"[NetworkSession] fetch() bridge not injected — falling back to Godot HTTPRequest."
	)


func _pump_http_queue() -> void:
	if _http_busy or _http_queue.is_empty():
		return
	if _web_pending_id != "":
		return
	var job: Dictionary = _http_queue.pop_front()
	if OS.has_feature("web"):
		_ensure_web_http_ready()
		if WebNakamaHttp.bridge_ready():
			_start_web_request(job)
			return
		_http_queue.push_front(job)
		_schedule_web_http_retry()
		return
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


func _schedule_web_http_retry() -> void:
	if _web_http_retry_scheduled:
		return
	_web_http_retry_scheduled = true
	var timer := get_tree().create_timer(0.3)
	timer.timeout.connect(func() -> void:
		_web_http_retry_scheduled = false
		_pump_http_queue()
	, CONNECT_ONE_SHOT)


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


## Web export: send via browser fetch() (async); response read in _poll_web_request().
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
		_handle_error("Web network unavailable (window.PQ bridge).")
		_pump_http_queue()


func _poll_web_request() -> void:
	if _web_pending_id == "":
		return
	var res := WebNakamaHttp.poll(_web_pending_id)
	if res.is_empty():
		if Time.get_ticks_msec() - _web_request_started_ms > WEB_HTTP_TIMEOUT_MS:
			_web_pending_id = ""
			_http_busy = false
			_handle_error("Web network timeout (Nakama unreachable).")
			_pump_http_queue()
		return
	_web_pending_id = ""
	var response_code := int(res.get("status", 0))
	var text := str(res.get("text", ""))
	if not bool(res.get("ok", false)) and response_code == 0:
		_http_busy = false
		_handle_error("Web network: " + str(res.get("error", "fetch failed")))
		_pump_http_queue()
		return
	# _on_http_completed clears _http_busy and resumes the pump.
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
	# Web export: null bytes in body → JSON.parse fails even when token is present.
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


## Web fallback: extract "username":"..." from raw text when JSON.parse fails.
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
	# Web export: do not request gzip (else Godot error code 8 / stream_peer_gzip).
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

	# Auth: token may be present even when JSON.parse fails (Web export / WASM).
	if http_kind == "auth_account":
		var was_registration := bool(_http.get_meta("is_registration", false)) if _http.has_meta("is_registration") else false
		if _http.has_meta("is_registration"):
			_http.remove_meta("is_registration")
		if _http_is_success(response_code):
			var fields: Dictionary
			if typeof(parsed) == TYPE_DICTIONARY:
				fields = parsed as Dictionary
			else:
				fields = _extract_auth_fields_from_text(text)
			if _apply_auth_session_from_fields(fields, was_registration):
				_pump_http_queue()
				return
		_clear_auth_http_pending()
		_handle_error(_friendly_auth_error(response_code, parsed, text))
		_pump_http_queue()
		return

	# Account preferences (Nakama storage). Best-effort: non-blocking on failure.
	if http_kind == "prefs_write":
		_pump_http_queue()
		return
	if http_kind == "prefs_read":
		if _http_is_success(response_code):
			preferences_loaded.emit(_extract_prefs_from_storage(parsed, text))
		_pump_http_queue()
		return

	# Nakama sometimes returns HTTP 200/204 with empty body (e.g. PUT account) — not an error.
	if parsed == null and _http_is_success(response_code):
		if http_kind == "account_info":
			# Web fallback: if JSON did not parse, try extracting username from raw text.
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
			"[NetworkSession] Non-JSON HTTP response "
			+ str(response_code)
			+ " : "
			+ preview
		)
		_handle_error(
			"Unreadable server response (HTTP " + str(response_code) + "). Re-export the Web client."
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
		# Web export: payload string sometimes keeps literal \".
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
	# Godot/WASM parse failed: extract payload string manually then re-parse.
	var inner_text := _extract_payload_string_literal(text)
	if inner_text != "":
		var inner_parsed: Variant = _parse_json_safe(inner_text)
		if typeof(inner_parsed) == TYPE_DICTIONARY:
			return inner_parsed
	# RPC response without envelope, or truncated JSON.
	var direct: Variant = _parse_json_safe(_extract_json_object_text(text))
	if typeof(direct) == TYPE_DICTIONARY:
		return direct
	# Detect "left" ONLY on the real value "status":"left"
	# (else "seconds_left" triggers a false positive → 0/8).
	if _text_has_status_left(text):
		return {"status": "left", "players": 0}
	if _looks_like_queue_rpc_text(text):
		return _extract_queue_fields_from_text(text)
	return null


func _text_has_status_left(text: String) -> bool:
	# Handles escaped ("status":"left") and unescaped (\"status\":\"left\") JSON.
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
	# Unescape first: RPC payloads often arrive as escaped JSON
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


func _extract_json_float_field(text: String, field: String) -> float:
	var re := RegEx.new()
	if re.compile('"' + field + '"\\s*:\\s*([0-9]+\\.?[0-9]*)') != OK:
		return -1.0
	var m := re.search(text.replace('\\"', '"'))
	if m == null:
		return -1.0
	return float(m.get_string(1))


func _extract_recent_from_text(text: String) -> Array:
	var out: Array = []
	var t := text.replace('\\"', '"')
	var re := RegEx.new()
	if re.compile('"recent"\\s*:\\s*\\[([^\\]]*)\\]') != OK:
		return out
	var m := re.search(t)
	if m == null:
		return out
	for part in m.get_string(1).split(","):
		var token := part.strip_edges().replace("\"", "")
		if token == "W" or token == "L":
			out.append(token)
	return out


func _extract_profile_from_text(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var parsed: Variant = _parse_json_safe(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed as Dictionary
		if d.has("payload"):
			var inner: Variant = _decode_nakama_rpc_payload(d)
			if typeof(inner) == TYPE_DICTIONARY:
				return inner as Dictionary
		if d.has("games") or d.has("wins") or d.has("recent"):
			return d
	var inner_text := _extract_payload_string_literal(text)
	if inner_text != "":
		var inner_parsed: Variant = _parse_json_safe(inner_text)
		if typeof(inner_parsed) == TYPE_DICTIONARY:
			return inner_parsed as Dictionary
	var t := text.replace('\\"', '"')
	var out := {}
	for key in ["games", "wins", "losses", "total_seconds", "level"]:
		var iv := _extract_json_int_field(t, key)
		if iv >= 0:
			out[key] = iv
	var wr := _extract_json_float_field(t, "winrate")
	if wr >= 0.0:
		out["winrate"] = wr
	var recent := _extract_recent_from_text(text)
	if not recent.is_empty():
		out["recent"] = recent
	var user_re := RegEx.new()
	if user_re.compile('"username"\\s*:\\s*"([^"]+)"') == OK:
		var um := user_re.search(t)
		if um:
			out["username"] = um.get_string(1)
	return out


func _extract_leaderboard_from_text(text: String) -> Dictionary:
	if text.is_empty():
		return {"entries": []}
	var parsed: Variant = _parse_json_safe(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed as Dictionary
		var inner: Variant = _decode_nakama_rpc_payload(d)
		if typeof(inner) == TYPE_DICTIONARY:
			d = inner as Dictionary
		if d.has("entries"):
			var entries := _normalize_entries(d.get("entries", []))
			if not entries.is_empty():
				return {"entries": entries}
	var inner_text := _extract_payload_string_literal(text)
	if inner_text != "":
		var inner_parsed: Variant = _parse_json_safe(inner_text)
		if typeof(inner_parsed) == TYPE_DICTIONARY:
			var entries := _normalize_entries((inner_parsed as Dictionary).get("entries", []))
			if not entries.is_empty():
				return {"entries": entries}
	var loose := _extract_leaderboard_entries_loose(text)
	if not loose.is_empty():
		return {"entries": loose}
	return {"entries": []}


func _extract_leaderboard_entries_loose(text: String) -> Array:
	var t := text.replace('\\"', '"').replace("\\\\", "\\")
	var entries: Array = []
	var block_re := RegEx.new()
	if block_re.compile('\\{[^{}]*"wins"\\s*:\\s*\\d+[^{}]*\\}') != OK:
		return entries
	var pos := 0
	var wins_re := RegEx.new()
	var user_re := RegEx.new()
	var uid_re := RegEx.new()
	if wins_re.compile('"wins"\\s*:\\s*(\\d+)') != OK:
		return entries
	user_re.compile('"username"\\s*:\\s*"([^"]*)"')
	uid_re.compile('"user_id"\\s*:\\s*"([^"]+)"')
	while true:
		var bm := block_re.search(t, pos)
		if bm == null:
			break
		var block := bm.get_string(0)
		pos = bm.get_end()
		var wins := 0
		var wm := wins_re.search(block)
		if wm:
			wins = int(wm.get_string(1))
		var display_name := ""
		var um := user_re.search(block)
		if um:
			display_name = um.get_string(1).strip_edges()
		var uid := ""
		var uid_m := uid_re.search(block)
		if uid_m:
			uid = uid_m.get_string(1).strip_edges()
		if display_name == "" or display_name == uid:
			if uid.length() >= 6:
				display_name = "Joueur %s" % uid.substr(0, 6)
			else:
				display_name = "Joueur"
		var row := {"username": display_name, "wins": wins}
		if uid != "":
			row["user_id"] = uid
		entries.append(row)
	return entries


func _normalize_profile_cache() -> void:
	profile_cache["games"] = int(profile_cache.get("games", 0))
	profile_cache["wins"] = int(profile_cache.get("wins", 0))
	profile_cache["losses"] = int(profile_cache.get("losses", 0))
	profile_cache["total_seconds"] = int(profile_cache.get("total_seconds", 0))
	profile_cache["winrate"] = float(profile_cache.get("winrate", 0.0))
	profile_cache["level"] = int(profile_cache.get("level", 0))
	var games := int(profile_cache["games"])
	var wins := int(profile_cache["wins"])
	if wins <= 0 and games > 0 and float(profile_cache["winrate"]) > 0.0:
		profile_cache["wins"] = int(round(float(games) * float(profile_cache["winrate"]) / 100.0))
	var recent_val: Variant = profile_cache.get("recent", [])
	if typeof(recent_val) == TYPE_DICTIONARY:
		profile_cache["recent"] = (recent_val as Dictionary).get("items", [])
	elif typeof(recent_val) != TYPE_ARRAY:
		profile_cache["recent"] = []
	games = int(profile_cache.get("games", 0))
	wins = int(profile_cache.get("wins", 0))
	if games > 0 and wins >= 0 and float(profile_cache.get("winrate", 0.0)) <= 0.0:
		profile_cache["winrate"] = float(wins) / float(games) * 100.0


func _merge_profile_stats_from_server(data: Dictionary) -> void:
	if data.is_empty():
		return
	if profile_cache.is_empty():
		profile_cache = {}
	for key in ["games", "wins", "losses", "total_seconds", "level"]:
		if data.has(key):
			profile_cache[key] = int(data[key])
	if data.has("winrate"):
		profile_cache["winrate"] = float(data["winrate"])
	if data.has("recent"):
		var recent_val: Variant = data["recent"]
		if typeof(recent_val) == TYPE_ARRAY:
			profile_cache["recent"] = recent_val
	_normalize_profile_cache()


func get_leaderboard_display_name(entry: Dictionary) -> String:
	return _leaderboard_display_name(entry)


func _leaderboard_display_name(entry: Dictionary) -> String:
	var name := str(entry.get("username", "")).strip_edges()
	if _is_human_username(name):
		return name
	name = str(entry.get("display_name", "")).strip_edges()
	if _is_human_username(name):
		return name
	var uid := str(entry.get("user_id", "")).strip_edges()
	if uid.length() >= 6:
		return "Joueur %s" % uid.substr(0, 6)
	return "Joueur"


func _normalize_leaderboard_entries(entries: Array) -> Array:
	var out: Array = []
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = (item as Dictionary).duplicate(true)
		if int(e.get("wins", -1)) < 0:
			var wr_score := float(e.get("winrate", 0.0))
			if wr_score > 100.0:
				e["wins"] = int(e.get("subscore", 0))
			else:
				e["wins"] = int(e.get("score", e.get("subscore", 0)))
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("wins", 0)) > int(b.get("wins", 0))
	)
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
		if rpc_id == "get_player_profile":
			payload = _extract_profile_from_text(raw_text)
		elif rpc_id == "get_leaderboard":
			payload = _extract_leaderboard_from_text(raw_text)
		elif rpc_id == "join_queue" or rpc_id == "queue_status":
			if _looks_like_queue_rpc_text(raw_text):
				payload = _extract_queue_fields_from_text(raw_text)
			else:
				payload = {"status": "waiting", "players": 1, "max_players": 8, "seconds_left": 60}
		elif rpc_id == "submit_match_result":
			request_player_profile()
			request_leaderboard()
			return
		elif _is_benign_rpc(rpc_id):
			return
		else:
			var preview := raw_text.substr(0, mini(160, raw_text.length())).strip_edges()
			_rpc_warn_once(
				"rpc_" + rpc_id,
				"[NetworkSession] RPC "
				+ rpc_id
				+ " unreadable (HTTP "
				+ str(code)
				+ "): "
				+ preview
			)
			match_failed.emit(
				"Invalid RPC response (" + rpc_id + "). Preview: " + preview
			)
			return

	if rpc_id == "leave_queue" or rpc_id == "ping":
		return

	if rpc_id == "join_queue" or rpc_id == "queue_status":
		if rpc_id == "join_queue":
			_awaiting_join_ack = false
			_join_ack_started_ms = 0
			if not payload.is_empty():
				_in_queue = true
		_apply_queue_payload(payload)
	elif rpc_id == "get_player_profile":
		if int(payload.get("games", 0)) <= 0 and int(payload.get("wins", 0)) <= 0:
			var extracted := _extract_profile_from_text(raw_text)
			if not extracted.is_empty():
				for key in extracted.keys():
					payload[key] = extracted[key]
		_apply_player_profile_payload(payload)
	elif rpc_id == "get_leaderboard":
		var lb_entries := _normalize_entries(payload.get("entries", []))
		if lb_entries.is_empty():
			var extracted := _extract_leaderboard_from_text(raw_text)
			if not extracted.is_empty():
				payload = extracted
			elif typeof(payload.get("entries", null)) == TYPE_DICTIONARY:
				payload = {"entries": []}
		_apply_leaderboard_payload(payload)
	elif rpc_id == "submit_match_result":
		if not payload.is_empty() and payload.has("games"):
			_merge_profile_stats_from_server(payload)
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
	if typeof(payload) != TYPE_DICTIONARY or (payload as Dictionary).is_empty():
		profile_cache = {}
		profile_updated.emit(profile_cache)
		return
	profile_cache = (payload as Dictionary).duplicate(true)
	_normalize_profile_cache()
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
		leaderboard_cache = _normalize_leaderboard_entries(
			_normalize_entries((payload as Dictionary).get("entries", []))
		)
	leaderboard_updated.emit(leaderboard_cache)
	profile_updated.emit(profile_cache)


func _apply_queue_payload(payload: Dictionary) -> void:
	var status := str(payload.get("status", "waiting"))
	if status == "wait":
		status = "waiting"
	var players := int(payload.get("players", 0))
	var max_p := int(payload.get("max_players", 8))
	var seconds := int(payload.get("seconds_left", 60))
	# Avoid 0/8: queue_status may arrive before join_queue finishes on the server.
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
		print("[NetworkSession] Match ready — ws=%s" % ws)
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
		print("[NetworkSession] WebSocket connection already in progress, ignored.")
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
				_retry_register_while_waiting()
				print(
					"[NetworkSession] Game WebSocket connected — registering (peer %d)."
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
	print("[NetworkSession] Connecting WebSocket → ", url)
	var err := _match_peer.create_client(url)
	if err != OK:
		return "WebSocket client error %s (URL: %s)" % [str(err), url]
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
				"WebSocket refused (URL: %s). Is the game server (port 9080) running? "
				+ "VPS : systemctl status powerquest-game — Apache : ProxyPass /game/ → ws://127.0.0.1:9080/"
			) % url
		if Time.get_ticks_msec() - start_ms > timeout_ms:
			return (
				"WebSocket timeout (%s). Check powerquest-game on the VPS (port 9080)."
			) % url
		await get_tree().create_timer(0.1).timeout
	return "WebSocket connection interrupted."


func _retry_register_while_waiting() -> void:
	for attempt in range(4):
		await get_tree().create_timer(3.0).timeout
		if not _waiting_map_after_connect:
			return
		if _match_peer == null:
			continue
		if _match_peer.get_connection_status() != WebSocketMultiplayerPeer.CONNECTION_CONNECTED:
			continue
		print(
			"[NetworkSession] Re-registering with server (attempt %d)."
			% (attempt + 2)
		)
		rpc_register_for_match.rpc_id(1, get_display_username())


## Each client announces presence; server starts the map at 2+ players.
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
		"[NetworkSession] Client registered peer %d (%d connected, max %d)."
		% [peer_id, _server_registered_peers.size(), MAX_PLAYERS_TO_START]
	)
	_consider_match_start()


## WebSocket peer lives on this autoload to survive change_scene (dedicated server).
func attach_server_peer(peer: WebSocketMultiplayerPeer) -> void:
	_match_peer = peer
	multiplayer.multiplayer_peer = peer
	if not peer.peer_connected.is_connected(_on_server_peer_connected):
		peer.peer_connected.connect(_on_server_peer_connected)
	if not peer.peer_disconnected.is_connected(_on_server_peer_disconnected):
		peer.peer_disconnected.connect(_on_server_peer_disconnected)
	print("[NetworkSession] Server peer attached (autoload — survives change_scene).")


func _on_server_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[NetworkSession] WebSocket client connected: ", peer_id)
	_consider_match_start()


func _on_server_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[NetworkSession] WebSocket client disconnected: ", peer_id)
	_server_registered_peers.erase(peer_id)
	if _server_match_started and MapSession.is_online_match and MapSession.online_camps_ready:
		OnlineGameSync.handle_player_abandoned(peer_id)
	if multiplayer.get_peers().is_empty():
		reset_server_match_state()


## Present player count (registered or connected peers as fallback).
func _current_player_count() -> int:
	return maxi(_server_registered_peers.size(), multiplayer.get_peers().size())


## Decide when to start: immediately if full (8), else after a grace window
## once minimum is met (lets the rest of the group connect, up to 8).
func _consider_match_start() -> void:
	if _server_match_started:
		return
	var count := _current_player_count()
	if count >= MAX_PLAYERS_TO_START:
		print("[NetworkSession] Lobby full (%d) — starting immediately." % count)
		server_begin_online_match(MAX_PLAYERS_TO_START)
		return
	if count >= MIN_PLAYERS_TO_START:
		_schedule_match_start_after_grace()


func _schedule_match_start_after_grace() -> void:
	if _match_start_check_scheduled or _server_match_started:
		return
	_match_start_check_scheduled = true
	print(
		"[NetworkSession] %d players — waiting %.0fs for full group."
		% [_current_player_count(), LOBBY_START_GRACE_SEC]
	)
	await get_tree().create_timer(LOBBY_START_GRACE_SEC).timeout
	_match_start_check_scheduled = false
	if _server_match_started:
		return
	var count := _current_player_count()
	if count < MIN_PLAYERS_TO_START:
		return
	print("[NetworkSession] Starting after grace — %d players." % count)
	server_begin_online_match(count)


func server_begin_online_match(player_count: int = MIN_PLAYERS_TO_START) -> void:
	if _server_match_started:
		return
	_server_match_started = true
	_server_registered_peers.clear()
	_waiting_map_after_connect = false
	var map_index := MapSession.pick_random_online_map_index()
	print("[NetworkSession] Starting match (%d players, map %d)." % [player_count, map_index])
	MapSession.active_map_index = map_index
	MapSession.is_online_match = true
	MapSession.local_team = 0
	MapSession.online_player_count = player_count

	var peers := multiplayer.get_peers()
	print("[NetworkSession] Sending begin_match RPC to %d client(s)." % peers.size())
	for peer_id in peers:
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


func is_server_match_running() -> bool:
	return _server_match_started


## Called by the game server when 2+ clients are connected (RPC).
@rpc("authority", "call_remote", "reliable")
func rpc_begin_online_match(
	player_count: int = MIN_PLAYERS_TO_START, map_index: int = 0
) -> void:
	if ServerMode.is_dedicated_server:
		return
	var map_idx := MapSession.normalize_online_map_index(
		map_index if map_index > 0 else MapSession.active_map_index
	)
	print("[NetworkSession] Client — loading map %d (%d players)." % [map_idx, player_count])
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
			return "Connection failed (network or unreachable API)"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Domain name not found (DNS)"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connection dropped — Nakama CORS or WebSocket /game (often 503 = game server stopped on VPS)"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "SSL certificate error (HTTPS)"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Request blocked by browser (CORS or mixed content)"
		8:
			# RESULT_BODY_DECODE_ERROR (Godot versions) — often gzip on /v2
			return "Unreadable response (gzip) — re-export Web + Apache without compression on /v2"
		_:
			return "Godot HTTP error code %s" % str(result)


func _normalize_entries(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	if typeof(value) == TYPE_DICTIONARY:
		var dict := value as Dictionary
		if dict.is_empty():
			return []
		var out: Array = []
		for key in dict.keys():
			var item: Variant = dict[key]
			if typeof(item) == TYPE_DICTIONARY:
				out.append(item)
		return out
	return []


func _friendly_auth_error(response_code: int, parsed, raw_text: String) -> String:
	if typeof(parsed) == TYPE_DICTIONARY:
		var msg := str(parsed.get("message", "")).to_lower()
		if response_code == 401 or response_code == 403:
			return tr("AUTH_WRONG_CREDENTIALS")
		if response_code == 409 or "already" in msg or "exists" in msg or "unique" in msg:
			if "username" in msg or "pseudo" in msg:
				return tr("AUTH_USERNAME_TAKEN")
			return tr("AUTH_EMAIL_OR_USER_TAKEN")
		if response_code == 400:
			if "email" in msg:
				return tr("AUTH_EMAIL_FORMAT")
			if "password" in msg:
				return tr("AUTH_PASSWORD_INVALID")
			if "username" in msg:
				return tr("AUTH_USERNAME_INVALID_TAKEN")
			return tr("AUTH_DATA_INVALID")
	if response_code == 0:
		return tr("NET_SERVER_UNREACHABLE")
	if response_code >= 200 and response_code < 300:
		return "Unexpected server response. Re-export the Web client and redeploy on the VPS."
	if typeof(parsed) == TYPE_DICTIONARY:
		var msg := str(parsed.get("message", "")).strip_edges()
		if msg != "":
			return msg
	return "Connection refused (HTTP %s)." % str(response_code)


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


func _jwt_is_expired(token: String) -> bool:
	var payload := _parse_jwt_payload(token)
	if not payload.has("exp"):
		return false
	var exp := int(payload.get("exp", 0))
	if exp <= 0:
		return false
	return Time.get_unix_time_from_system() >= exp - 30


func _handle_error(msg: String) -> void:
	_pending_auth_email = ""
	_pending_auth_password = ""
	_leave_queue_pending = false
	if _auth_http_pending:
		_clear_auth_http_pending()
	var in_matchmaking := (
		_in_queue or _awaiting_join_ack or _match_handoff_started or _ws_connecting
	)
	if _awaiting_join_ack:
		_awaiting_join_ack = false
		_join_ack_started_ms = 0
	_pump_http_queue()
	if in_matchmaking:
		match_failed.emit(msg)
	elif is_authenticated:
		# Do not log the user out for a secondary HTTP error (e.g. leave_queue).
		push_warning("[NetworkSession] " + msg)
	else:
		auth_failed.emit(msg)


func _process(_delta: float) -> void:
	# Web export: poll in-flight fetch() response (async).
	if _web_pending_id != "":
		_poll_web_request()
	if _auth_http_pending and _auth_http_started_ms > 0:
		if Time.get_ticks_msec() - _auth_http_started_ms > AUTH_HTTP_TIMEOUT_MS:
			_clear_auth_http_pending()
			auth_failed.emit(tr("AUTH_TIMEOUT"))
	if _awaiting_join_ack and _join_ack_started_ms > 0:
		if Time.get_ticks_msec() - _join_ack_started_ms > JOIN_ACK_TIMEOUT_MS:
			_awaiting_join_ack = false
			_join_ack_started_ms = 0
			match_failed.emit(tr("NET_QUEUE_TIMEOUT"))
	if _waiting_map_after_connect:
		_map_wait_elapsed += _delta
		if _map_wait_elapsed >= MAP_WAIT_TIMEOUT:
			_waiting_map_after_connect = false
			game_connection_failed.emit(tr("NET_MAP_NOT_STARTED"))
	if not _in_queue or not is_authenticated or _match_handoff_started or _awaiting_join_ack:
		return
	if _http_busy:
		return
	_last_queue_poll += _delta
	if _last_queue_poll < 2.0:
		return
	_last_queue_poll = 0.0
	_rpc("queue_status")
