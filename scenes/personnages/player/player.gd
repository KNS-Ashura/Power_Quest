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
const SCENE_RANGE_PROJECTILE_LOOP = preload("res://scenes/personnages/range/range-loop-projectile.tscn")
const SCENE_MORTAR_EXPLOSION_BASE = preload("res://scenes/personnages/mortar/explosion.tscn")
const SCENE_MORTAR_EXPLOSION_POISON = preload("res://scenes/personnages/mortar/poison-explosion.tscn")
const SCENE_MORTAR_EXPLOSION_FEU = preload("res://scenes/personnages/mortar/fire-explosion.tscn")
const SCENE_MORTAR_EXPLOSION_ULT = preload("res://scenes/personnages/mortar/explosion-ult.tscn")
const MORTAR_ATTACK_COOLDOWN_NIVEAU_1 = 4.8
const MORTAR_ATTACK_COOLDOWN_NIVEAU_2 = 3.9
const MORTAR_ATTACK_COOLDOWN_NIVEAU_3 = 3.2
const MORTAR_SORT_COOLDOWN_DEFAUT = 12.0
## Calque 1 = sol (Nav_ground map 2, nav map 1). Calque 2 = eau (Nav_water map 2).
const NAV_LAYER_SOL := 1
const NAV_LAYER_EAU := 2

@export var forcer_navigation_eau: bool = false

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
var cycle_explosion_mortar : int = 0
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

	_configurer_calques_navigation()
	agent_navigation.path_desired_distance = 10.0
	await get_tree().process_frame
	agent_navigation.target_position = global_position
	timer_attaque.timeout.connect(_on_timer_attaque_timeout)
	_configurer_animations_mort()

func _configurer_calques_navigation() -> void:
	if not is_instance_valid(agent_navigation):
		return
	agent_navigation.navigation_layers = NAV_LAYER_EAU if _est_unite_aquatique() else NAV_LAYER_SOL

func _est_unite_aquatique() -> bool:
	if forcer_navigation_eau:
		return true
	var chemin_scene := scene_file_path
	return chemin_scene.contains("/Water_") or chemin_scene.contains("/water_")

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
		var cible_valide := cible_attaque
		if est_gardien_camp and cible_valide.global_position.distance_to(position_garde) > rayon_poursuite_gardien:
			cible_attaque = null
			timer_attaque.stop()
			agent_navigation.target_position = position_garde
			doit_avancer = true
		else:
			agent_navigation.target_position = cible_valide.global_position

		if is_instance_valid(cible_attaque) and cible_attaque in zone_detection.get_overlapping_bodies():
			doit_avancer = false
			if timer_attaque.is_stopped():
				if _est_mortar():
					# Mortar: tire immédiatement à la première fenêtre de tir, puis applique le cooldown.
					_tirer_mortar_distance(cible_attaque)
					timer_attaque.start(_cooldown_mortar_niveau())
				else:
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
		if _est_healer():
			_jouer_animation_attaque(cible_attaque)
			_appliquer_soin_cible(cible_attaque)
			return
		if _est_mortar():
			_tirer_mortar_distance(cible_attaque)
			return
		if _est_range():
			_jouer_animation_attaque(cible_attaque)
			_tirer_projectile_range(cible_attaque)
			return
		if cible_attaque.has_method("recevoir_degats"):
			_jouer_animation_attaque(cible_attaque)
			cible_attaque.recevoir_degats(degats_unite, self)
			_animer_attaque_melee()
	else:
		timer_attaque.stop()
		cible_attaque = null

func _animer_attaque_melee():
	if is_instance_valid(cible_attaque):
		# Plus de "dash" visuel: l'animation d'attaque gère maintenant le mouvement perçu.
		for sprite in _sprites_animes_unite():
			var flash = create_tween()
			flash.tween_property(sprite, "modulate", Color.RED, 0.1)
			flash.tween_property(sprite, "modulate", _couleur_unite(), 0.1)

func _rechercher_cible_automatique():
	if _est_healer():
		var allies = zone_detection.get_overlapping_bodies().filter(func(c):
			return c != self and c.get("equipe") != null and c.get("equipe") == equipe and not c.is_in_group("camps") and "hp_actuels" in c and "hp_max" in c and c.hp_actuels < c.hp_max
		)
		if est_gardien_camp:
			allies = allies.filter(func(c): return c.global_position.distance_to(position_garde) <= rayon_defense_gardien)
		if allies.size() > 0:
			allies.sort_custom(func(a, b):
				var ratio_a = float(a.hp_actuels) / max(1.0, float(a.hp_max))
				var ratio_b = float(b.hp_actuels) / max(1.0, float(b.hp_max))
				if ratio_a != ratio_b:
					return ratio_a < ratio_b
				return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
			)
			attaquer_cible(allies[0])
		return

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

