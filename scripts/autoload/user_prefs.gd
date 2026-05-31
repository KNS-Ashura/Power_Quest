extends Node

## User preferences (language, volumes, etc.).
## - Persisted locally in user://settings.cfg (kept in IndexedDB on Web,
##   so the correct language is restored after a refresh).
## - Linked to the account via Nakama storage: on login we fetch account
##   preferences and apply language; a language change is synced back when logged in.

signal language_changed(locale: String)
signal audio_volumes_changed(music_linear: float, sfx_linear: float)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "general"
const DEFAULT_LOCALE := "en"
const SUPPORTED_LOCALES := ["en", "fr", "de"]
const DEFAULT_VOLUME_PERCENT := 50

var _locale: String = DEFAULT_LOCALE
var _music_volume_percent: int = DEFAULT_VOLUME_PERCENT
var _sfx_volume_percent: int = DEFAULT_VOLUME_PERCENT
var _account_synced: bool = false


func _ready() -> void:
	_load_local()
	_apply_locale()
	call_deferred("apply_audio_volumes")
	if not NetworkSession.auth_ready.is_connected(_on_auth_ready):
		NetworkSession.auth_ready.connect(_on_auth_ready)
	if not NetworkSession.session_closed.is_connected(_on_session_closed):
		NetworkSession.session_closed.connect(_on_session_closed)
	if not NetworkSession.preferences_loaded.is_connected(_on_account_prefs_loaded):
		NetworkSession.preferences_loaded.connect(_on_account_prefs_loaded)


func get_language() -> String:
	return _locale


func apply_locale_now() -> void:
	_apply_locale()
	if UITranslator.has_method("refresh_tree"):
		UITranslator.call_deferred("refresh_tree")


## Change language: apply, persist locally, and sync to account when logged in.
func set_language(locale: String, sync_account: bool = true) -> void:
	if not SUPPORTED_LOCALES.has(locale):
		return
	if locale == _locale:
		# Always re-apply (another source may have changed the locale).
		_apply_locale()
		return
	_locale = locale
	_apply_locale()
	_save_local()
	language_changed.emit(_locale)
	if sync_account and NetworkSession.is_account_logged_in():
		NetworkSession.save_account_preferences(_to_dict())


func get_music_volume_percent() -> int:
	return _music_volume_percent


func get_sfx_volume_percent() -> int:
	return _sfx_volume_percent


func get_music_linear() -> float:
	return float(_music_volume_percent) / 100.0


func get_sfx_linear() -> float:
	return float(_sfx_volume_percent) / 100.0


func set_music_volume_percent(percent: int) -> void:
	var value := clampi(percent, 0, 100)
	if value == _music_volume_percent:
		apply_audio_volumes()
		return
	_music_volume_percent = value
	_save_local()
	apply_audio_volumes()
	audio_volumes_changed.emit(get_music_linear(), get_sfx_linear())


func set_sfx_volume_percent(percent: int) -> void:
	var value := clampi(percent, 0, 100)
	if value == _sfx_volume_percent:
		apply_audio_volumes()
		return
	_sfx_volume_percent = value
	_save_local()
	apply_audio_volumes()
	audio_volumes_changed.emit(get_music_linear(), get_sfx_linear())


func apply_audio_volumes() -> void:
	var music_linear := get_music_linear()
	var sfx_linear := get_sfx_linear()
	if Music.has_method("set_volume_linear"):
		Music.set_volume_linear(music_linear)
	if Sound.has_method("set_sfx_volume_linear"):
		Sound.set_sfx_volume_linear(sfx_linear)


func _apply_locale() -> void:
	TranslationBootstrap.ensure_loaded()
	_locale = TranslationBootstrap.normalize_locale(_locale)
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
	_music_volume_percent = clampi(int(cfg.get_value(SECTION, "music_volume", DEFAULT_VOLUME_PERCENT)), 0, 100)
	_sfx_volume_percent = clampi(int(cfg.get_value(SECTION, "sfx_volume", DEFAULT_VOLUME_PERCENT)), 0, 100)


func _save_local() -> void:
	var cfg := ConfigFile.new()
	# Keep any other values already stored.
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, "language", _locale)
	cfg.set_value(SECTION, "music_volume", _music_volume_percent)
	cfg.set_value(SECTION, "sfx_volume", _sfx_volume_percent)
	cfg.save(SETTINGS_PATH)


func _on_auth_ready() -> void:
	if NetworkSession.is_account_logged_in():
		NetworkSession.request_account_preferences()


func _on_session_closed() -> void:
	_account_synced = false


func _on_account_prefs_loaded(prefs: Dictionary) -> void:
	var lang := str(prefs.get("language", "")).strip_edges()
	if SUPPORTED_LOCALES.has(lang):
		# Account wins: apply account language.
		if lang != _locale:
			_locale = lang
			_apply_locale()
			_save_local()
			language_changed.emit(_locale)
		_account_synced = true
	elif not _account_synced and NetworkSession.is_account_logged_in():
		# Account has no preference yet: write current local language.
		_account_synced = true
		NetworkSession.save_account_preferences(_to_dict())
