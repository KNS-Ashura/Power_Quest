extends CharacterBody2D

signal killed_by(tueur, tueur_team)

@export var stats : UnitStats

enum Owner { PLAYER, ENEMY, NEUTRAL }
@export var team: Owner = Owner.PLAYER

var hp_max : int = 100
var current_hp : int = 100
var unit_speed : float = 150.0
var unit_damage : int = 10
var is_selected : bool = false
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
const NAV_LAYER_GROUND := 1
const NAV_LAYER_WATER := 2

@export var force_water_navigation: bool = false

@onready var agent_navigation = $NavigationAgent2D
var attack_target_node : Node2D = null
@onready var zone_detection = $ZoneDetection
@onready var timer_attaque = $TimerAttaque

var temps_recherche : float = 0.5
var timer_recherche : float = 0.0

var cooldown_actuel_sort : float = 0.0
var temps_restant_boost : float = 0.0
var boost_actif : bool = false
var attack_rate_multiplier: float = 1.0
var is_dying : bool = false
var cycle_explosion_mortar : int = 0
var is_camp_guardian: bool = false
var guard_position: Vector2 = Vector2.ZERO
var guard_defense_radius: float = 260.0
var guard_chase_radius: float = 320.0

func _ready():
	if stats:
		hp_max = stats.hp_max
		current_hp = hp_max
		unit_speed = stats.speed
		unit_damage = stats.damage
		_appliquer_couleur_unite()
		
		if has_node("ProgressBar"):
			$ProgressBar.max_value = hp_max
			$ProgressBar.value = current_hp
		
		var shape = $ZoneDetection/CollisionShape2D.shape
		if shape is CircleShape2D:
			$ZoneDetection/CollisionShape2D.shape = shape.duplicate()
			$ZoneDetection/CollisionShape2D.shape.radius = stats.range
			
		agent_navigation.target_desired_distance = stats.range - 5.0

	_configurer_calques_navigation()
	agent_navigation.path_desired_distance = 10.0
	await get_tree().process_frame
	agent_navigation.target_position = global_position
	timer_attaque.timeout.connect(_on_timer_attaque_timeout)
	_configurer_animations_mort()

func _configurer_calques_navigation() -> void:
	if not is_instance_valid(agent_navigation):
		return
	agent_navigation.navigation_layers = NAV_LAYER_WATER if _is_naval_unit() else NAV_LAYER_GROUND

func _is_naval_unit() -> bool:
	if force_water_navigation:
		return true
	var chemin_scene := scene_file_path
	return chemin_scene.contains("/Water_") or chemin_scene.contains("/water_")

func set_selection(etat : bool):
	is_selected = etat
	self.modulate = Color(1.2, 1.2, 1.2) if is_selected else Color(1, 1, 1)

func move_to(cible : Vector2):
	if is_camp_guardian:
		return
	attack_target_node = null
	agent_navigation.target_position = cible

func attack_target(cible : Node2D):
	if is_camp_guardian and is_instance_valid(cible):
		if cible.global_position.distance_to(guard_position) > guard_chase_radius:
			return
	attack_target_node = cible
	if is_instance_valid(cible):
		agent_navigation.target_position = cible.global_position

var dernier_regard : String = "f"

func _physics_process(_delta):
	if is_dying:
		return

	var doit_avancer = true
	
	if cooldown_actuel_sort > 0:
		cooldown_actuel_sort -= _delta
		
	if boost_actif:
		temps_restant_boost -= _delta
		if temps_restant_boost <= 0:
			boost_actif = false
			unit_speed = stats.speed
			unit_damage = stats.damage
			attack_rate_multiplier = 1.0
			_appliquer_couleur_unite()
	
	if is_instance_valid(attack_target_node):
		var cible_valide := attack_target_node
		if is_camp_guardian and cible_valide.global_position.distance_to(guard_position) > guard_chase_radius:
			attack_target_node = null
			timer_attaque.stop()
			agent_navigation.target_position = guard_position
			doit_avancer = true
		else:
			agent_navigation.target_position = cible_valide.global_position

		if is_instance_valid(attack_target_node) and attack_target_node in zone_detection.get_overlapping_bodies():
			doit_avancer = false
			if timer_attaque.is_stopped():
				if _est_mortar():
					# Mortar: tire immédiatement à la première fenêtre de tir, puis applique le cooldown.
					_tirer_mortar_distance(attack_target_node)
					timer_attaque.start(_cooldown_mortar_niveau())
				else:
					var cadence = _attack_rate_actuelle()
					timer_attaque.start(1.0 / cadence)
		else:
			timer_attaque.stop()
	else:
		timer_attaque.stop()
		timer_recherche -= _delta
		if timer_recherche <= 0:
			_rechercher_cible_automatique()
			timer_recherche = temps_recherche

		if is_camp_guardian and global_position.distance_to(guard_position) > 8.0:
			agent_navigation.target_position = guard_position
		elif agent_navigation.is_navigation_finished():
			doit_avancer = false
			
	if doit_avancer:
		var prochain_point = agent_navigation.get_next_path_position()
		velocity = global_position.direction_to(prochain_point) * unit_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	update_animation()