func _est_healer() -> bool:
	return stats != null and stats.type_unite == UniteStats.TypeUnite.HEAL

func _est_range() -> bool:
	return stats != null and stats.type_unite == UniteStats.TypeUnite.ARCHER

func _est_mortar() -> bool:
	return stats != null and stats.type_unite == UniteStats.TypeUnite.MORTAR

func _tirer_projectile_range(cible: Node2D):
	if not is_instance_valid(cible):
		timer_attaque.stop()
		return
	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj = SCENE_RANGE_PROJECTILE_LOOP.instantiate()
	parent_node.add_child(proj)
	proj.global_position = global_position
	if proj.has_method("lancer"):
		proj.lancer(cible, degats_unite, self)

func _niveau_mortar() -> int:
	if stats == null:
		return 1
	var nom_lower := String(stats.nom).to_lower()
	if nom_lower.find("iii") != -1 or nom_lower.find(" 3") != -1:
		return 3
	if nom_lower.find("ii") != -1 or nom_lower.find(" 2") != -1:
		return 2
	return 1

func _cooldown_mortar_niveau() -> float:
	var niveau := _niveau_mortar()
	if niveau >= 3:
		return MORTAR_ATTACK_COOLDOWN_NIVEAU_3
	if niveau == 2:
		return MORTAR_ATTACK_COOLDOWN_NIVEAU_2
	return MORTAR_ATTACK_COOLDOWN_NIVEAU_1

func _tirer_mortar_distance(cible: Node2D):
	if not is_instance_valid(cible):
		timer_attaque.stop()
		cible_attaque = null
		return
	var position_impact := cible.global_position
	var explosion = _prochaine_explosion_mortar()
	_spawn_mortar_explosion_vfx(explosion["scene"], position_impact)
	_appliquer_degats_zone(position_impact, explosion["rayon"], explosion["degats"])

func _prochaine_explosion_mortar() -> Dictionary:
	var base = {
		"scene": SCENE_MORTAR_EXPLOSION_BASE,
		"rayon": 84.0,
		"degats": degats_unite
	}
	var poison = {
		"scene": SCENE_MORTAR_EXPLOSION_POISON,
		"rayon": 96.0,
		"degats": int(round(float(degats_unite) * 0.65))
	}
	var feu = {
		"scene": SCENE_MORTAR_EXPLOSION_FEU,
		"rayon": 110.0,
		"degats": int(round(float(degats_unite) * 0.85))
	}

	var niveau := _niveau_mortar()
	var sequence: Array = [base]
	if niveau == 2:
		sequence = [base, poison]
	elif niveau >= 3:
		sequence = [base, poison, feu]

	var index = cycle_explosion_mortar % sequence.size()
	cycle_explosion_mortar += 1
	return sequence[index]

func _spawn_mortar_explosion_vfx(scene: PackedScene, position_world: Vector2):
	if scene == null:
		return
	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		return
	var vfx = scene.instantiate()
	parent_node.add_child(vfx)
	vfx.global_position = position_world
	if vfx.is_in_group("soldats"):
		vfx.remove_from_group("soldats")
	var sprite := vfx.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(sprite):
		if sprite.sprite_frames and sprite.sprite_frames.has_animation("explosion"):
			sprite.sprite_frames.set_animation_loop("explosion", false)
			sprite.play("explosion")
			sprite.animation_finished.connect(func(): if is_instance_valid(vfx): vfx.queue_free(), CONNECT_ONE_SHOT)
		else:
			vfx.queue_free()

func _appliquer_degats_zone(centre: Vector2, rayon: float, degats: int):
	var requete = PhysicsShapeQueryParameters2D.new()
	var cercle = CircleShape2D.new()
	cercle.radius = rayon
	requete.shape = cercle
	requete.transform = Transform2D(0, centre)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true

	var resultats = get_world_2d().direct_space_state.intersect_shape(requete)
	for res in resultats:
		var obj = res.collider
		if not is_instance_valid(obj):
			continue
		if obj == self:
			continue
		if not obj.has_method("recevoir_degats"):
			continue
		if obj.get("equipe") == null or obj.equipe == equipe:
			continue
		if obj.is_in_group("camps"):
			continue
		obj.recevoir_degats(degats, self)

