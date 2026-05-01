extends CanvasLayer

@onready var panel = $Control/Panel
@onready var label_argent = $Control/LabelArgent
@onready var label_queue = $Control/Panel/LabelQueue
@onready var label_niveau = $Control/Panel/LabelNiveau
@onready var btn_upgrade = $Control/Panel/GridContainer/BtnUpgrade

var current_batiment = null

func _ready():
	panel.hide()
	var manager = get_tree().get_first_node_in_group("manager_rts")
	if manager:
		manager.batiment_selectionne_change.connect(_on_batiment_change)
	
	Economie.argent_modifie.connect(_on_argent_modifie)
	_on_argent_modifie(Economie.argent)

func _on_batiment_change(bat):
	Sound.play_menu2()
	if current_batiment and current_batiment.has_signal("production_maj"):
		if current_batiment.production_maj.is_connected(_update_queue_display):
			current_batiment.production_maj.disconnect(_update_queue_display)
	if current_batiment and current_batiment.has_signal("camp_upgrade"):
		if current_batiment.camp_upgrade.is_connected(_on_camp_upgrade):
			current_batiment.camp_upgrade.disconnect(_on_camp_upgrade)

	current_batiment = bat
	
	if current_batiment and current_batiment.get("equipe") == 0:
		panel.show()
		_update_queue_display(0, 0)
		_update_niveau_display()
		_refresh_upgrade_button()
		if not current_batiment.production_maj.is_connected(_update_queue_display):
			current_batiment.production_maj.connect(_update_queue_display)
		if current_batiment.has_signal("camp_upgrade") and not current_batiment.camp_upgrade.is_connected(_on_camp_upgrade):
			current_batiment.camp_upgrade.connect(_on_camp_upgrade)
			
			Sound.play_menu2()
	else:
		panel.hide()
		label_niveau.text = ""

func _update_queue_display(taille, progression):
	if taille > 0:
		label_queue.text = "File : " + str(taille) + " (" + str(int(progression * 100)) + "%)"
	else:
		label_queue.text = "File vide"
	_update_niveau_display()
	_refresh_upgrade_button()

func _update_niveau_display():
	if not current_batiment:
		label_niveau.text = ""
		return
	var nv = int(current_batiment.get("niveau_camp"))
	label_niveau.text = "Niveau camp : " + str(nv)

func _refresh_upgrade_button():
	if not current_batiment:
		btn_upgrade.disabled = true
		btn_upgrade.text = "Upgrade Camp"
		return
	if not current_batiment.has_method("peut_ameliorer"):
		btn_upgrade.disabled = true
		btn_upgrade.text = "Upgrade indisponible"
		return

	if not current_batiment.peut_ameliorer():
		btn_upgrade.disabled = true
		btn_upgrade.text = "Camp MAX"
		return

	var cout = current_batiment.cout_upgrade_prochain_niveau() if current_batiment.has_method("cout_upgrade_prochain_niveau") else -1
	var peut_payer = cout > 0 and Economie.argent >= cout
	btn_upgrade.disabled = not peut_payer
	btn_upgrade.text = "Upgrade Camp (%sG)" % str(cout) if cout > 0 else "Upgrade Camp"

func _on_btn_inf_pressed():
	Sound.play_menu1()
	if current_batiment:
		current_batiment.demander_production(0)

func _on_btn_arc_pressed():
	Sound.play_menu1()
	if current_batiment:
		current_batiment.demander_production(1)

func _on_btn_lourd_pressed():
	Sound.play_menu1()
	if current_batiment:
		current_batiment.demander_production(2)

func _on_btn_support_pressed():
	Sound.play_menu1()
	if current_batiment:
		current_batiment.demander_production(3)

func _on_btn_heal_pressed():
	Sound.play_menu1()
	if current_batiment:
		current_batiment.demander_production(4)

func _on_btn_anti_armor_pressed():
	Sound.play_menu1()
	if current_batiment:
		current_batiment.demander_production(5)

func _on_btn_mortar_pressed():
	Sound.play_menu1()
	if current_batiment:
		current_batiment.demander_production(6)

func _on_btn_upgrade_pressed():
	if not current_batiment or not current_batiment.has_method("ameliorer_camp"):
		return
	if current_batiment.ameliorer_camp():
		Sound.play_menu1()
		_update_niveau_display()
		_refresh_upgrade_button()

func _on_camp_upgrade(_nouveau_niveau):
	_update_niveau_display()
	_refresh_upgrade_button()

func _on_argent_modifie(val):
	label_argent.text = "OR : " + str(val)
	_refresh_upgrade_button()
