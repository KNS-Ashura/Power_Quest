extends CharacterBody2D

const UnitNameUtilsRef = preload("res://scripts/common/unit_name_utils.gd")
const PlayerAnimationControllerRef = preload("res://scripts/characters/player_animation_controller.gd")
const PlayerTransportControllerRef = preload("res://scripts/characters/player_transport_controller.gd")
const PlayerNetworkControllerRef = preload("res://scripts/characters/player_network_controller.gd")
const PlayerSpellControllerRef = preload("res://scripts/characters/player_spell_controller.gd")
const PlayerMovementControllerRef = preload("res://scripts/characters/player_movement_controller.gd")
const PlayerCombatControllerRef = preload("res://scripts/characters/player_combat_controller.gd")

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
const MORTAR_ATTACK_COOLDOWN_NIVEAU_1: float = 4.8
const MORTAR_ATTACK_COOLDOWN_NIVEAU_2: float = 3.9
const MORTAR_ATTACK_COOLDOWN_NIVEAU_3: float = 3.2
const MORTAR_SORT_COOLDOWN_DEFAUT: float = 12.0
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
const PROJECTILE_ATTACK_ANIM_DELAY_RANGE := 0.11
const PROJECTILE_ATTACK_ANIM_DELAY_HEAL := 0.12
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
var _pending_projectile_ticket: int = 0

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


func is_selectable_as_local_army() -> bool:
	return MapSession.is_local_team(int(team))


func matches_selection_hotkey(keycode: int) -> bool:
	if is_camp_guardian or stats == null:
		return false
	return UnitStats.selection_hotkey_for_type(stats.unit_type) == keycode


func move_to(cible : Vector2):
	if net_remote_proxy:
		return
	if is_camp_guardian:
		return
	attack_target_node = null
	if is_instance_valid(agent_navigation):
		agent_navigation.target_desired_distance = 8.0
	agent_navigation.target_position = cible

func _arreter_combat() -> void:
	attack_target_node = null
	_pending_projectile_ticket += 1
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
		if is_instance_valid(agent_navigation):
			agent_navigation.target_desired_distance = max(8.0, _rayon_zone_detection() - 5.0)
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
	if is_instance_valid(agent_navigation):
		if is_instance_valid(attack_target_node):
			agent_navigation.target_desired_distance = max(8.0, _rayon_zone_detection() - 5.0)
		else:
			agent_navigation.target_desired_distance = 8.0
	
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
	PlayerCombatControllerRef.on_timer_attaque_timeout(self)

func _animer_attaque_melee():
	PlayerCombatControllerRef.animer_attaque_melee(self)

func _rechercher_cible_automatique():
	PlayerCombatControllerRef.rechercher_cible_automatique(self)

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
	PlayerCombatControllerRef.tirer_projectile_range(self, cible)

func _montant_soin() -> int:
	return PlayerCombatControllerRef.montant_soin(self)

func _tirer_projectile_heal(cible: Node2D) -> void:
	PlayerCombatControllerRef.tirer_projectile_heal(self, cible)


func _programmer_tir_projectile(cible: Node2D, delay_seconds: float, heal_projectile: bool) -> void:
	PlayerCombatControllerRef.programmer_tir_projectile(self, cible, delay_seconds, heal_projectile)


func _declencher_tir_projectile(ticket: int, cible: Node2D, heal_projectile: bool) -> void:
	PlayerCombatControllerRef.declencher_tir_projectile(self, ticket, cible, heal_projectile)

func _est_gardien_port() -> bool:
	return scene_file_path.contains("/port_guardian/")

func _est_gardien_camp() -> bool:
	return is_camp_guardian and scene_file_path.contains("/guardian/") and not _est_gardien_port()

func _niveau_gardien_port() -> int:
	if stats == null:
		return 1
	return UnitNameUtilsRef.level_from_unit_name(String(stats.name))

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
	PlayerCombatControllerRef.gerer_tirs_passifs_gardien(self, delta)

func _ennemis_portee_tir_passif_gardien() -> Array:
	return PlayerCombatControllerRef.ennemis_portee_tir_passif_gardien(self)

func _scene_projectile_gardien_passif() -> PackedScene:
	return PlayerCombatControllerRef.scene_projectile_gardien_passif(self)

func _vitesse_projectile_gardien_passif() -> float:
	return PlayerCombatControllerRef.vitesse_projectile_gardien_passif(self)

func _tirer_projectile_gardien_passif(cible: Node2D) -> void:
	PlayerCombatControllerRef.tirer_projectile_gardien_passif(self, cible)

func _duree_effet_soin() -> float:
	return DUREE_EFFET_SOIN_DEFAUT

func _niveau_unite() -> int:
	if stats == null:
		return 1
	return UnitNameUtilsRef.level_from_unit_name(String(stats.name))

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
	PlayerCombatControllerRef.tirer_mortar_distance(self, cible)

func _prochaine_explosion_mortar() -> Dictionary:
	return PlayerCombatControllerRef.prochaine_explosion_mortar(self)

