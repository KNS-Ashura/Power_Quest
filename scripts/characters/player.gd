extends CharacterBody2D

signal killed_by(tueur, tueur_team)

@export var stats : UnitStats

enum Owner { PLAYER, ENEMY, NEUTRAL }
@export var team: Owner = Owner.PLAYER

var net_sync_id: int = -1
var net_remote_proxy: bool = false
var _net_target_position: Vector2 = Vector2.ZERO
var _net_lerp_active: bool = false
var _network_damage: bool = false

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
const SCENE_ANTI_ARMOR_PROJECTILE_LOOP = preload("res://scenes/personnages/anti_armor/anti-armor-loop-projectile.tscn")
const RAYON_TIR_PASSIF_PORT_GARDIEN := 420.0
const VITESSE_PROJECTILE_PORT_GARDIEN := 320.0
const VITESSE_PROJECTILE_CAMP_GARDIEN := 380.0
const VITESSE_PROJECTILE_ANTI_ARMOR_SORT := 120.0
const DUREE_EFFET_SOIN_DEFAUT := 4.0
const NOM_NOEUD_EFFET_BUFF := "BuffEffectVfx"
const MULTIPLICATEUR_DEGATS_ANTI_ARMOR_SORT := 2.0
const DUREE_SORT_ANTI_ARMOR_NIVEAU_1 := 10.0
const BONUS_DUREE_SORT_ANTI_ARMOR_PAR_NIVEAU := 2.0
const RAYON_SORT_ANTI_ARMOR_NIVEAU_1 := 150.0
const BONUS_RAYON_SORT_ANTI_ARMOR_PAR_NIVEAU := 30.0
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
const SCENE_WATER_TRANSPORT_MARK_FX = preload("res://scenes/personnages/water-transporter/water-transporter-effect.tscn")
const SCENE_WATER_TRANSPORT_BOARD_FX = preload("res://scenes/personnages/water-transporter/water-transporter-effect-2.tscn")
const WATER_TRANSPORT_MARK_RADIUS := 150.0
const WATER_TRANSPORT_COOLDOWN := 30.0
const WATER_TRANSPORT_SCALE_BONUS := 0.05
const WATER_TRANSPORT_DISEMBARK_TRIGGER_DIST := 60.0
const WATER_TRANSPORT_DISEMBARK_MAX_DIST := 30.0
const WATER_TRANSPORT_DISEMBARK_MIN_CLEARANCE := 18.0
const WATER_TRANSPORT_DISEMBARK_SPREAD := 14.0
const WATER_TRANSPORT_CAP_BY_LEVEL := {1: 5, 2: 8, 3: 11}
## Navigation 2D (bitmask) — doit correspondre aux régions dans Main :
## layer 1 (valeur 1) = Nav_ground | layer 2 (valeur 2) = Nav_water
const NAV_LAYER_GROUND := 1
const NAV_LAYER_WATER := 2

## Calques physique : alliés ne se bloquent pas entre eux (glissement latéral).
const COLLISION_LAYER_WORLD := 1
const COLLISION_LAYER_PLAYER_UNIT := 2
const COLLISION_LAYER_ENEMY_UNIT := 4
const UNIT_BODY_RADIUS := 10.0
const GUARDIAN_BODY_RADIUS := 11.0
const SEPARATION_RADIUS := 52.0
const SEPARATION_FORCE := 95.0

@export var force_water_navigation: bool = false

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
var anti_armor_sort_actif : bool = false
var temps_restant_anti_armor_sort : float = 0.0
var multiplicateur_degats_subis : float = 1.0
var attack_rate_multiplier: float = 1.0
var is_dying : bool = false
var cycle_explosion_mortar : int = 0
var is_camp_guardian: bool = false
var guard_position: Vector2 = Vector2.ZERO
var guard_defense_radius: float = 260.0
var guard_chase_radius: float = 320.0

enum WaterTransportPhase { IDLE, UNITS_MARKED, CARRYING }
var water_transport_phase: WaterTransportPhase = WaterTransportPhase.IDLE
var water_transport_marked: Array[Node2D] = []
var water_transport_boarded: Array[Node2D] = []
var water_transport_origin: Dictionary = {}
var water_transport_cooldown: float = 0.0
var water_transport_base_scale: Vector2 = Vector2.ONE

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
	water_transport_base_scale = scale
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
	if _is_naval_unit():
		agent_navigation.navigation_layers = NAV_LAYER_WATER
	else:
		agent_navigation.navigation_layers = NAV_LAYER_GROUND

