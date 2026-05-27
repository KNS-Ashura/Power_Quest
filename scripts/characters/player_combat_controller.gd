extends RefCounted
class_name PlayerCombatController


static func on_timer_attaque_timeout(owner: Node) -> void:
	if not owner._cible_combat_valide(owner.attack_target_node):
		owner._arreter_combat()
		return
	if not (owner.attack_target_node in owner.zone_detection.get_overlapping_bodies()):
		owner._arreter_combat()
		return
	if owner._est_healer():
		owner._jouer_animation_attaque(owner.attack_target_node)
		owner._programmer_tir_projectile(owner.attack_target_node, owner.PROJECTILE_ATTACK_ANIM_DELAY_HEAL, true)
		return
	if owner._est_mortar():
		tirer_mortar_distance(owner, owner.attack_target_node)
		return
	if owner._est_range() or owner._est_water_range_unite() or (owner.stats != null and owner.stats.is_ranged):
		owner._jouer_animation_attaque(owner.attack_target_node)
		owner._programmer_tir_projectile(owner.attack_target_node, owner.PROJECTILE_ATTACK_ANIM_DELAY_RANGE, false)
		return
	if owner.attack_target_node.has_method("take_damage"):
		owner._jouer_animation_attaque(owner.attack_target_node)
		owner._deal_combat_damage(owner.attack_target_node, owner.unit_damage)
		animer_attaque_melee(owner)


static func animer_attaque_melee(owner: Node) -> void:
	if is_instance_valid(owner.attack_target_node):
		for sprite in owner._sprites_animes_unite():
			var flash: Tween = owner.create_tween()
			flash.tween_property(sprite, "modulate", Color.RED, 0.1)
			flash.tween_property(sprite, "modulate", owner._couleur_unite(), 0.1)


static func rechercher_cible_automatique(owner: Node) -> void:
	if owner._est_healer():
		var allies: Array = owner.zone_detection.get_overlapping_bodies().filter(func(c):
			return c != owner and owner._cible_combat_valide(c)
		)
		if owner.is_camp_guardian:
			allies = allies.filter(func(c): return c.global_position.distance_to(owner.guard_position) <= owner.guard_defense_radius)
		if allies.size() > 0:
			allies.sort_custom(func(a, b):
				var ratio_a: float = float(a.current_hp) / max(1.0, float(a.hp_max))
				var ratio_b: float = float(b.current_hp) / max(1.0, float(b.hp_max))
				if ratio_a != ratio_b:
					return ratio_a < ratio_b
				return owner.global_position.distance_to(a.global_position) < owner.global_position.distance_to(b.global_position)
			)
			owner.attack_target(allies[0])
		return

	var cibles: Array = owner.zone_detection.get_overlapping_bodies().filter(func(c):
		return c != owner and owner._cible_combat_valide(c)
	)
	if owner.is_camp_guardian:
		cibles = cibles.filter(func(c): return c.global_position.distance_to(owner.guard_position) <= owner.guard_defense_radius)

	if cibles.size() > 0:
		cibles.sort_custom(func(a, b):
			var a_est_soldat: bool = not a.is_in_group("camps")
			var b_est_soldat: bool = not b.is_in_group("camps")
			if a_est_soldat != b_est_soldat:
				return a_est_soldat
			return owner.global_position.distance_to(a.global_position) < owner.global_position.distance_to(b.global_position)
		)
		owner.attack_target(cibles[0])


static func tirer_projectile_range(owner: Node, cible: Node2D) -> void:
	if not owner._cible_combat_valide(cible):
		owner._arreter_combat()
		return
	var parent_node: Node = owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var scene_proj: PackedScene = owner.SCENE_WATER_RANGE_PROJECTILE_LOOP if owner._est_water_range_unite() else owner.SCENE_RANGE_PROJECTILE_LOOP
	var proj: Node = scene_proj.instantiate()
	parent_node.add_child(proj)
	proj.global_position = owner.global_position
	if proj.has_method("launch"):
		proj.launch(cible, owner.unit_damage, owner)


static func montant_soin(owner: Node) -> int:
	return int(max(10.0, float(owner.hp_max) * 0.12))


static func tirer_projectile_heal(owner: Node, cible: Node2D) -> void:
	if not owner._cible_combat_valide(cible):
		owner._arreter_combat()
		return
	var parent_node: Node = owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj: Node = owner.SCENE_HEALER_PROJECTILE_LOOP.instantiate()
	parent_node.add_child(proj)
	proj.global_position = owner.global_position
	if proj.has_method("launch"):
		proj.launch(cible, montant_soin(owner), owner)


static func programmer_tir_projectile(owner: Node, cible: Node2D, delay_seconds: float, heal_projectile: bool) -> void:
	if not owner._cible_combat_valide(cible):
		return
	owner._pending_projectile_ticket += 1
	var ticket: int = owner._pending_projectile_ticket
	if delay_seconds <= 0.0:
		declencher_tir_projectile(owner, ticket, cible, heal_projectile)
		return
	var timer: SceneTreeTimer = owner.get_tree().create_timer(delay_seconds)
	timer.timeout.connect(func(): declencher_tir_projectile(owner, ticket, cible, heal_projectile), CONNECT_ONE_SHOT)


static func declencher_tir_projectile(owner: Node, ticket: int, cible: Node2D, heal_projectile: bool) -> void:
	if ticket != owner._pending_projectile_ticket:
		return
	if not owner._cible_combat_valide(cible):
		return
	if not (cible in owner.zone_detection.get_overlapping_bodies()):
		return
	if heal_projectile:
		tirer_projectile_heal(owner, cible)
	else:
		tirer_projectile_range(owner, cible)


