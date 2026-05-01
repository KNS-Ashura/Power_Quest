extends StaticBody2D

enum Proprietaire { JOUEUR, ENNEMI, NEUTRE }
@export var equipe : Proprietaire = Proprietaire.NEUTRE
@export var revenu_par_seconde : int = 5
@export var hp_max : int = 500
@export_range(1, 3, 1) var niveau_camp : int = 1
@export var multiplicateur_temps_production : float = 1.0
@export var cout_upgrade_niveau_2 : int = 200
@export var cout_upgrade_niveau_3 : int = 350
var hp_actuels : int = hp_max
var gardien : Node2D = null

const SCENES_INFANTERIE = {
	1: preload("res://scenes/personnages/infantry/infantry-1.tscn"),
	2: preload("res://scenes/personnages/infantry/infantry-2.tscn"),
	3: preload("res://scenes/personnages/infantry/infantry-3.tscn")
}
const SCENE_RANGE = preload("res://scenes/personnages/range/range-1.tscn")
const SCENE_HEAVY = preload("res://scenes/personnages/heavy/heavy-1.tscn")
const SCENE_SUPPORT = preload("res://scenes/personnages/support/support-1.tscn")
const SCENE_HEALER = preload("res://scenes/personnages/healer/healer-1.tscn")
const SCENES_ANTI_ARMOR = {
	1: preload("res://scenes/personnages/anti_armor/anti_armor-1.tscn"),
	2: preload("res://scenes/personnages/anti_armor/anti_armor-2.tscn"),
	3: preload("res://scenes/personnages/anti_armor/anti_armor-3.tscn")
}
const SCENES_GARDIEN = {
	1: preload("res://scenes/personnages/guardian/gardien-1.tscn"),
	2: preload("res://scenes/personnages/guardian/gardien-2.tscn"),
	3: preload("res://scenes/personnages/guardian/gardien-3.tscn")
}
var stats_infanterie_par_niveau = {
	1: preload("res://scripts/resources/infantry/infantry-1.tres"),
	2: preload("res://scripts/resources/infantry/infantry-2.tres"),
	3: preload("res://scripts/resources/infantry/infantry-3.tres")
}
var stats_archer = preload("res://scripts/resources/archer.tres")
var stats_lourd = preload("res://scripts/resources/lourd.tres")
var stats_support = preload("res://scripts/resources/support.tres")
var stats_heal = preload("res://scripts/resources/heal.tres")
var stats_anti_armor_par_niveau = {
	1: preload("res://scripts/resources/anti_armor/anti_armor-1.tres"),
	2: preload("res://scripts/resources/anti_armor/anti_armor-2.tres"),
	3: preload("res://scripts/resources/anti_armor/anti_armor-3.tres")
}
var stats_gardien_par_niveau = {
	1: preload("res://scripts/resources/gardien/gardien-1.tres"),
	2: preload("res://scripts/resources/gardien/gardien-2.tres"),
	3: preload("res://scripts/resources/gardien/gardien-3.tres")
}
var stats_mortar = preload("res://scripts/resources/mortar.tres")

var catalogue_unites = {}

var file_production : Array = []
var temps_restant : float = 0.0
var temps_total_unite_actuelle : float = 1.0

@onready var point_apparition = $Marker2D
@onready var timer_revenu = Timer.new()

var timer_ia_production : Timer = null
@export var frequence_ia : float = 15.0

signal production_maj(file_taille, progression)
signal camp_upgrade(nouveau_niveau)

func _ready():
	_appliquer_configuration_niveau()
	_rafraichir_catalogue_unites()
	add_to_group("camps")
	_mettre_a_jour_groupes_et_visuels()
	
	if has_node("AnimatedSprite2D"): $AnimatedSprite2D.play()
	
	add_child(timer_revenu)
	timer_revenu.wait_time = 1.0
	timer_revenu.timeout.connect(_on_timer_revenu_timeout)
	timer_revenu.start()
	
	timer_ia_production = Timer.new()
	add_child(timer_ia_production)
	timer_ia_production.wait_time = frequence_ia
	timer_ia_production.timeout.connect(_on_timer_ia_timeout)
	timer_ia_production.start()

func _rafraichir_catalogue_unites():
	catalogue_unites = {
		0: _stats_infanterie_niveau(), 1: stats_archer, 2: stats_lourd, 3: stats_support,
		4: stats_heal, 5: _stats_anti_armor_niveau(), 6: stats_mortar
	}

func _stats_pour_niveau(stats_par_niveau: Dictionary) -> UniteStats:
	if stats_par_niveau.has(niveau_camp):
		return stats_par_niveau[niveau_camp]
	return stats_par_niveau[1]

func _scene_pour_niveau(scenes_par_niveau: Dictionary) -> PackedScene:
	if scenes_par_niveau.has(niveau_camp):
		return scenes_par_niveau[niveau_camp]
	return scenes_par_niveau[1]

func _stats_infanterie_niveau() -> UniteStats:
	return _stats_pour_niveau(stats_infanterie_par_niveau)

func _stats_anti_armor_niveau() -> UniteStats:
	return _stats_pour_niveau(stats_anti_armor_par_niveau)

