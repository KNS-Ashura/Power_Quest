extends Node2D

const BestiaryCatalogue = preload("res://scripts/menu/bestiaire_catalogue.gd")

@onready var _unit_name: Label = %NomDeLaMap
@onready var _description: Label = %Description1
@onready var _stats: Label = %StatsBlock
@onready var _preview_host: Node2D = %UnitPreviewHost
@onready var _map_image: TextureRect = %CarteImage

var _current_unit_index: int = 0


func _ready() -> void:
	if _map_image != null:
		_map_image.visible = false
	var back := get_node_or_null("BackToMenu") as BaseButton
	if back != null and not back.pressed.is_connected(_on_back_to_menu):
		back.pressed.connect(_on_back_to_menu)
	show_unit(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		show_unit(_current_unit_index)


func show_unit(unit_index: int) -> void:
	_current_unit_index = unit_index
	var entry: Dictionary = BestiaryCatalogue.unit_entry(unit_index)
	var unit_type: int = int(entry.get("type", UnitStats.UnitType.INFANTRY))
	var stats: UnitStats = BestiaryCatalogue.stats_for_unit_type(unit_type)

	if _unit_name != null:
		_unit_name.text = tr(str(entry.get("name_key", "")))
	if _description != null:
		_description.uppercase = false
		_description.text = tr(str(entry.get("desc_key", "")))
	if _stats != null:
		_stats.text = BestiaryCatalogue.format_stats(stats)

	_spawn_preview(unit_type)


func _spawn_preview(unit_type: int) -> void:
	if _preview_host == null:
		return
	for child in _preview_host.get_children():
		child.queue_free()
	var scene: PackedScene = BestiaryCatalogue.scene_for_unit_type(unit_type)
	if scene == null:
		return
	var unit := scene.instantiate()
	_preview_host.add_child(unit)
	unit.position = Vector2(32, 48)
	if "team" in unit:
		unit.team = 0
	var sprite := unit.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null:
		if sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		elif sprite.sprite_frames.get_animation_names().size() > 0:
			sprite.play(sprite.sprite_frames.get_animation_names()[0])


func _on_arrow_left_pressed() -> void:
	var book := get_tree().current_scene
	if book != null and book.has_method("open_bestiary_maps"):
		await book.open_bestiary_maps()


func _on_arrow_right_pressed() -> void:
	var count: int = BestiaryCatalogue.UNITS.size()
	if count <= 0:
		return
	show_unit((_current_unit_index + 1) % count)


func _on_back_to_menu() -> void:
	var book := get_tree().current_scene
	if book != null and book.has_method("_on_main_menu_pressed"):
		book._on_main_menu_pressed()
