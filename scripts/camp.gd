extends StaticBody2D

enum Proprietaire { JOUEUR, ENNEMI, NEUTRE }
@export var equipe : Proprietaire = Proprietaire.NEUTRE
@export var revenu_par_seconde : int = 5
@export var hp_max : int = 500
var hp_actuels : int = hp_max
var gardien : Node2D = null

const SCENE_BASE_SOLDAT = preload("res://scenes/personnages/player/soldat.tscn")
var stats_infanterie = preload("res://scripts/resources/infanterie.tres")
var stats_archer = preload("res://scripts/resources/archer.tres")
var stats_lourd = preload("res://scripts/resources/lourd.tres")
var stats_support = preload("res://scripts/resources/support.tres")
var stats_heal = preload("res://scripts/resources/heal.tres")
var stats_anti_armor = preload("res://scripts/resources/anti_armor.tres")
var stats_mortar = preload("res://scripts/resources/mortar.tres")

var catalogue_unites = {
	0: stats_infanterie, 1: stats_archer, 2: stats_lourd, 3: stats_support,
	4: stats_heal, 5: stats_anti_armor, 6: stats_mortar
}

var file_production : Array = []
var temps_restant : float = 0.0
var temps_total_unite_actuelle : float = 1.0

@onready var point_apparition = $Marker2D
@onready var timer_revenu = Timer.new()

const SCENE_PROJECTILE = preload("res://scenes/objets/projectile.tscn")
var portee_attaque : float = 200.0
var degats_attaque : int = 5
var cadence_attaque : float = 1.0

var zone_attaque : Area2D = null
var timer_attaque : Timer = null
var cible_actuelle : Node2D = null

var timer_ia_production : Timer = null
@export var frequence_ia : float = 15.0

signal production_maj(file_taille, progression)

func _ready():
	add_to_group("camps")
	_mettre_a_jour_groupes_et_visuels()
	
	if has_node("AnimatedSprite2D"): $AnimatedSprite2D.play()
	
	add_child(timer_revenu)
	timer_revenu.wait_time = 1.0
	timer_revenu.timeout.connect(_on_timer_revenu_timeout)
	timer_revenu.start()

	zone_attaque = Area2D.new()
	var collision = CollisionShape2D.new()
	var cercle = CircleShape2D.new()
	cercle.radius = portee_attaque
	collision.shape = cercle
	zone_attaque.add_child(collision)
	add_child(zone_attaque)
	
	timer_attaque = Timer.new()
	add_child(timer_attaque)
	timer_attaque.wait_time = cadence_attaque
	timer_attaque.timeout.connect(_on_timer_attaque_timeout)
	
	timer_ia_production = Timer.new()
	add_child(timer_ia_production)
	timer_ia_production.wait_time = frequence_ia
	timer_ia_production.timeout.connect(_on_timer_ia_timeout)
	timer_ia_production.start()

	zone_attaque.body_entered.connect(_on_zone_body_entered)

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
	var nouveau_gardien = SCENE_BASE_SOLDAT.instantiate()
	nouveau_gardien.stats = stats_lourd if equipe == Proprietaire.NEUTRE else stats_infanterie
	
	nouveau_gardien.global_position = (point_apparition.global_position if point_apparition else global_position) + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	nouveau_gardien.equipe = equipe
	
	if equipe == Proprietaire.JOUEUR: nouveau_gardien.add_to_group("soldats")
	elif equipe == Proprietaire.ENNEMI:
		if nouveau_gardien.is_in_group("soldats"): nouveau_gardien.remove_from_group("soldats")
		nouveau_gardien.add_to_group("ennemis")
		
	nouveau_gardien.mort_par_tueur.connect(_on_gardien_tue)
	get_parent().add_child(nouveau_gardien)
	gardien = nouveau_gardien

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
			temps_total_unite_actuelle = data.temps_fabrication
			temps_restant = temps_total_unite_actuelle

func terminer_production():
	var stat = catalogue_unites[file_production.pop_front()]
	var soldat = SCENE_BASE_SOLDAT.instantiate()
	soldat.stats = stat
	soldat.global_position = (point_apparition.global_position if point_apparition else global_position) + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	soldat.equipe = equipe
	
	if equipe == Proprietaire.JOUEUR: soldat.add_to_group("soldats")
	else:
		if soldat.is_in_group("soldats"): soldat.remove_from_group("soldats")
		soldat.add_to_group("ennemis")
		
	get_parent().add_child(soldat)
	
	if file_production.size() > 0:
		temps_total_unite_actuelle = catalogue_unites[file_production[0]].temps_fabrication
		temps_restant = temps_total_unite_actuelle
	else:
		production_maj.emit(0, 0)

func _on_timer_ia_timeout(): pass

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
	for i in range(quantite):
		var s = SCENE_BASE_SOLDAT.instantiate()
		s.stats = stats_infanterie
		s.global_position = (point_apparition.global_position if point_apparition else global_position) + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_parent().add_child(s)

func _on_zone_body_entered(_body):
	if timer_attaque.is_stopped():
		_on_timer_attaque_timeout()
		timer_attaque.start()

func _on_timer_attaque_timeout():
	_chercher_cible()
	if is_instance_valid(cible_actuelle): _tirer_projectile(cible_actuelle)
	else: timer_attaque.stop()

func _chercher_cible():
	if equipe == Proprietaire.NEUTRE: 
		cible_actuelle = null
		return
		
	var adversaires = zone_attaque.get_overlapping_bodies().filter(func(c): return c.has_method("recevoir_degats") and c.get("equipe") != null and c.get("equipe") != equipe)
	if adversaires.size() > 0:
		adversaires.sort_custom(func(a, b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
		cible_actuelle = adversaires[0]
	else: cible_actuelle = null

func _tirer_projectile(target):
	var proj = SCENE_PROJECTILE.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.global_position = global_position
	proj.lancer(target, degats_attaque, self)
