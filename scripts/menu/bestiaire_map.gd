extends Node2D

const BestiaryCatalogue = preload("res://scripts/menu/bestiaire_catalogue.gd")

@onready var _map_image: TextureRect = %CarteImage
@onready var _map_name: Label = %NomDeLaMap

var _map_index: int = 0
var _unit_buttons: Array[TextureButton] = []
var _unit_labels: Array[Label] = []


func _ready() -> void:
	_collect_unit_widgets()
	_wire_unit_buttons()
	var desc := get_node_or_null("PageDroite/Description1") as Label
	if desc != null:
		desc.hide()
	var back := get_node_or_null("BackToMenu") as BaseButton
	if back != null and not back.pressed.is_connected(_on_back_to_menu):
		back.pressed.connect(_on_back_to_menu)
	update_map_display()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		update_map_display()
		_refresh_unit_labels()


func _collect_unit_widgets() -> void:
	_unit_buttons.clear()
	_unit_labels.clear()
	for i in range(1, 11):
		var ctrl := get_node_or_null("PageDroite/ControlBiome%d" % i)
		if ctrl == null:
			_unit_buttons.append(null)
			_unit_labels.append(null)
			continue
		var btn := ctrl.get_node_or_null("ZoneBiome1") as TextureButton
		var lbl := ctrl.get_node_or_null("CURSED") as Label
		_unit_buttons.append(btn)
		_unit_labels.append(lbl)


func _wire_unit_buttons() -> void:
	for i in range(_unit_buttons.size()):
		var btn := _unit_buttons[i]
		if btn == null:
			continue
		var unit_index := i
		if not btn.pressed.is_connected(_on_unit_button_pressed.bind(unit_index)):
			btn.pressed.connect(_on_unit_button_pressed.bind(unit_index))
	_refresh_unit_labels()


func _refresh_unit_labels() -> void:
	for i in range(_unit_labels.size()):
		var lbl := _unit_labels[i]
		if lbl == null:
			continue
		var entry: Dictionary = BestiaryCatalogue.unit_entry(i)
		lbl.text = tr(str(entry.get("name_key", "")))


func update_map_display() -> void:
	var maps: Array = BestiaryCatalogue.MAPS
	if maps.is_empty():
		return
	var data: Dictionary = maps[_map_index]
	if _map_name != null:
		_map_name.text = tr(str(data.get("name_key", "")))
	if _map_image != null:
		var img: Variant = data.get("image")
		if img is Texture2D:
			_map_image.texture = img
		elif img is SpriteFrames:
			_map_image.texture = (img as SpriteFrames).get_frame_texture("default", 0)


func _on_arrow_right_pressed() -> void:
	var count: int = BestiaryCatalogue.MAPS.size()
	if count <= 0:
		return
	_map_index = (_map_index + 1) % count
	update_map_display()


func _on_arrow_left_pressed() -> void:
	var count: int = BestiaryCatalogue.MAPS.size()
	if count <= 0:
		return
	_map_index = (_map_index - 1 + count) % count
	update_map_display()


func _on_unit_button_pressed(unit_index: int) -> void:
	var book := get_tree().current_scene
	if book != null and book.has_method("open_bestiary_unit"):
		await book.open_bestiary_unit(unit_index)


func _on_back_to_menu() -> void:
	var book := get_tree().current_scene
	if book != null and book.has_method("_on_main_menu_pressed"):
		book._on_main_menu_pressed()
