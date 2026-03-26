extends Node2D

var en_selection : bool = false
var point_depart : Vector2 = Vector2.ZERO

@onready var boite_selection = $BoiteSelection

func _ready():
	# On cache la boîte au démarrage
	boite_selection.hide()

func _unhandled_input(event):
	# Si on fait un CLIC GAUCHE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# On commence à dessiner
			en_selection = true
			point_depart = get_global_mouse_position()
			boite_selection.global_position = point_depart
			boite_selection.size = Vector2.ZERO
			boite_selection.show()
		else:
			# On relâche le clic
			en_selection = false
			boite_selection.hide()
			selectionner_unites()

	# Si on BOUGE LA SOURIS pendant qu'on clique
	if event is InputEventMouseMotion and en_selection:
		var position_actuelle = get_global_mouse_position()
		
		# Ces maths permettent de dessiner la boîte dans n'importe quel sens (vers le haut, la gauche...)
		boite_selection.global_position = Vector2(min(point_depart.x, position_actuelle.x), min(point_depart.y, position_actuelle.y))
		boite_selection.size = Vector2(abs(position_actuelle.x - point_depart.x), abs(position_actuelle.y - point_depart.y))
		
		# --- AJOUTE CECI A LA FIN DE LA FONCTION _unhandled_input ---
	
	# Si on fait un CLIC DROIT
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var destination = get_global_mouse_position()
		var selection = []
		
		# On récupère tous les soldats sélectionnés
		for soldat in get_tree().get_nodes_in_group("soldats"):
			if soldat.est_selectionne:
				selection.append(soldat)
		
		var nb = selection.size()
		if nb == 0: return # Rien à faire si rien n'est sélectionné
		
		# Calcul de la formation (grille simple)
		var colonnes = ceil(sqrt(nb))
		var espacement = 32.0 # Distance entre les soldats
		
		for i in range(nb):
			var x = (i % int(colonnes)) * espacement
			var y = (i / int(colonnes)) * espacement
			
			# On centre la formation sur le point de clic
			var offset = Vector2(
				x - (colonnes - 1) * espacement / 2.0,
				y - (ceil(float(nb) / colonnes) - 1) * espacement / 2.0
			)
			selection[i].aller_vers(destination + offset)

func selectionner_unites():
	# On crée une zone mathématique invisible par dessus notre zone visuelle
	var zone = Rect2(boite_selection.global_position, boite_selection.size)
	
	# On récupère tous les soldats de la carte grâce au groupe !
	var liste_soldats = get_tree().get_nodes_in_group("soldats")
	
	for soldat in liste_soldats:
		# Si le soldat touche notre zone
		if zone.has_point(soldat.global_position):
			soldat.set_selection(true)
		else:
			# Astuce : si on trace une boîte vide (un simple clic), ça désélectionne les autres !
			soldat.set_selection(false)
