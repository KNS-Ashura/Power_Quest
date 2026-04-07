extends CanvasLayer

@onready var panel = $Control/Panel
@onready var label_argent = $Control/LabelArgent
@onready var label_queue = $Control/Panel/LabelQueue

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

	current_batiment = bat
	
	if current_batiment and current_batiment.get("equipe") == 0:
		panel.show()
		_update_queue_display(0, 0)
		if not current_batiment.production_maj.is_connected(_update_queue_display):
			current_batiment.production_maj.connect(_update_queue_display)
			
			Sound.play_menu2()
	else:
		panel.hide()

func _update_queue_display(taille, progression):
	if taille > 0:
		label_queue.text = "File : " + str(taille) + " (" + str(int(progression * 100)) + "%)"
	else:
		label_queue.text = "File vide"

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

func _on_argent_modifie(val):
	label_argent.text = "OR : " + str(val)