static func gerer_tirs_passifs_gardien(owner: Node, delta: float) -> void:
	var ennemis: Array = ennemis_portee_tir_passif_gardien(owner)
	if ennemis.is_empty():
		owner.timer_tir_passif_gardien = 0.0
		return
	owner.timer_tir_passif_gardien -= delta
	if owner.timer_tir_passif_gardien > 0.0:
		return
	owner.timer_tir_passif_gardien = 1.0 / float(owner._niveau_gardien_port())
	ennemis.sort_custom(func(a, b):
		return owner.global_position.distance_to(a.global_position) < owner.global_position.distance_to(b.global_position)
	)
	tirer_projectile_gardien_passif(owner, ennemis[0])


static func ennemis_portee_tir_passif_gardien(owner: Node) -> Array:
	var requete := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = owner.RAYON_TIR_PASSIF_PORT_GARDIEN
	requete.shape = cercle
	requete.transform = Transform2D(0, owner.global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	requete.collision_mask = owner.COLLISION_LAYER_PLAYER_UNIT | owner.COLLISION_LAYER_ENEMY_UNIT

	var cibles: Array = []
	for res in owner.get_world_2d().direct_space_state.intersect_shape(requete):
		var obj: Variant = res.collider
		if not is_instance_valid(obj) or obj == owner:
			continue
		if not obj.has_method("take_damage") or obj.is_in_group("camps"):
			continue
		if obj.get("team") == null or obj.team == owner.team:
			continue
		if obj.global_position.distance_to(owner.guard_position) > owner.guard_chase_radius:
			continue
		cibles.append(obj)
	return cibles


static func scene_projectile_gardien_passif(owner: Node) -> PackedScene:
	if owner._est_gardien_port():
		return owner.SCENE_PORT_GUARDIAN_PROJECTILE_LOOP
	return owner.SCENE_CAMP_GUARDIAN_PROJECTILE_LOOP


static func vitesse_projectile_gardien_passif(owner: Node) -> float:
	if owner._est_gardien_port():
		return owner.VITESSE_PROJECTILE_PORT_GARDIEN
	return owner.VITESSE_PROJECTILE_CAMP_GARDIEN


static func tirer_projectile_gardien_passif(owner: Node, cible: Node2D) -> void:
	if not is_instance_valid(cible):
		return
	var parent_node: Node = owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var proj: Node = scene_projectile_gardien_passif(owner).instantiate()
	parent_node.add_child(proj)
	proj.global_position = owner.global_position
	if proj.has_method("launch"):
		proj.launch(cible, owner.unit_damage, owner, vitesse_projectile_gardien_passif(owner))


static func tirer_mortar_distance(owner: Node, cible: Node2D) -> void:
	if not owner._cible_combat_valide(cible):
		owner._arreter_combat()
		return
	var position_impact: Vector2 = cible.global_position
	var explosion: Dictionary = prochaine_explosion_mortar(owner)
	spawn_mortar_explosion_vfx(owner, explosion["scene"], position_impact)
	appliquer_degats_zone(owner, position_impact, explosion["rayon"], explosion["degats"])


static func prochaine_explosion_mortar(owner: Node) -> Dictionary:
	var base: Dictionary = {
		"scene": owner.SCENE_MORTAR_EXPLOSION_BASE,
		"rayon": 84.0,
		"degats": owner.unit_damage
	}
	var poison: Dictionary = {
		"scene": owner.SCENE_MORTAR_EXPLOSION_POISON,
		"rayon": 96.0,
		"degats": int(round(float(owner.unit_damage) * 0.65))
	}
	var feu: Dictionary = {
		"scene": owner.SCENE_MORTAR_EXPLOSION_FEU,
		"rayon": 110.0,
		"degats": int(round(float(owner.unit_damage) * 0.85))
	}

	var niveau: int = owner._niveau_mortar()
	var sequence: Array = [base]
	if niveau == 2:
		sequence = [base, poison]
	elif niveau >= 3:
		sequence = [base, poison, feu]

	var index: int = owner.cycle_explosion_mortar % sequence.size()
	owner.cycle_explosion_mortar += 1
	return sequence[index]


static func spawn_mortar_explosion_vfx(owner: Node, scene: PackedScene, position_world: Vector2) -> void:
	if scene == null:
		return
	var parent_node: Node = owner.get_parent()
	if not is_instance_valid(parent_node):
		return
	var vfx: Node = scene.instantiate()
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


static func appliquer_degats_zone(owner: Node, centre: Vector2, rayon: float, degats: int) -> void:
	var requete := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = rayon
	requete.shape = cercle
	requete.transform = Transform2D(0, centre)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true

	var resultats: Array = owner.get_world_2d().direct_space_state.intersect_shape(requete)
	for res in resultats:
		var obj: Variant = res.collider
		if not is_instance_valid(obj):
			continue
		if obj == owner:
			continue
		if not obj.has_method("take_damage"):
			continue
		if obj.get("team") == null or obj.team == owner.team:
			continue
		if obj.is_in_group("camps"):
			continue
		owner._deal_combat_damage(obj, degats)


static func appliquer_soin_cible(owner: Node, cible: Node2D) -> void:
	if not owner._cible_combat_valide(cible):
		owner._arreter_combat()
		return

	var soin: int = montant_soin(owner)
	cible.current_hp = min(cible.hp_max, cible.current_hp + soin)
	if cible.has_node("ProgressBar"):
		cible.get_node("ProgressBar").value = cible.current_hp
	owner._attacher_effet_soin_sur(cible)
