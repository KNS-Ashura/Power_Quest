extends CanvasLayer

@onready var btn_heal: Button = $Control/Panel/HBoxContainer/BtnHeal
@onready var btn_boost: Button = $Control/Panel/HBoxContainer/BtnBoost
@onready var btn_mortar_spell: Button = $Control/Panel/HBoxContainer/BtnMortarSpell
@onready var btn_anti_armor: Button = $Control/Panel/HBoxContainer/BtnAntiArmor
@onready var btn_water_transport: Button = $Control/Panel/HBoxContainer/BtnWaterTransport

const SPELL_EFFECT_RADIUS: float = 150.0
const ZONE_DISPLAY_DURATION: float = 0.6
const CIRCLE_POINT_COUNT: int = 48
const HEAL_BORDER_COLOR: Color = Color(0.2, 1.0, 0.2, 1.0)
const HEAL_FILL_COLOR: Color = Color(0.2, 1.0, 0.2, 0.2)
const BOOST_BORDER_COLOR: Color = Color(0.25, 0.55, 1.0, 1.0)
const BOOST_FILL_COLOR: Color = Color(0.25, 0.55, 1.0, 0.2)
const MORTAR_BORDER_COLOR: Color = Color(1.0, 0.55, 0.15, 1.0)
const MORTAR_FILL_COLOR: Color = Color(1.0, 0.55, 0.15, 0.2)
const ANTI_ARMOR_BORDER_COLOR: Color = Color(1.0, 0.35, 0.75, 1.0)
const ANTI_ARMOR_FILL_COLOR: Color = Color(1.0, 0.35, 0.75, 0.2)
const TRANSPORT_BORDER_COLOR: Color = Color(0.2, 0.75, 1.0, 1.0)
const TRANSPORT_FILL_COLOR: Color = Color(0.2, 0.75, 1.0, 0.22)
const TRANSPORT_MARKED_MODULATE: Color = Color(0.55, 0.85, 1.0, 1.0)
const TRANSPORT_CARRYING_MODULATE: Color = Color(0.35, 1.0, 0.65, 1.0)

const SPELL_BTN_LABELS := {
	"heal": "Heal",
	"boost": "Boost",
	"mortar": "Mortar Ult",
	"anti_armor": "Armor Break",
}

var _selected_healer_count: int = 0
var _selected_support_count: int = 0
var _selected_mortar_count: int = 0
var _selected_anti_armor_count: int = 0
var _selected_transporter_count: int = 0


func _ready() -> void:
	btn_heal.disabled = true
	btn_boost.disabled = true
	btn_mortar_spell.disabled = true
	btn_anti_armor.disabled = true
	btn_water_transport.disabled = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_transport_marks()


func _process(_delta: float) -> void:
	_refresh_button_state()


func _spell_cast_availability(unit_type: int) -> Dictionary:
	var ready_count := 0
	var min_cd := INF
	for unit in _get_selected_units_by_type(unit_type):
		if unit.has_method("can_cast_spell") and unit.can_cast_spell():
			ready_count += 1
			continue
		if unit.has_method("get_spell_cooldown_remaining"):
			var cd: float = unit.get_spell_cooldown_remaining()
			if cd > 0.0:
				min_cd = minf(min_cd, cd)
	if min_cd == INF:
		min_cd = 0.0
	return {"ready": ready_count, "min_cooldown": min_cd}


func _apply_spell_button_state(btn: Button, selected_count: int, unit_type: int, label_key: String) -> void:
	var base_label: String = SPELL_BTN_LABELS.get(label_key, label_key)
	if selected_count <= 0:
		btn.disabled = true
		btn.text = base_label
		btn.modulate = Color.WHITE
		return

	var availability: Dictionary = _spell_cast_availability(unit_type)
	if availability.ready > 0:
		btn.disabled = false
		btn.text = base_label
		btn.modulate = Color.WHITE
		return

	btn.disabled = true
	var min_cd: float = availability.min_cooldown
	if min_cd > 0.0:
		btn.text = "%s %.0fs" % [base_label, ceil(min_cd)]
		btn.modulate = Color(0.65, 0.65, 0.65, 1.0)
	else:
		btn.text = base_label
		btn.modulate = Color(0.65, 0.65, 0.65, 1.0)


