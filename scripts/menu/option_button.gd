extends OptionButton

@export_file("*.ttf", "*.otf") var chemin_police: String = "res://assets/menu/fonts/m5x7.ttf"


func _ready() -> void:
	_setup_popup_theme()
	_rebuild_items()
	if not UserPrefs.language_changed.is_connected(_rebuild_items):
		UserPrefs.language_changed.connect(_rebuild_items)


func _setup_popup_theme() -> void:
	var popup := get_popup()
	var style_fond := StyleBoxFlat.new()
	style_fond.bg_color = Color("cfad82")
	style_fond.set_corner_radius_all(5)
	style_fond.content_margin_left = 15
	style_fond.content_margin_top = 5
	style_fond.content_margin_bottom = 5
	popup.add_theme_stylebox_override("panel", style_fond)

	if ResourceLoader.exists(chemin_police):
		var ma_font = load(chemin_police)
		popup.add_theme_font_override("font", ma_font)

	popup.add_theme_font_size_override("font_size", 24)
	popup.add_theme_color_override("font_color", Color("2d1b14"))
	popup.add_theme_color_override("font_hover_color", Color("ffffff"))

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color("3a8c91")
	style_hover.set_corner_radius_all(3)
	popup.add_theme_stylebox_override("hover", style_hover)

	popup.add_theme_constant_override("check_v_offset", 0)
	popup.add_theme_constant_override("item_start_padding", 15)


func _rebuild_items(_locale: String = "") -> void:
	clear()
	add_item(tr("TXT_LANG_EN"), 0)
	add_item(tr("TXT_LANG_FR"), 1)
	add_item(tr("TXT_LANG_DE"), 2)
	var popup := get_popup()
	for i in popup.item_count:
		popup.set_item_as_checkable(i, false)
	_synchroniser_selection()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if item_count >= 3:
			set_item_text(0, tr("TXT_LANG_EN"))
			set_item_text(1, tr("TXT_LANG_FR"))
			set_item_text(2, tr("TXT_LANG_DE"))
			_synchroniser_selection()


func _synchroniser_selection() -> void:
	var langue_actuelle := TranslationServer.get_locale()
	if langue_actuelle.begins_with("en"):
		selected = 0
	elif langue_actuelle.begins_with("fr"):
		selected = 1
	elif langue_actuelle.begins_with("de"):
		selected = 2