func _stats_gardien_niveau() -> UniteStats:
	return _stats_pour_niveau(stats_gardien_par_niveau)

func _scene_infanterie_niveau() -> PackedScene:
	return _scene_pour_niveau(SCENES_INFANTERIE)

func _scene_anti_armor_niveau() -> PackedScene:
	return _scene_pour_niveau(SCENES_ANTI_ARMOR)

func _scene_gardien_niveau() -> PackedScene:
	return _scene_pour_niveau(SCENES_GARDIEN)

func _appliquer_configuration_niveau():
	match niveau_camp:
		1:
			revenu_par_seconde = 5
			hp_max = 500
			frequence_ia = 15.0
			multiplicateur_temps_production = 1.0
		2:
			revenu_par_seconde = 7
			hp_max = 700
			frequence_ia = 12.0
			multiplicateur_temps_production = 0.85
		3:
			revenu_par_seconde = 10
			hp_max = 1000
			frequence_ia = 9.0
			multiplicateur_temps_production = 0.7
		_:
			revenu_par_seconde = 5
			hp_max = 500
			frequence_ia = 15.0
			multiplicateur_temps_production = 1.0
	hp_actuels = hp_max

func temps_fabrication_unite(unite_id: int) -> float:
	if not catalogue_unites.has(unite_id):
		return 1.0
	return _temps_fabrication_pour(catalogue_unites[unite_id])

func _temps_fabrication_pour(data: UniteStats) -> float:
	return max(0.1, data.temps_fabrication * multiplicateur_temps_production)

func _process(delta):
	if not is_instance_valid(gardien):
		_invoquer_gardien()
	
	if file_production.size() > 0:
		temps_restant -= delta
		production_maj.emit(file_production.size(), 1.0 - (temps_restant / temps_total_unite_actuelle))
		if temps_restant <= 0:
			terminer_production()

func _invoquer_gardien():
	if is_instance_valid(gardien): return
	var nouveau_gardien = _scene_gardien_niveau().instantiate()
	if not ("stats" in nouveau_gardien):
		push_warning("Scene gardien invalide: la racine doit contenir la propriete 'stats'.")
		nouveau_gardien.queue_free()
		return
	nouveau_gardien.stats = _stats_gardien_niveau()

	var spawn_position = _position_spawn_gardien()
	nouveau_gardien.equipe = equipe
	
	if equipe == Proprietaire.JOUEUR: nouveau_gardien.add_to_group("soldats")
	elif equipe == Proprietaire.ENNEMI:
		if nouveau_gardien.is_in_group("soldats"): nouveau_gardien.remove_from_group("soldats")
		nouveau_gardien.add_to_group("ennemis")
		
	get_parent().add_child(nouveau_gardien)
	nouveau_gardien.global_position = spawn_position
	if nouveau_gardien.has_method("configurer_mode_gardien"):
		nouveau_gardien.configurer_mode_gardien(spawn_position, 260.0, 320.0)
	nouveau_gardien.mort_par_tueur.connect(_on_gardien_tue)
	gardien = nouveau_gardien

func _position_spawn_gardien() -> Vector2:
	var base = point_apparition.global_position if point_apparition else (global_position + Vector2(0, 90))
	# Force un minimum vertical pour eviter un gardien qui spawn trop haut.
	base.y = max(base.y, global_position.y + 90.0)
	return base + Vector2(randf_range(-14, 14), randf_range(8, 20))

func _on_gardien_tue(tueur : Node2D, tueur_equipe : int = -1):
	if tueur_equipe != -1 and tueur_equipe != equipe: _etre_capture_par_equipe(tueur_equipe)
	elif is_instance_valid(tueur) and tueur.get("equipe") != null and tueur.equipe != equipe: _etre_capture_par_equipe(tueur.equipe)
	else: _etre_capture_par_equipe(Proprietaire.NEUTRE)

func _etre_capture_par_equipe(nouvelle_equipe):
	equipe = nouvelle_equipe
	hp_actuels = hp_max
	file_production.clear()
	_mettre_a_jour_groupes_et_visuels()

func _on_timer_revenu_timeout():
	if equipe == Proprietaire.JOUEUR: Economie.ajouter_argent(revenu_par_seconde)

func demander_production(id : int = 0):
	if equipe != Proprietaire.JOUEUR or not catalogue_unites.has(id): return
	var data = catalogue_unites[id]
	if Economie.retrancher_argent(data.prix):
		file_production.append(id)
		if file_production.size() == 1:
			temps_total_unite_actuelle = _temps_fabrication_pour(data)
			temps_restant = temps_total_unite_actuelle

