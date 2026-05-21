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
const SCENE_RANGE_PROJECTILE_LOOP = preload("uid://swrp6c3h83xg")
const SCENE_WATER_RANGE_PROJECTILE_LOOP = preload("uid://djbfyhto8wuop")
const SCENE_HEALER_PROJECTILE_LOOP = preload("uid://5cvanebkvuv0")
const SCENE_HEALER_EFFECT = preload("uid://cdvvumicj5qty")
const SCENE_SUPPORT_EFFECT = preload("uid://ca8jxgt0j8nmw")
const SCENE_DOUBLE_EFFECT = preload("uid://badrqmpt16vq7")
const DUREE_INVULN_SORT_NIVEAU_1 := 10.0
const DUREE_BOOST_SORT_NIVEAU_1 := 20.0
const BONUS_INVULN_PAR_NIVEAU := 5.0
const BONUS_BOOST_PAR_NIVEAU := 10.0
const SCENE_PORT_GUARDIAN_PROJECTILE_LOOP = preload("res://scenes/personnages/port_guardian/gardian-port-loop-projectile.tscn")
const SCENE_CAMP_GUARDIAN_PROJECTILE_LOOP = preload("uid://ofkkgjehycuj")
const RAYON_TIR_PASSIF_PORT_GARDIEN := 420.0
const VITESSE_PROJECTILE_PORT_GARDIEN := 320.0
const VITESSE_PROJECTILE_CAMP_GARDIEN := 380.0
const DUREE_EFFET_SOIN_DEFAUT := 4.0
const NOM_NOEUD_EFFET_BUFF := "BuffEffectVfx"
const FACTEUR_ZONE_RANGE := 0.65
const FACTEUR_ZONE_HEALER := 0.6
const FACTEUR_ZONE_GARDIEN_CAMP := 0.85
const SCENE_MORTAR_EXPLOSION_BASE = preload("res://scenes/personnages/mortar/explosion.tscn")
const SCENE_MORTAR_EXPLOSION_POISON = preload("res://scenes/personnages/mortar/poison-explosion.tscn")
const SCENE_MORTAR_EXPLOSION_FEU = preload("res://scenes/personnages/mortar/fire-explosion.tscn")
const SCENE_MORTAR_EXPLOSION_ULT = preload("res://scenes/personnages/mortar/explosion-ult.tscn")
const MORTAR_ATTACK_COOLDOWN_NIVEAU_1 = 4.8
const MORTAR_ATTACK_COOLDOWN_NIVEAU_2 = 3.9
const MORTAR_ATTACK_COOLDOWN_NIVEAU_3 = 3.2
const MORTAR_SORT_COOLDOWN_DEFAUT = 12.0
const COOLDOWN_SORT_SECONDES := 60.0
## Navigation 2D (bitmask) — doit correspondre aux régions dans Main :
## layer 1 (valeur 1) = Nav_ground | layer 2 (valeur 2) = Nav_water
## layer 3 (valeur 4) = ground-and-water-unit (mesh combiné sol+eau pour support/healer)
const NAV_LAYER_GROUND := 1
const NAV_LAYER_WATER := 2
const NAV_LAYER_GROUND_AND_WATER := 4

## Calques physique : alliés ne se bloquent pas entre eux (glissement latéral).
const COLLISION_LAYER_WORLD := 1
const COLLISION_LAYER_PLAYER_UNIT := 2
const COLLISION_LAYER_ENEMY_UNIT := 4
const UNIT_BODY_RADIUS := 10.0
const GUARDIAN_BODY_RADIUS := 11.0
const SEPARATION_RADIUS := 52.0
const SEPARATION_FORCE := 95.0

@export var force_water_navigation: bool = false
@export var force_amphibious_navigation: bool = false

@onready var agent_navigation = $NavigationAgent2D
var attack_target_node : Node2D = null
@onready var zone_detection = $ZoneDetection
@onready var timer_attaque = $TimerAttaque

