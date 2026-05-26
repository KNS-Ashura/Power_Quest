extends Node2D

const MSG_MAP_MISSING := "Map %d is not available yet (missing scene file)."
const IA_LEVELS: Array[String] = ["Simple", "Normal", "Difficile"]

var difficultes: Array[String] = IA_LEVELS
var index_ia_actuel: int = 0


var liste_des_cartes: Array[Dictionary] = [
	{
		"nom": "Undead Land",
		"image_map": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_map1/map_test.tres"),
		"map_index": 1
	},
	{
		"nom": "Desert Land",
		"image_map": preload("res://assets/menu/img-sur-mesure/scene_maps/assets_map1/map_test.tres"),
		"map_index": 2
	}
]
var index_carte_actuelle: int = 0




@onready var label_ia: Label = %IntituleIA 
@onready var fleche_gauche_ia: TextureButton = %FlecheGauche
@onready var fleche_droite_ia: TextureButton = %FlecheDroite


@onready var label_nom_map: Label = %MapName
@onready var texture_image_map: TextureRect = %ImgMap
@onready var label_nom_map_large: Label = %NomMap
@onready var btn_launch_game: TextureButton = $LaunchGame



func _ready() -> void:
	if btn_launch_game and not btn_launch_game.pressed.is_connected(_on_launch_game_pressed):
		btn_launch_game.pressed.connect(_on_launch_game_pressed)
	index_ia_actuel = MapSession.get_ai_difficulty()
	update_display_ia()
	update_display_map()


func update_display_ia() -> void:
	label_ia.text = difficultes[index_ia_actuel]

func _on_fleche_droite_pressed() -> void:
	index_ia_actuel = (index_ia_actuel + 1) % difficultes.size()
	update_display_ia()

func _on_fleche_gauche_pressed() -> void:
	index_ia_actuel = (index_ia_actuel - 1 + difficultes.size()) % difficultes.size()
	update_display_ia()



func update_display_map() -> void:
	var d = liste_des_cartes[index_carte_actuelle]
	label_nom_map.text = d["nom"]
	label_nom_map_large.text = d["nom"]

	if d["image_map"] is Texture:
		texture_image_map.texture = d["image_map"]
	elif d["image_map"] is SpriteFrames:
		texture_image_map.texture = d["image_map"].get_frame_texture("default", 0)

func _on_fleche_droite_2_pressed() -> void:
	index_carte_actuelle = (index_carte_actuelle + 1) % liste_des_cartes.size()
	update_display_map()

func _on_fleche_gauche_2_pressed() -> void:
	index_carte_actuelle = (index_carte_actuelle - 1 + liste_des_cartes.size()) % liste_des_cartes.size()
	update_display_map()


func _on_launch_game_pressed() -> void:
	var map_index: int = int(liste_des_cartes[index_carte_actuelle].get("map_index", 1))
	MapSession.active_ai_difficulty = index_ia_actuel
	MapSession.active_map_index = map_index
	if not MapSession.is_map_available(map_index):
		push_warning(MSG_MAP_MISSING % map_index)
		return
	MapSession.reset_online_state()
	get_tree().change_scene_to_file(MapSession.GAME_SHELL_SCENE)
