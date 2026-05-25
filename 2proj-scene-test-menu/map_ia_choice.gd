extends Node2D


var difficultes: Array[String] = ["Débutant", "Avancé", "Expert"]
var index_ia_actuel: int = 0


var liste_des_cartes: Array[Dictionary] = [
	{
		"nom": "THE GREEN ISLAND",
		"image_map": preload("res://assets/img-sur-mesure/scene_maps/assets_map1/map_test.tres")
	},
	{
		"nom": "CHEVALIER TEST",
		"image_map": preload("res://assets/img-sur-mesure/chevalier.tres")
	},
	{
		"nom": "FANTOME TEST",
		"image_map": preload("res://assets/img-sur-mesure/ghost.tres")
	}
]
var index_carte_actuelle: int = 0




@onready var label_ia: Label = %IntituleIA 
@onready var fleche_gauche_ia: TextureButton = %FlecheGauche
@onready var fleche_droite_ia: TextureButton = %FlecheDroite


@onready var label_nom_map: Label = %MapName
@onready var texture_image_map: TextureRect = %ImgMap


@onready var fleche_gauche_map: TextureButton = %FlecheGauche2
@onready var fleche_droite_map: TextureButton = %FlecheDroite2



func _ready() -> void:
	
	

	
	fleche_gauche_ia.pressed.connect(_on_fleche_gauche_ia_pressed)
	fleche_droite_ia.pressed.connect(_on_fleche_droite_ia_pressed)
	
	
	fleche_gauche_map.pressed.connect(_on_fleche_gauche_map_pressed)
	fleche_droite_map.pressed.connect(_on_fleche_droite_map_pressed)
	
	
	update_display_ia()
	update_display_map()


func update_display_ia() -> void:
	label_ia.text = difficultes[index_ia_actuel]

func _on_fleche_droite_ia_pressed() -> void:
	index_ia_actuel = (index_ia_actuel + 1) % difficultes.size()
	update_display_ia()

func _on_fleche_gauche_ia_pressed() -> void:
	index_ia_actuel = (index_ia_actuel - 1 + difficultes.size()) % difficultes.size()
	update_display_ia()



func update_display_map() -> void:
	var d = liste_des_cartes[index_carte_actuelle]
	
	
	label_nom_map.text = d["nom"]
	
	
	if d["image_map"] is Texture:
		texture_image_map.texture = d["image_map"]
	elif d["image_map"] is SpriteFrames:
		
		texture_image_map.texture = d["image_map"].get_frame_texture("default", 0)

func _on_fleche_droite_map_pressed() -> void:
	index_carte_actuelle = (index_carte_actuelle + 1) % liste_des_cartes.size()
	update_display_map()

func _on_fleche_gauche_map_pressed() -> void:
	index_carte_actuelle = (index_carte_actuelle - 1 + liste_des_cartes.size()) % liste_des_cartes.size()
	update_display_map()