func _on_timer_attaque_timeout():
	if is_instance_valid(attack_target_node):
		if _est_healer():
			_jouer_animation_attaque(attack_target_node)
			_appliquer_soin_cible(attack_target_node)
			return
		if _est_mortar():
			_tirer_mortar_distance(attack_target_node)
			return
		if _est_range():
			_jouer_animation_attaque(attack_target_node)
			_tirer_projectile_range(attack_target_node)
			return
		if attack_target_node.has_method("take_damage"):
			_jouer_animation_attaque(attack_target_node)
			attack_target_node.take_damage(unit_damage, self)
			_animer_attaque_melee()
	else:
		timer_attaque.stop()
		attack_target_node = null

func _animer_attaque_melee():
	if is_instance_valid(attack_target_node):
		# Plus de "dash" visuel: l'animation d'attaque gère maintenant le mouvement perçu.
		for sprite in _sprites_animes_unite():
			var flash = create_tween()
			flash.tween_property(sprite, "modulate", Color.RED, 0.1)
			flash.tween_property(sprite, "modulate", _couleur_unite(), 0.1)

func _rechercher_cible_automatique():
	if _est_healer():
		var allies = zone_detection.get_overlapping_bodies().filter(func(c):
			return c != self and c.get("team") != null and c.get("team") == team and not c.is_in_group("camps") and "current_hp" in c and "hp_max" in c and c.current_hp < c.hp_max
		)
		if is_camp_guardian:
			allies = allies.filter(func(c): return c.global_position.distance_to(guard_position) <= guard_defense_radius)
		if allies.size() > 0:
			allies.sort_custom(func(a, b):
				var ratio_a = float(a.current_hp) / max(1.0, float(a.hp_max))
				var ratio_b = float(b.current_hp) / max(1.0, float(b.hp_max))
				if ratio_a != ratio_b:
					return ratio_a < ratio_b
				return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
			)
			attack_target(allies[0])
		return

	var cibles = zone_detection.get_overlapping_bodies().filter(func(c):
		return c != self and c.has_method("take_damage") and not c.is_in_group("camps") and c.get("team") != null and c.get("team") != team
	)
	if is_camp_guardian:
		cibles = cibles.filter(func(c): return c.global_position.distance_to(guard_position) <= guard_defense_radius)
	
	if cibles.size() > 0:
		cibles.sort_custom(func(a, b):
			var a_est_soldat = not a.is_in_group("camps")
			var b_est_soldat = not b.is_in_group("camps")
			if a_est_soldat != b_est_soldat: return a_est_soldat
			return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
		)
		attack_target(cibles[0])

func _est_healer() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.HEAL

func _est_range() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.ARCHER

func _est_mortar() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.MORTAR

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
	if proj.has_method("launch"):
		proj.launch(cible, unit_damage, self)

func _niveau_mortar() -> int:
	if stats == null:
		return 1
	var nom_lower := String(stats.name).to_lower()
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
		attack_target_node = null
		return
	var position_impact := cible.global_position
	var explosion = _prochaine_explosion_mortar()
	_spawn_mortar_explosion_vfx(explosion["scene"], position_impact)
	_appliquer_degats_zone(position_impact, explosion["rayon"], explosion["degats"])

