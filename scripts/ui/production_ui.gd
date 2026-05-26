extends CanvasLayer

@onready var panel = $Control/Panel
@onready var gold_label = $Control/GoldPanel/GoldRow/LabelArgent
@onready var queue_label = $Control/Panel/LabelQueue
@onready var level_label = $Control/Panel/LabelNiveau
@onready var btn_upgrade = $Control/Panel/GridContainer/BtnUpgrade
@onready var btn_inf = $Control/Panel/GridContainer/BtnInf
@onready var btn_arc = $Control/Panel/GridContainer/BtnArc
@onready var btn_heavy = $Control/Panel/GridContainer/BtnHeavy
@onready var btn_support = $Control/Panel/GridContainer/BtnSupport
@onready var btn_heal = $Control/Panel/GridContainer/BtnHeal
@onready var btn_anti_armor = $Control/Panel/GridContainer/BtnAntiArmor
@onready var btn_mortar = $Control/Panel/GridContainer/BtnMortar

var selected_building = null
var _port_production_mode := false


func _ready() -> void:
	panel.hide()
	_connect_manager_signal()
	call_deferred("_connect_manager_signal")

	Economy.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(Economy.gold)


func _connect_manager_signal() -> void:
	var manager = get_tree().get_first_node_in_group("manager_rts")
	if manager and not manager.selected_building_changed.is_connected(_on_building_changed):
		manager.selected_building_changed.connect(_on_building_changed)


func _on_building_changed(building) -> void:
	Sound.play_menu2()
	if selected_building and selected_building.has_signal("production_updated"):
		if selected_building.production_updated.is_connected(_update_queue_display):
			selected_building.production_updated.disconnect(_update_queue_display)
	if selected_building and selected_building.has_signal("camp_upgradedd"):
		if selected_building.camp_upgradedd.is_connected(_on_camp_upgradedd):
			selected_building.camp_upgradedd.disconnect(_on_camp_upgradedd)

	selected_building = building

	if selected_building and selected_building.get("team") == 0:
		_port_production_mode = selected_building.has_method("is_port") and selected_building.is_port()
		panel.show()
		_apply_production_button_layout()
		_update_queue_display(0, 0)
		_update_level_display()
		_refresh_upgrade_button()
		if not selected_building.production_updated.is_connected(_update_queue_display):
			selected_building.production_updated.connect(_update_queue_display)
		if selected_building.has_signal("camp_upgradedd") and not selected_building.camp_upgradedd.is_connected(_on_camp_upgradedd):
			selected_building.camp_upgradedd.connect(_on_camp_upgradedd)
			Sound.play_menu2()
	else:
		_port_production_mode = false
		panel.hide()
		level_label.text = ""


func _apply_production_button_layout() -> void:
	if _port_production_mode:
		btn_support.hide()
		btn_heal.hide()
		btn_anti_armor.hide()
		btn_mortar.hide()
		_set_port_button_labels()
	else:
		btn_support.show()
		btn_heal.show()
		btn_anti_armor.show()
		btn_mortar.show()
		btn_inf.text = "Infantry (50G)"
		btn_arc.text = "Range (80G)"
		btn_heavy.text = "Heavy (150G)"
		btn_support.text = "Support (100G)"
		btn_heal.text = "Heal (100G)"
		btn_anti_armor.text = "Anti-Armor (90G)"
		btn_mortar.text = "Mortier (200G)"


func _set_port_button_labels() -> void:
	if not selected_building:
		return
	var catalog: Dictionary = selected_building.get("unit_catalog")
	if catalog.is_empty():
		return
	var ids := [0, 1, 2]
	var buttons := [btn_inf, btn_arc, btn_heavy]
	var defaults := ["Water Transport", "Water Tank", "Water Range"]
	for i in ids.size():
		var stat: UnitStats = catalog.get(ids[i])
		if stat:
			buttons[i].text = "%s (%sG)" % [stat.name, str(stat.price)]
		else:
			buttons[i].text = defaults[i]


func _update_queue_display(size, progress) -> void:
	if size > 0:
		queue_label.text = "Queue: " + str(size) + " (" + str(int(progress * 100)) + "%)"
	else:
		queue_label.text = "Queue empty"
	_update_level_display()
	_refresh_upgrade_button()


func _update_level_display() -> void:
	if not selected_building:
		level_label.text = ""
		return
	var level = int(selected_building.get("camp_level"))
	if _port_production_mode:
		level_label.text = "Port level: " + str(level)
	else:
		level_label.text = "Camp level: " + str(level)


func _refresh_upgrade_button() -> void:
	if not selected_building:
		btn_upgrade.disabled = true
		var label := "Upgrade Port" if _port_production_mode else "Upgrade Camp"
		btn_upgrade.text = label
		return
	if not selected_building.has_method("can_upgrade"):
		btn_upgrade.disabled = true
		btn_upgrade.text = "Upgrade unavailable"
		return

	if not selected_building.can_upgrade():
		btn_upgrade.disabled = true
		btn_upgrade.text = ("Port MAX" if _port_production_mode else "Camp MAX")
		return

	var cost = selected_building.next_upgrade_cost() if selected_building.has_method("next_upgrade_cost") else -1
	var can_afford = cost > 0 and Economy.gold >= cost
	btn_upgrade.disabled = not can_afford
	var upgrade_label := "Upgrade Port" if _port_production_mode else "Upgrade Camp"
	btn_upgrade.text = "%s (%sG)" % [upgrade_label, str(cost)] if cost > 0 else upgrade_label


func _on_btn_inf_pressed() -> void:
	Sound.play_menu1()
	if selected_building:
		selected_building.request_production(0)


func _on_btn_arc_pressed() -> void:
	Sound.play_menu1()
	if selected_building:
		selected_building.request_production(1)


func _on_btn_lourd_pressed() -> void:
	Sound.play_menu1()
	if selected_building:
		selected_building.request_production(2)


func _on_btn_support_pressed() -> void:
	Sound.play_menu1()
	if selected_building:
		selected_building.request_production(3)


func _on_btn_heal_pressed() -> void:
	Sound.play_menu1()
	if selected_building:
		selected_building.request_production(4)


func _on_btn_anti_armor_pressed() -> void:
	Sound.play_menu1()
	if selected_building:
		selected_building.request_production(5)


func _on_btn_mortar_pressed() -> void:
	Sound.play_menu1()
	if selected_building:
		selected_building.request_production(6)


func _on_btn_upgrade_pressed() -> void:
	if not selected_building or not selected_building.has_method("upgrade_camp"):
		return
	if selected_building.upgrade_camp():
		Sound.play_menu1()
		_update_level_display()
		_refresh_upgrade_button()


func _on_camp_upgradedd(_new_level) -> void:
	_update_level_display()
	_refresh_upgrade_button()
	if _port_production_mode:
		_set_port_button_labels()


func _on_gold_changed(value) -> void:
	gold_label.text = str(value)
	_refresh_upgrade_button()