func _scene_pour_unite(stat: UniteStats, unite_id: int = -1) -> PackedScene:
	if unite_id == 1:
		return SCENE_RANGE
	if unite_id == 2:
		return SCENE_HEAVY
	if unite_id == 3:
		return SCENE_SUPPORT
	if unite_id == 4:
		return SCENE_HEALER
	if unite_id == 5:
		return _scene_anti_armor_niveau()
	if stat.type_unite == UniteStats.TypeUnite.INFANTERIE:
		return _scene_infanterie_niveau()
	if stat.type_unite == UniteStats.TypeUnite.ARCHER:
		return SCENE_RANGE
	if stat.type_unite == UniteStats.TypeUnite.LOURD:
		return SCENE_HEAVY
	if stat.type_unite == UniteStats.TypeUnite.SUPPORT:
		return SCENE_SUPPORT
	if stat.type_unite == UniteStats.TypeUnite.HEAL:
		return SCENE_HEALER
	if stat.type_unite == UniteStats.TypeUnite.ANTI_ARMOR:
		return _scene_anti_armor_niveau()
	return _scene_infanterie_niveau()

func terminer_production():
	var unite_id = file_production.pop_front()
	var stat = catalogue_unites[unite_id]
	var soldat = _scene_pour_unite(stat, unite_id).instantiate()
	if not ("stats" in soldat):
		push_warning("Scene unite invalide pour id %s: la racine doit contenir la propriete 'stats'." % str(unite_id))
		soldat.queue_free()
		if file_production.size() > 0:
			temps_total_unite_actuelle = _temps_fabrication_pour(catalogue_unites[file_production[0]])
			temps_restant = temps_total_unite_actuelle
		else:
			production_maj.emit(0, 0)
		return
	soldat.stats = stat
	var spawn_position = (point_apparition.global_position if point_apparition else global_position) + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	soldat.equipe = equipe
	
	if equipe == Proprietaire.JOUEUR: soldat.add_to_group("soldats")
	else:
		if soldat.is_in_group("soldats"): soldat.remove_from_group("soldats")
		soldat.add_to_group("ennemis")
		
	get_parent().add_child(soldat)
	soldat.global_position = spawn_position
	if file_production.size() > 0:
		temps_total_unite_actuelle = _temps_fabrication_pour(catalogue_unites[file_production[0]])
		temps_restant = temps_total_unite_actuelle
	else:
		production_maj.emit(0, 0)

func _on_timer_ia_timeout(): pass

func cout_upgrade_prochain_niveau() -> int:
	match niveau_camp:
		1:
			return cout_upgrade_niveau_2
		2:
			return cout_upgrade_niveau_3
		_:
			return -1

func peut_ameliorer() -> bool:
	return equipe == Proprietaire.JOUEUR and niveau_camp < 3

func ameliorer_camp() -> bool:
	if not peut_ameliorer():
		return false

	var cout = cout_upgrade_prochain_niveau()
	if cout <= 0:
		return false
	if not Economie.retrancher_argent(cout):
		return false

	niveau_camp += 1
	_appliquer_configuration_niveau()
	_rafraichir_catalogue_unites()
	camp_upgrade.emit(niveau_camp)

	if is_instance_valid(timer_ia_production):
		timer_ia_production.wait_time = frequence_ia

	if file_production.size() > 0:
		temps_total_unite_actuelle = _temps_fabrication_pour(catalogue_unites[file_production[0]])
		temps_restant = min(temps_restant, temps_total_unite_actuelle)
		production_maj.emit(file_production.size(), 1.0 - (temps_restant / temps_total_unite_actuelle))

	# Le gardien actuel est remplacé pour appliquer la scène/stats du nouveau niveau.
	if is_instance_valid(gardien):
		gardien.queue_free()
		gardien = null

	return true

func set_selection(etat : bool):
	modulate = Color(1.5, 1.5, 1.5) if etat else Color(1, 1, 1)

func recevoir_degats(montant : int, auteur : Node2D = null):
	hp_actuels -= montant
	if hp_actuels <= 0: _etre_capture(auteur)

func _etre_capture(auteur : Node2D, auteur_equipe : int = -1):
	hp_actuels = hp_max
	file_production.clear()
	if auteur_equipe != -1: equipe = auteur_equipe
	elif is_instance_valid(auteur) and auteur.get("equipe") != null: equipe = auteur.equipe
	else: equipe = Proprietaire.NEUTRE
	_mettre_a_jour_groupes_et_visuels()

func _mettre_a_jour_groupes_et_visuels():
	if is_in_group("ennemis"): remove_from_group("ennemis")
	match equipe:
		Proprietaire.JOUEUR:
			$ColorRect.color = Color(0.1, 0.4, 0.8, 0.3)
			$Label.text = "ALLIE"
		Proprietaire.ENNEMI:
			add_to_group("ennemis")
			$ColorRect.color = Color(0.8, 0.1, 0.1, 0.3)
			$Label.text = "ENNEMI"
		Proprietaire.NEUTRE:
			$ColorRect.color = Color(0.5, 0.5, 0.5, 0.3)
			$Label.text = "NEUTRE"
	queue_redraw()

func _draw(): pass

func recevoir_renforts(quantite : int):
	var stats_infanterie = _stats_infanterie_niveau()
	for i in range(quantite):
		var s = _scene_pour_unite(stats_infanterie).instantiate()
		s.stats = stats_infanterie
		var spawn_position = (point_apparition.global_position if point_apparition else global_position) + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_parent().add_child(s)
		s.global_position = spawn_position
