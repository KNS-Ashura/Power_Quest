extends Node2D

# --- 1. CONFIGURATION DES DONNÉES ---
var liste_des_cartes = [
	{
		"nom": "Undead Land",
		"image_map": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_map1/map_test.tres"),
		"portrait": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_generale/imgDroite.tres"),
		"description": "A cursed battlefield haunted by the dead.",
		"attr1": "CURSED LAND", "attr2": "GLOWING LAND",
		"attr3": "SWAMP LAND", "attr4": "UNDEAD LAND"
	},
	{
		"nom": "Desert Land",
		"image_map": preload("res://assets/menu/img-sur-mesure/ghost.tres"),
		"portrait": preload("res://assets/menu/img-sur-mesure/ghost.tres"),
		"description": "A dry desert map with open lines and harsh ground.",
		"attr1": "DESERT", "attr2": "ROCKY AREA",
		"attr3": "DRY LAND", "attr4": "ANCIENT RUINS"
	}
]

var index_carte_actuelle = 0

# --- 2. RÉFÉRENCES AUX NŒUDS (Basé sur image_1c1186.png) ---
@onready var label_nom = %NomDeLaMap
@onready var sprite_carte = %CarteImage
@onready var portrait_deco = %InsideDeco
@onready var label_desc = %Description1

# Références aux labels de tes biomes (ceux avec le %)
@onready var attr1 = %CURSED
@onready var attr2 = %GLOWING
@onready var attr3 = %CAVE
@onready var attr4 = %UNDEAD

func _ready():
	update_display()

# --- 3. FONCTION DE MISE À JOUR ---
func update_display():
	var d = liste_des_cartes[index_carte_actuelle]
	
	# Page Gauche
	label_nom.text = d["nom"]
	if sprite_carte is AnimatedSprite2D:
		sprite_carte.sprite_frames = d["image_map"]
		sprite_carte.play()
	else:
		sprite_carte.texture = d["image_map"]
		
	# Page Droite
	label_desc.text = d["description"]
	portrait_deco.texture = d["portrait"]
	
	# Mise à jour des textes de biomes
	attr1.text = d["attr1"]
	attr2.text = d["attr2"]
	attr3.text = d["attr3"]
	attr4.text = d["attr4"]

# --- 4. SIGNAUX DES BOUTONS ---
func _on_fleche_droite_pressed():
	index_carte_actuelle = (index_carte_actuelle + 1) % liste_des_cartes.size()
	update_display()

func _on_fleche_gauche_pressed():
	index_carte_actuelle = (index_carte_actuelle - 1 + liste_des_cartes.size()) % liste_des_cartes.size()
	update_display()
