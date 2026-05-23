extends Node2D

const MSG_MAP_MISSING := "Map %d is not available yet (missing scene file)."

var difficultes: Array[String] = ["Débutant", "Avancé", "Expert"]
var index_ia_actuel: int = 0

var liste_des_cartes: Array[Dictionary] = [
	{
		"nom": "Map 1 — Undead Land",
		"map_index": 1,
		"image_map": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_map1/map_test.tres"),
	},
	{
		"nom": "Map 2 — Cave Land",
		"map_index": 2,
		"image_map": preload("res://assets/menu/img-sur-mesure/chevalier.tres"),
	},
	{
		"nom": "Map 3",
		"map_index": 3,
		"image_map": preload("res://assets/menu/img-sur-mesure/ghost.tres"),
	},
]
var index_carte_actuelle: int = 0

@onready var label_ia: Label = %IntituleIA
@onready var fleche_gauche_ia: TextureButton = %FlecheGauche
@onready var fleche_droite_ia: TextureButton = %FlecheDroite
@onready var label_nom_map: Label = %MapName
@onready var texture_image_map: TextureRect = %ImgMap
@onready var fleche_gauche_map: TextureButton = %FlecheGauche2
@onready var fleche_droite_map: TextureButton = %FlecheDroite2
@onready var btn_launch: TextureButton = $LaunchGame


func _ready() -> void:
	fleche_gauche_ia.pressed.connect(_on_fleche_gauche_ia_pressed)
	fleche_droite_ia.pressed.connect(_on_fleche_droite_ia_pressed)
	fleche_gauche_map.pressed.connect(_on_fleche_gauche_map_pressed)
	fleche_droite_map.pressed.connect(_on_fleche_droite_map_pressed)
	if btn_launch and not btn_launch.pressed.is_connected(_on_launch_game_pressed):
		btn_launch.pressed.connect(_on_launch_game_pressed)
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
	var d: Dictionary = liste_des_cartes[index_carte_actuelle]
	label_nom_map.text = d["nom"]
	var map_index: int = int(d.get("map_index", 1))
	if btn_launch:
		btn_launch.disabled = not MapSession.is_map_available(map_index)
	var preview = d["image_map"]
	if preview is Texture:
		texture_image_map.texture = preview
	elif preview is SpriteFrames:
		texture_image_map.texture = preview.get_frame_texture("default", 0)


func _on_fleche_droite_map_pressed() -> void:
	index_carte_actuelle = (index_carte_actuelle + 1) % liste_des_cartes.size()
	update_display_map()


func _on_fleche_gauche_map_pressed() -> void:
	index_carte_actuelle = (index_carte_actuelle - 1 + liste_des_cartes.size()) % liste_des_cartes.size()
	update_display_map()


func _on_launch_game_pressed() -> void:
	var d: Dictionary = liste_des_cartes[index_carte_actuelle]
	var map_index: int = int(d.get("map_index", 1))
	MapSession.active_map_index = map_index
	if not MapSession.is_map_available(map_index):
		push_warning(MSG_MAP_MISSING % map_index)
		return
	get_tree().change_scene_to_file(MapSession.GAME_SHELL_SCENE)