func _is_naval_unit() -> bool:
	if force_water_navigation:
		return true
	if stats != null:
		return stats.unit_type == UnitStats.UnitType.WATER_TANK \
			or stats.unit_type == UnitStats.UnitType.WATER_RANGE \
			or stats.unit_type == UnitStats.UnitType.WATER_TRANSPORT
	var chemin_scene := scene_file_path
	return chemin_scene.contains("/water-range/") or chemin_scene.contains("/water-tank/")

func set_selection(etat : bool):
	is_selected = etat
	self.modulate = Color(1.2, 1.2, 1.2) if is_selected else Color(1, 1, 1)

func move_to(cible : Vector2):
	if net_remote_proxy:
		return
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
	if net_remote_proxy:
		return
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
	if net_remote_proxy:
		_physics_process_network_proxy(_delta)
		return

	if is_camp_guardian and (_est_gardien_port() or _est_gardien_camp()):
		_gerer_tirs_passifs_gardien(_delta)

	var doit_avancer = true
	
	if cooldown_actuel_sort > 0:
		cooldown_actuel_sort -= _delta
	if water_transport_cooldown > 0.0:
		water_transport_cooldown = maxf(0.0, water_transport_cooldown - _delta)
		
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

	if anti_armor_sort_actif:
		temps_restant_anti_armor_sort -= _delta
		if temps_restant_anti_armor_sort <= 0:
			anti_armor_sort_actif = false
			temps_restant_anti_armor_sort = 0.0
			multiplicateur_degats_subis = 1.0
			_appliquer_couleur_unite()
	
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
		_deal_combat_damage(attack_target_node, unit_damage)
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

func _est_anti_armor() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.ANTI_ARMOR

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
		_deal_combat_damage(obj, degats)

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
	if (
		MapSession.is_online_match
		and OnlineGameSync.is_online_active()
		and not _network_damage
		and MapSession.is_local_team(team)
		and net_sync_id >= 0
	):
		return

	var degats_finaux = montant
	
	if is_instance_valid(auteur) and "stats" in auteur and auteur.stats != null:
		if auteur.stats.unit_type == 5:
			degats_finaux = degats_finaux * 3 if (stats and stats.unit_type == 2) else int(float(degats_finaux) * 0.5)
	if anti_armor_sort_actif:
		degats_finaux = int(round(float(degats_finaux) * multiplicateur_degats_subis))
				
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
	if (
		MapSession.is_online_match
		and OnlineGameSync.is_online_active()
		and MapSession.is_local_team(team)
		and net_sync_id >= 0
		and not _network_damage
	):
		OnlineGameSync.report_unit_death(net_sync_id)

	if _est_water_transporter():
		if water_transport_boarded.size() > 0:
			_water_transport_release_boarded_at_origin()
		elif water_transport_phase == WaterTransportPhase.UNITS_MARKED:
			_water_transport_clear_marked()

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

func _est_water_transporter() -> bool:
	return stats != null and stats.unit_type == UnitStats.UnitType.WATER_TRANSPORT


func get_water_transport_cooldown_remaining() -> float:
	return water_transport_cooldown


func get_water_transport_phase() -> int:
	return int(water_transport_phase)


func get_anti_armor_spell_radius() -> float:
	return _rayon_sort_anti_armor()


func can_use_water_transport() -> bool:
	if not _est_water_transporter() or is_dying:
		return false
	if water_transport_phase != WaterTransportPhase.IDLE:
		return true
	return water_transport_cooldown <= 0.0


func water_transport_step() -> bool:
	if not can_use_water_transport():
		return false
	match water_transport_phase:
		WaterTransportPhase.IDLE:
			return _water_transport_mark_allies()
		WaterTransportPhase.UNITS_MARKED:
			return _water_transport_board_marked()
		WaterTransportPhase.CARRYING:
			return _water_transport_disembark()
	return false


func water_transport_cancel_mark() -> void:
	if water_transport_phase != WaterTransportPhase.UNITS_MARKED:
		return
	_water_transport_clear_marked()


func _water_transport_capacity() -> int:
	return WATER_TRANSPORT_CAP_BY_LEVEL.get(_niveau_unite(), 5)


