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
var multiplicateur_cadence_attaque: float = 1.0
var est_en_train_de_mourir : bool = false
var est_gardien_camp: bool = false
var position_garde: Vector2 = Vector2.ZERO
var rayon_defense_gardien: float = 260.0
var rayon_poursuite_gardien: float = 320.0

func _ready():
	if stats:
		hp_max = stats.hp_max
		hp_actuels = hp_max
		vitesse_unite = stats.vitesse
		degats_unite = stats.degats
		_appliquer_couleur_unite()
		
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
	_configurer_animations_mort()
	_configurer_animations_attaque()

func set_selection(etat : bool):
	est_selectionne = etat
	self.modulate = Color(1.2, 1.2, 1.2) if est_selectionne else Color(1, 1, 1)

func aller_vers(cible : Vector2):
	if est_gardien_camp:
		return
	cible_attaque = null
	agent_navigation.target_position = cible

func attaquer_cible(cible : Node2D):
	if est_gardien_camp and is_instance_valid(cible):
		if cible.global_position.distance_to(position_garde) > rayon_poursuite_gardien:
			return
	cible_attaque = cible
	if is_instance_valid(cible):
		agent_navigation.target_position = cible.global_position

var dernier_regard : String = "f"

func _physics_process(_delta):
	if est_en_train_de_mourir:
		return

	var doit_avancer = true
	
	if cooldown_actuel_sort > 0:
		cooldown_actuel_sort -= _delta
		
	if boost_actif:
		temps_restant_boost -= _delta
		if temps_restant_boost <= 0:
			boost_actif = false
			vitesse_unite = stats.vitesse
			degats_unite = stats.degats
			multiplicateur_cadence_attaque = 1.0
			_appliquer_couleur_unite()
	
	if is_instance_valid(cible_attaque):
		if est_gardien_camp and cible_attaque.global_position.distance_to(position_garde) > rayon_poursuite_gardien:
			cible_attaque = null
			timer_attaque.stop()
			agent_navigation.target_position = position_garde
			doit_avancer = true
		
		agent_navigation.target_position = cible_attaque.global_position
		
		if cible_attaque in zone_detection.get_overlapping_bodies():
			doit_avancer = false
			if timer_attaque.is_stopped():
				var cadence = _cadence_attaque_actuelle()
				timer_attaque.start(1.0 / cadence)
		else:
			timer_attaque.stop()
	else:
		timer_attaque.stop()
		timer_recherche -= _delta
		if timer_recherche <= 0:
			_rechercher_cible_automatique()
			timer_recherche = temps_recherche

		if est_gardien_camp and global_position.distance_to(position_garde) > 8.0:
			agent_navigation.target_position = position_garde
		elif agent_navigation.is_navigation_finished():
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
		_jouer_animation_attaque(cible_attaque)
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
		# Plus de "dash" visuel: l'animation d'attaque gère maintenant le mouvement perçu.
		var flash = create_tween()
		flash.tween_property($AnimatedSprite2D, "modulate", Color.RED, 0.1)
		flash.tween_property($AnimatedSprite2D, "modulate", _couleur_unite(), 0.1)

func _rechercher_cible_automatique():
	var cibles = zone_detection.get_overlapping_bodies().filter(func(c):
		return c != self and c.has_method("recevoir_degats") and not c.is_in_group("camps") and c.get("equipe") != null and c.get("equipe") != equipe
	)
	if est_gardien_camp:
		cibles = cibles.filter(func(c): return c.global_position.distance_to(position_garde) <= rayon_defense_gardien)
	
	if cibles.size() > 0:
		cibles.sort_custom(func(a, b):
			var a_est_soldat = not a.is_in_group("camps")
			var b_est_soldat = not b.is_in_group("camps")
			if a_est_soldat != b_est_soldat: return a_est_soldat
			return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
		)
		attaquer_cible(cibles[0])

func mettre_a_jour_animation():
	if not has_node("AnimatedSprite2D"):
		return

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.is_playing():
		if sprite.animation.begins_with("attack_") or sprite.animation.begins_with("death_"):
			return

	if velocity.length() > 5.0:
		if abs(velocity.x) > abs(velocity.y): dernier_regard = "r" if velocity.x > 0 else "l"
		else: dernier_regard = "f" if velocity.y > 0 else "b"
		sprite.play("run_" + dernier_regard)
	else:
		sprite.play("idle_" + dernier_regard)

func recevoir_degats(montant : int, auteur = null, auteur_equipe : int = -1):
	if est_en_train_de_mourir:
		return

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
	if est_en_train_de_mourir:
		return

	est_en_train_de_mourir = true
	mort_par_tueur.emit(tueur, tueur_equipe)
	velocity = Vector2.ZERO
	cible_attaque = null
	timer_attaque.stop()

	# Stoppe tout blocage physique/agent dès le début de l'anim de mort.
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(agent_navigation):
		agent_navigation.target_position = global_position
		agent_navigation.avoidance_enabled = false

	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if has_node("ZoneDetection"):
		$ZoneDetection.monitoring = false
		$ZoneDetection.monitorable = false
	if has_node("ZoneDetection/CollisionShape2D"):
		$ZoneDetection/CollisionShape2D.set_deferred("disabled", true)

	var anim_mort_jouee := _jouer_animation_mort()
	if anim_mort_jouee:
		await $AnimatedSprite2D.animation_finished
	queue_free()

func _jouer_animation_mort() -> bool:
	if not has_node("AnimatedSprite2D"):
		return false

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var anim = "death_" + dernier_regard
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		return true
	elif sprite.sprite_frames and sprite.sprite_frames.has_animation("idle_" + dernier_regard):
		sprite.play("idle_" + dernier_regard)
	return false

