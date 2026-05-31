extends Node

## Production URLs — adjust on the VPS.
## Local dev: run Nakama (deploy/docker-compose) + Godot server with --server.

@export var nakama_scheme: String = "https"
## Same domain as the Web game → no CORS (proxy /v2 and /game in 000-default-le-ssl.conf).
@export var nakama_host: String = "powerquest.robinmatelot.codes"
@export var nakama_port: int = 443
@export var nakama_server_key: String = "defaultkey"

## Trailing slash required for Apache ProxyPass /game/ → ws://127.0.0.1:9080/
const PROD_GAME_WS_URL := "wss://powerquest.robinmatelot.codes/game/"

@export var game_ws_url: String = PROD_GAME_WS_URL

## Local dev (override when host is localhost in the editor)
@export var dev_nakama_host: String = "127.0.0.1"
@export var dev_nakama_port: int = 7350
@export var dev_game_ws_url: String = "ws://127.0.0.1:9080"


func use_dev_endpoints() -> bool:
	# On VPS: do not set PQ_DEV. Locally: export PQ_DEV=1
	return OS.get_environment("PQ_DEV") == "1"


func nakama_base_url() -> String:
	if use_dev_endpoints():
		return "http://%s:%d" % [dev_nakama_host, dev_nakama_port]
	var port_suffix := "" if nakama_port == 443 or nakama_port == 80 else ":%d" % nakama_port
	return "%s://%s%s" % [nakama_scheme, nakama_host, port_suffix]


func resolved_game_ws_url() -> String:
	if use_dev_endpoints():
		var dev := dev_game_ws_url.strip_edges()
		return dev if dev != "" else "ws://127.0.0.1:9080"
	var prod := game_ws_url.strip_edges()
	return prod if prod != "" else PROD_GAME_WS_URL