func _est_unite_terrestre_transportable(unit: Node) -> bool:
	if not is_instance_valid(unit) or unit == self:
		return false
	if unit.get("is_dying") and unit.is_dying:
		return false
	if unit.get_meta("water_transport_hidden", false):
		return false
	if unit.get("is_camp_guardian") and unit.is_camp_guardian:
		return false
	if not unit.get("stats") or unit.stats == null:
		return false
	if unit.get("team") != team:
		return false
	var ut: UnitStats.UnitType = unit.stats.unit_type
	return ut == UnitStats.UnitType.INFANTRY \
		or ut == UnitStats.UnitType.ARCHER \
		or ut == UnitStats.UnitType.HEAVY \
		or ut == UnitStats.UnitType.SUPPORT \
		or ut == UnitStats.UnitType.HEAL \
		or ut == UnitStats.UnitType.ANTI_ARMOR \
		or ut == UnitStats.UnitType.MORTAR


func _water_transport_mark_allies() -> bool:
	var allies := _water_transport_allies_in_radius()
	if allies.is_empty():
		return false
	var cap := _water_transport_capacity()
	allies.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	water_transport_marked.clear()
	for unit in allies:
		if water_transport_marked.size() >= cap:
			break
		water_transport_marked.append(unit)
		_attacher_effet_sur_cible(unit, SCENE_WATER_TRANSPORT_MARK_FX, 3600.0)
	water_transport_phase = WaterTransportPhase.UNITS_MARKED
	return true