var temps_recherche : float = 0.5
var timer_recherche : float = 0.0
var timer_tir_passif_gardien : float = 0.0

var cooldown_actuel_sort : float = 0.0
var temps_restant_boost : float = 0.0
var boost_actif : bool = false
var invulnerabilite_actif : bool = false
var temps_restant_invulnerabilite : float = 0.0
var attack_rate_multiplier: float = 1.0
var is_dying : bool = false
var cycle_explosion_mortar : int = 0
var is_camp_guardian: bool = false
var guard_position: Vector2 = Vector2.ZERO
var guard_defense_radius: float = 260.0
var guard_chase_radius: float = 320.0

func _apply_stats_to_unit() -> void:
	if not stats:
		return
	hp_max = stats.hp_max
	current_hp = hp_max
	unit_speed = stats.speed
	unit_damage = stats.damage
	_appliquer_couleur_unite()
	if has_node("ProgressBar"):
		$ProgressBar.max_value = hp_max
		$ProgressBar.value = current_hp
	var rayon := _rayon_zone_detection()
	var shape = $ZoneDetection/CollisionShape2D.shape
	if shape is CircleShape2D:
		$ZoneDetection/CollisionShape2D.shape = shape.duplicate()
		$ZoneDetection/CollisionShape2D.shape.radius = rayon
	if is_instance_valid(agent_navigation):
		agent_navigation.target_desired_distance = max(8.0, rayon - 5.0)

func _ready():
	_apply_stats_to_unit()
	_configurer_calques_navigation()
	_configurer_mouvement_et_collisions()
	agent_navigation.path_desired_distance = 10.0
	await get_tree().process_frame
	agent_navigation.target_position = global_position
	timer_attaque.timeout.connect(_on_timer_attaque_timeout)
	_configurer_animations_mort()

func _configurer_calques_navigation() -> void:
	if not is_instance_valid(agent_navigation):
		return
	if _is_amphibious_unit():
		agent_navigation.navigation_layers = NAV_LAYER_GROUND_AND_WATER
	elif _is_naval_unit():
		agent_navigation.navigation_layers = NAV_LAYER_WATER
	else:
		agent_navigation.navigation_layers = NAV_LAYER_GROUND

func _is_amphibious_unit() -> bool:
	if force_amphibious_navigation:
		return true
	if stats != null:
		return stats.unit_type == UnitStats.UnitType.SUPPORT or stats.unit_type == UnitStats.UnitType.HEAL
	var chemin_scene := scene_file_path
	return chemin_scene.contains("/support/") or chemin_scene.contains("/healer/")

func _is_naval_unit() -> bool:
	if _is_amphibious_unit():
		return false
	if force_water_navigation:
		return true
	if stats != null:
		return stats.unit_type == UnitStats.UnitType.WATER_TANK or stats.unit_type == UnitStats.UnitType.WATER_RANGE
	var chemin_scene := scene_file_path
	return chemin_scene.contains("/water-range/") or chemin_scene.contains("/water-tank/")

func set_selection(etat : bool):
	is_selected = etat
	self.modulate = Color(1.2, 1.2, 1.2) if is_selected else Color(1, 1, 1)

func move_to(cible : Vector2):
	if is_camp_guardian:
		return
	attack_target_node = null
	agent_navigation.target_position = cible

func _arreter_combat() -> void:
	attack_target_node = null
	if is_instance_valid(timer_attaque):
		timer_attaque.stop()
	velocity = Vector2.ZERO

func _cible_combat_valide(cible: Node) -> bool:
	if cible == null or not is_instance_valid(cible):
		return false
	if not cible.is_inside_tree():
		return false
	if "is_dying" in cible and cible.is_dying:
		return false
	if "current_hp" in cible and cible.current_hp <= 0:
		return false
	if _est_healer():
		if not ("current_hp" in cible and "hp_max" in cible):
			return false
		if cible.get("team") == null or cible.team != team:
			return false
		return cible.current_hp < cible.hp_max
	if cible.has_method("take_damage"):
		if cible.is_in_group("camps"):
			return false
		if cible.get("team") != null and cible.team == team:
			return false
		return true
	return false

