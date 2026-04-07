extends CharacterBody2D

signal mort_par_tueur(tueur, tueur_equipe)

@export var stats : UniteStats

enum Proprietaire { JOUEUR, ENNEMI, NEUTRE }
@export var equipe : Proprietaire = Proprietaire.JOUEUR

var hp_max : int = 100
var hp_actuels : int = 100
var vitesse_unite : float = 150.0
var degats_unite : int = 10
var est_selectionne : bool = false

const SCENE_PROJECTILE = preload("res://scenes/objets/projectile.tscn")

@onready var agent_navigation = $NavigationAgent2D
var cible_attaque : Node2D = null
@onready var zone_detection = $ZoneDetection
@onready var timer_attaque = $TimerAttaque

var temps_recherche : float = 0.5
var timer_recherche : float = 0.0

var cooldown_actuel_sort : float = 0.0
var temps_restant_boost : float = 0.0
var boost_actif : bool = false

func _ready():
	if stats:
		hp_max = stats.hp_max
		hp_actuels = hp_max
		vitesse_unite = stats.vitesse
		degats_unite = stats.degats
		$AnimatedSprite2D.modulate = stats.couleur
		
		if has_node("ProgressBar"):
			$ProgressBar.max_value = hp_max
			$ProgressBar.value = hp_actuels
		
		var shape = $ZoneDetection/CollisionShape2D.shape
		if shape is CircleShape2D:
			$ZoneDetection/CollisionShape2D.shape = shape.duplicate()
			$ZoneDetection/CollisionShape2D.shape.radius = stats.portee
			
		agent_navigation.target_desired_distance = stats.portee - 5.0
	
	agent_navigation.path_desired_distance = 10.0
	await get_tree().process_frame
	agent_navigation.target_position = global_position
	timer_attaque.timeout.connect(_on_timer_attaque_timeout)

func set_selection(etat : bool):
	est_selectionne = etat
	self.modulate = Color(1.2, 1.2, 1.2) if est_selectionne else Color(1, 1, 1)

func aller_vers(cible : Vector2):
	cible_attaque = null
	agent_navigation.target_position = cible

func attaquer_cible(cible : Node2D):
	cible_attaque = cible
	if is_instance_valid(cible):
		agent_navigation.target_position = cible.global_position

var dernier_regard : String = "f"

func _physics_process(_delta):
	var doit_avancer = true
	
	if cooldown_actuel_sort > 0:
		cooldown_actuel_sort -= _delta
		
	if boost_actif:
		temps_restant_boost -= _delta
		if temps_restant_boost <= 0:
			boost_actif = false
			vitesse_unite = stats.vitesse
			degats_unite = stats.degats
			$AnimatedSprite2D.modulate = stats.couleur
	
	if is_instance_valid(cible_attaque):
		agent_navigation.target_position = cible_attaque.global_position
		
		if cible_attaque in zone_detection.get_overlapping_bodies():
			doit_avancer = false
			if timer_attaque.is_stopped():
				var cadence = stats.cadence_attaque if stats and "cadence_attaque" in stats else 1.0
				timer_attaque.start(1.0 / cadence)
		else:
			timer_attaque.stop()
	else:
		timer_attaque.stop()
		timer_recherche -= _delta
		if timer_recherche <= 0:
			_rechercher_cible_automatique()
			timer_recherche = temps_recherche

		if agent_navigation.is_navigation_finished():
			doit_avancer = false
			
	if doit_avancer:
		var prochain_point = agent_navigation.get_next_path_position()
		velocity = global_position.direction_to(prochain_point) * vitesse_unite
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	mettre_a_jour_animation()

func _on_timer_attaque_timeout():
	if is_instance_valid(cible_attaque):
		if stats and stats.est_a_distance:
			var proj = SCENE_PROJECTILE.instantiate()
			get_parent().add_child(proj)
			proj.position = global_position
			proj.lancer(cible_attaque, degats_unite, self)
		elif cible_attaque.has_method("recevoir_degats"):
			cible_attaque.recevoir_degats(degats_unite, self)
			_animer_attaque_melee()
	else:
		timer_attaque.stop()
		cible_attaque = null

