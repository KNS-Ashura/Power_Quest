extends Node

## Charge traduction.csv au runtime pour éviter les clés brutes (MENU_*)
## quand les fichiers .translation importés ne sont pas à jour.

const CSV_PATH := "res://assets/menu/traduction.csv"
const LOCALES := ["en", "fr", "de"]
const LOCALE_COLUMNS := {"en": 1, "fr": 2, "de": 3}

var _loaded: bool = false


func _init() -> void:
	_load_from_csv()


func _load_from_csv() -> void:
	if _loaded:
		return
	if not FileAccess.file_exists(CSV_PATH):
		push_warning("[TranslationBootstrap] CSV introuvable : " + CSV_PATH)
		return

	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_warning("[TranslationBootstrap] Impossible de lire : " + CSV_PATH)
		return

	var header := file.get_line()
	if header.is_empty() or not header.begins_with("id;"):
		file.close()
		push_warning("[TranslationBootstrap] En-tête CSV invalide.")
		return

	var by_locale: Dictionary = {}
	for loc in LOCALES:
		by_locale[loc] = {}

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split(";")
		if parts.size() < 4:
			continue
		var key := str(parts[0]).strip_edges()
		if key.is_empty():
			continue
		for loc in LOCALES:
			var col: int = LOCALE_COLUMNS[loc]
			if col < parts.size():
				by_locale[loc][key] = str(parts[col])

	file.close()

	for loc in LOCALES:
		var translation := Translation.new()
		translation.locale = loc
		for key in by_locale[loc]:
			translation.add_message(key, str(by_locale[loc][key]))
		TranslationServer.add_translation(translation)

	_loaded = true