func _appliquer_soin_cible(cible: Node2D):
	if not is_instance_valid(cible):
		timer_attaque.stop()
		cible_attaque = null
		return
	if not ("hp_actuels" in cible and "hp_max" in cible):
		return
	if cible.get("equipe") == null or cible.equipe != equipe:
		return
	if cible.hp_actuels >= cible.hp_max:
		cible_attaque = null
		return

	var soin = int(max(10.0, float(hp_max) * 0.12))
	cible.hp_actuels = min(cible.hp_max, cible.hp_actuels + soin)
	if cible.has_node("ProgressBar"):
		cible.get_node("ProgressBar").value = cible.hp_actuels

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
		_jouer_animation_sur_sprites("run_" + dernier_regard)
	else:
		_jouer_animation_sur_sprites("idle_" + dernier_regard)

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
	if _est_mortar():
		_jouer_animation_sur_sprites("attack_" + dernier_regard, "idle_" + dernier_regard)
		_spawn_mortar_explosion_vfx(SCENE_MORTAR_EXPLOSION_BASE, global_position)
		_appliquer_degats_zone(global_position, 120.0, int(round(float(degats_unite) * 1.15)))
		await get_tree().create_timer(0.22).timeout
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
		_jouer_animation_sur_sprites(anim, "idle_" + dernier_regard)
		return true
	elif sprite.sprite_frames and sprite.sprite_frames.has_animation("idle_" + dernier_regard):
		_jouer_animation_sur_sprites("idle_" + dernier_regard)
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
		_jouer_animation_sur_sprites(anim)

func _direction_depuis_cible(pos_cible: Vector2) -> String:
	var delta := pos_cible - global_position
	if abs(delta.y) >= abs(delta.x):
		return "b" if delta.y < 0 else "f"
	return "l" if delta.x < 0 else "r"

func _sprites_animes_unite() -> Array[AnimatedSprite2D]:
	var sprites: Array[AnimatedSprite2D] = []
	for child in get_children():
		if child is AnimatedSprite2D:
			sprites.append(child as AnimatedSprite2D)
	return sprites

func _jouer_animation_sur_sprites(anim: String, fallback: String = ""):
	for sprite in _sprites_animes_unite():
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
		elif fallback != "" and sprite.sprite_frames and sprite.sprite_frames.has_animation(fallback):
			sprite.play(fallback)

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

	for d in directions.keys():
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

func lancer_sort():
	if not stats or cooldown_actuel_sort > 0:
		return
	if _est_mortar():
		if _lancer_sort_mortar_ult():
			var cooldown_sort_mortar = stats.cooldown_sort if stats.cooldown_sort > 0 else MORTAR_SORT_COOLDOWN_DEFAUT
			cooldown_actuel_sort = cooldown_sort_mortar
		return
	if stats.cooldown_sort <= 0:
		return
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

func _lancer_sort_mortar_ult() -> bool:
	var niveau = _niveau_mortar()
	var nb_cibles = 1
	if niveau == 2:
		nb_cibles = 2
	elif niveau >= 3:
		nb_cibles = 3

	var cibles = _cibles_ennemies_plus_proches_mortar(nb_cibles)
	if cibles.is_empty():
		return false

	var degats_sort = int(round(float(degats_unite) * 1.2))
	for cible in cibles:
		var position_impact = cible.global_position
		_spawn_mortar_explosion_vfx(SCENE_MORTAR_EXPLOSION_ULT, position_impact)
		_appliquer_degats_zone(position_impact, 112.0, degats_sort)
	return true

func _cibles_ennemies_plus_proches_mortar(nb_max: int) -> Array:
	var cibles: Array = zone_detection.get_overlapping_bodies().filter(func(c):
		return c != self and c.has_method("recevoir_degats") and not c.is_in_group("camps") and c.get("equipe") != null and c.get("equipe") != equipe
	)
	if cibles.is_empty():
		return []

	cibles.sort_custom(func(a, b):
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)

	var resultat: Array = []
	var limite = mini(nb_max, cibles.size())
	for i in range(limite):
		resultat.append(cibles[i])
	return resultat

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
	for sprite in _sprites_animes_unite():
		sprite.modulate = _couleur_unite()

func configurer_mode_gardien(position_ancre: Vector2, rayon_defense: float = 260.0, rayon_poursuite: float = 320.0):
	est_gardien_camp = true
	position_garde = position_ancre
	rayon_defense_gardien = rayon_defense
	rayon_poursuite_gardien = rayon_poursuite
	agent_navigation.target_position = position_garde
