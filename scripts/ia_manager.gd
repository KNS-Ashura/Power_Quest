extends Node

enum ProfilIA { AGRESSIF, STRATEGIQUE, EPARPILLE }

var profil_actuel : ProfilIA = ProfilIA.STRATEGIQUE

var or_ia : int = 200
var timer_reflexion : Timer

func _ready():
	print("IA Manager (Ennemi) Actif. Profil : ", profil_actuel)
	
	timer_reflexion = Timer.new()
	add_child(timer_reflexion)
	timer_reflexion.wait_time = 3.0 # L'IA réfléchit toutes les 3 secondes
	timer_reflexion.timeout.connect(_on_reflexion)
	timer_reflexion.start()
	
	GameManager.timer_global.timeout.connect(_on_cycle_global)

func _on_cycle_global():
	# L'IA reçoit de l'or de base comme le joueur
	or_ia += GameManager.bonus_or
	
	var mes_camps = _recuperer_mes_camps()
	for camp in mes_camps:
		# Revenu passif par camp possédé
		or_ia += camp.revenu_par_seconde * GameManager.temps_cycle
		
	print("IA - Fin de cycle global. Or total: ", or_ia)

func _on_reflexion():
	if GameManager.fin_de_partie: return
	
	var mes_camps = _recuperer_mes_camps()
	if mes_camps.size() == 0: return # Plus de camp
	
	_gerer_production(mes_camps)
	_gerer_militaires()

func _recuperer_mes_camps() -> Array:
	var camps = []
	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.get("equipe") == 1: # ENNEMI
			camps.append(camp)
	return camps

func _gerer_production(mes_camps : Array):
	# L'IA tente de produire en boucle tant qu'elle a de l'or et des camps libres
	for camp in mes_camps:
		if camp.file_production.size() > 1: continue # Ne sature pas les files d'attente
		
		var unite_choisie = -1
		
		match profil_actuel:
			ProfilIA.AGRESSIF:
				unite_choisie = _choisir_unite([0, 0, 0, 1]) # Beaucoup d'infanterie (0) et un peu d'archer (1)
			ProfilIA.STRATEGIQUE:
				unite_choisie = _choisir_unite([1, 2, 4, 5, 6]) # Ranged, Lourds, Heals, AntiArmor, Mortiers
			ProfilIA.EPARPILLE:
				unite_choisie = randi() % 7 # Totalement aléatoire
		
		if unite_choisie != -1:
			var prix = camp.catalogue_unites[unite_choisie].prix
			if or_ia >= prix:
				or_ia -= prix
				camp.file_production.append(unite_choisie)
				if camp.file_production.size() == 1:
					camp.temps_total_unite_actuelle = camp.catalogue_unites[unite_choisie].temps_fabrication
					camp.temps_restant = camp.temps_total_unite_actuelle

func _choisir_unite(liste_choix : Array) -> int:
	return liste_choix[randi() % liste_choix.size()]

func _gerer_militaires():
	var mes_troupes = get_tree().get_nodes_in_group("ennemis")
	if mes_troupes.size() == 0: return
	
	match profil_actuel:
		ProfilIA.AGRESSIF:
			# Lance toutes ses troupes oisives vers un camp allié au lieu de réfléchir
			var cible = _trouver_camp_le_plus_proche(mes_troupes[0].global_position, 0) # Cible = JOUEUR
			if cible:
				_donner_ordre_attaque(mes_troupes, cible)
				
		ProfilIA.STRATEGIQUE:
			# Séparer les troupes en escouades ou attaque structurée
			# Pour faire simple : Envoie tout sur le camp Neutre le plus proche, puis sur le Joueur.
			var cible = _trouver_camp_le_plus_proche(mes_troupes[0].global_position, 2) # NEUTRE
			if not cible:
				cible = _trouver_camp_le_plus_proche(mes_troupes[0].global_position, 0) # JOUEUR
			if cible:
				_donner_ordre_attaque(mes_troupes, cible)

		ProfilIA.EPARPILLE:
			# Choisit une unité au hasard et l'envoie n'importe où
			for troupe in mes_troupes:
				if randf() > 0.5:
					var cible = _trouver_camp_hasard([0, 2])
					if cible and is_instance_valid(cible.gardien):
						troupe.attaquer_cible(cible.gardien)

func _trouver_camp_le_plus_proche(pos: Vector2, id_equipe: int) -> Node2D:
	var plus_proche = null
	var dist_min = 999999.0
	
	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.get("equipe") == id_equipe:
			var d = camp.global_position.distance_to(pos)
			if d < dist_min:
				dist_min = d
				plus_proche = camp
	return plus_proche

func _trouver_camp_hasard(ids_equipes_possibles : Array) -> Node2D:
	var potentiels = []
	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.get("equipe") in ids_equipes_possibles:
			potentiels.append(camp)
	if potentiels.size() > 0:
		return potentiels[randi() % potentiels.size()]
	return null

func _donner_ordre_attaque(troupes: Array, camp_cible: Node2D):
	if !is_instance_valid(camp_cible.gardien): return
	
	for troupe in troupes:
		# Si la troupe n'a pas de cible valide
		if troupe.has_method("attaquer_cible") and not is_instance_valid(troupe.get("cible_attaque")):
			troupe.attaquer_cible(camp_cible.gardien)