func _animer_attaque_melee():
	if is_instance_valid(cible_attaque):
		var anim_tween = create_tween()
		var dir = global_position.direction_to(cible_attaque.global_position)
		var pos_initiale = $AnimatedSprite2D.position
		anim_tween.tween_property($AnimatedSprite2D, "position", pos_initiale + dir * 8, 0.1)
		anim_tween.tween_property($AnimatedSprite2D, "position", pos_initiale, 0.1)
		
		var flash = create_tween()
		flash.tween_property($AnimatedSprite2D, "modulate", Color.RED, 0.1)
		flash.tween_property($AnimatedSprite2D, "modulate", stats.couleur if stats else Color.WHITE, 0.1)

func _rechercher_cible_automatique():
	var cibles = zone_detection.get_overlapping_bodies().filter(func(c):
		return c != self and c.has_method("recevoir_degats") and not c.is_in_group("camps") and c.get("equipe") != null and c.get("equipe") != equipe
	)
	
	if cibles.size() > 0:
		cibles.sort_custom(func(a, b):
			var a_est_soldat = not a.is_in_group("camps")
			var b_est_soldat = not b.is_in_group("camps")
			if a_est_soldat != b_est_soldat: return a_est_soldat
			return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
		)
		attaquer_cible(cibles[0])

func mettre_a_jour_animation():
	if velocity.length() > 5.0:
		if abs(velocity.x) > abs(velocity.y): dernier_regard = "r" if velocity.x > 0 else "l"
		else: dernier_regard = "f" if velocity.y > 0 else "b"
		$AnimatedSprite2D.play("run_" + dernier_regard)
	else:
		$AnimatedSprite2D.play("idle_" + dernier_regard)

func recevoir_degats(montant : int, auteur : Node2D = null, auteur_equipe : int = -1):
	var degats_finaux = montant
	
	if is_instance_valid(auteur) and "stats" in auteur and auteur.stats != null:
		if auteur.stats.type_unite == 5:
			degats_finaux = degats_finaux * 3 if (stats and stats.type_unite == 2) else int(float(degats_finaux) * 0.5)
				
	hp_actuels -= degats_finaux
	
	if has_node("ProgressBar"):
		$ProgressBar.value = hp_actuels
		
	if hp_actuels <= 0:
		var eq = auteur_equipe
		if eq == -1 and is_instance_valid(auteur) and auteur.get("equipe") != null:
			eq = auteur.equipe
		moteur_de_mort(auteur, eq)

func moteur_de_mort(tueur : Node2D = null, tueur_equipe : int = -1):
	mort_par_tueur.emit(tueur, tueur_equipe)
	queue_free()

func lancer_sort():
	if not stats or stats.cooldown_sort <= 0 or cooldown_actuel_sort > 0: return
	cooldown_actuel_sort = stats.cooldown_sort
	
	var requete = PhysicsShapeQueryParameters2D.new()
	var cercle = CircleShape2D.new()
	cercle.radius = 150.0
	requete.shape = cercle
	requete.transform = Transform2D(0, global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	
	var resultats = get_world_2d().direct_space_state.intersect_shape(requete)
	var groupe = "soldats" if equipe == Proprietaire.JOUEUR else "ennemis"
	
	for res in resultats:
		var obj = res.collider
		if obj and obj.is_in_group(groupe):
			if stats.type_unite == 3 and obj.has_method("recevoir_boost"):
				obj.recevoir_boost(stats.duree_sort)
			elif stats.type_unite == 4 and "hp_actuels" in obj and "hp_max" in obj:
				obj.hp_actuels = min(obj.hp_max, obj.hp_actuels + 50)
				if obj.has_node("ProgressBar"):
					obj.get_node("ProgressBar").value = obj.hp_actuels

func recevoir_boost(duree: float):
	boost_actif = true
	temps_restant_boost = duree
	vitesse_unite = stats.vitesse * 1.5
	degats_unite = int(stats.degats * 1.5)
	$AnimatedSprite2D.modulate = Color(1.5, 1.5, 0.5)
