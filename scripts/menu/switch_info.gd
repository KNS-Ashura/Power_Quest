extends Node2D


var liste_des_cartes = [
	{
		"nom": "MAP_GREEN_ISLAND",
		"image_map": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_map1/map_test.tres"),
		"portrait": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_generale/imgDroite.tres"),
		"description": "MAP_DESC_TEST",
		"attr1": "MAP_CURSED_LAND", "attr2": "MAP_GLOWING_LAND",
		"attr3": "MAP_CAVE_LAND", "attr4": "MAP_UNDEAD_LAND"
	},
	{
		"nom": "MAP_NAME_1",
		"image_map": preload("res://assets/menu/img-sur-mesure/chevalier.tres"),
		"portrait": preload("res://assets/menu/img-sur-mesure/chevalier.tres"),
		"description": "MAP_DESC_TEST",
		"attr1": "MAP_CURSED_LAND", "attr2": "MAP_GLOWING_LAND",
		"attr3": "MAP_CAVE_LAND", "attr4": "MAP_UNDEAD_LAND"
	},
	{
		"nom": "MAP_NAME_3",
		"image_map": preload("res://assets/menu/img-sur-mesure/ghost.tres"),
		"portrait": preload("res://assets/menu/img-sur-mesure/ghost.tres"),
		"description": "MAP_DESC_TEST",
		"attr1": "MAP_CURSED_LAND", "attr2": "MAP_GLOWING_LAND",
		"attr3": "MAP_CAVE_LAND", "attr4": "MAP_UNDEAD_LAND"
	}
]

var index_carte_actuelle = 0

@onready var label_nom = %NomDeLaMap
@onready var sprite_carte = %CarteImage
@onready var portrait_deco = %InsideDeco
@onready var label_desc = %Description1

@onready var attr1 = %CURSED
@onready var attr2 = %GLOWING
@onready var attr3 = %CAVE
@onready var attr4 = %UNDEAD

func _ready() -> void:
	update_display()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		update_display()


func update_display():
	var d = liste_des_cartes[index_carte_actuelle]
	

	label_nom.text = tr(d["nom"])
	
	if sprite_carte is AnimatedSprite2D:
		sprite_carte.sprite_frames = d["image_map"]
		
		if d["image_map"] != null:
			sprite_carte.play()
	else:
		sprite_carte.texture = d["image_map"]

	label_desc.text = tr(d["description"])
	portrait_deco.texture = d["portrait"]
	
	
	attr1.text = tr(str(d.get("attr1", "")))
	attr2.text = tr(str(d.get("attr2", "")))
	attr3.text = tr(str(d.get("attr3", "")))
	attr4.text = tr(str(d.get("attr4", "")))


func _on_fleche_droite_pressed():
	index_carte_actuelle = (index_carte_actuelle + 1) % liste_des_cartes.size()
	update_display()

func _on_fleche_gauche_pressed():
	index_carte_actuelle = (index_carte_actuelle - 1 + liste_des_cartes.size()) % liste_des_cartes.size()
	update_display()
