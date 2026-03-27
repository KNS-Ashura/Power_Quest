extends Node

var temps_cycle : float = 30.0 # Toutes les 30 secondes
var bonus_or : int = 100
var nb_soldats_renfort : int = 2

@onready var timer_global = Timer.new()

func _ready():
	add_child(timer_global)
	timer_global.wait_time = temps_cycle
	timer_global.timeout.connect(_on_timer_global_timeout)
	timer_global.start()
	print("GameManager actif : Pulse toutes les ", temps_cycle, " secondes.")
	
	# Appel décalé pour s'assurer que tous les camps sont bien chargés
	call_deferred("_assigner_camps_initial")

func _assigner_camps_initial():
	var tous_les_camps = get_tree().get_nodes_in_group("camps")
	if tous_les_camps.size() < 2: return
	
	print("Distribution aléatoire des camps (", tous_les_camps.size(), " au total)...")
	tous_les_camps.shuffle()
	
	# Ex: Chaque joueur reçoit 1 camp par défaut, ou plus si la carte est grande
	var nb_camps_par_joueur = max(1, tous_les_camps.size() / 4)
	var index = 0
	
	for i in range(nb_camps_par_joueur):
		tous_les_camps[index]._etre_capture_par_equipe(0) # JOUEUR (0)
		index += 1
		tous_les_camps[index]._etre_capture_par_equipe(1) # ENNEMI (1)
		index += 1
		
	while index < tous_les_camps.size():
		tous_les_camps[index]._etre_capture_par_equipe(2) # NEUTRE (2)
		index += 1

var fin_de_partie : bool = false

func _process(_delta):
	if fin_de_partie: return
	
	var tous_les_camps = get_tree().get_nodes_in_group("camps")
	if tous_les_camps.size() == 0: return
	
	var nb_joueur = 0
	var nb_ennemi = 0
	
	for camp in tous_les_camps:
		if camp.get("equipe") == 0: nb_joueur += 1
		elif camp.get("equipe") == 1: nb_ennemi += 1
		
	if nb_joueur == 0:
		fin_de_partie = true
		print("=== DEFAITE ! Vous n'avez plus aucun camp. ===")
		# TODO: Afficher l'écran de défaite
		
	elif nb_ennemi == 0:
		# S'il y a plus d'1 jour écoulé (pour éviter une victoire dès la frame 1 si le rand bug)
		fin_de_partie = true
		print("=== VICTOIRE ! Les ennemis ont été éliminés. ===")
		# TODO: Afficher l'écran de victoire

func _on_timer_global_timeout():
	if fin_de_partie: return
	# 1. Donner l'or
	Economie.ajouter_argent(bonus_or)
	
	# 2. Donner les troupes au premier camp du joueur trouvé
	var mes_camps = []
	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.get("equipe") == 0: # 0 = Proprietaire.JOUEUR
			mes_camps.append(camp)
	
	if mes_camps.size() > 0:
		mes_camps[0].recevoir_renforts(nb_soldats_renfort)
	
	print("--- CYCLE GLOBAL : Bonus de ", bonus_or, " or et ", nb_soldats_renfort, " soldats ! ---")
