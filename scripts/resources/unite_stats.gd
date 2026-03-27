extends Resource
class_name UniteStats

enum TypeUnite { INFANTERIE, ARCHER, LOURD, SUPPORT, HEAL, ANTI_ARMOR, MORTAR }

@export var type_unite : TypeUnite = TypeUnite.INFANTERIE
@export var nom : String = "Soldat"
@export var prix : int = 50
@export var hp_max : int = 100
@export var vitesse : float = 150.0
@export var degats : int = 10
@export var portee : float = 40.0
@export var temps_fabrication : float = 5.0
@export var est_a_distance : bool = false
@export var couleur : Color = Color(1, 1, 1)
@export var cooldown_sort : float = 0.0
@export var duree_sort : float = 0.0