func attack_target(cible : Node2D):
	if not _cible_combat_valide(cible):
		return
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

	if is_camp_guardian and (_est_gardien_port() or _est_gardien_camp()):
		_gerer_tirs_passifs_gardien(_delta)

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
			_mettre_a_jour_effet_visuel(self)

	if invulnerabilite_actif:
		temps_restant_invulnerabilite -= _delta
		if temps_restant_invulnerabilite <= 0:
			invulnerabilite_actif = false
			_appliquer_couleur_unite()
			_mettre_a_jour_effet_visuel(self)
	
	if is_instance_valid(attack_target_node) and not _cible_combat_valide(attack_target_node):
		_arreter_combat()

	if is_instance_valid(attack_target_node):
		var cible_valide := attack_target_node
		if is_camp_guardian and cible_valide.global_position.distance_to(guard_position) > guard_chase_radius:
			_arreter_combat()
			agent_navigation.target_position = guard_position
			doit_avancer = true
		else:
			agent_navigation.target_position = cible_valide.global_position
			var dans_zone: bool = cible_valide in zone_detection.get_overlapping_bodies()
			if dans_zone:
				doit_avancer = false
				if timer_attaque.is_stopped():
					if _est_mortar():
						_tirer_mortar_distance(attack_target_node)
						timer_attaque.start(_cooldown_mortar_niveau())
					else:
						var cadence = _attack_rate_actuelle()
						timer_attaque.start(1.0 / cadence)
			else:
				_arreter_combat()
	else:
		if is_instance_valid(timer_attaque):
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
		_appliquer_deplacement_vers(prochain_point)
	else:
		velocity = Vector2.ZERO

	update_animation()

func _on_timer_attaque_timeout():
	if not _cible_combat_valide(attack_target_node):
		_arreter_combat()
		return
	if not (attack_target_node in zone_detection.get_overlapping_bodies()):
		_arreter_combat()
		return
	if _est_healer():
		_jouer_animation_attaque(attack_target_node)
		_tirer_projectile_heal(attack_target_node)
		return
	if _est_mortar():
		_tirer_mortar_distance(attack_target_node)
		return
	if _est_range() or _est_water_range_unite() or (stats != null and stats.is_ranged):
		_jouer_animation_attaque(attack_target_node)
		_tirer_projectile_range(attack_target_node)
		return
	if attack_target_node.has_method("take_damage"):
		_jouer_animation_attaque(attack_target_node)
		attack_target_node.take_damage(unit_damage, self)
		_animer_attaque_melee()

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
			return c != self and _cible_combat_valide(c)
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
		return c != self and _cible_combat_valide(c)
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

func _est_water_range_unite() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.WATER_RANGE

func _est_mortar() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.MORTAR

func _tirer_projectile_range(cible: Node2D):
	if not _cible_combat_valide(cible):
		_arreter_combat()
		return
	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		return
	var scene_proj := SCENE_WATER_RANGE_PROJECTILE_LOOP if _est_water_range_unite() else SCENE_RANGE_PROJECTILE_LOOP
	var proj = scene_proj.instantiate()
	parent_node.add_child(proj)
	proj.global_position = global_position
	if proj.has_method("launch"):
		proj.launch(cible, unit_damage, self)

func _montant_soin() -> int:
	return int(max(10.0, float(hp_max) * 0.12))

func _tirer_projectile_heal(cible: Node2D) -> void:
	if not _cible_combat_valide(cible):
		_arreter_combat()
		return
	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj = SCENE_HEALER_PROJECTILE_LOOP.instantiate()
	parent_node.add_child(proj)
	proj.global_position = global_position
	if proj.has_method("launch"):
		proj.launch(cible, _montant_soin(), self)

func _est_gardien_port() -> bool:
	return scene_file_path.contains("/port_guardian/")

