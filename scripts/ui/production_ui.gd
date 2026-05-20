extends CanvasLayer

@onready var panel = $Control/Panel
@onready var gold_label = $Control/LabelArgent
@onready var queue_label = $Control/Panel/LabelQueue
@onready var level_label = $Control/Panel/LabelNiveau
@onready var btn_upgrade = $Control/Panel/GridContainer/BtnUpgrade

var selected_building = null


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
		if selected_building.has_method("is_port") and selected_building.is_port():
			panel.hide()
			level_label.text = "Port — naval production coming soon"
			return
		panel.show()
		_update_queue_display(0, 0)
		_update_level_display()
		_refresh_upgrade_button()
		if not selected_building.production_updated.is_connected(_update_queue_display):
			selected_building.production_updated.connect(_update_queue_display)
		if selected_building.has_signal("camp_upgradedd") and not selected_building.camp_upgradedd.is_connected(_on_camp_upgradedd):
			selected_building.camp_upgradedd.connect(_on_camp_upgradedd)
			Sound.play_menu2()
	else:
		panel.hide()
		level_label.text = ""


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
	level_label.text = "Camp level: " + str(level)


func _refresh_upgrade_button() -> void:
	if not selected_building:
		btn_upgrade.disabled = true
		btn_upgrade.text = "Upgrade Camp"
		return
	if not selected_building.has_method("can_upgrade"):
		btn_upgrade.disabled = true
		btn_upgrade.text = "Upgrade unavailable"
		return

	if not selected_building.can_upgrade():
		btn_upgrade.disabled = true
		btn_upgrade.text = "Camp MAX"
		return

	var cost = selected_building.next_upgrade_cost() if selected_building.has_method("next_upgrade_cost") else -1
	var can_afford = cost > 0 and Economy.gold >= cost
	btn_upgrade.disabled = not can_afford
	btn_upgrade.text = "Upgrade Camp (%sG)" % str(cost) if cost > 0 else "Upgrade Camp"


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


func _on_gold_changed(value) -> void:
	gold_label.text = "GOLD: " + str(value)
	_refresh_upgrade_button()