func _jouer_animation_attaque(cible: Node2D):
	if not is_instance_valid(cible):
		return
	if not has_node("AnimatedSprite2D"):
		return

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var dir := _direction_depuis_cible(cible.global_position)
	var anim := "attack_" + dir
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)

func _direction_depuis_cible(pos_cible: Vector2) -> String:
	var delta := pos_cible - global_position
	if abs(delta.y) >= abs(delta.x):
		return "b" if delta.y < 0 else "f"
	return "l" if delta.x < 0 else "r"

func _configurer_animations_mort():
	if not has_node("AnimatedSprite2D"):
		return

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var frames = sprite.sprite_frames
	if frames == null:
		return
	if not frames.has_animation("run_f") or frames.get_frame_count("run_f") == 0:
		return

	var run_frame = frames.get_frame_texture("run_f", 0)
	if not (run_frame is AtlasTexture):
		return

	var atlas_run: AtlasTexture = run_frame
	if atlas_run.atlas == null:
		return

	var base_path := atlas_run.atlas.resource_path
	if base_path == "":
		return

	var death_path := base_path.get_base_dir() + "/death.png"
	if not ResourceLoader.exists(death_path):
		return

	var death_tex = load(death_path)
	if not (death_tex is Texture2D):
		return

	var frame_size := atlas_run.region.size
	if frame_size.x <= 0 or frame_size.y <= 0:
		return

	var cols := int(floor(float(death_tex.get_width()) / frame_size.x))
	var rows := int(floor(float(death_tex.get_height()) / frame_size.y))
	if cols <= 0 or rows <= 0:
		return

	var directions: Dictionary = {
		"f": 0,
		"l": 1,
		"r": 2,
		"b": 3
	}
	var speed := frames.get_animation_speed("run_f")

	for d: String in directions.keys():
		var row: int = int(directions[d])
		if row >= rows:
			continue

		var anim_name: String = "death_" + d
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, false)
		frames.set_animation_speed(anim_name, speed)

		for i in range(cols):
			var a := AtlasTexture.new()
			a.atlas = death_tex
			a.region = Rect2(i * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y)
			frames.add_frame(anim_name, a)

func _configurer_animations_attaque():
	if not has_node("AnimatedSprite2D"):
		return

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var frames = sprite.sprite_frames
	if frames == null:
		return
	if not frames.has_animation("run_f") or frames.get_frame_count("run_f") == 0:
		return

	var run_frame = frames.get_frame_texture("run_f", 0)
	if not (run_frame is AtlasTexture):
		return

	var atlas_run: AtlasTexture = run_frame
	if atlas_run.atlas == null:
		return

	var base_path := atlas_run.atlas.resource_path
	if base_path == "":
		return

	var attack_path := base_path.get_base_dir() + "/attack.png"
	if not ResourceLoader.exists(attack_path):
		return

	var attack_tex = load(attack_path)
	if not (attack_tex is Texture2D):
		return

	var frame_size := atlas_run.region.size
	if frame_size.x <= 0 or frame_size.y <= 0:
		return

	var cols := int(floor(float(attack_tex.get_width()) / frame_size.x))
	var rows := int(floor(float(attack_tex.get_height()) / frame_size.y))
	if cols <= 0 or rows <= 0:
		return

	var directions: Dictionary = {
		"f": 0, # 1ere ligne = front
		"b": 1, # 2eme ligne = back
		"l": 2, # 3eme ligne = gauche
		"r": 3  # 4eme ligne = droite
	}
	var speed := frames.get_animation_speed("run_f")

	for d: String in directions.keys():
		var row: int = int(directions[d])
		if row >= rows:
			continue

		var anim_name: String = "attack_" + d
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, false)
		frames.set_animation_speed(anim_name, speed)

		for i in range(cols):
			var a := AtlasTexture.new()
			a.atlas = attack_tex
			a.region = Rect2(i * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y)
			frames.add_frame(anim_name, a)

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
				obj.recevoir_boost(stats.duree_sort + 10.0)
			elif stats.type_unite == 4 and "hp_actuels" in obj and "hp_max" in obj:
				obj.hp_actuels = min(obj.hp_max, obj.hp_actuels + 50)
				if obj.has_node("ProgressBar"):
					obj.get_node("ProgressBar").value = obj.hp_actuels

func recevoir_boost(duree: float):
	boost_actif = true
	temps_restant_boost = duree
	vitesse_unite = stats.vitesse * 1.25
	degats_unite = int(round(stats.degats * 1.25))
	multiplicateur_cadence_attaque = 1.25
	_appliquer_couleur_unite()

func _cadence_attaque_actuelle() -> float:
	var cadence_base = stats.cadence_attaque if stats and "cadence_attaque" in stats else 1.0
	return cadence_base * multiplicateur_cadence_attaque

func _couleur_unite() -> Color:
	if boost_actif:
		return Color(1.0, 0.95, 0.25)
	if equipe == Proprietaire.ENNEMI:
		return Color(1.0, 0.2, 0.2)
	return Color.WHITE

func _appliquer_couleur_unite():
	if has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.modulate = _couleur_unite()

func configurer_mode_gardien(position_ancre: Vector2, rayon_defense: float = 260.0, rayon_poursuite: float = 320.0):
	est_gardien_camp = true
	position_garde = position_ancre
	rayon_defense_gardien = rayon_defense
	rayon_poursuite_gardien = rayon_poursuite
	agent_navigation.target_position = position_garde