func _refresh_button_state() -> void:
	var healers := 0
	var supports := 0
	var mortars := 0
	var anti_armors := 0
	var transporters := 0

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
			5:
				anti_armors += 1
			7:
				transporters += 1

	if healers == _selected_healer_count \
			and supports == _selected_support_count \
			and mortars == _selected_mortar_count \
			and anti_armors == _selected_anti_armor_count \
			and transporters == _selected_transporter_count:
		_apply_spell_button_state(btn_heal, _selected_healer_count, 4, "heal")
		_apply_spell_button_state(btn_boost, _selected_support_count, 3, "boost")
		_apply_spell_button_state(btn_mortar_spell, _selected_mortar_count, 6, "mortar")
		_apply_spell_button_state(btn_anti_armor, _selected_anti_armor_count, 5, "anti_armor")
		_update_transport_button_visuals()
		return

	_selected_healer_count = healers
	_selected_support_count = supports
	_selected_mortar_count = mortars
	_selected_anti_armor_count = anti_armors
	_selected_transporter_count = transporters

	_apply_spell_button_state(btn_heal, _selected_healer_count, 4, "heal")
	_apply_spell_button_state(btn_boost, _selected_support_count, 3, "boost")
	_apply_spell_button_state(btn_mortar_spell, _selected_mortar_count, 6, "mortar")
	_apply_spell_button_state(btn_anti_armor, _selected_anti_armor_count, 5, "anti_armor")
	_update_transport_button_visuals()


func _update_transport_button_visuals() -> void:
	if _selected_transporter_count <= 0:
		btn_water_transport.disabled = true
		btn_water_transport.modulate = Color.WHITE
		btn_water_transport.text = "Transport"
		return

	var transporters := _get_selected_units_by_type(7)
	var max_cd := 0.0
	var any_marked := false
	var any_carrying := false
	for unit in transporters:
		if unit.has_method("get_water_transport_cooldown_remaining"):
			max_cd = maxf(max_cd, unit.get_water_transport_cooldown_remaining())
		if unit.has_method("get_water_transport_phase"):
			var phase: int = unit.get_water_transport_phase()
			if phase == 1:
				any_marked = true
			elif phase == 2:
				any_carrying = true

	btn_water_transport.disabled = _selected_transporter_count <= 0 or (max_cd > 0.0 and not any_marked and not any_carrying)
	if max_cd > 0.0:
		btn_water_transport.text = "Transport %.0fs" % ceil(max_cd)
		btn_water_transport.modulate = Color(0.65, 0.65, 0.65, 1.0)
	elif any_carrying:
		btn_water_transport.text = "Disembark"
		btn_water_transport.modulate = TRANSPORT_CARRYING_MODULATE
	elif any_marked:
		btn_water_transport.text = "Embark"
		btn_water_transport.modulate = TRANSPORT_MARKED_MODULATE
	else:
		btn_water_transport.text = "Transport"
		btn_water_transport.modulate = Color.WHITE


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


func _on_btn_anti_armor_pressed() -> void:
	var anti_armors: Array = _get_selected_units_by_type(5)
	var casts := 0
	for anti_armor in anti_armors:
		if _try_cast_spell(anti_armor):
			casts += 1
			var radius: float = anti_armor.get_anti_armor_spell_radius() if anti_armor.has_method("get_anti_armor_spell_radius") else SPELL_EFFECT_RADIUS
			_show_effect_zone(anti_armor.global_position, radius, ANTI_ARMOR_BORDER_COLOR, ANTI_ARMOR_FILL_COLOR)
	print("%d anti-armor(s) selected, %d spell(s) cast" % [_selected_anti_armor_count, casts])


func _on_btn_water_transport_pressed() -> void:
	var transporters: Array = _get_selected_units_by_type(7)
	var steps := 0
	for transporter in transporters:
		if not transporter.has_method("water_transport_step"):
			continue
		var phase_before: int = transporter.get_water_transport_phase() if transporter.has_method("get_water_transport_phase") else 0
		if transporter.water_transport_step():
			steps += 1
			if MapSession.is_local_team(int(transporter.get("team"))):
				Sound.play_transport()
			if phase_before == 0:
				_show_effect_zone(
					transporter.global_position,
					SPELL_EFFECT_RADIUS,
					TRANSPORT_BORDER_COLOR,
					TRANSPORT_FILL_COLOR
				)
	print("%d transporter(s) selected, %d transport step(s)" % [_selected_transporter_count, steps])


func _cancel_transport_marks() -> void:
	for unit in get_tree().get_nodes_in_group("soldiers"):
		if not unit.get("is_selected"):
			continue
		if unit.has_method("water_transport_cancel_mark"):
			unit.water_transport_cancel_mark()


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
