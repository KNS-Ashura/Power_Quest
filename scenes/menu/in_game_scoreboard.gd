extends Node2D

var template_ligne = preload("res://scenes/menu/ligne_joueur.tscn")
@onready var liste_joueurs = $MainPanel/TableauContainer/ListeJoueurs

var data_joueurs = [
	{"nom": "Toi (Joueur 1)", "troupes": 42, "camps": 3, "or": 1500},
	{"nom": "Ennemi IA 1", "troupes": 15, "camps": 1, "or": 300},
	{"nom": "Toi (Joueur 1)", "troupes": 42, "camps": 3, "or": 1500},
	{"nom": "Ennemi IA 1", "troupes": 15, "camps": 1, "or": 300},
	{"nom": "Toi (Joueur 1)", "troupes": 42, "camps": 3, "or": 1500},
	{"nom": "Ennemi IA 1", "troupes": 15, "camps": 1, "or": 300},
	{"nom": "Toi (Joueur 1)", "troupes": 42, "camps": 3, "or": 1500},
	{"nom": "Ennemi IA 1", "troupes": 15, "camps": 1, "or": 300}
]

func _ready():
	print("\n=============================================")
	print("--- [DEBUG] INITIALISATION DU SCOREBOARD ---")
	print("=============================================")
	
	# 1. Vérification du conteneur cible
	if liste_joueurs == null:
		print("[ERREUR CRITIQUE] Le conteneur 'liste_joueurs' n'a pas été trouvé !")
		print("  -> Chemin configuré : $MainPanel/TableauContainer/ListeJoueurs")
		print("  -> Vérifie si les noms ou l'arborescence dans l'éditeur correspondent.")
		return
	else:
		print("[OK] Conteneur 'liste_joueurs' trouvé avec succès.")
		print("  -> Nombre d'enfants au démarrage : ", liste_joueurs.get_child_count())

	# 2. Forcer la visibilité de l'interface
	if has_node("MainPanel"):
		$MainPanel.show()
		$MainPanel.modulate.a = 1.0
		print("[OK] Visibilité et opacité de MainPanel forcées à 100%.")
	
	# 3. Nettoyage des anciens enfants
	print("[DEBUG] Nettoyage de la liste...")
	for child in liste_joueurs.get_children():
		child.queue_free()
		
	generer_classement()

func generer_classement():
	print("\n--- [DEBUG] DÉBUT DE LA GÉNÉRATION DES JOUEURS ---")
	
	# 4. Vérification du fichier préchargé
	if template_ligne == null:
		print("[ERREUR CRITIQUE] Impossible de charger 'ligne_joueur.tscn'. Vérifie le chemin du preload.")
		return
	else:
		print("[OK] Fichier 'ligne_joueur.tscn' chargé en mémoire.")

	print("[DEBUG] Nombre de joueurs à insérer : ", data_joueurs.size())

	for i in range(data_joueurs.size()):
		print("\n  -> [Joueur ", i, "] Préparation de : ", data_joueurs[i]["nom"])
		
		var ligne = template_ligne.instantiate()
		if ligne == null:
			print("     [ERREUR] Échec critique lors de l'instanciation (.instantiate())")
			continue
			
		# Recherche des nœuds à la racine (si le changement de racine a fonctionné)
		var node_name = ligne.get_node_or_null("TxtNom")
		var node_troupes = ligne.get_node_or_null("TxtTroupes")
		var node_camps = ligne.get_node_or_null("TxtCamps")
		var node_or = ligne.get_node_or_null("TxtOr")
		
		# 5. Diagnostic intelligent des nœuds de la ligne
		if node_name == null:
			print("     [ATTENTION] 'TxtNom' est introuvable à la racine de la ligne.")
			
			# Vérification automatique de sécurité : le sous-nœud existe-t-il encore ?
			if ligne.get_node_or_null("LigneJoueur/TxtNom") != null:
				print("     [INFO TROUVÉE] Ils sont dans 'LigneJoueur/TxtNom'. La scène modèle n'a pas été enregistrée après modification de la racine !")
				node_name = ligne.get_node("LigneJoueur/TxtNom")
				node_troupes = ligne.get_node("LigneJoueur/TxtTroupes")
				node_camps = ligne.get_node("LigneJoueur/TxtCamps")
				node_or = ligne.get_node("LigneJoueur/TxtOr")
			else:
				print("     [ERREUR] Les nœuds restent introuvables. Vérifie l'orthographe exacte dans ta scène modèle.")
		else:
			print("     [OK] Nœuds détectés directement à la racine de la ligne.")

		# Remplissage des textes si les nœuds sont valides
		if node_name: node_name.text = data_joueurs[i]["nom"]
		if node_troupes: node_troupes.text = str(data_joueurs[i]["troupes"])
		if node_camps: node_camps.text = str(data_joueurs[i]["camps"])
		if node_or: node_or.text = str(data_joueurs[i]["or"])
		
		# 6. Ajout au conteneur
		liste_joueurs.add_child(ligne)
		print("     [OK] Ligne connectée à l'UI. Enfants totaux dans la liste : ", liste_joueurs.get_child_count())
		
	print("\n=============================================")
	print("--- [DEBUG] FIN DE LA GÉNÉRATION ---")
	print("=============================================")