func _prochaine_explosion_mortar() -> Dictionary:
	var base = {
		"scene": SCENE_MORTAR_EXPLOSION_BASE,
		"rayon": 84.0,
		"degats": unit_damage
	}
	var poison = {
		"scene": SCENE_MORTAR_EXPLOSION_POISON,
		"rayon": 96.0,
		"degats": int(round(float(unit_damage) * 0.65))
	}
	var feu = {
		"scene": SCENE_MORTAR_EXPLOSION_FEU,
		"rayon": 110.0,
		"degats": int(round(float(unit_damage) * 0.85))
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
	if vfx.is_in_group("soldiers"):
		vfx.remove_from_group("soldiers")
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
		if not obj.has_method("take_damage"):
			continue
		if obj.get("team") == null or obj.team == team:
			continue
		if obj.is_in_group("camps"):
			continue
		obj.take_damage(degats, self)

func _appliquer_soin_cible(cible: Node2D):
	if not is_instance_valid(cible):
		timer_attaque.stop()
		attack_target_node = null
		return
	if not ("current_hp" in cible and "hp_max" in cible):
		return
	if cible.get("team") == null or cible.team != team:
		return
	if cible.current_hp >= cible.hp_max:
		attack_target_node = null
		return

	var soin = int(max(10.0, float(hp_max) * 0.12))
	cible.current_hp = min(cible.hp_max, cible.current_hp + soin)
	if cible.has_node("ProgressBar"):
		cible.get_node("ProgressBar").value = cible.current_hp

func update_animation():
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

func take_damage(montant : int, auteur = null, auteur_team : int = -1):
	if is_dying:
		return

	var degats_finaux = montant
	
	if is_instance_valid(auteur) and "stats" in auteur and auteur.stats != null:
		if auteur.stats.unit_type == 5:
			degats_finaux = degats_finaux * 3 if (stats and stats.unit_type == 2) else int(float(degats_finaux) * 0.5)
				
	current_hp -= degats_finaux
	
	if has_node("ProgressBar"):
		$ProgressBar.value = current_hp
		
	if current_hp <= 0:
		var eq = auteur_team
		if eq == -1 and is_instance_valid(auteur) and auteur.get("team") != null:
			eq = auteur.team
		die(auteur, eq)

func die(tueur : Node2D = null, tueur_team : int = -1):
	if is_dying:
		return

	is_dying = true
	if _est_mortar():
		_jouer_animation_sur_sprites("attack_" + dernier_regard, "idle_" + dernier_regard)
		_spawn_mortar_explosion_vfx(SCENE_MORTAR_EXPLOSION_BASE, global_position)
		_appliquer_degats_zone(global_position, 120.0, int(round(float(unit_damage) * 1.15)))
		await get_tree().create_timer(0.22).timeout
	killed_by.emit(tueur, tueur_team)
	velocity = Vector2.ZERO
	attack_target_node = null
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

func cast_spell():
	if not stats or cooldown_actuel_sort > 0:
		return
	if _est_mortar():
		if _cast_spell_mortar_ult():
			var spell_cooldown_mortar = stats.spell_cooldown if stats.spell_cooldown > 0 else MORTAR_SORT_COOLDOWN_DEFAUT
			cooldown_actuel_sort = spell_cooldown_mortar
		return
	if stats.spell_cooldown <= 0:
		return
	cooldown_actuel_sort = stats.spell_cooldown
	
	var requete = PhysicsShapeQueryParameters2D.new()
	var cercle = CircleShape2D.new()
	cercle.radius = 150.0
	requete.shape = cercle
	requete.transform = Transform2D(0, global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	
	var resultats = get_world_2d().direct_space_state.intersect_shape(requete)
	var groupe = "soldiers" if team == Owner.PLAYER else "enemies"
	
	for res in resultats:
		var obj = res.collider
		if obj and obj.is_in_group(groupe):
			if stats.unit_type == 3 and obj.has_method("receive_boost"):
				obj.receive_boost(stats.spell_duration + 10.0)
			elif stats.unit_type == 4 and "current_hp" in obj and "hp_max" in obj:
				obj.current_hp = min(obj.hp_max, obj.current_hp + 50)
				if obj.has_node("ProgressBar"):
					obj.get_node("ProgressBar").value = obj.current_hp

func _cast_spell_mortar_ult() -> bool:
	var niveau = _niveau_mortar()
	var nb_cibles = 1
	if niveau == 2:
		nb_cibles = 2
	elif niveau >= 3:
		nb_cibles = 3

	var cibles = _cibles_ennemies_plus_proches_mortar(nb_cibles)
	if cibles.is_empty():
		return false

	var degats_sort = int(round(float(unit_damage) * 1.2))
	for cible in cibles:
		var position_impact = cible.global_position
		_spawn_mortar_explosion_vfx(SCENE_MORTAR_EXPLOSION_ULT, position_impact)
		_appliquer_degats_zone(position_impact, 112.0, degats_sort)
	return true

func _cibles_ennemies_plus_proches_mortar(nb_max: int) -> Array:
	var cibles: Array = zone_detection.get_overlapping_bodies().filter(func(c):
		return c != self and c.has_method("take_damage") and not c.is_in_group("camps") and c.get("team") != null and c.get("team") != team
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

func receive_boost(duree: float):
	boost_actif = true
	temps_restant_boost = duree
	unit_speed = stats.speed * 1.25
	unit_damage = int(round(stats.damage * 1.25))
	attack_rate_multiplier = 1.25
	_appliquer_couleur_unite()

func _attack_rate_actuelle() -> float:
	var cadence_base = stats.attack_rate if stats and "attack_rate" in stats else 1.0
	return cadence_base * attack_rate_multiplier

func _couleur_unite() -> Color:
	if boost_actif:
		return Color(1.0, 0.95, 0.25)
	if team == Owner.ENEMY:
		return Color(1.0, 0.2, 0.2)
	return Color.WHITE

func _appliquer_couleur_unite():
	for sprite in _sprites_animes_unite():
		sprite.modulate = _couleur_unite()

func configure_guardian_mode(position_ancre: Vector2, rayon_defense: float = 260.0, rayon_poursuite: float = 320.0):
	is_camp_guardian = true
	guard_position = position_ancre
	guard_defense_radius = rayon_defense
	guard_chase_radius = rayon_poursuite
	agent_navigation.target_position = guard_position
