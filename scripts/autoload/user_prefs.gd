extends Node

## Préférences utilisateur (langue, volumes…).
## - Persistées localement dans user://settings.cfg (conservé en IndexedDB sur le Web,
##   donc la bonne langue est rappliquée après un refresh).
## - Liées au compte via le stockage Nakama : à la connexion on récupère les
##   préférences du compte et on applique la langue ; un changement de langue
##   est resynchronisé sur le compte si connecté.

signal language_changed(locale: String)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "general"
const DEFAULT_LOCALE := "en"
const SUPPORTED_LOCALES := ["en", "fr", "de"]

var _locale: String = DEFAULT_LOCALE
var _account_synced: bool = false


func _ready() -> void:
	_load_local()
	_apply_locale()
	if not NetworkSession.auth_ready.is_connected(_on_auth_ready):
		NetworkSession.auth_ready.connect(_on_auth_ready)
	if not NetworkSession.session_closed.is_connected(_on_session_closed):
		NetworkSession.session_closed.connect(_on_session_closed)
	if not NetworkSession.preferences_loaded.is_connected(_on_account_prefs_loaded):
		NetworkSession.preferences_loaded.connect(_on_account_prefs_loaded)


func get_language() -> String:
	return _locale


## Change la langue : applique, persiste localement et resynchronise le compte.
func set_language(locale: String, sync_account: bool = true) -> void:
	if not SUPPORTED_LOCALES.has(locale):
		return
	if locale == _locale:
		# Toujours réappliquer (au cas où une autre source aurait changé la locale).
		_apply_locale()
		return
	_locale = locale
	_apply_locale()
	_save_local()
	language_changed.emit(_locale)
	if sync_account and NetworkSession.is_account_logged_in():
		NetworkSession.save_account_preferences(_to_dict())


func _apply_locale() -> void:
	TranslationServer.set_locale(_locale)


func _to_dict() -> Dictionary:
	return {"language": _locale}


func _load_local() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var lang := str(cfg.get_value(SECTION, "language", DEFAULT_LOCALE))
	if SUPPORTED_LOCALES.has(lang):
		_locale = lang


func _save_local() -> void:
	var cfg := ConfigFile.new()
	# Conserve d'éventuelles autres valeurs déjà présentes.
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, "language", _locale)
	cfg.save(SETTINGS_PATH)


func _on_auth_ready() -> void:
	if NetworkSession.is_account_logged_in():
		NetworkSession.request_account_preferences()


func _on_session_closed() -> void:
	_account_synced = false


func _on_account_prefs_loaded(prefs: Dictionary) -> void:
	var lang := str(prefs.get("language", "")).strip_edges()
	if SUPPORTED_LOCALES.has(lang):
		# Le compte fait foi : applique la langue du compte.
		if lang != _locale:
			_locale = lang
			_apply_locale()
			_save_local()
			language_changed.emit(_locale)
		_account_synced = true
	elif not _account_synced and NetworkSession.is_account_logged_in():
		# Le compte n'a pas encore de préférence : on y écrit la langue locale courante.
		_account_synced = true
		NetworkSession.save_account_preferences(_to_dict())
