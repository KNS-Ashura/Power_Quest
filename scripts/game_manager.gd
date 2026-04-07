extends Node

var temps_cycle : float = 30.0
var bonus_or : int = 100
var nb_soldats_renfort : int = 2
var fin_de_partie : bool = false

@onready var timer_global = Timer.new()

func _ready():
	add_child(timer_global)
	timer_global.wait_time = temps_cycle
	timer_global.timeout.connect(_on_timer_global_timeout)
	timer_global.start()
	call_deferred("_assigner_camps_initial")

func _assigner_camps_initial():
	var tous_les_camps = get_tree().get_nodes_in_group("camps")
	if tous_les_camps.size() < 2: return
	
	tous_les_camps.shuffle()
	
	var nb_camps_par_joueur = max(1, tous_les_camps.size() / 4)
	var index = 0
	
	for i in range(nb_camps_par_joueur):
		tous_les_camps[index]._etre_capture_par_equipe(0)
		index += 1
		tous_les_camps[index]._etre_capture_par_equipe(1)
		index += 1
		
	while index < tous_les_camps.size():
		tous_les_camps[index]._etre_capture_par_equipe(2)
		index += 1

func _process(_delta):
	if fin_de_partie: return
	
	var tous_les_camps = get_tree().get_nodes_in_group("camps")
	if tous_les_camps.size() == 0: return
	
	var nb_joueur = 0
	var nb_ennemi = 0
	
	for camp in tous_les_camps:
		var eq = camp.get("equipe")
		if eq == 0: nb_joueur += 1
		elif eq == 1: nb_ennemi += 1
		
	if nb_joueur == 0:
		fin_de_partie = true
		print("DEFAITE")
	elif nb_ennemi == 0:
		fin_de_partie = true
		print("VICTOIRE")

func _on_timer_global_timeout():
	if fin_de_partie: return
	
	Economie.ajouter_argent(bonus_or)
	
	for camp in get_tree().get_nodes_in_group("camps"):
		if camp.get("equipe") == 0:
			camp.recevoir_renforts(nb_soldats_renfort)
			break