func _est_gardien_camp() -> bool:
	return is_camp_guardian and scene_file_path.contains("/guardian/") and not _est_gardien_port()

func _niveau_gardien_port() -> int:
	if stats == null:
		return 1
	var nom_lower := String(stats.name).to_lower()
	if nom_lower.find("iii") != -1 or nom_lower.find(" 3") != -1:
		return 3
	if nom_lower.find("ii") != -1 or nom_lower.find(" 2") != -1:
		return 2
	return 1

func _rayon_zone_detection() -> float:
	if stats == null:
		return 100.0
	if _est_healer():
		return stats.range * FACTEUR_ZONE_HEALER
	if _est_range():
		return stats.range * FACTEUR_ZONE_RANGE
	if is_camp_guardian and not _est_gardien_port():
		return stats.range * FACTEUR_ZONE_GARDIEN_CAMP
	return stats.range

func _gerer_tirs_passifs_gardien(delta: float) -> void:
	var ennemis: Array = _ennemis_portee_tir_passif_gardien()
	if ennemis.is_empty():
		timer_tir_passif_gardien = 0.0
		return
	timer_tir_passif_gardien -= delta
	if timer_tir_passif_gardien > 0.0:
		return
	timer_tir_passif_gardien = 1.0 / float(_niveau_gardien_port())
	ennemis.sort_custom(func(a, b):
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)
	_tirer_projectile_gardien_passif(ennemis[0])

