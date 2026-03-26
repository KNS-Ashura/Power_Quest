extends Area2D

var revenu_par_seconde : int = 10

const SCENE_SOLDAT = preload("res://scenes/personnages/player/soldat.tscn")

@onready var camp_menu = $HUDLayer/CampMenu
@onready var label_argent = $HUDLayer/LabelArgent
@onready var conteneur_boutons = $HUDLayer/CampMenu/GridContainer
@onready var point_apparition = $PointApparition
@onready var timer_entrainement = $TimerEntrainement

var file_attente : Array = []

var troupes_data = {
	0: {"nom": "Épéiste", "prix": 50},
	1: {"nom": "Archer", "prix": 75},
	2: {"nom": "Lancier", "prix": 60},
	3: {"nom": "Cavalier", "prix": 150},
	4: {"nom": "Mage", "prix": 200},
	5: {"nom": "Guérisseur", "prix": 120},
	6: {"nom": "Paladin", "prix": 300}
}

func _ready():
	camp_menu.hide()
	
	# On se connecte à l'économie globale pour mettre à jour l'affichage
	Economie.argent_modifie.connect(func(_nouveau_montant): mettre_a_jour_affichage_argent())
	mettre_a_jour_affichage_argent()
	
	var index = 0
	for bouton in conteneur_boutons.get_children():
		if bouton is Button and index < 7:
			var troupe = troupes_data[index]
			bouton.text = troupe["nom"] + " (" + str(troupe["prix"]) + ")"
			bouton.pressed.connect(acheter_troupe.bind(index))
			index += 1

func _on_timer_timeout():
	Economie.ajouter_argent(revenu_par_seconde)

func mettre_a_jour_affichage_argent():
	label_argent.text = "Argent : " + str(Economie.argent)
	if file_attente.size() > 0:
		label_argent.text += " | En attente : " + str(file_attente.size())

func _on_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		camp_menu.show()
		get_viewport().set_input_as_handled()

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if camp_menu.visible:
			camp_menu.hide()

func acheter_troupe(id_troupe):
	var troupe = troupes_data[id_troupe]
	
	if Economie.retrancher_argent(troupe["prix"]):
		file_attente.append(id_troupe)
		mettre_a_jour_affichage_argent()
		print(troupe["nom"] + " ajouté à la file d'attente !")
		if timer_entrainement.is_stopped():
			timer_entrainement.start()
	else:
		print("Pas assez d'argent pour : " + troupe["nom"])

func _on_timer_entrainement_timeout():
	if file_attente.size() > 0:
		var id_troupe_terminee = file_attente.pop_front()
		var troupe = troupes_data[id_troupe_terminee]
		var nouveau_soldat = SCENE_SOLDAT.instantiate()
		var decalage = Vector2(randf_range(-10, 10), randf_range(-10, 10))
		nouveau_soldat.global_position = point_apparition.global_position + decalage
		get_parent().add_child(nouveau_soldat)
		print(troupe["nom"] + " est prêt et déployé !")
		mettre_a_jour_affichage_argent()
		if file_attente.size() > 0:
			timer_entrainement.start()
		else:
			print("File d'attente terminée.")
