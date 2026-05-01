extends Node

enum ProfilIA { AGRESSIF, STRATEGIQUE, EPARPILLE }
var profil_actuel : ProfilIA = ProfilIA.STRATEGIQUE
var or_ia : int = 200
var timer_reflexion : Timer

func _ready():
	timer_reflexion = Timer.new()
	add_child(timer_reflexion)
	timer_reflexion.wait_time = 3.0
	timer_reflexion.timeout.connect(_on_reflexion)
	timer_reflexion.start()
	GameManager.timer_global.timeout.connect(_on_cycle_global)

func _on_cycle_global():
	or_ia += GameManager.bonus_or
	for camp in _recuperer_mes_camps():
		or_ia += camp.revenu_par_seconde * GameManager.temps_cycle

func _on_reflexion():
	if GameManager.fin_de_partie: return
	var mes_camps = _recuperer_mes_camps()
	if mes_camps.is_empty(): return
	
	_gerer_production(mes_camps)
	_gerer_militaires()

func _recuperer_mes_camps() -> Array:
	# En solo, l'IA contrôle l'équipe 1. En multi, l'IA est inactive (joueur humain).
	if ServerConnection.has_valid_session():
		return []
	return get_tree().get_nodes_in_group("camps").filter(func(c): return c.get("equipe") == 1)

func _gerer_production(mes_camps : Array):
	for camp in mes_camps:
		if camp.file_production.size() > 1: continue
		
		var unite_choisie = -1
		match profil_actuel:
			ProfilIA.AGRESSIF: unite_choisie = [0, 0, 0, 1].pick_random()
			ProfilIA.STRATEGIQUE: unite_choisie = [1, 2, 4, 5, 6].pick_random()
			ProfilIA.EPARPILLE: unite_choisie = randi() % 7
		
		if unite_choisie != -1:
			var data = camp.catalogue_unites[unite_choisie]
			if or_ia >= data.prix:
				or_ia -= data.prix
				camp.file_production.append(unite_choisie)
				if camp.file_production.size() == 1:
					camp.temps_total_unite_actuelle = data.temps_fabrication
					camp.temps_restant = camp.temps_total_unite_actuelle

func _gerer_militaires():
	var troupes = get_tree().get_nodes_in_group("ennemis")
	if troupes.is_empty(): return
	
	match profil_actuel:
		ProfilIA.AGRESSIF:
			var c = _trouver_camp(troupes[0].global_position, 0)
			if c: _donner_ordre(troupes, c)
		ProfilIA.STRATEGIQUE:
			var c = _trouver_camp(troupes[0].global_position, 2)
			if not c: c = _trouver_camp(troupes[0].global_position, 0)
			if c: _donner_ordre(troupes, c)
		ProfilIA.EPARPILLE:
			for t in troupes:
				if randf() > 0.5:
					var potentiels = get_tree().get_nodes_in_group("camps").filter(func(ca): return ca.get("equipe") in [0, 2])
					if not potentiels.is_empty():
						var cible = potentiels.pick_random()
						if is_instance_valid(cible.gardien): t.attaquer_cible(cible.gardien)

func _trouver_camp(pos: Vector2, id_eq: int) -> Node2D:
	var c = get_tree().get_nodes_in_group("camps").filter(func(ca): return ca.get("equipe") == id_eq)
	if c.is_empty(): return null
	c.sort_custom(func(a,b): return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	return c[0]

func _donner_ordre(troupes: Array, camp_cible: Node2D):
	if !is_instance_valid(camp_cible.gardien): return
	for t in troupes:
		if t.has_method("attaquer_cible") and not is_instance_valid(t.get("cible_attaque")):
			t.attaquer_cible(camp_cible.gardien)
