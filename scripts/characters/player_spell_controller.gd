extends RefCounted
class_name PlayerSpellController


static func can_cast_spell(owner: Node) -> bool:
	if not owner.stats or owner.is_dying:
		return false
	if owner.cooldown_actuel_sort > 0.0:
		return false
	if owner._est_mortar() or owner._est_healer() or (owner.stats.unit_type == UnitStats.UnitType.SUPPORT) or owner._est_anti_armor():
		return true
	return owner.stats.spell_cooldown > 0.0


static func cast_spell(owner: Node) -> bool:
	if not can_cast_spell(owner):
		return false
	if owner._est_mortar():
		if cast_spell_mortar_ult(owner):
			owner.cooldown_actuel_sort = owner.COOLDOWN_SORT_SECONDES
			return true
		return false
	if owner._est_anti_armor():
		if cast_spell_anti_armor(owner):
			owner.cooldown_actuel_sort = owner.COOLDOWN_SORT_SECONDES
			return true
		return false

	var requete := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = 150.0
	requete.shape = cercle
	requete.transform = Transform2D(0, owner.global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true

	var resultats: Array = owner.get_world_2d().direct_space_state.intersect_shape(requete)
	var groupe := "soldiers" if owner.team == owner.Owner.PLAYER else "enemies"
	var au_moins_un_effet: bool = false
	var cibles_sync: Array = []

	for res in resultats:
		var obj: Variant = res.collider
		if not obj or not obj.is_in_group(groupe):
			continue
		if owner.stats.unit_type == UnitStats.UnitType.SUPPORT and obj.has_method("receive_boost"):
			obj.receive_boost(owner._duree_sort_boost())
			au_moins_un_effet = true
			_append_sync_id(cibles_sync, obj)
		elif owner.stats.unit_type == UnitStats.UnitType.HEAL and obj.has_method("recevoir_invulnerabilite_sort"):
			obj.recevoir_invulnerabilite_sort(owner._duree_sort_invulnerabilite())
			au_moins_un_effet = true
			_append_sync_id(cibles_sync, obj)

	if not au_moins_un_effet:
		return false

	owner.cooldown_actuel_sort = owner.COOLDOWN_SORT_SECONDES
	_rapport_sort_reseau(owner, cibles_sync)
	return true


static func cast_spell_mortar_ult(owner: Node) -> bool:
	var niveau: int = owner._niveau_mortar()
	var nb_cibles: int = 1
	if niveau == 2:
		nb_cibles = 2
	elif niveau >= 3:
		nb_cibles = 3

	var cibles: Array = cibles_ennemies_plus_proches_mortar(owner, nb_cibles)
	if cibles.is_empty():
		return false

	var degats_sort: int = int(round(float(owner.unit_damage) * 1.2))
	var positions_impact: Array = []
	for cible in cibles:
		var position_impact: Vector2 = cible.global_position
		positions_impact.append(position_impact)
		owner._spawn_mortar_explosion_vfx(owner.SCENE_MORTAR_EXPLOSION_ULT, position_impact)
		owner._appliquer_degats_zone(position_impact, 112.0, degats_sort)
	_rapport_sort_mortar_reseau(owner, positions_impact)
	return true


static func rayon_sort_anti_armor(owner: Node) -> float:
	return owner.RAYON_SORT_ANTI_ARMOR_NIVEAU_1 + float(owner._niveau_unite() - 1) * owner.BONUS_RAYON_SORT_ANTI_ARMOR_PAR_NIVEAU


static func duree_sort_anti_armor(owner: Node) -> float:
	if owner.stats and owner.stats.spell_duration > 0.0:
		return owner.stats.spell_duration
	return owner.DUREE_SORT_ANTI_ARMOR_NIVEAU_1 + float(owner._niveau_unite() - 1) * owner.BONUS_DUREE_SORT_ANTI_ARMOR_PAR_NIVEAU


static func cast_spell_anti_armor(owner: Node) -> bool:
	var cibles: Array[Node2D] = cibles_ennemies_sort_anti_armor(owner)
	if cibles.is_empty():
		return false
	var cible: Node2D = cible_plus_de_pv_sort_anti_armor(cibles)
	if not is_instance_valid(cible):
		return false
	tirer_projectile_sort_anti_armor(owner, cible)
	var cibles_sync: Array = []
	_append_sync_id(cibles_sync, cible)
	_rapport_sort_anti_armor_reseau(owner, cibles_sync)
	return true


static func cibles_ennemies_sort_anti_armor(owner: Node) -> Array[Node2D]:
	var requete := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = rayon_sort_anti_armor(owner)
	requete.shape = cercle
	requete.transform = Transform2D(0, owner.global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	var resultat: Array[Node2D] = []
	for res in owner.get_world_2d().direct_space_state.intersect_shape(requete):
		var obj := res.collider as Node2D
		if obj == null or obj == owner:
			continue
		if obj.is_in_group("camps"):
			continue
		if obj.get("team") == null or obj.team == owner.team:
			continue
		if not obj.has_method("take_damage"):
			continue
		resultat.append(obj)
	return resultat


static func cible_plus_de_pv_sort_anti_armor(cibles: Array[Node2D]) -> Node2D:
	var meilleure_cible: Node2D = null
	var meilleur_pv: int = -1
	for cible in cibles:
		if not is_instance_valid(cible):
			continue
		var pv: int = int(cible.get("current_hp")) if cible.get("current_hp") != null else int(cible.get("hp_max"))
		if meilleure_cible == null or pv > meilleur_pv:
			meilleure_cible = cible
			meilleur_pv = pv
	return meilleure_cible


static func tirer_projectile_sort_anti_armor(owner: Node, cible: Node2D) -> void:
	if not is_instance_valid(cible):
		return
	var parent_node := owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj: Node = owner.SCENE_ANTI_ARMOR_PROJECTILE_LOOP.instantiate()
	parent_node.add_child(proj)
	proj.global_position = owner.global_position
	if proj.has_method("launch"):
		proj.launch(
			cible,
			duree_sort_anti_armor(owner),
			owner.MULTIPLICATEUR_DEGATS_ANTI_ARMOR_SORT,
			owner,
			owner.VITESSE_PROJECTILE_ANTI_ARMOR_SORT
		)


static func cibles_ennemies_plus_proches_mortar(owner: Node, nb_max: int) -> Array:
	var cibles: Array = owner.zone_detection.get_overlapping_bodies().filter(func(c):
		return c != owner and c.has_method("take_damage") and not c.is_in_group("camps") and c.get("team") != null and c.get("team") != owner.team
	)
	if cibles.is_empty():
		return []

	cibles.sort_custom(func(a, b):
		return owner.global_position.distance_to(a.global_position) < owner.global_position.distance_to(b.global_position)
	)

	var resultat: Array = []
	var limite: int = mini(nb_max, cibles.size())
	for i in range(limite):
		resultat.append(cibles[i])
	return resultat


static func recevoir_invulnerabilite_sort(owner: Node, duree: float) -> void:
	if duree <= 0.0 or not owner.stats:
		return
	owner.invulnerabilite_actif = true
	owner.temps_restant_invulnerabilite = maxf(owner.temps_restant_invulnerabilite, duree)
	owner._appliquer_couleur_unite()
	owner._mettre_a_jour_effet_visuel(owner)


static func receive_boost(owner: Node, duree: float) -> void:
	if duree <= 0.0 or not owner.stats:
		return
	owner.boost_actif = true
	owner.temps_restant_boost = maxf(owner.temps_restant_boost, duree)
	owner.unit_speed = owner.stats.speed * 1.25
	owner.unit_damage = int(round(owner.stats.damage * 1.25))
	owner.attack_rate_multiplier = 1.25
	owner._appliquer_couleur_unite()
	owner._mettre_a_jour_effet_visuel(owner)


static func receive_anti_armor_spell(owner: Node, duree: float, multiplicateur: float) -> void:
	if duree <= 0.0 or multiplicateur <= 1.0 or not owner.stats:
		return
	owner.anti_armor_sort_actif = true
	owner.temps_restant_anti_armor_sort = maxf(owner.temps_restant_anti_armor_sort, duree)
	owner.multiplicateur_degats_subis = maxf(owner.multiplicateur_degats_subis, multiplicateur)
	owner._appliquer_couleur_unite()


static func attack_rate_actuelle(owner: Node) -> float:
	var cadence_base: float = owner.stats.attack_rate if owner.stats and "attack_rate" in owner.stats else 1.0
	return cadence_base * owner.attack_rate_multiplier


static func couleur_unite(owner: Node) -> Color:
	if owner.invulnerabilite_actif and owner.boost_actif:
		return Color(0.45, 1.0, 0.55)
	if owner.invulnerabilite_actif:
		return Color(0.35, 1.0, 0.45)
	if owner.boost_actif:
		return Color(1.0, 0.95, 0.25)
	if owner.anti_armor_sort_actif:
		return Color(1.0, 0.45, 0.85)
	if owner.team == owner.Owner.ENEMY:
		return Color(1.0, 0.2, 0.2)
	return Color.WHITE


static func appliquer_couleur_unite(owner: Node) -> void:
	for sprite in owner._sprites_animes_unite():
		sprite.modulate = couleur_unite(owner)


static func _append_sync_id(dest: Array, unit: Node) -> void:
	if unit.get("net_sync_id") == null:
		return
	var sid: int = int(unit.net_sync_id)
	if sid >= 0 and not dest.has(sid):
		dest.append(sid)


static func _rapport_sort_reseau(owner: Node, target_sync_ids: Array) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	if owner.net_sync_id < 0 or bool(owner.get("net_remote_proxy")):
		return
	if not MapSession.is_local_team(int(owner.team)):
		return
	var spell_type: int = OnlineGameSync.SPELL_INVULN
	var params: Dictionary = {"duration": owner._duree_sort_invulnerabilite()}
	if owner.stats and owner.stats.unit_type == UnitStats.UnitType.SUPPORT:
		spell_type = OnlineGameSync.SPELL_BOOST
		params = {"duration": owner._duree_sort_boost()}
	OnlineGameSync.report_spell_cast(owner.net_sync_id, spell_type, target_sync_ids, params)


static func _rapport_sort_mortar_reseau(owner: Node, positions: Array) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	if owner.net_sync_id < 0 or bool(owner.get("net_remote_proxy")):
		return
	if not MapSession.is_local_team(int(owner.team)):
		return
	OnlineGameSync.report_spell_cast(
		owner.net_sync_id, OnlineGameSync.SPELL_MORTAR, [], {"positions": positions}
	)


static func _rapport_sort_anti_armor_reseau(owner: Node, target_sync_ids: Array) -> void:
	if not MapSession.is_online_match or not OnlineGameSync.is_online_active():
		return
	if owner.net_sync_id < 0 or bool(owner.get("net_remote_proxy")):
		return
	if not MapSession.is_local_team(int(owner.team)):
		return
	OnlineGameSync.report_spell_cast(
		owner.net_sync_id,
		OnlineGameSync.SPELL_ANTI_ARMOR,
		target_sync_ids,
		{
			"duration": duree_sort_anti_armor(owner),
			"multiplier": owner.MULTIPLICATEUR_DEGATS_ANTI_ARMOR_SORT,
		}
	)


static func apply_spell_network_remote(
	owner: Node, spell_type: int, target_sync_ids: Array, params: Dictionary
) -> void:
	owner.cooldown_actuel_sort = owner.COOLDOWN_SORT_SECONDES
	match spell_type:
		OnlineGameSync.SPELL_INVULN:
			var duree: float = float(params.get("duration", 0.0))
			for sid in target_sync_ids:
				var unit: Node = OnlineGameSync.get_unit(int(sid))
				if unit != null:
					recevoir_invulnerabilite_sort(unit, duree)
		OnlineGameSync.SPELL_BOOST:
			var duree_boost: float = float(params.get("duration", 0.0))
			for sid in target_sync_ids:
				var ally: Node = OnlineGameSync.get_unit(int(sid))
				if ally != null:
					receive_boost(ally, duree_boost)
		OnlineGameSync.SPELL_MORTAR:
			var positions: Variant = params.get("positions", [])
			if positions is Array:
				for pos in positions:
					if pos is Vector2:
						owner._spawn_mortar_explosion_vfx(owner.SCENE_MORTAR_EXPLOSION_ULT, pos)
		OnlineGameSync.SPELL_ANTI_ARMOR:
			for sid in target_sync_ids:
				var cible: Node = OnlineGameSync.get_unit(int(sid))
				if cible is Node2D:
					tirer_projectile_sort_anti_armor(owner, cible as Node2D)
