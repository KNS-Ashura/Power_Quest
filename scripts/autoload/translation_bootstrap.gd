extends Node

## Charge les traductions pour l'export Web.
## Source de vérité : translation_keys.gd (généré depuis traduction.csv).

var _loaded: bool = false


func _ready() -> void:
	call_deferred("ensure_loaded")


func ensure_loaded() -> void:
	if _loaded:
		return
	var count := TranslationKeys.apply_to_server()
	_loaded = count > 0
	if not _loaded:
		push_warning("[TranslationBootstrap] Aucune traduction chargée.")


func normalize_locale(locale: String) -> String:
	var code := locale.strip_edges().to_lower()
	if code.is_empty():
		return "en"
	if code.begins_with("fr"):
		return "fr"
	if code.begins_with("de"):
		return "de"
	return "en"


func reapply_current_locale() -> void:
	ensure_loaded()
	var locale := normalize_locale(TranslationServer.get_locale())
	TranslationServer.set_locale(locale)
