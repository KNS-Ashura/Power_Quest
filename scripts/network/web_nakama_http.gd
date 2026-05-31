class_name WebNakamaHttp
extends RefCounted

## Nakama HTTP via browser fetch() (Web export only).
##
## The window.PQ bridge is INJECTED AT RUNTIME by GDScript (ensure_bridge), so:
##   - no JS file to copy,
##   - no index.html edits,
##   - no export_presets.cfg dependency (head_include).
## It therefore survives each Godot Web export automatically.

# Compact one-line JS: JavaScriptBridge.eval is more reliable this way
# (multi-line / tab strings can fail silently).
const _BRIDGE_JS := "window.PQ=window.PQ||{};window.PQ._r=window.PQ._r||{};window.PQ.send=function(id,url,method,h,b){var hd={};try{hd=JSON.parse(h||'{}');}catch(e){hd={};}var o={method:method||'POST',headers:hd,cache:'no-store',credentials:'omit'};if(method!=='GET'&&b){o.body=b;}fetch(url,o).then(function(r){return r.text().then(function(t){window.PQ._r[id]=JSON.stringify({ok:r.ok,status:r.status,text:t});});}).catch(function(e){window.PQ._r[id]=JSON.stringify({ok:false,status:0,text:'',error:String(e)});});};window.PQ.poll=function(id){if(Object.prototype.hasOwnProperty.call(window.PQ._r,id)){var v=window.PQ._r[id];delete window.PQ._r[id];return v;}return '';};window.PQ.lsGet=function(k){try{return localStorage.getItem(k)||'';}catch(e){return '';}};window.PQ.lsSet=function(k,v){try{localStorage.setItem(k,v);}catch(e){}};window.PQ.lsDel=function(k){try{localStorage.removeItem(k);}catch(e){}};"


static func is_available() -> bool:
	return OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge")


static func bridge_ready() -> bool:
	if not is_available():
		return false
	# Return a STRING ('yes'/'no'): robust against bool/float eval conversions.
	var ok: Variant = JavaScriptBridge.eval(
		"((window.PQ&&typeof window.PQ.send==='function'&&typeof window.PQ.poll==='function')?'yes':'no')",
		true
	)
	return str(ok).strip_edges() == "yes"


## Inject the bridge if missing. Call before any request (idempotent).
static func ensure_bridge() -> bool:
	if not is_available():
		return false
	if bridge_ready():
		return true
	JavaScriptBridge.eval(_BRIDGE_JS, true)
	return bridge_ready()


## Start an async request. Read the result with poll(id).
static func send(
	id: String, url: String, method: int, headers: PackedStringArray, body: String
) -> bool:
	if not ensure_bridge():
		return false
	var headers_dict: Dictionary = {}
	for h in headers:
		var sep := h.find(":")
		if sep > 0:
			headers_dict[h.substr(0, sep).strip_edges()] = h.substr(sep + 1).strip_edges()
	var method_name := "GET"
	if method == HTTPClient.METHOD_POST:
		method_name = "POST"
	elif method == HTTPClient.METHOD_PUT:
		method_name = "PUT"
	elif method == HTTPClient.METHOD_DELETE:
		method_name = "DELETE"
	var js := (
		"window.PQ.send("
		+ JSON.stringify(id)
		+ ","
		+ JSON.stringify(url)
		+ ","
		+ JSON.stringify(method_name)
		+ ","
		+ JSON.stringify(JSON.stringify(headers_dict))
		+ ","
		+ JSON.stringify(body)
		+ ")"
	)
	JavaScriptBridge.eval(js, true)
	return true


## Returns {} while the request is pending, otherwise {ok, status, text}.
static func poll(id: String) -> Dictionary:
	if not is_available():
		return {}
	var raw: Variant = JavaScriptBridge.eval(
		"window.PQ.poll(" + JSON.stringify(id) + ")", true
	)
	if raw == null:
		return {}
	var raw_str := str(raw).strip_edges()
	if raw_str.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw_str)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {"ok": false, "status": 0, "text": raw_str}


static func ls_get(key: String) -> String:
	if not ensure_bridge():
		return ""
	var raw: Variant = JavaScriptBridge.eval(
		"window.PQ.lsGet(" + JSON.stringify(key) + ")", true
	)
	if raw == null:
		return ""
	return str(raw)


static func ls_set(key: String, value: String) -> void:
	if not ensure_bridge() or value.is_empty():
		return
	JavaScriptBridge.eval(
		"window.PQ.lsSet(" + JSON.stringify(key) + "," + JSON.stringify(value) + ")",
		true
	)


static func ls_del(key: String) -> void:
	if not ensure_bridge():
		return
	JavaScriptBridge.eval("window.PQ.lsDel(" + JSON.stringify(key) + ")", true)
