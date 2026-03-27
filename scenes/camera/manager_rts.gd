extends Node2D

@onready var boite_selection = $BoiteSelection

var en_selection : bool = false
var point_depart : Vector2 = Vector2.ZERO

# --- NOUVEAU : Référence au bâtiment ---
var batiment_selectionne : Node2D = null
signal batiment_selectionne_change(batiment)

# --- Caméra ---
@onready var camera = $Camera2D
@export var vitesse_camera : float = 400.0
@export var vitesse_zoom : float = 0.1
var zoom_cible : float = 1.0
var zoom_min : float = 0.5
var zoom_max : float = 2.0

func _ready():
	# On cache la boîte au démarrage
	boite_selection.hide()
	add_to_group("manager_rts")
	
	# Initialisation camera
	if camera:
		camera.make_current()

func _process(delta):
	_gerer_mouvement_camera(delta)
	_gerer_zoom_camera(delta)

func _gerer_mouvement_camera(delta):
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	
	if dir != Vector2.ZERO:
		camera.global_position += dir.normalized() * vitesse_camera * delta * (1.0 / camera.zoom.x)

func _gerer_zoom_camera(delta):
	camera.zoom = camera.zoom.lerp(Vector2(zoom_cible, zoom_cible), 10.0 * delta)

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
	# --- SORT MAGIQUE (TOUCHE E) ---
	if event is InputEventKey and event.keycode == KEY_E and event.pressed:
		var sort_lance = false
		for soldat in get_tree().get_nodes_in_group("soldats"):
			if soldat.get("est_selectionne") and soldat.has_method("lancer_sort"):
				soldat.lancer_sort()
				sort_lance = true
		if sort_lance:
			return # On consomme l'input
	
	# ZOOM MOLETTE
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_cible = clamp(zoom_cible + vitesse_zoom, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_cible = clamp(zoom_cible - vitesse_zoom, zoom_min, zoom_max)

	# Si on BOUGE LA SOURIS pendant qu'on clique
	if event is InputEventMouseMotion and en_selection:
		var position_actuelle = get_global_mouse_position()
		
		# Ces maths permettent de dessiner la boîte dans n'importe quel sens (vers le haut, la gauche...)
		boite_selection.global_position = Vector2(min(point_depart.x, position_actuelle.x), min(point_depart.y, position_actuelle.y))
		boite_selection.size = Vector2(abs(position_actuelle.x - point_depart.x), abs(position_actuelle.y - point_depart.y))
		
		# Si on commence à tracer une boîte, on déselectionne le bâtiment
		if boite_selection.size.length() > 10:
			deselect_batiment()
		
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
		
		# --- FIX CIBLAGE : Détection robuste de la cible ---
		var espace = get_world_2d().direct_space_state
		var requete = PhysicsPointQueryParameters2D.new()
		requete.position = destination
		# On ne détecte plus les Areas pour ne pas cibler la zone de capture géante accidentellement
		requete.collide_with_areas = false
		requete.collide_with_bodies = true
		
		var resultats = espace.intersect_point(requete)
		var cible_a_attaquer = null
		
		for res in resultats:
			var obj = res.collider
			# On ne cible plus les bases, seulement les troupes
			if obj and obj.has_method("recevoir_degats") and not obj.is_in_group("camps"):
				var eq = obj.get("equipe")
				if eq != null and eq != 0: # Si c'est une équipe ennemie
					cible_a_attaquer = obj
					break
				
		if cible_a_attaquer:
			# On attaque la cible
			print("ORDRE D'ATTAQUE sur : ", cible_a_attaquer.name)
			for soldat in selection:
				if soldat.has_method("attaquer_cible"):
					soldat.attaquer_cible(cible_a_attaquer)
		else:
			# Calcul de la formation (grille simple)
			var colonnes = ceil(sqrt(nb))
			var espacement = 24.0 # PLUS COMPACT : 24 au lieu de 32
			
			for i in range(nb):
				var x = (i % int(colonnes)) * espacement
				var y = (i / int(colonnes)) * espacement
				
				# On centre la formation sur le point de clic
				var offset = Vector2(
					x - (colonnes - 1) * espacement / 2.0,
					y - (ceil(float(nb) / colonnes) - 1) * espacement / 2.0
				)
				# On s'assure que le mouvement est précis
				selection[i].aller_vers(destination + offset)

func selectionner_unites():
	# On crée une zone mathématique invisible par dessus notre zone visuelle
	var zone = Rect2(boite_selection.global_position, boite_selection.size)
	
	# On récupère tous les soldats de la carte grâce au groupe !
	var liste_soldats = get_tree().get_nodes_in_group("soldats")
	var unites_selectionnees = 0
	
	for soldat in liste_soldats:
		if soldat.get("equipe") == 0: # 0 = Proprietaire.JOUEUR
			# Si le soldat touche notre zone
			if zone.has_point(soldat.global_position):
				soldat.set_selection(true)
				unites_selectionnees += 1
			else:
				# Astuce : si on trace une boîte vide (un simple clic), ça désélectionne les autres !
				if soldat.has_method("set_selection"):
					soldat.set_selection(false)
		else:
			# Sécurité : on désélectionne les ennemis "au cas où"
			if soldat.has_method("set_selection"):
				soldat.set_selection(false)

	# --- NOUVEAU : Si on a fait un simple clic (pas de boîte) ---
	if boite_selection.size.length() < 5:
		# On cherche si on a cliqué sur un bâtiment
		var espace = get_world_2d().direct_space_state
		var requete = PhysicsPointQueryParameters2D.new()
		requete.position = boite_selection.global_position
		# On veut détecter les bâtiments (leur "corps")
		requete.collide_with_areas = false
		requete.collide_with_bodies = true
		var resultats = espace.intersect_point(requete)
		
		for res in resultats:
			if res.collider and res.collider.is_in_group("camps"):
				select_batiment(res.collider)
				return
		
		# Si on a cliqué dans le vide, on déselectionne tout
		if unites_selectionnees == 0:
			deselect_batiment()

func select_batiment(bat):
	if batiment_selectionne:
		deselect_batiment()
	batiment_selectionne = bat
	if batiment_selectionne.has_method("set_selection"):
		batiment_selectionne.set_selection(true)
	batiment_selectionne_change.emit(batiment_selectionne)
	print("Bâtiment sélectionné : ", bat.name)

func deselect_batiment():
	if batiment_selectionne:
		if batiment_selectionne.has_method("set_selection"):
			batiment_selectionne.set_selection(false)
		batiment_selectionne = null
		batiment_selectionne_change.emit(null)
