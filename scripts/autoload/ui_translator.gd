extends Node

## Applies translations to scene text stored as keys (MENU_*).


func _ready() -> void:
	if not UserPrefs.language_changed.is_connected(_on_language_changed):
		UserPrefs.language_changed.connect(_on_language_changed)
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_refresh_tree")


func _on_language_changed(_locale: String) -> void:
	call_deferred("_refresh_tree")


func _on_node_added(node: Node) -> void:
	call_deferred("_refresh_node", node)


func refresh_tree() -> void:
	_refresh_tree()


func _refresh_tree() -> void:
	TranslationBootstrap.ensure_loaded()
	var locale := TranslationBootstrap.normalize_locale(UserPrefs.get_language())
	TranslationServer.set_locale(locale)
	var root := get_tree().root
	if root != null:
		_refresh_node(root)


func _refresh_node(node: Node) -> void:
	if node is Label:
		_translate_property(node, "text")
	elif node is Button:
		_translate_property(node, "text")
	elif node is LineEdit:
		_translate_property(node, "placeholder_text")
		_translate_property(node, "text")
	elif node is RichTextLabel:
		_translate_property(node, "text")
	elif node is CheckBox:
		_translate_property(node, "text")
	elif node is OptionButton and node.get_item_count() == 0:
		pass
	for child in node.get_children():
		_refresh_node(child)


func _translate_property(node: Object, property_name: String) -> void:
	if not property_name in node:
		return
	var meta_key := "_ui_tr_%s" % property_name
	var raw := str(node.get(property_name))
	var key := raw
	if node.has_meta(meta_key):
		key = str(node.get_meta(meta_key))
	elif _looks_like_translation_key(raw):
		node.set_meta(meta_key, raw)
	else:
		return
	var translated := tr(key)
	if translated != key and not translated.is_empty():
		node.set(property_name, translated)


func _looks_like_translation_key(value: String) -> bool:
	if value.is_empty() or not value.contains("_"):
		return false
	for i in value.length():
		var code := value.unicode_at(i)
		var is_upper := code >= 65 and code <= 90
		var is_digit := code >= 48 and code <= 57
		if is_upper or is_digit or code == 95:
			continue
		return false
	return true