func _ennemis_portee_tir_passif_gardien() -> Array:
	var requete := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = RAYON_TIR_PASSIF_PORT_GARDIEN
	requete.shape = cercle
	requete.transform = Transform2D(0, global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	requete.collision_mask = COLLISION_LAYER_PLAYER_UNIT | COLLISION_LAYER_ENEMY_UNIT

	var cibles: Array = []
	for res in get_world_2d().direct_space_state.intersect_shape(requete):
		var obj = res.collider
		if not is_instance_valid(obj) or obj == self:
			continue
		if not obj.has_method("take_damage") or obj.is_in_group("camps"):
			continue
		if obj.get("team") == null or obj.team == team:
			continue
		if obj.global_position.distance_to(guard_position) > guard_chase_radius:
			continue
		cibles.append(obj)
	return cibles

func _scene_projectile_gardien_passif() -> PackedScene:
	if _est_gardien_port():
		return SCENE_PORT_GUARDIAN_PROJECTILE_LOOP
	return SCENE_CAMP_GUARDIAN_PROJECTILE_LOOP

func _vitesse_projectile_gardien_passif() -> float:
	if _est_gardien_port():
		return VITESSE_PROJECTILE_PORT_GARDIEN
	return VITESSE_PROJECTILE_CAMP_GARDIEN

func _tirer_projectile_gardien_passif(cible: Node2D) -> void:
	if not is_instance_valid(cible):
		return
	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj = _scene_projectile_gardien_passif().instantiate()
	parent_node.add_child(proj)
	proj.global_position = global_position
	if proj.has_method("launch"):
		proj.launch(cible, unit_damage, self, _vitesse_projectile_gardien_passif())

func _duree_effet_soin() -> float:
	return DUREE_EFFET_SOIN_DEFAUT

func _niveau_unite() -> int:
	if stats == null:
		return 1
	var nom_lower := String(stats.name).to_lower()
	if nom_lower.find("iii") != -1 or nom_lower.find(" 3") != -1:
		return 3
	if nom_lower.find("ii") != -1 or nom_lower.find(" 2") != -1:
		return 2
	return 1

func _duree_sort_invulnerabilite() -> float:
	var niveau := _niveau_unite()
	return DUREE_INVULN_SORT_NIVEAU_1 + float(niveau - 1) * BONUS_INVULN_PAR_NIVEAU

func _duree_sort_boost() -> float:
	var niveau := _niveau_unite()
	return DUREE_BOOST_SORT_NIVEAU_1 + float(niveau - 1) * BONUS_BOOST_PAR_NIVEAU

func _duree_effet_visuel_sur_cible(cible: Node2D) -> float:
	var duree := 0.0
	if cible.get("invulnerabilite_actif") and cible.invulnerabilite_actif:
		duree = maxf(duree, cible.temps_restant_invulnerabilite)
	if cible.get("boost_actif") and cible.boost_actif:
		duree = maxf(duree, cible.temps_restant_boost)
	return duree

func _scene_effet_pour_cible(cible: Node2D) -> PackedScene:
	var invuln: bool = cible.get("invulnerabilite_actif") == true and bool(cible.invulnerabilite_actif)
	var boost: bool = cible.get("boost_actif") == true and bool(cible.boost_actif)
	if invuln and boost:
		return SCENE_DOUBLE_EFFECT
	if invuln:
		return SCENE_HEALER_EFFECT
	if boost:
		return SCENE_SUPPORT_EFFECT
	return null

func _mettre_a_jour_effet_visuel(cible: Node2D) -> void:
	if not is_instance_valid(cible):
		return
	var existant := cible.get_node_or_null(NOM_NOEUD_EFFET_BUFF)
	if is_instance_valid(existant):
		existant.queue_free()
	var scene_fx := _scene_effet_pour_cible(cible)
	if scene_fx == null:
		return
	var duree := _duree_effet_visuel_sur_cible(cible)
	if duree <= 0.0:
		return
	var fx = scene_fx.instantiate()
	fx.name = NOM_NOEUD_EFFET_BUFF
	cible.add_child(fx)
	if fx.has_method("demarrer"):
		fx.demarrer(duree)

func _attacher_effet_soin_sur(cible: Node2D) -> void:
	if not is_instance_valid(cible):
		return
	if cible.get("invulnerabilite_actif") and cible.invulnerabilite_actif:
		_mettre_a_jour_effet_visuel(cible)
		return
	_attacher_effet_sur_cible(cible, SCENE_HEALER_EFFECT, _duree_effet_soin())

func _attacher_effet_sur_cible(cible: Node2D, scene_fx: PackedScene, duree: float) -> void:
	if not is_instance_valid(cible) or scene_fx == null or duree <= 0.0:
		return
	var existant := cible.get_node_or_null(NOM_NOEUD_EFFET_BUFF)
	if is_instance_valid(existant):
		existant.queue_free()
	var fx = scene_fx.instantiate()
	fx.name = NOM_NOEUD_EFFET_BUFF
	cible.add_child(fx)
	if fx.has_method("demarrer"):
		fx.demarrer(duree)

func _niveau_mortar() -> int:
	return _niveau_unite()

func _cooldown_mortar_niveau() -> float:
	var niveau := _niveau_mortar()
	if niveau >= 3:
		return MORTAR_ATTACK_COOLDOWN_NIVEAU_3
	if niveau == 2:
		return MORTAR_ATTACK_COOLDOWN_NIVEAU_2
	return MORTAR_ATTACK_COOLDOWN_NIVEAU_1

func _tirer_mortar_distance(cible: Node2D):
	if not _cible_combat_valide(cible):
		_arreter_combat()
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
	if not _cible_combat_valide(cible):
		_arreter_combat()
		return

	var soin = _montant_soin()
	cible.current_hp = min(cible.hp_max, cible.current_hp + soin)
	if cible.has_node("ProgressBar"):
		cible.get_node("ProgressBar").value = cible.current_hp
	_attacher_effet_soin_sur(cible)

func update_animation():
	if not has_node("AnimatedSprite2D"):
		return

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.is_playing():
		if sprite.animation.begins_with("death_"):
			return
		if sprite.animation.begins_with("attack_"):
			var combat_actif: bool = is_instance_valid(attack_target_node) \
				and _cible_combat_valide(attack_target_node) \
				and attack_target_node in zone_detection.get_overlapping_bodies()
			if not combat_actif:
				_jouer_animation_sur_sprites("idle_" + dernier_regard)
			return

	if velocity.length() > 5.0:
		if abs(velocity.x) > abs(velocity.y): dernier_regard = "r" if velocity.x > 0 else "l"
		else: dernier_regard = "f" if velocity.y > 0 else "b"
		_jouer_animation_sur_sprites("run_" + dernier_regard)
	else:
		_jouer_animation_sur_sprites("idle_" + dernier_regard)

func take_damage(montant : int, auteur = null, auteur_team : int = -1):
	if is_dying or invulnerabilite_actif:
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
	_arreter_combat()

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

func peut_lancer_sort() -> bool:
	if not stats or is_dying:
		return false
	if cooldown_actuel_sort > 0.0:
		return false
	if _est_mortar() or _est_healer() or (stats.unit_type == UnitStats.UnitType.SUPPORT):
		return true
	return stats.spell_cooldown > 0.0

func cast_spell() -> bool:
	if not peut_lancer_sort():
		return false
	if _est_mortar():
		if _cast_spell_mortar_ult():
			cooldown_actuel_sort = COOLDOWN_SORT_SECONDES
			return true
		return false

	var requete := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = 150.0
	requete.shape = cercle
	requete.transform = Transform2D(0, global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true

	var resultats = get_world_2d().direct_space_state.intersect_shape(requete)
	var groupe := "soldiers" if team == Owner.PLAYER else "enemies"
	var au_moins_un_effet := false

	for res in resultats:
		var obj = res.collider
		if not obj or not obj.is_in_group(groupe):
			continue
		if stats.unit_type == UnitStats.UnitType.SUPPORT and obj.has_method("receive_boost"):
			obj.receive_boost(_duree_sort_boost())
			au_moins_un_effet = true
		elif stats.unit_type == UnitStats.UnitType.HEAL and obj.has_method("recevoir_invulnerabilite_sort"):
			obj.recevoir_invulnerabilite_sort(_duree_sort_invulnerabilite())
			au_moins_un_effet = true

	if not au_moins_un_effet:
		return false

	cooldown_actuel_sort = COOLDOWN_SORT_SECONDES
	return true

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

func recevoir_invulnerabilite_sort(duree: float) -> void:
	if duree <= 0.0 or not stats:
		return
	invulnerabilite_actif = true
	temps_restant_invulnerabilite = maxf(temps_restant_invulnerabilite, duree)
	_appliquer_couleur_unite()
	_mettre_a_jour_effet_visuel(self)

func receive_boost(duree: float):
	if duree <= 0.0 or not stats:
		return
	boost_actif = true
	temps_restant_boost = maxf(temps_restant_boost, duree)
	unit_speed = stats.speed * 1.25
	unit_damage = int(round(stats.damage * 1.25))
	attack_rate_multiplier = 1.25
	_appliquer_couleur_unite()
	_mettre_a_jour_effet_visuel(self)

func _attack_rate_actuelle() -> float:
	var cadence_base = stats.attack_rate if stats and "attack_rate" in stats else 1.0
	return cadence_base * attack_rate_multiplier

func _couleur_unite() -> Color:
	if invulnerabilite_actif and boost_actif:
		return Color(0.45, 1.0, 0.55)
	if invulnerabilite_actif:
		return Color(0.35, 1.0, 0.45)
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
	_configurer_mouvement_et_collisions()
	if is_instance_valid(agent_navigation):
		agent_navigation.target_position = guard_position


func _est_scene_gardien() -> bool:
	var chemin := scene_file_path
	return chemin.contains("/guardian/") or chemin.contains("/port_guardian/")


func _configurer_mouvement_et_collisions() -> void:
	motion_mode = MOTION_MODE_FLOATING
	floor_stop_on_slope = false
	floor_block_on_wall = false
	safe_margin = 0.035
	_appliquer_calques_collision_equipe()
	_configurer_zone_detection()
	_configurer_forme_collision()
	_configurer_evitement_navigation()


func _appliquer_calques_collision_equipe() -> void:
	match team:
		Owner.PLAYER:
			collision_layer = COLLISION_LAYER_PLAYER_UNIT
			collision_mask = COLLISION_LAYER_WORLD | COLLISION_LAYER_ENEMY_UNIT
		Owner.ENEMY:
			collision_layer = COLLISION_LAYER_ENEMY_UNIT
			collision_mask = COLLISION_LAYER_WORLD | COLLISION_LAYER_PLAYER_UNIT
		_:
			collision_layer = COLLISION_LAYER_PLAYER_UNIT | COLLISION_LAYER_ENEMY_UNIT
			collision_mask = COLLISION_LAYER_WORLD


func _configurer_zone_detection() -> void:
	if not is_instance_valid(zone_detection):
		return
	# L'Area2D doit voir les corps sur les calques unités (sinon plus d'attaque auto).
	zone_detection.collision_layer = 0
	zone_detection.monitorable = false
	zone_detection.monitoring = true
	zone_detection.collision_mask = (
		COLLISION_LAYER_PLAYER_UNIT
		| COLLISION_LAYER_ENEMY_UNIT
		| COLLISION_LAYER_WORLD
	)


func _configurer_forme_collision() -> void:
	if not has_node("CollisionShape2D"):
		return
	var shape_node: CollisionShape2D = $CollisionShape2D
	var shape = shape_node.shape
	if shape is CircleShape2D:
		var circle: CircleShape2D = shape.duplicate()
		if is_camp_guardian or _est_scene_gardien():
			circle.radius = GUARDIAN_BODY_RADIUS
		else:
			circle.radius = UNIT_BODY_RADIUS
		shape_node.shape = circle


func _configurer_evitement_navigation() -> void:
	if not is_instance_valid(agent_navigation):
		return
	agent_navigation.avoidance_enabled = true
	var rayon := GUARDIAN_BODY_RADIUS if (is_camp_guardian or _est_scene_gardien()) else UNIT_BODY_RADIUS
	agent_navigation.radius = rayon * 0.9
	agent_navigation.neighbor_distance = 70.0
	agent_navigation.max_neighbors = 8
	agent_navigation.time_horizon_agents = 0.45
	agent_navigation.max_speed = unit_speed


func _appliquer_deplacement_vers(prochain_point: Vector2) -> void:
	var vitesse_desiree := _calculer_vitesse_desiree(prochain_point)
	velocity = vitesse_desiree
	move_and_slide()
	if get_slide_collision_count() > 0 and velocity.length() < unit_speed * 0.35:
		var glisse := Vector2.ZERO
		for i in get_slide_collision_count():
			var normale := get_slide_collision(i).get_normal()
			glisse += Vector2(-normale.y, normale.x) * signf(vitesse_desiree.dot(Vector2(-normale.y, normale.x)))
		if glisse.length_squared() > 0.01:
			velocity = glisse.normalized() * unit_speed * 0.75
			move_and_slide()


func _calculer_vitesse_desiree(prochain_point: Vector2) -> Vector2:
	var direction := global_position.direction_to(prochain_point)
	if direction.length_squared() < 0.0001:
		return Vector2.ZERO
	var vitesse := direction * unit_speed
	vitesse += _calculer_repulsion_allies()
	if vitesse.length() > unit_speed:
		vitesse = vitesse.normalized() * unit_speed
	return vitesse


func _calculer_repulsion_allies() -> Vector2:
	var repulsion := Vector2.ZERO
	var groupe := "soldiers" if team == Owner.PLAYER else "enemies"
	for node in get_tree().get_nodes_in_group(groupe):
		if node == self or not (node is CharacterBody2D):
			continue
		if not is_instance_valid(node):
			continue
		if "is_dying" in node and node.is_dying:
			continue
		var ecart: Vector2 = global_position - node.global_position
		var distance := ecart.length()
		if distance < 0.001 or distance > SEPARATION_RADIUS:
			continue
		var intensite := (SEPARATION_RADIUS - distance) / SEPARATION_RADIUS
		repulsion += ecart.normalized() * intensite * SEPARATION_FORCE
	return repulsion
