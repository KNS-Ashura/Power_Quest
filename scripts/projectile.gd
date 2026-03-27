extends Area2D

var cible : Node2D = null
var degats : int = 0
var vitesse : float = 450.0
var auteur : Node2D = null
var equipe_tireur : int = -1

func lancer(target : Node2D, p_degats : int, p_auteur : Node2D = null):
	cible = target
	degats = p_degats
	auteur = p_auteur
	if is_instance_valid(auteur) and auteur.get("equipe") != null:
		equipe_tireur = auteur.equipe

func _process(delta):
	if is_instance_valid(cible):
		var direction = global_position.direction_to(cible.global_position)
		look_at(cible.global_position)
		global_position += direction * vitesse * delta
		
		# Sécurité impact si collisionArea rate de peu
		if global_position.distance_to(cible.global_position) < 12:
			_appliquer_degats()
	else:
		# Si la cible est détruite avant l'impact, on détruit le projectile
		queue_free()

func _on_body_entered(body):
	if body == cible:
		_appliquer_degats()

func _appliquer_degats():
	if is_instance_valid(auteur) and "stats" in auteur and auteur.stats != null and auteur.stats.type_unite == 6:
		# Explosion de zone pour Mortier (Type 6)
		_explosion_mortier()
	else:
		# Impact direct classique
		if is_instance_valid(cible) and cible.has_method("recevoir_degats"):
			cible.recevoir_degats(degats, auteur, equipe_tireur)
	queue_free()

func _explosion_mortier():
	var rayon_explosion = 100.0 # Rayon d'impact spécifié
	var espace = get_world_2d().direct_space_state
	
	var requete = PhysicsShapeQueryParameters2D.new()
	var cercle = CircleShape2D.new()
	cercle.radius = rayon_explosion
	requete.shape = cercle
	requete.transform = Transform2D(0, global_position)
	requete.collide_with_areas = false
	requete.collide_with_bodies = true
	
	var resultats = espace.intersect_shape(requete)
	
	for res in resultats:
		var obj = res.collider
		if obj and obj.has_method("recevoir_degats") and not obj.is_in_group("camps"):
			# Dégâts de zone (friendly fire désactivé)
			if obj.get("equipe") != null and obj.get("equipe") != equipe_tireur:
				var distance = global_position.distance_to(obj.global_position)
				var ratio = 1.0 - clamp(distance / rayon_explosion, 0.0, 1.0)
				ratio = max(0.2, ratio) # Minimum 20% de dégâts sur les bords
				var degats_calcules = int(float(degats) * ratio)
				obj.recevoir_degats(degats_calcules, auteur, equipe_tireur)
