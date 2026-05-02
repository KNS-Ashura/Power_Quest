extends CharacterBody2D

const SCENE_IMPACT = preload("res://scenes/personnages/range/range-land-projectile.tscn")

var cible: Node2D = null
var degats: int = 0
var vitesse: float = 520.0
var auteur: Node2D = null
var equipe_tireur: int = -1
var deja_touche: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func lancer(target: Node2D, p_degats: int, p_auteur: Node2D = null):
	cible = target
	degats = p_degats
	auteur = p_auteur
	if is_instance_valid(auteur) and auteur.get("equipe") != null:
		equipe_tireur = auteur.equipe
	_mettre_animation_direction()

func _process(delta):
	if deja_touche:
		return
	if not is_instance_valid(cible):
		queue_free()
		return

	var dir = global_position.direction_to(cible.global_position)
	global_position += dir * vitesse * delta
	_mettre_animation_direction()

	if global_position.distance_to(cible.global_position) < 14.0:
		_impacter()

func _impacter():
	if deja_touche:
		return
	deja_touche = true

	if is_instance_valid(cible) and cible.has_method("recevoir_degats"):
		cible.recevoir_degats(degats, auteur, equipe_tireur)

	var parent_node = get_parent()
	if is_instance_valid(parent_node):
		var impact = SCENE_IMPACT.instantiate()
		parent_node.add_child(impact)
		impact.global_position = global_position
		if impact.has_method("jouer_impact"):
			impact.jouer_impact(_direction_depuis_vecteur((cible.global_position - global_position) if is_instance_valid(cible) else Vector2.DOWN))
	queue_free()

func _mettre_animation_direction():
	if not is_instance_valid(sprite):
		return
	var delta = (cible.global_position - global_position) if is_instance_valid(cible) else Vector2.DOWN
	var dir = _direction_depuis_vecteur(delta)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(dir):
		sprite.play(dir)

func _direction_depuis_vecteur(delta: Vector2) -> String:
	if abs(delta.y) >= abs(delta.x):
		return "b" if delta.y < 0 else "f"
	return "l" if delta.x < 0 else "r"