func _water_transport_allies_in_radius() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var requete := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = WATER_TRANSPORT_MARK_RADIUS
	requete.shape = cercle
	requete.transform = Transform2D(0, global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	var groupe := "soldiers" if team == Owner.PLAYER else "enemies"
	for res in get_world_2d().direct_space_state.intersect_shape(requete):
		var obj = res.collider as Node2D
		if obj == null or not obj.is_in_group(groupe):
			continue
		if _est_unite_terrestre_transportable(obj):
			result.append(obj)
	return result


func _water_transport_board_marked() -> bool:
	if water_transport_marked.is_empty():
		_water_transport_clear_marked()
		return false
	water_transport_boarded.clear()
	water_transport_origin.clear()
	for unit in water_transport_marked:
		if not is_instance_valid(unit):
			continue
		water_transport_origin[unit] = unit.global_position
		water_transport_boarded.append(unit)
		_retirer_effet_transport(unit)
		_attacher_effet_sur_cible(unit, SCENE_WATER_TRANSPORT_BOARD_FX, 0.45)
		_water_transport_hide_unit(unit)
	water_transport_marked.clear()
	if water_transport_boarded.is_empty():
		water_transport_phase = WaterTransportPhase.IDLE
		return false
	var bonus := 1.0 + WATER_TRANSPORT_SCALE_BONUS * float(water_transport_boarded.size())
	scale = water_transport_base_scale * bonus
	water_transport_phase = WaterTransportPhase.CARRYING
	return true


func _water_transport_disembark() -> bool:
	if water_transport_boarded.is_empty():
		_water_transport_reset_after_disembark()
		return false
	var land_point := _water_transport_nearest_ground_point(global_position)
	if land_point == Vector2.INF:
		push_warning("Transport: approchez-vous de la cote (sol) pour debarquer.")
		return false
	var count := water_transport_boarded.size()
	for i in range(count):
		var unit: Node2D = water_transport_boarded[i]
		if not is_instance_valid(unit):
			continue
		var angle := TAU * float(i) / float(max(count, 1))
		var offset := Vector2(cos(angle), sin(angle)) * WATER_TRANSPORT_DISEMBARK_SPREAD
		var spawn_pos := land_point + offset
		if not _water_transport_is_valid_land_point(spawn_pos):
			spawn_pos = land_point
		_water_transport_show_unit(unit, spawn_pos)
	water_transport_boarded.clear()
	water_transport_origin.clear()
	_water_transport_reset_after_disembark()
	water_transport_cooldown = WATER_TRANSPORT_COOLDOWN
	return true


func _water_transport_reset_after_disembark() -> void:
	water_transport_phase = WaterTransportPhase.IDLE
	scale = water_transport_base_scale


func _water_transport_clear_marked() -> void:
	for unit in water_transport_marked:
		if is_instance_valid(unit):
			_retirer_effet_transport(unit)
	water_transport_marked.clear()
	water_transport_phase = WaterTransportPhase.IDLE


func _water_transport_release_boarded_at_origin() -> void:
	for unit in water_transport_boarded:
		if not is_instance_valid(unit):
			continue
		var origin: Vector2 = water_transport_origin.get(unit, global_position)
		_water_transport_show_unit(unit, origin)
	water_transport_boarded.clear()
	water_transport_origin.clear()
	water_transport_marked.clear()
	scale = water_transport_base_scale
	water_transport_phase = WaterTransportPhase.IDLE


func _water_transport_hide_unit(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	_arreter_combat_unite(unit)
	unit.visible = false
	unit.collision_layer = 0
	unit.collision_mask = 0
	unit.set_process(false)
	unit.set_physics_process(false)
	if unit.has_node("ZoneDetection"):
		unit.get_node("ZoneDetection").monitoring = false
	unit.set_meta("water_transport_hidden", true)
	unit.set_meta("water_transport_carrier", self)


func _water_transport_show_unit(unit: Node2D, spawn_pos: Vector2) -> void:
	if not is_instance_valid(unit):
		return
	_retirer_effet_transport(unit)
	unit.visible = true
	unit.global_position = spawn_pos
	unit.collision_layer = COLLISION_LAYER_PLAYER_UNIT if unit.get("team") == Owner.PLAYER else COLLISION_LAYER_ENEMY_UNIT
	unit.collision_mask = COLLISION_LAYER_WORLD | COLLISION_LAYER_PLAYER_UNIT | COLLISION_LAYER_ENEMY_UNIT
	unit.set_process(true)
	unit.set_physics_process(true)
	if unit.has_node("ZoneDetection"):
		var zone: Area2D = unit.get_node("ZoneDetection")
		zone.monitoring = true
	if unit.has_method("_configurer_calques_navigation"):
		unit._configurer_calques_navigation()
	if unit.has_method("_configurer_mouvement_et_collisions"):
		unit._configurer_mouvement_et_collisions()
	unit.remove_meta("water_transport_hidden")
	if unit.has_meta("water_transport_carrier"):
		unit.remove_meta("water_transport_carrier")


func _arreter_combat_unite(unit: Node) -> void:
	if unit.has_method("_arreter_combat"):
		unit._arreter_combat()
	elif unit.get("attack_target_node") != null:
		unit.attack_target_node = null


func _retirer_effet_transport(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var fx = unit.get_node_or_null(NOM_NOEUD_EFFET_BUFF)
	if is_instance_valid(fx):
		fx.queue_free()


func _water_transport_nav_regions() -> Array[NavigationRegion2D]:
	var regions: Array[NavigationRegion2D] = []
	var root := get_tree().current_scene
	if is_instance_valid(root):
		_collect_nav_regions_for_transport(root, regions)
	if regions.is_empty():
		var map_slot := get_tree().root.find_child("MapSlot", true, false)
		if map_slot:
			_collect_nav_regions_for_transport(map_slot, regions)
	return regions


func _water_transport_closest_point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq <= 0.0001:
		return a
	var t: float = clampf((point - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	return a + ab * t


func _water_transport_closest_point_on_polygon(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	if polygon.size() < 3:
		return Vector2.INF
	var best := Vector2.INF
	var best_d2 := INF
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var candidate := _water_transport_closest_point_on_segment(point, a, b)
		var d2 := point.distance_squared_to(candidate)
		if d2 < best_d2:
			best_d2 = d2
			best = candidate
	return best


func _water_transport_surface_mask_at(world_pos: Vector2) -> int:
	var surface_mask := 0
	for region in _water_transport_nav_regions():
		if not is_instance_valid(region):
			continue
		var nav_polygon: NavigationPolygon = region.navigation_polygon
		if nav_polygon == null:
			continue
		var vertices: PackedVector2Array = nav_polygon.get_vertices()
		var local_pos := region.to_local(world_pos)
		for polygon_idx in range(nav_polygon.get_polygon_count()):
			var polygon_indices: PackedInt32Array = nav_polygon.get_polygon(polygon_idx)
			if polygon_indices.size() < 3:
				continue
			var polygon_local := PackedVector2Array()
			for vertex_idx in polygon_indices:
				polygon_local.append(vertices[vertex_idx])
			if Geometry2D.is_point_in_polygon(local_pos, polygon_local):
				surface_mask |= region.navigation_layers
				break
	return surface_mask


func _water_transport_is_valid_land_point(world_pos: Vector2) -> bool:
	var surface_mask := _water_transport_surface_mask_at(world_pos)
	return (surface_mask & NAV_LAYER_GROUND) != 0 and (surface_mask & NAV_LAYER_WATER) == 0


func _water_transport_closest_on_layers(from: Vector2, layer_mask: int) -> Vector2:
	var best := Vector2.INF
	var best_d2 := INF
	for region in _water_transport_nav_regions():
		if not is_instance_valid(region):
			continue
		if (region.navigation_layers & layer_mask) == 0:
			continue
		var nav_polygon: NavigationPolygon = region.navigation_polygon
		if nav_polygon == null:
			continue
		var vertices: PackedVector2Array = nav_polygon.get_vertices()
		var local_pos := region.to_local(from)
		for polygon_idx in range(nav_polygon.get_polygon_count()):
			var polygon_indices: PackedInt32Array = nav_polygon.get_polygon(polygon_idx)
			if polygon_indices.size() < 3:
				continue
			var polygon_local := PackedVector2Array()
			var polygon_world := PackedVector2Array()
			for vertex_idx in polygon_indices:
				var local_vertex := vertices[vertex_idx]
				polygon_local.append(local_vertex)
				polygon_world.append(region.to_global(local_vertex))
			var candidate := from if Geometry2D.is_point_in_polygon(local_pos, polygon_local) else _water_transport_closest_point_on_polygon(from, polygon_world)
			if candidate == Vector2.INF:
				continue
			var d2 := from.distance_squared_to(candidate)
			if d2 < best_d2:
				best_d2 = d2
				best = candidate
	return best


func _water_transport_nearest_ground_point(from: Vector2) -> Vector2:
	var shore := _water_transport_closest_on_layers(from, NAV_LAYER_GROUND)
	if shore == Vector2.INF:
		return Vector2.INF
	if from.distance_to(shore) > WATER_TRANSPORT_DISEMBARK_TRIGGER_DIST:
		return Vector2.INF

	var toward_shore := shore - from
	if toward_shore.length_squared() < 1.0:
		return shore

	var pushed := shore + toward_shore.normalized() * WATER_TRANSPORT_DISEMBARK_MIN_CLEARANCE
	var land_point := _water_transport_closest_on_layers(pushed, NAV_LAYER_GROUND)
	if land_point == Vector2.INF:
		return shore
	if from.distance_to(land_point) > WATER_TRANSPORT_DISEMBARK_MAX_DIST:
		return shore
	return land_point


func _collect_nav_regions_for_transport(node: Node, out: Array) -> void:
	if node is NavigationRegion2D:
		out.append(node)
	for child in node.get_children():
		_collect_nav_regions_for_transport(child, out)


func can_cast_spell() -> bool:
	if not stats or is_dying:
		return false
	if cooldown_actuel_sort > 0.0:
		return false
	if _est_mortar() or _est_healer() or (stats.unit_type == UnitStats.UnitType.SUPPORT) or _est_anti_armor():
		return true
	return stats.spell_cooldown > 0.0

func cast_spell() -> bool:
	if not can_cast_spell():
		return false
	if _est_mortar():
		if _cast_spell_mortar_ult():
			cooldown_actuel_sort = COOLDOWN_SORT_SECONDES
			return true
		return false
	if _est_anti_armor():
		if _cast_spell_anti_armor():
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


func _rayon_sort_anti_armor() -> float:
	return RAYON_SORT_ANTI_ARMOR_NIVEAU_1 + float(_niveau_unite() - 1) * BONUS_RAYON_SORT_ANTI_ARMOR_PAR_NIVEAU


func _duree_sort_anti_armor() -> float:
	if stats and stats.spell_duration > 0.0:
		return stats.spell_duration
	return DUREE_SORT_ANTI_ARMOR_NIVEAU_1 + float(_niveau_unite() - 1) * BONUS_DUREE_SORT_ANTI_ARMOR_PAR_NIVEAU


func _cast_spell_anti_armor() -> bool:
	var cibles := _cibles_ennemies_sort_anti_armor()
	if cibles.is_empty():
		return false
	var cible := _cible_plus_de_pv_sort_anti_armor(cibles)
	if not is_instance_valid(cible):
		return false
	_tirer_projectile_sort_anti_armor(cible)
	return true


func _cibles_ennemies_sort_anti_armor() -> Array[Node2D]:
	var requete := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = _rayon_sort_anti_armor()
	requete.shape = cercle
	requete.transform = Transform2D(0, global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	var resultat: Array[Node2D] = []
	for res in get_world_2d().direct_space_state.intersect_shape(requete):
		var obj := res.collider as Node2D
		if obj == null or obj == self:
			continue
		if obj.is_in_group("camps"):
			continue
		if obj.get("team") == null or obj.team == team:
			continue
		if not obj.has_method("take_damage"):
			continue
		resultat.append(obj)
	return resultat


func _cible_plus_de_pv_sort_anti_armor(cibles: Array[Node2D]) -> Node2D:
	var meilleure_cible: Node2D = null
	var meilleur_pv := -1
	for cible in cibles:
		if not is_instance_valid(cible):
			continue
		var pv := int(cible.get("current_hp")) if cible.get("current_hp") != null else int(cible.get("hp_max"))
		if meilleure_cible == null or pv > meilleur_pv:
			meilleure_cible = cible
			meilleur_pv = pv
	return meilleure_cible


func _tirer_projectile_sort_anti_armor(cible: Node2D) -> void:
	if not is_instance_valid(cible):
		return
	var parent_node := get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj = SCENE_ANTI_ARMOR_PROJECTILE_LOOP.instantiate()
	parent_node.add_child(proj)
	proj.global_position = global_position
	if proj.has_method("launch"):
		proj.launch(
			cible,
			_duree_sort_anti_armor(),
			MULTIPLICATEUR_DEGATS_ANTI_ARMOR_SORT,
			self,
			VITESSE_PROJECTILE_ANTI_ARMOR_SORT
		)

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


func receive_anti_armor_spell(duree: float, multiplicateur: float = MULTIPLICATEUR_DEGATS_ANTI_ARMOR_SORT) -> void:
	if duree <= 0.0 or multiplicateur <= 1.0 or not stats:
		return
	anti_armor_sort_actif = true
	temps_restant_anti_armor_sort = maxf(temps_restant_anti_armor_sort, duree)
	multiplicateur_degats_subis = maxf(multiplicateur_degats_subis, multiplicateur)
	_appliquer_couleur_unite()

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
	if anti_armor_sort_actif:
		return Color(1.0, 0.45, 0.85)
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


func _deal_combat_damage(cible: Node, degats: int) -> void:
	if not cible.has_method("take_damage"):
		return
	if MapSession.is_online_match and OnlineGameSync.is_online_active():
		if MapSession.is_local_team(team):
			var target_sync: int = int(cible.get("net_sync_id")) if cible.get("net_sync_id") != null else -1
			if target_sync >= 0:
				cible.take_damage(degats, self, team)
				if net_sync_id >= 0:
					OnlineGameSync.report_damage(net_sync_id, target_sync, degats, int(team))
				return
		if bool(cible.get("net_remote_proxy")):
			return
	cible.take_damage(degats, self, team)


func take_damage_network_remote(montant: int, auteur_team: int) -> void:
	_network_damage = true
	take_damage(montant, null, auteur_team)
	_network_damage = false


func apply_network_order(move_to: Vector2, target: Node) -> void:
	net_remote_proxy = true
	if is_instance_valid(target) and target.has_method("take_damage"):
		attack_target_node = target as Node2D
		agent_navigation.target_position = target.global_position
	else:
		attack_target_node = null
		agent_navigation.target_position = move_to


func apply_network_state(pos: Vector2, vel: Vector2, hp: int) -> void:
	_net_target_position = pos
	_net_lerp_active = true
	velocity = vel
	if hp >= 0:
		current_hp = mini(hp, hp_max)
		if has_node("ProgressBar"):
			$ProgressBar.value = current_hp


func force_network_death() -> void:
	if is_dying:
		return
	die(null, -1)


func _physics_process_network_proxy(delta: float) -> void:
	if _net_lerp_active:
		global_position = global_position.lerp(_net_target_position, clampf(delta * 9.0, 0.0, 1.0))
		if global_position.distance_to(_net_target_position) < 4.0:
			_net_lerp_active = false
	if is_instance_valid(attack_target_node):
		agent_navigation.target_position = attack_target_node.global_position
		if attack_target_node in zone_detection.get_overlapping_bodies():
			_on_timer_attaque_timeout()
	update_animation()


func _calculer_repulsion_allies() -> Vector2:
	var repulsion := Vector2.ZERO
	var groupe := "soldiers" if MapSession.is_local_team(team) else "enemies"
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
