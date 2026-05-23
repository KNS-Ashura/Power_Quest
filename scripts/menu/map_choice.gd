extends Node2D


var liste_des_cartes = [
	{
		"nom": "THE GREEN ISLAND",
		"image_map": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_map1/map_test.tres"),
		"portrait": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_generale/imgDroite.tres"),
		"description": "VOILA DU TEXTE ET J'EN REJOUE POUR TESTER, C'EST COOL",
		"attr1": "CURSED LAND", "attr2": "GLOWING LAND",
		"attr3": "CAVE LAND", "attr4": "UNDEAD LAND"
	},
	{
		"nom": "CHEVALIER TEST",
		"image_map": preload("res://assets/menu/img-sur-mesure/chevalier.tres"),
		"portrait": preload("res://assets/menu/img-sur-mesure/chevalier.tres"),
		"description": "Je suis un chevalier super mega stylé",
		"attr1": "ROCKY AREA", "attr2": "WINTER LAND",
		"attr3": "SEABED LAND", "attr4": "FLYING ISLAND"
	},
	{
		"nom": "FANTOME TEST",
		"image_map": preload("res://assets/menu/img-sur-mesure/ghost.tres"),
		"portrait": preload("res://assets/menu/img-sur-mesure/ghost.tres"),
		"description": "Je suis un fantome super mega stylé",
		"attr1": "FOREST", "attr2": "DESERT",
		"attr3": "SWAMP LAND", "attr4": "GLADES LAND"
	}
]

var index_carte_actuelle = 0


@onready var label_nom = $MapChoice/MapName        # Le label "Map 1" sous la section Map
@onready var sprite_carte = $ImgMap                # Le TextureRect qui affiche la grande image à droite



func _ready():
	
	$MapChoice/FlecheGauche2.pressed.connect(_on_fleche_gauche_pressed)
	$MapChoice/FlecheDroite2.pressed.connect(_on_fleche_droite_pressed)
	
	update_display()


func update_display():
	var d = liste_des_cartes[index_carte_actuelle]
	
	
	label_nom.text = d["nom"]
	

	if sprite_carte is AnimatedSprite2D:
		sprite_carte.sprite_frames = d["image_map"]
		sprite_carte.play()
	else:
		sprite_carte.texture = d["image_map"]

	


func _on_fleche_droite_pressed():
	index_carte_actuelle = (index_carte_actuelle + 1) % liste_des_cartes.size()
	update_display()

func _on_fleche_gauche_pressed():
	index_carte_actuelle = (index_carte_actuelle - 1 + liste_des_cartes.size()) % liste_des_cartes.size()
	update_display()