func _spawn_mortar_explosion_vfx(scene: PackedScene, position_world: Vector2):
	PlayerCombatControllerRef.spawn_mortar_explosion_vfx(self, scene, position_world)

func _appliquer_degats_zone(centre: Vector2, rayon: float, degats: int):
	PlayerCombatControllerRef.appliquer_degats_zone(self, centre, rayon, degats)

func _appliquer_soin_cible(cible: Node2D):
	PlayerCombatControllerRef.appliquer_soin_cible(self, cible)

func update_animation():
	PlayerAnimationControllerRef.update_animation(self)

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
	# Le propriétaire est autoritaire sur la mort de SON unité : il la signale
	# TOUJOURS (même morte par dégâts réseau) pour retirer les proxies partout.
	if (
		MapSession.is_online_match
		and OnlineGameSync.is_online_active()
		and MapSession.is_local_team(team)
		and net_sync_id >= 0
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
	return PlayerAnimationControllerRef.play_death_animation(self)

func _jouer_animation_attaque(cible: Node2D):
	PlayerAnimationControllerRef.play_attack_animation(self, cible)

func _direction_depuis_cible(pos_cible: Vector2) -> String:
	return PlayerAnimationControllerRef.direction_from_target(self, pos_cible)

func _sprites_animes_unite() -> Array[AnimatedSprite2D]:
	return PlayerAnimationControllerRef.animated_sprites(self)

func _jouer_animation_sur_sprites(anim: String, fallback: String = ""):
	PlayerAnimationControllerRef.play_on_sprites(self, anim, fallback)

func _configurer_animations_mort():
	PlayerAnimationControllerRef.configure_death_animations(self)

func _est_water_transporter() -> bool:
	return PlayerTransportControllerRef.is_water_transporter(self)


func get_water_transport_cooldown_remaining() -> float:
	return PlayerTransportControllerRef.get_cooldown_remaining(self)


func get_spell_cooldown_remaining() -> float:
	return maxf(0.0, cooldown_actuel_sort)


func get_water_transport_phase() -> int:
	return PlayerTransportControllerRef.get_phase(self)


func get_anti_armor_spell_radius() -> float:
	return _rayon_sort_anti_armor()


func can_use_water_transport() -> bool:
	return PlayerTransportControllerRef.can_use(self)


func water_transport_step() -> bool:
	return PlayerTransportControllerRef.step(self)


func water_transport_cancel_mark() -> void:
	PlayerTransportControllerRef.cancel_mark(self)


func _water_transport_capacity() -> int:
	return PlayerTransportControllerRef.capacity(self)


func _est_unite_terrestre_transportable(unit: Node) -> bool:
	return PlayerTransportControllerRef.is_land_unit_transportable(self, unit)


func _water_transport_mark_allies() -> bool:
	return PlayerTransportControllerRef.mark_allies(self)


func _water_transport_allies_in_radius() -> Array[Node2D]:
	return PlayerTransportControllerRef.allies_in_radius(self)


func _water_transport_board_marked() -> bool:
	return PlayerTransportControllerRef.board_marked(self)


func _water_transport_disembark() -> bool:
	return PlayerTransportControllerRef.disembark(self)


func _water_transport_reset_after_disembark() -> void:
	PlayerTransportControllerRef.reset_after_disembark(self)


func _water_transport_clear_marked() -> void:
	PlayerTransportControllerRef.clear_marked(self)


func _water_transport_release_boarded_at_origin() -> void:
	PlayerTransportControllerRef.release_boarded_at_origin(self)


func _water_transport_hide_unit(unit: Node2D) -> void:
	PlayerTransportControllerRef.hide_unit(self, unit)


func _water_transport_show_unit(unit: Node2D, spawn_pos: Vector2) -> void:
	PlayerTransportControllerRef.show_unit(self, unit, spawn_pos)


func _arreter_combat_unite(unit: Node) -> void:
	PlayerTransportControllerRef.stop_unit_combat(unit)


func _retirer_effet_transport(unit: Node2D) -> void:
	PlayerTransportControllerRef.remove_transport_fx(self, unit)


func _water_transport_nav_regions() -> Array[NavigationRegion2D]:
	return PlayerTransportControllerRef.nav_regions(self)


func _water_transport_closest_point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	return PlayerTransportControllerRef.closest_point_on_segment(point, a, b)


func _water_transport_closest_point_on_polygon(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	return PlayerTransportControllerRef.closest_point_on_polygon(point, polygon)


func _water_transport_surface_mask_at(world_pos: Vector2) -> int:
	return PlayerTransportControllerRef.surface_mask_at(self, world_pos)


func _water_transport_is_valid_land_point(world_pos: Vector2) -> bool:
	return PlayerTransportControllerRef.is_valid_land_point(self, world_pos)


func _water_transport_closest_on_layers(from: Vector2, layer_mask: int) -> Vector2:
	return PlayerTransportControllerRef.closest_on_layers(self, from, layer_mask)


func _water_transport_nearest_ground_point(from: Vector2) -> Vector2:
	return PlayerTransportControllerRef.nearest_ground_point(self, from)


func _collect_nav_regions_for_transport(node: Node, out: Array) -> void:
	PlayerTransportControllerRef.collect_nav_regions(node, out)


func can_cast_spell() -> bool:
	return PlayerSpellControllerRef.can_cast_spell(self)

func cast_spell() -> bool:
	return PlayerSpellControllerRef.cast_spell(self)

func _cast_spell_mortar_ult() -> bool:
	return PlayerSpellControllerRef.cast_spell_mortar_ult(self)


func _rayon_sort_anti_armor() -> float:
	return PlayerSpellControllerRef.rayon_sort_anti_armor(self)


func _duree_sort_anti_armor() -> float:
	return PlayerSpellControllerRef.duree_sort_anti_armor(self)


func _cast_spell_anti_armor() -> bool:
	return PlayerSpellControllerRef.cast_spell_anti_armor(self)


func _cibles_ennemies_sort_anti_armor() -> Array[Node2D]:
	return PlayerSpellControllerRef.cibles_ennemies_sort_anti_armor(self)


func _cible_plus_de_pv_sort_anti_armor(cibles: Array[Node2D]) -> Node2D:
	return PlayerSpellControllerRef.cible_plus_de_pv_sort_anti_armor(cibles)


func _tirer_projectile_sort_anti_armor(cible: Node2D) -> void:
	PlayerSpellControllerRef.tirer_projectile_sort_anti_armor(self, cible)

func _cibles_ennemies_plus_proches_mortar(nb_max: int) -> Array:
	return PlayerSpellControllerRef.cibles_ennemies_plus_proches_mortar(self, nb_max)

func recevoir_invulnerabilite_sort(duree: float) -> void:
	PlayerSpellControllerRef.recevoir_invulnerabilite_sort(self, duree)

func receive_boost(duree: float):
	PlayerSpellControllerRef.receive_boost(self, duree)


func receive_anti_armor_spell(duree: float, multiplicateur: float = MULTIPLICATEUR_DEGATS_ANTI_ARMOR_SORT) -> void:
	PlayerSpellControllerRef.receive_anti_armor_spell(self, duree, multiplicateur)

func _attack_rate_actuelle() -> float:
	return PlayerSpellControllerRef.attack_rate_actuelle(self)

func _couleur_unite() -> Color:
	return PlayerSpellControllerRef.couleur_unite(self)

func _appliquer_couleur_unite():
	PlayerSpellControllerRef.appliquer_couleur_unite(self)

func configure_guardian_mode(position_ancre: Vector2, rayon_defense: float = 260.0, rayon_poursuite: float = 320.0):
	PlayerMovementControllerRef.configure_guardian_mode(self, position_ancre, rayon_defense, rayon_poursuite)


func _est_scene_gardien() -> bool:
	return PlayerMovementControllerRef.est_scene_gardien(self)


func _configurer_mouvement_et_collisions() -> void:
	PlayerMovementControllerRef.configurer_mouvement_et_collisions(self)


func _appliquer_calques_collision_equipe() -> void:
	PlayerMovementControllerRef.appliquer_calques_collision_equipe(self)


func _configurer_zone_detection() -> void:
	PlayerMovementControllerRef.configurer_zone_detection(self)


func _configurer_forme_collision() -> void:
	PlayerMovementControllerRef.configurer_forme_collision(self)


func _configurer_evitement_navigation() -> void:
	PlayerMovementControllerRef.configurer_evitement_navigation(self)


func _appliquer_deplacement_vers(prochain_point: Vector2) -> void:
	PlayerMovementControllerRef.appliquer_deplacement_vers(self, prochain_point)


func _calculer_vitesse_desiree(prochain_point: Vector2) -> Vector2:
	return PlayerMovementControllerRef.calculer_vitesse_desiree(self, prochain_point)


func _deal_combat_damage(cible: Node, degats: int) -> void:
	PlayerNetworkControllerRef.deal_combat_damage(self, cible, degats)


func take_damage_network_remote(montant: int, auteur_team: int) -> void:
	PlayerNetworkControllerRef.take_damage_network_remote(self, montant, auteur_team)


func apply_network_order(move_to: Vector2, target: Node) -> void:
	PlayerNetworkControllerRef.apply_network_order(self, move_to, target)


func apply_network_state(pos: Vector2, vel: Vector2, hp: int) -> void:
	PlayerNetworkControllerRef.apply_network_state(self, pos, vel, hp)


func force_network_death() -> void:
	PlayerNetworkControllerRef.force_network_death(self)


func apply_heal_network_remote(amount: int, caster_sync_id: int) -> void:
	PlayerNetworkControllerRef.apply_heal_network_remote(self, amount, caster_sync_id)


func apply_spell_network_remote(spell_type: int, target_sync_ids: Array, params: Dictionary) -> void:
	PlayerSpellControllerRef.apply_spell_network_remote(self, spell_type, target_sync_ids, params)


func _physics_process_network_proxy(delta: float) -> void:
	PlayerNetworkControllerRef.physics_process_network_proxy(self, delta)


func _calculer_repulsion_allies() -> Vector2:
	return PlayerMovementControllerRef.calculer_repulsion_allies(self)
