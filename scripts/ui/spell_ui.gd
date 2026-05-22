extends CanvasLayer

@onready var btn_heal: Button = $Control/Panel/HBoxContainer/BtnHeal
@onready var btn_boost: Button = $Control/Panel/HBoxContainer/BtnBoost
@onready var btn_mortar_spell: Button = $Control/Panel/HBoxContainer/BtnMortarSpell

const SPELL_EFFECT_RADIUS: float = 150.0
const ZONE_DISPLAY_DURATION: float = 0.6
const CIRCLE_POINT_COUNT: int = 48
const HEAL_BORDER_COLOR: Color = Color(0.2, 1.0, 0.2, 1.0)
const HEAL_FILL_COLOR: Color = Color(0.2, 1.0, 0.2, 0.2)
const BOOST_BORDER_COLOR: Color = Color(0.25, 0.55, 1.0, 1.0)
const BOOST_FILL_COLOR: Color = Color(0.25, 0.55, 1.0, 0.2)
const MORTAR_BORDER_COLOR: Color = Color(1.0, 0.55, 0.15, 1.0)
const MORTAR_FILL_COLOR: Color = Color(1.0, 0.55, 0.15, 0.2)

var _selected_healer_count: int = 0
var _selected_support_count: int = 0
var _selected_mortar_count: int = 0


func _ready() -> void:
	btn_heal.disabled = true
	btn_boost.disabled = true
	btn_mortar_spell.disabled = true


func _process(_delta: float) -> void:
	_refresh_button_state()


func _refresh_button_state() -> void:
	var healers := 0
	var supports := 0
	var mortars := 0

	for unit in get_tree().get_nodes_in_group("soldiers"):
		if not unit.get("is_selected"):
			continue
		if unit.get("team") != 0:
			continue
		if not unit.get("stats"):
			continue

		match int(unit.stats.unit_type):
			3:
				supports += 1
			4:
				healers += 1
			6:
				mortars += 1

	if healers == _selected_healer_count and supports == _selected_support_count and mortars == _selected_mortar_count:
		return

	_selected_healer_count = healers
	_selected_support_count = supports
	_selected_mortar_count = mortars

	btn_heal.disabled = _selected_healer_count <= 0
	btn_boost.disabled = _selected_support_count <= 0
	btn_mortar_spell.disabled = _selected_mortar_count <= 0


func _on_btn_heal_pressed() -> void:
	var healers: Array = _get_selected_units_by_type(4)
	var casts := 0
	for healer in healers:
		if _try_cast_spell(healer):
			casts += 1
			_show_effect_zone(healer.global_position, SPELL_EFFECT_RADIUS, HEAL_BORDER_COLOR, HEAL_FILL_COLOR)
	print("%d healer(s) selected, %d spell(s) cast" % [_selected_healer_count, casts])


func _on_btn_boost_pressed() -> void:
	var supports: Array = _get_selected_units_by_type(3)
	var casts := 0
	for support in supports:
		if _try_cast_spell(support):
			casts += 1
			_show_effect_zone(support.global_position, SPELL_EFFECT_RADIUS, BOOST_BORDER_COLOR, BOOST_FILL_COLOR)
	print("%d support(s) selected, %d spell(s) cast" % [_selected_support_count, casts])


func _on_btn_mortar_spell_pressed() -> void:
	var mortars: Array = _get_selected_units_by_type(6)
	var casts := 0
	for mortar in mortars:
		if _try_cast_spell(mortar):
			casts += 1
			_show_effect_zone(mortar.global_position, SPELL_EFFECT_RADIUS, MORTAR_BORDER_COLOR, MORTAR_FILL_COLOR)
	print("%d mortar(s) selected, %d spell(s) cast" % [_selected_mortar_count, casts])


func _try_cast_spell(unit: Node) -> bool:
	if not unit.has_method("can_cast_spell") or not unit.can_cast_spell():
		return false
	if unit.has_method("cast_spell"):
		return unit.cast_spell()
	return false


func _get_selected_units_by_type(unit_type: int) -> Array:
	var result: Array = []
	for unit in get_tree().get_nodes_in_group("soldiers"):
		if not unit.get("is_selected"):
			continue
		if unit.get("team") != 0:
			continue
		if not unit.get("stats"):
			continue
		if int(unit.stats.unit_type) == unit_type:
			result.append(unit)
	return result


func _show_effect_zone(world_position: Vector2, radius: float, border_color: Color, fill_color: Color) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return

	var zone = Node2D.new()
	zone.global_position = world_position

	var outline = Line2D.new()
	outline.width = 4.0
	outline.default_color = border_color
	outline.closed = true

	var fill = Polygon2D.new()
	fill.color = fill_color

	var points: PackedVector2Array = []
	for i in range(CIRCLE_POINT_COUNT):
		var angle = TAU * float(i) / float(CIRCLE_POINT_COUNT)
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	outline.points = points
	fill.polygon = points

	zone.add_child(fill)
	zone.add_child(outline)
	scene.add_child(zone)

	var tween = create_tween()
	tween.tween_property(zone, "modulate:a", 0.0, ZONE_DISPLAY_DURATION)
	tween.finished.connect(func(): zone.queue_free())
